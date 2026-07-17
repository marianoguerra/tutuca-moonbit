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

// --- the Guest impl over tcomp ---

///|
pub struct WasmGuest {
  bundle : Int
  /// Set right after register_bundle so field decoding can wrap nested-child
  /// markers ({"$dyn": {"handle": n, "comp": s}}) as DynObj values.
  registered : Ref[@dyncomp.Bundle?]
}

///|
/// Recursively decode bridge JSON into a Value, wrapping nested-child
/// markers ({"$dyn": {"handle": n, "comp": s}}) as DynObj values at ANY
/// depth (inside lists/maps too).
fn WasmGuest::json_to_value(self : WasmGuest, j : Json) -> @tutuca.Value {
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
        _ => {
          let out : Map[String, @tutuca.Value] = {}
          for name, v in o {
            out[name] = self.json_to_value(v)
          }
          Map(out)
        }
      }
    Array(items) => List(items.map(v => self.json_to_value(v)))
    _ => @tutuca.Value::from_json(j)
  }
}

///|
fn WasmGuest::decode_value(self : WasmGuest, s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch { _ => return Null }
  self.json_to_value(j)
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
      Array([String(key), v]) => out.push((key, self.json_to_value(v)))
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
          Some(Array(items)) => items.map(v => self.json_to_value(v))
          _ => []
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
/// Where each in-flight load's completion messages should be dispatched
/// (the loading component's own path, captured via ctx.path()); loads
/// without a path notify the root.
let notify_paths : Map[Int, @tutuca.DispatchPath] = {}

///|
/// Start loading a bundle (a jco-transpiled ESM URL). Completion arrives via
/// the exported dyncomp_on_loaded / dyncomp_on_load_error callbacks as a
/// "dyncompLoaded" / "dyncompError" receive at the ROOT.
pub fn load(url : String) -> Int {
  let id = next_load.val
  next_load.val = id + 1
  tcomp_load(id, url)
  id
}

///|
/// Like load, but completion messages dispatch at `path` — pass ctx.path()
/// from the loading handler so any component anywhere in the tree (e.g. a
/// storybook pane) can host bundles without root-level plumbing.
pub fn load_from(path : @tutuca.DispatchPath, url : String) -> Int {
  let id = load(url)
  notify_paths[id] = path
  id
}

///|
fn notify(load_id : Int, name : String, args : Array[@tutuca.Value]) -> Unit {
  guard current.val is Some(app) else { return }
  match notify_paths.get(load_id) {
    Some(path) => {
      notify_paths.remove(load_id) |> ignore
      let _ = app.transactor.push_send(path, name, args)
      app.transactor.settle()
    }
    None => app.send_at_root(name, args~)
  }
}

///|
/// Wire this to the demo's exported `dyncomp_on_loaded`. Reloading a module
/// that is already registered hot-swaps it: the new bundle registers under
/// the module name, the "dyncompLoaded" handler runs (migrating state via
/// migrate_instance is the handler's choice), and the OLD bundle is dropped
/// afterwards (the settle is synchronous, so migration reads the old guest
/// before it goes away).
pub fn on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
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
      notify(load_id, "dyncompError", [
        Str("bundle rejected: bad manifest or view"),
      ])
      return
    }
  }
  registered.val = Some(bundle)
  let old_bid = by_name.get(bundle.module_name())
  bundles[bundle_id] = bundle
  by_name[bundle.module_name()] = bundle_id
  // listeners for events only guest views use (loader dedups repeats),
  // styles re-injected under the same id (replaced, not appended)
  @wglue.install(app)
  match current_doc.val {
    Some(doc) => @wglue.install_styles(app, doc)
    None => ()
  }
  notify(load_id, "dyncompLoaded", [Str(bundle.module_name())])
  // hot-swap: the handler above has settled; retire the superseded bundle
  match old_bid {
    Some(bid) =>
      if bid != bundle_id {
        bundles.remove(bid) |> ignore
        tcomp_drop_bundle(bid)
      }
    None => ()
  }
}

///|
/// Wire this to the demo's exported `dyncomp_on_load_error`.
pub fn on_load_error(load_id : Int, msg : String) -> Unit {
  notify(load_id, "dyncompError", [Str(msg)])
}

///|
/// Rebuild an instance of a (re)loaded module from an old guest value's
/// state projection — the hot-swap migration entry point (see
/// Bundle::migrate_instance).
pub fn migrate_instance(
  module_name : String,
  component : String,
  old : @tutuca.Value,
) -> @tutuca.Value? {
  guard by_name.get(module_name) is Some(bid) else { return None }
  guard bundles.get(bid) is Some(bundle) else { return None }
  match bundle.migrate_instance(old, component) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// The component names a loaded module declares, in manifest order. Empty if
/// the module is not loaded. Lets a host mount every component of a freshly
/// loaded bundle (the universal drop shell) without hard-coding names.
pub fn bundle_component_names(module_name : String) -> Array[String] {
  guard by_name.get(module_name) is Some(bid) else { return [] }
  guard bundles.get(bid) is Some(bundle) else { return [] }
  bundle.component_names()
}

///|
/// Every currently-loaded component as (module_name, component_name) pairs,
/// across all registered bundles. Backs the universal demo's "listComponents"
/// request so a picker can enumerate what can be mounted.
pub fn loaded_components() -> Array[(String, String)] {
  let out = []
  for module_name, bid in by_name {
    guard bundles.get(bid) is Some(bundle) else { continue }
    for name in bundle.component_names() {
      out.push((module_name, name))
    }
  }
  out
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
