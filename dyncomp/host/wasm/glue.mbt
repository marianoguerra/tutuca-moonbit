///| The `tcomp` FFI + lifecycle glue. Flow (no closures cross the boundary,
/// host-driven callbacks like the event bridge):
///   host load(url) -> JS imports the jco ESM, instantiates the guest,
///   calls the exported dyncomp_on_loaded(load_id, bundle_id, manifest_json)
///   -> glue registers the bundle into the live app's scope, refreshes
///   listeners/styles, and pushes a "dyncompLoaded" message so a host
///   component seeds instances as a plain state change.
///
/// Value JSON conventions with the JS bridge:
///   - args/maps cross as plain JSON (Value::to_json / from_json)
///   - get_field/call_method return "" for none, else a JSON value
///   - seq_entries returns "" for none, else [[key, value], ...]
///   - dispatch returns {"next": handle|null, "msgs": [{kind,name,args}]}
///   - with_field returns -1 for none, else the successor handle
///   - bucket ints follow WIT order: 0=input, 1=receive, 2=response

///|
extern "wasm" fn tcomp_load(load_id : Int, url : String) -> Unit = "tcomp" "load"

///|
extern "wasm" fn tcomp_create(
  bundle : Int,
  component : String,
  args_json : String,
) -> Int = "tcomp" "create"

///|
extern "wasm" fn tcomp_get_field(
  bundle : Int,
  handle : Int,
  name : String,
) -> String = "tcomp" "get_field"

///|
extern "wasm" fn tcomp_seq_entries(bundle : Int, handle : Int) -> String = "tcomp" "seq_entries"

///|
extern "wasm" fn tcomp_dispatch(
  bundle : Int,
  handle : Int,
  bucket : Int,
  name : String,
  args_json : String,
) -> String = "tcomp" "dispatch"

///|
extern "wasm" fn tcomp_call_method(
  bundle : Int,
  handle : Int,
  name : String,
  args_json : String,
) -> String = "tcomp" "call_method"

///|
extern "wasm" fn tcomp_with_field(
  bundle : Int,
  handle : Int,
  name : String,
  value_json : String,
) -> Int = "tcomp" "with_field"

///|
extern "wasm" fn tcomp_to_json(bundle : Int, handle : Int) -> String = "tcomp" "to_json"

///|
extern "wasm" fn tcomp_drop_instance(bundle : Int, handle : Int) -> Unit = "tcomp" "drop_instance"

///|
extern "wasm" fn tcomp_drop_bundle(bundle : Int) -> Unit = "tcomp" "drop_bundle"

// --- value codecs ---

///|
fn parse_value(s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch { _ => return Null }
  @tutuca.Value::from_json(j)
}

///|
fn args_json(args : Array[@tutuca.Value]) -> String {
  let arr : Array[Json] = args.map(v => v.to_json())
  Json::array(arr).stringify()
}

///|
fn map_json(args : Map[String, @tutuca.Value]) -> String {
  let obj : Map[String, Json] = {}
  for name, v in args {
    obj[name] = v.to_json()
  }
  Json::object(obj).stringify()
}

///|
fn json_values(j : Json) -> Array[@tutuca.Value] {
  match j {
    Array(items) => items.map(@tutuca.Value::from_json)
    _ => []
  }
}

// --- the Guest impl over tcomp ---

///|
pub struct WasmGuest {
  bundle : Int
  /// Set right after register_bundle so field decoding can wrap nested-child
  /// markers ({"$dyn": {"handle": n, "comp": s}}) as DynObj values.
  registered : Ref[@dyncomp.Bundle?]
}

///|
/// Decode a JSON value from the bridge, wrapping top-level nested-child
/// markers into DynObj values. Markers nested deeper inside lists/maps are
/// not resolved in v0.1 (they decode as plain data).
fn WasmGuest::decode_value(self : WasmGuest, s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch { _ => return Null }
  match j {
    Object(o) =>
      match o.get("$dyn") {
        Some(Object(m)) => {
          let handle = match m.get("handle") {
            Some(Number(n, ..)) => n.to_int()
            _ => return Null
          }
          let comp = match m.get("comp") {
            Some(String(c)) => c
            _ => return Null
          }
          match self.registered.val {
            Some(bundle) =>
              match bundle.wrap_instance(comp, handle) {
                Some(v) => v
                None => Null
              }
            None => Null
          }
        }
        _ => @tutuca.Value::from_json(j)
      }
    _ => @tutuca.Value::from_json(j)
  }
}

///|
fn bucket_int(bucket : @tutuca.HandlerBucket) -> Int {
  match bucket {
    Input => 0
    Receive => 1
    Response => 2
    Bubble => -1 // never forwarded: DynObj declares no bubble handlers
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn create(self, component, args) {
  tcomp_create(self.bundle, component, map_json(args))
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn get_field(self, handle, name) {
  let raw = tcomp_get_field(self.bundle, handle, name)
  if raw == "" {
    None
  } else {
    Some(self.decode_value(raw))
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn seq_entries(self, handle) {
  let s = tcomp_seq_entries(self.bundle, handle)
  guard s != "" else { return None }
  let j = @json.parse(s) catch { _ => return None }
  guard j is Array(items) else { return None }
  let out = []
  for item in items {
    match item {
      Array([String(key), v]) => out.push((key, @tutuca.Value::from_json(v)))
      _ => ()
    }
  }
  Some(out)
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn dispatch(
  self,
  handle,
  bucket,
  name,
  args,
) {
  let raw = tcomp_dispatch(
    self.bundle,
    handle,
    bucket_int(bucket),
    name,
    args_json(args),
  )
  let empty : @dyncomp.DispatchResult = { next: None, msgs: [] }
  let j = @json.parse(raw) catch { _ => return empty }
  guard j is Object(o) else { return empty }
  let next = match o.get("next") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let msgs : Array[@dyncomp.ControlMsg] = []
  match o.get("msgs") {
    Some(Array(items)) =>
      for item in items {
        guard item is Object(m) else { continue }
        let name = match m.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let args = match m.get("args") {
          Some(a) => json_values(a)
          None => []
        }
        match m.get("kind") {
          Some(String("emit")) => msgs.push(Emit(name, args))
          Some(String("send")) => msgs.push(Send(name, args))
          Some(String("request")) => msgs.push(Request(name, args))
          _ => ()
        }
      }
    _ => ()
  }
  { next, msgs }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn call_method(
  self,
  handle,
  name,
  args,
) {
  parse_value(tcomp_call_method(self.bundle, handle, name, args_json(args)))
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn with_field(self, handle, name, v) {
  // a nested-child value encodes as a marker (Value::to_json drops Obj)
  let encoded = match v {
    Obj(o) =>
      match o.obj_field(@dyncomp.handle_field) {
        Some(Num(h)) => "{\"$dyn\": {\"handle\": \{h.to_int()}}}"
        _ => v.to_json().stringify()
      }
    _ => v.to_json().stringify()
  }
  let next = tcomp_with_field(self.bundle, handle, name, encoded)
  if next < 0 {
    None
  } else {
    Some(next)
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn to_json_string(self, handle) {
  tcomp_to_json(self.bundle, handle)
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn drop_instance(self, handle) {
  tcomp_drop_instance(self.bundle, handle)
}

// --- lifecycle glue ---

///|
let current : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
let current_doc : Ref[@wdom.WasmNode?] = { val: None }

///|
let bundles : Map[Int, @dyncomp.Bundle] = {}

///|
let by_name : Map[String, Int] = {}

///|
let next_load : Ref[Int] = { val: 1 }

///|
/// Hand the live app to the glue after mounting (mirrors @wglue.install).
pub fn set_app(app : @app.App[@wdom.WasmNode], doc : @wdom.WasmNode) -> Unit {
  current.val = Some(app)
  current_doc.val = Some(doc)
}

///|
/// Start loading a bundle (a jco-transpiled ESM URL). Completion arrives via
/// the exported dyncomp_on_loaded / dyncomp_on_load_error callbacks.
pub fn load(url : String) -> Int {
  let id = next_load.val
  next_load.val = id + 1
  tcomp_load(id, url)
  id
}

///|
/// Wire this to the demo's exported `dyncomp_on_loaded`.
pub fn on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  ignore(load_id)
  guard current.val is Some(app) else { return }
  let registered : Ref[@dyncomp.Bundle?] = { val: None }
  let bundle = try {
    let manifest = @dyncomp.DynManifest::from_json_string(manifest_json)
    @dyncomp.register_bundle(
      app.scope,
      WasmGuest::{ bundle: bundle_id, registered },
      manifest,
    )
  } catch {
    _ => {
      app.send_at_root("dyncompError", args=[
        Str("bundle rejected: bad manifest or view"),
      ])
      return
    }
  }
  registered.val = Some(bundle)
  bundles[bundle_id] = bundle
  by_name[bundle.module_name()] = bundle_id
  // listeners for events only guest views use (loader dedups repeats),
  // styles re-injected under the same id (replaced, not appended)
  @wglue.install(app)
  match current_doc.val {
    Some(doc) => @wglue.install_styles(app, doc)
    None => ()
  }
  app.send_at_root("dyncompLoaded", args=[Str(bundle.module_name())])
}

///|
/// Wire this to the demo's exported `dyncomp_on_load_error`.
pub fn on_load_error(load_id : Int, msg : String) -> Unit {
  ignore(load_id)
  guard current.val is Some(app) else { return }
  app.send_at_root("dyncompError", args=[Str(msg)])
}

///|
/// Create an instance of a loaded bundle's component as a tree value.
pub fn make_instance(
  module_name : String,
  component : String,
  args? : Map[String, @tutuca.Value] = {},
) -> @tutuca.Value? {
  guard by_name.get(module_name) is Some(bid) else { return None }
  guard bundles.get(bid) is Some(bundle) else { return None }
  match bundle.make_instance(component, args~) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// The live app's settled root value (for inspection/state display).
pub fn app_root_value() -> @tutuca.Value? {
  guard current.val is Some(app) else { return None }
  app.root_value()
}

///|
/// Drop a whole bundle (guest instances included). Phase 3 will track live
/// instance handles; for now this only clears the tables and the JS side.
pub fn drop_bundle(module_name : String) -> Unit {
  guard by_name.get(module_name) is Some(bid) else { return }
  by_name.remove(module_name) |> ignore
  bundles.remove(bid) |> ignore
  tcomp_drop_bundle(bid)
}
