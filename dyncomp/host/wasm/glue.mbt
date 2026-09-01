///| The `tcomp` FFI + lifecycle glue. Flow (no closures cross the boundary,
/// host-driven callbacks like the event bridge):
///   host load(url) -> JS instantiates the guest core through the host ABI,
///   calls the exported dyncomp_on_loaded(load_id, bundle_id, manifest_json)
///   -> glue registers the bundle into the live app's scope, refreshes
///   listeners/styles, and pushes a "dyncompLoaded" message so a host
///   component seeds instances as a plain state change.
///
/// Both completion messages carry the load id `load_url` / `load_dropped` /
/// `load_bytes` answered with — dyncompLoaded(module-name, load-id) and
/// dyncompError(reason, load-id) — so a host with more than one load in flight
/// can tell whose completion it just received.
///
/// Value JSON conventions with the JS bridge:
///   - args/maps cross as plain JSON (Value::to_json / from_json)
///   - get_field/get_property/render operations return "" for none, else JSON
///   - dispatch returns {"handled": bool, "next": handle|null,
///     "msgs": [{kind,name,args,...}]},
///     where a msg may also carry `path` (relative steps) or `opts` (request
///     routing) — see control_msg below
///   - serve_intent returns {"ok": value} or {"err": value}
///   - with_field returns -1 for none, else the successor handle
///   - the internal dispatch category is 0=message, 1=intent; the WIT exports
///     are fixed `handle-message` / `handle-intent` operations

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
extern "wasm" fn tcomp_dispatch(
  bundle : Int,
  handle : Int,
  bucket : Int,
  name : String,
  args_json : String,
  bindings_json : String,
) -> String = "tcomp" "dispatch"

///|
extern "wasm" fn tcomp_render_call(
  bundle : Int,
  handle : Int,
  category : String,
  name : String,
  args_json : String,
  bindings_json : String,
) -> String = "tcomp" "render_call"

///|
extern "wasm" fn tcomp_get_property(
  bundle : Int,
  handle : Int,
  name : String,
) -> String = "tcomp" "get_property"

///|
extern "wasm" fn tcomp_set_property(
  bundle : Int,
  handle : Int,
  name : String,
  value_json : String,
) -> String = "tcomp" "set_property"

///|
extern "wasm" fn tcomp_with_field(
  bundle : Int,
  handle : Int,
  name : String,
  value_json : String,
) -> Int = "tcomp" "with_field"

///|
extern "wasm" fn tcomp_serve_intent(
  bundle : Int,
  name : String,
  args_json : String,
) -> String = "tcomp" "serve_intent"

///|
/// Load a bundle from a file the user DROPPED, by the id the drop event's
/// value carried (see the app bridge's `dropped_files`).
extern "wasm" fn tcomp_load_dropped(file_id : Int, load_id : Int) -> Unit = "tcomp" "load_dropped"

///|
/// Load the same kind of bundle from a URL. One archive format, three ways to
/// name one: what the page dropped, what it can fetch, or what it already has.
extern "wasm" fn tcomp_load_url(url : String, load_id : Int) -> Unit = "tcomp" "load_url"

///|
/// ...and the third: bytes the page is already holding, by the id
/// `registerArchive` (in `loader.mjs`) answered with.
extern "wasm" fn tcomp_load_bytes(archive_id : Int, load_id : Int) -> Unit = "tcomp" "load_bytes"

///|
/// What `config.get` answers with, for ONE bundle — the manifest's declared
/// variables with this host's bindings applied.
///
/// Per bundle rather than per host: two registrations of one archive with
/// different variables are the case config vars exist for, and a page-wide
/// table could not tell them apart.
extern "wasm" fn tcomp_set_bundle_config(
  bundle_id : Int,
  config_json : String,
) -> Unit = "tcomp" "set_bundle_config"

///|
/// The guest's own state, base64 (see the bridge): "" is a guest that does not
/// persist. Text rather than bytes because that is what this FFI speaks, and
/// base64 is already the encoding a snapshot and a KV store use.
extern "wasm" fn tcomp_persist(bundle : Int, handle : Int) -> String = "tcomp" "persist"

///|
/// Bytes back into an instance; -1 is the guest refusing them.
extern "wasm" fn tcomp_restore(
  bundle : Int,
  component : String,
  state_b64 : String,
) -> Int = "tcomp" "restore"

///|
extern "wasm" fn tcomp_drop_instance(bundle : Int, handle : Int) -> Unit = "tcomp" "drop_instance"

///|
extern "wasm" fn tcomp_drop_bundle(bundle : Int) -> Unit = "tcomp" "drop_bundle"

// --- value codecs ---

///|
/// A corrupt payload from the guest boundary is a bug worth seeing, not just
/// an empty value: log it to the console before falling back. (The app-level
/// "dyncompError" channel is load-scoped, and these failures happen
/// mid-dispatch where re-entering the transactor isn't safe.)
fn bad_payload(what : String, raw : String) -> Unit {
  @core.log(
    @core.any("tutuca dyncomp: guest \{what} returned invalid JSON: \{raw}"),
  )
}

///|
fn parse_value(s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch {
    _ => {
      bad_payload("value", s)
      return Null
    }
  }
  @tutuca.Value::from_json(j)
}

///|
/// Values on their way INTO a guest — a message's arguments, a constructor's
/// arguments, a render call's bindings.
///
/// `child_json` rather than `to_json`, and the difference is the whole of what
/// an instance IS on the other side. `Value::to_json` has no form for an `Obj`
/// so it writes the object's FIELDS, which for a guest instance is a copy of
/// its state under a name that no longer refers to it: the guest stores a map,
/// answers reads with a map, and a `<x render>` over that field draws nothing.
/// What has to cross is the HANDLE.
///
/// `with_field` and `set_property` always did this; `create` and `dispatch`
/// did not, so an instance handed to a component as a constructor argument or
/// in a message was flattened on the way in — the same instance survived being
/// written to a field afterwards, which is what made it look like a rendering
/// bug rather than an encoding one.
fn args_json(args : Array[@tutuca.Value]) -> String {
  Json::array(args.map(v => @dyncomp.child_json(v))).stringify()
}

///|
/// The same, keyed. See `args_json`.
fn map_json(args : Map[String, @tutuca.Value]) -> String {
  let obj : Map[String, Json] = Map([])
  for name, v in args {
    obj[name] = @dyncomp.child_json(v)
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
          let out : Map[String, @tutuca.Value] = Map([])
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
  let j = @json.parse(s) catch {
    _ => {
      bad_payload("field value", s)
      return Null
    }
  }
  self.json_to_value(j)
}

///|
fn bucket_int(bucket : @tutuca.HandlerBucket) -> Int {
  @dyncomp.bucket_ordinal(bucket)
}

///|
/// One relative path step of a `send-at` / `intent-at` (WIT `path-step`, as
/// the bridge's JSON: `{"field": "left"}`, `{"item": ["seq", "k"]}` or
/// `{"at": ["seq", 3]}`).
fn path_step(j : Json) -> @tutuca.Step? {
  guard j is Object(o) else { return None }
  match o.get("field") {
    Some(String(name)) => return Some(FieldStep(name))
    _ => ()
  }
  match o.get("item") {
    Some(Array([String(field), String(key)])) =>
      return Some(SeqStep(field~, key=KStr(key)))
    _ => ()
  }
  match o.get("at") {
    Some(Array([String(field), Number(i, ..)])) =>
      return Some(SeqStep(field~, key=KInt(i.to_int())))
    _ => ()
  }
  None
}

///|
fn path_steps(j : Json?) -> Array[@tutuca.Step] {
  let out : Array[@tutuca.Step] = []
  match j {
    Some(Array(items)) =>
      for item in items {
        match path_step(item) {
          Some(s) => out.push(s)
          None => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// One buffered call's `value` field, for the two that carry a value and no
/// name (WIT `reply` / `fail`).
fn WasmGuest::value_field(
  self : WasmGuest,
  m : Map[String, Json],
  key : String,
) -> @tutuca.Value {
  match m.get(key) {
    Some(j) => self.json_to_value(j)
    None => Null
  }
}

///|
/// An intent's routing (WIT `intent-opts`), as the bridge's JSON.
///
/// An empty `route` means the DEFAULT, and the default is the host's to
/// supply — `IntentOpts::new` spells it in exactly one place, so a guest that
/// says nothing cannot disagree with it.
fn intent_opts(j : Json?) -> @tutuca.IntentOpts {
  guard j is Some(Object(o)) else { return @tutuca.IntentOpts::new() }
  let name = (key : String) => {
    match o.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  }
  let route : Array[@tutuca.Leg] = []
  if o.get("route") is Some(Array(legs)) {
    for leg in legs {
      match leg {
        String("dyn") => route.push(Dyn)
        String("lex") => route.push(Lex)
        _ => ()
      }
    }
  }
  if route.is_empty() {
    return @tutuca.IntentOpts::new(
      on_ok_name?=name("onOk"),
      on_error_name?=name("onError"),
      on_unhandled_name?=name("onUnhandled"),
      live_path=o.get("livePath") is Some(True),
    )
  }
  @tutuca.IntentOpts::new(
    route~,
    on_ok_name?=name("onOk"),
    on_error_name?=name("onError"),
    on_unhandled_name?=name("onUnhandled"),
    live_path=o.get("livePath") is Some(True),
  )
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
pub impl @dyncomp.Guest for WasmGuest with fn handle_dispatch(
  self,
  handle,
  bucket,
  name,
  args,
  bindings,
) {
  let raw = tcomp_dispatch(
    self.bundle,
    handle,
    bucket_int(bucket),
    name,
    args_json(args),
    map_json(bindings),
  )
  let empty : @dyncomp.DispatchResult = {
    handled: false,
    next: None,
    msgs: [],
  }
  let j = @json.parse(raw) catch {
    _ => {
      bad_payload("dispatch result", raw)
      return empty
    }
  }
  guard j is Object(o) else { return empty }
  let handled = o.get("handled") is Some(True)
  let next = match o.get("next") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let msgs : Array[@dyncomp.ControlMsg] = []
  match o.get("msgs") {
    Some(Array(items)) =>
      for item in items {
        guard item is Object(m) else { continue }
        // the one message with no name at all
        if m.get("kind") is Some(String("stopPropagation")) {
          msgs.push(StopPropagation)
          continue
        }
        let args = match m.get("args") {
          Some(Array(items)) => items.map(v => self.json_to_value(v))
          _ => []
        }
        // The three that carry no NAME, because they act on the intent that
        // arrived rather than starting one. Matched before the name guard, or
        // a `reply` would be dropped for lacking a field it never has.
        match m.get("kind") {
          Some(String("forward")) => {
            msgs.push(Forward(args, intent_opts(m.get("opts"))))
            continue
          }
          Some(String("reply")) => {
            msgs.push(Reply(self.value_field(m, "value")))
            continue
          }
          Some(String("fail")) => {
            msgs.push(Fail(self.value_field(m, "value")))
            continue
          }
          _ => ()
        }
        let name = match m.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        match m.get("kind") {
          Some(String("send")) => msgs.push(Send(name, args))
          Some(String("sendReply")) => msgs.push(SendReply(name, args))
          Some(String("sendAt")) =>
            msgs.push(SendAt(path_steps(m.get("path")), name, args))
          Some(String("intent")) =>
            msgs.push(Intent(name, args, intent_opts(m.get("opts"))))
          Some(String("intentAt")) =>
            msgs.push(
              IntentAt(
                path_steps(m.get("path")),
                name,
                args,
                intent_opts(m.get("opts")),
              ),
            )
          _ => ()
        }
      }
    _ => ()
  }
  { handled, next, msgs, }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn render_call(
  self,
  handle,
  category,
  name,
  args,
  bindings,
) {
  parse_value(
    tcomp_render_call(
      self.bundle,
      handle,
      category,
      name,
      args_json(args),
      map_json(bindings),
    ),
  )
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn get_property(self, handle, name) {
  let raw = tcomp_get_property(self.bundle, handle, name)
  if raw == "" {
    None
  } else {
    Some(parse_value(raw))
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn set_property(
  self,
  handle,
  name,
  value,
) {
  let raw = tcomp_set_property(
    self.bundle,
    handle,
    name,
    @dyncomp.child_json(value).stringify(),
  )
  let parsed = @json.parse(raw) catch { _ => return GuestPropertyMissing }
  match parsed {
    Object(m) =>
      match m.get("tag") {
        Some(String("changed")) =>
          match m.get("next") {
            Some(Number(n, ..)) => GuestPropertyChanged(n.to_int())
            _ => GuestPropertyRefused
          }
        Some(String("unchanged")) => GuestPropertyUnchanged
        Some(String("refused")) => GuestPropertyRefused
        _ => GuestPropertyMissing
      }
    _ => GuestPropertyMissing
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn with_field(self, handle, name, v) {
  let next = tcomp_with_field(
    self.bundle,
    handle,
    name,
    @dyncomp.child_json(v).stringify(),
  )
  if next < 0 {
    None
  } else {
    Some(next)
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn serve_intent(self, name, args) {
  let raw = tcomp_serve_intent(self.bundle, name, args_json(args))
  let j = @json.parse(raw) catch {
    _ => {
      bad_payload("serve_intent", raw)
      return Err(Str("guest request \{name} returned invalid JSON"))
    }
  }
  guard j is Object(o) else {
    return Err(Str("guest request \{name} returned a non-object"))
  }
  match o.get("ok") {
    Some(v) => Ok(self.json_to_value(v))
    None =>
      Err(
        match o.get("err") {
          Some(v) => self.json_to_value(v)
          None => Str("guest request \{name} answered neither ok nor err")
        },
      )
  }
}

///|
/// Base64 in the transport, bytes in the host: the decode happens here so that
/// everything above (`Snapshot`, `Store`) deals in one shape and the encoding
/// is a fact about this bridge rather than about persistence.
pub impl @dyncomp.Guest for WasmGuest with fn persist(self, handle) {
  let b64 = tcomp_persist(self.bundle, handle)
  if b64 == "" {
    b""
  } else {
    @base64.decode(b64[:]) catch {
      _ => {
        bad_payload("persist", b64)
        b""
      }
    }
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn restore(self, component, state) {
  let handle = tcomp_restore(self.bundle, component, @base64.encode(state[:]))
  if handle < 0 {
    None
  } else {
    Some(handle)
  }
}

///|
pub impl @dyncomp.Guest for WasmGuest with fn drop_instance(self, handle) {
  tcomp_drop_instance(self.bundle, handle)
}

// --- lifecycle glue ---

///|
let current : Ref[@app.App[@wdom.WasmNode]?] = { val: None, }

///|
let current_doc : Ref[@wdom.WasmNode?] = { val: None, }

///|
let bundles : Map[Int, @dyncomp.Bundle] = Map([])

///|
/// A registration's identity: `Bundle::key()` — the module AND the variables
/// it was registered with. What a hot swap replaces, and what keeps two
/// configurations of one archive from evicting each other.
let by_key : Map[String, Int] = Map([])

///|
/// A convenience index, name -> most recently registered bundle of that name.
///
/// This bridge's published surface addresses a bundle by module name, and that
/// stays true: naming one is what a page can write down. With two
/// configurations loaded the name alone is ambiguous, and "the last one
/// registered" is the answer that keeps the ordinary case — load, then mount
/// from the "dyncompLoaded" handler — reading exactly as it did.
///
/// A page that means a SPECIFIC configuration passes the key instead; every
/// lookup here goes through `find_bundle`, which takes either.
let by_name : Map[String, Int] = Map([])

///|
/// The bundle a page means, addressed by key or by module name.
///
/// Key first, because it is unambiguous and a name may not be: a page that
/// went to the trouble of holding a key gets the bundle it asked for rather
/// than whichever one loaded last.
fn find_bundle(which : String) -> @dyncomp.Bundle? {
  let bid = match by_key.get(which) {
    Some(bid) => bid
    None =>
      match by_name.get(which) {
        Some(bid) => bid
        None => return None
      }
  }
  bundles.get(bid)
}

///|
/// A guest for a loaded bundle, and the manifest it was registered from, for a
/// host that wants to register that module AGAIN somewhere else.
///
/// The case this exists for is driving a bundle's scenes: `tutucard/drive`
/// mounts a component on an in-memory DOM, one fresh `ComponentStack` per
/// scene, which means registering the module again — and registering needs a
/// `&Guest` and a `DynManifest`, neither of which this bridge published. A page
/// could reach the instantiated module and could not test it.
///
/// The guest is a NEW `WasmGuest` over the same instantiated module rather than
/// the one this bridge registered, and the difference is the whole reason this
/// is a function rather than a field. A guest carries the bundle it was last
/// registered as, so that a child token can be wrapped through the right one;
/// a driver rebinds that per scene. Handing back the live guest would leave the
/// page's own drawn instance wrapping through whichever scene ran last, which
/// is a drawn card quietly breaking because something tested it.
///
/// `None` when nothing by that name or key is loaded. Same addressing as every
/// other entry point here — see `find_bundle`.
pub fn guest_for(which : String) -> (&@dyncomp.Guest, @dyncomp.DynManifest)? {
  guard find_bundle(which) is Some(bundle) else { return None }
  guard by_key.get(bundle.key()) is Some(bid) else { return None }
  (
    (WasmGuest::{ bundle: bid, registered: { val: None, }, } : &@dyncomp.Guest),
    bundle.manifest(),
  )
  |> Some
}

///|
let next_load : Ref[Int] = { val: 1, }

///|
/// What this page will accept from a bundle. Every load is screened against it,
/// and a bundle that asks for something it does not grant is REFUSED — the
/// error reaches the page as `dyncompError` with the reasons.
///
/// Untrusted until a page says otherwise, which is the only safe default for a
/// loader whose whole purpose is to accept an archive from somewhere: a page
/// that has not thought about the question has not granted anything.
let policy : Ref[@policy.Policy] = { val: @policy.Policy::untrusted(), }

///|
/// Hand the live app to the glue after mounting (mirrors @wglue.install), and
/// subscribe the superseded-handle sweep to the app's drained cascades — after
/// the App's own re-render, since that is what still reads the successors.
///
/// `policy` is the page's answer to "what may a bundle I have never seen do
/// here". It belongs on this call rather than on each load because it is a
/// property of the HOST, not of an archive: a page that screened one bundle
/// more strictly than the next would be deciding by provenance, which is
/// exactly the thing a sandbox exists to avoid needing.
pub fn set_app(
  app : @app.App[@wdom.WasmNode],
  doc : @wdom.WasmNode,
  policy? : @policy.Policy = @policy.Policy::untrusted(),
) -> Unit {
  current.val = Some(app)
  current_doc.val = Some(doc)
  set_policy(policy)
  // The policy decides what a view may NAME; handing the app the SAME sanitizer
  // makes the render-time chain enforce it, so a policy permitting raw markup
  // cannot end up beside an app that would send the payload straight to
  // `set_inner_html`. The app builds the chain itself (`@mdfilter.filter_for`),
  // which is what keeps the two from being set from different values — and
  // there is no call that could take the chain away again.
  app.set_sanitizer(policy.sanitizer)
  // The same answer, for what an `@on` argument's `e.<path>` may read. The
  // registration screening (`screen_view` → `check_event_paths`) already
  // refused off-list paths in the views it accepted; this makes the runtime
  // resolver agree with that decision — the second fence, not a second
  // opinion.
  app.set_event_paths(policy.event_paths)
  @dyncomp.install_gc(app.transactor)
}

///|
/// Values dropped since the last call, oldest first, and clears the log.
///
/// The developer-facing half of the render-time sanitizer. `Policy::check_view`
/// settles what a view NAMES — every tag, attribute and handler name in a view
/// is a literal, so an allowlist over names is complete over the described part
/// of it. It cannot settle what a value HOLDS: `AttrItem::Plain` carries a
/// `Val`, so an `href` is an expression until it renders. `@filter.Baseline` is
/// the other half, and it runs between `render_root` and the diff — the one
/// point where the value is concrete and the DOM is untouched.
///
/// `App::new` installs it, for every tutuca app. What
/// is here is the reporting, which is still glue's job — by render
/// time there is no author to report to, since the value may have come from a
/// guest's state rather than from its template, so a page that wants to say
/// "this component tried to render a javascript: URL" drains this and shows it.
pub fn take_filter_reports() -> Array[String] {
  guard current.val is Some(app) else { return [] }
  app.take_filter_reports().map(@filter.Dropped::to_string)
}

///|
/// Change what this page accepts, for a host that decides after mounting (a
/// person approving a bundle, say). It applies to LOADS, so a bundle already
/// registered under the old answer stays registered: revoking is dropping the
/// bundle, not narrowing the policy.
pub fn set_policy(next : @policy.Policy) -> Unit {
  policy.val = next
}

///|
/// What this page currently accepts.
pub fn current_policy() -> @policy.Policy {
  policy.val
}

///|
/// Where each in-flight load's completion messages should be dispatched
/// (the loading component's own path, captured via ctx.path()); loads
/// without a path notify the root.
let notify_paths : Map[Int, @tutuca.DispatchPath] = Map([])

///|
/// Why a load did NOT register, by load id, for the JS side to read back.
///
/// The completion messages go to the APP — a `dyncompError` receive at the
/// path that started the load — which is the right channel for a page showing
/// a person what happened, and the wrong one for the code that CALLED load.
/// That caller is a JS promise, and until it can see a refusal it resolves the
/// same way for a bundle that registered and one that did not: the page says
/// "loaded", `loaded_components` is empty, and nothing anywhere says why.
///
/// So the reason is kept here too, and `load_error` hands it over once. Both
/// channels carry the same sentence; neither is the other's fallback.
let load_errors : Map[Int, String] = Map([])

///|
/// The next load id, with `path` recorded as where its completion messages
/// dispatch — pass `ctx.path()` from the loading handler so any component
/// anywhere in the tree can host bundles without root-level plumbing.
fn next_load_at(path : @tutuca.DispatchPath) -> Int {
  let id = next_load.val
  next_load.val = id + 1
  notify_paths[id] = path
  id
}

///|
/// Load a `.tutuca.tar.gz` bundle from a URL.
///
/// RETURNS BEFORE THE BUNDLE EXISTS. What comes back is the load's id, not a
/// loaded bundle: nothing is registered and no component of it can be
/// instantiated until completion arrives, via the exported dyncomp_on_loaded /
/// dyncomp_on_load_error callbacks, as a `dyncompLoaded(module_name, load_id)`
/// or `dyncompError(reason, load_id)` receive at `path`.
///
/// Exactly one of the two arrives for every load — the loader answers on every
/// failure path it has — so a host that waits for one does not hang, and a host
/// that reports success before one is reporting a download it started rather
/// than a component it mounted. Match on the id to answer the request that
/// began the load. See `docs/dynamic-components.md`.
pub fn load_url(path : @tutuca.DispatchPath, url : String) -> Int {
  let id = next_load_at(path)
  tcomp_load_url(url, id)
  id
}

///|
/// Load a dropped `.tutuca.tar.gz` bundle: `file_id` is what the drop event's
/// value named (`@on.drop="loadDropped e.value"` -> a list of file descriptors),
/// and completion messages dispatch at `path` like `load_url`. The drop is an
/// ordinary tutuca event, so the handler that acts on it is an ordinary handler.
pub fn load_dropped(path : @tutuca.DispatchPath, file_id : Int) -> Int {
  let id = next_load_at(path)
  tcomp_load_dropped(file_id, id)
  id
}

///|
/// Load a bundle the page BUILT: `archive_id` is what `registerArchive(bytes)`
/// in `dyncomp/host/wasm/loader.mjs` answered with, and completion arrives at
/// `path` like the other two.
///
/// For a page that generates bundles rather than fetching them, this is the
/// difference between handing over bytes and staging them behind an object URL
/// only to fetch them back — which is not merely a detour: the URL has to
/// survive the round trip through wasm, and revoking it is a race in both
/// directions. A page that has the archive says so.
///
/// The id is consumed by this call. Register the bytes where you load them.
pub fn load_bytes(path : @tutuca.DispatchPath, archive_id : Int) -> Int {
  let id = next_load_at(path)
  tcomp_load_bytes(archive_id, id)
  id
}

///|
/// Answer the load, at the path that asked for it.
///
/// The load id is appended to every message rather than left to the callers,
/// because it is what makes a completion ATTRIBUTABLE and a caller that forgot
/// it would be indistinguishable from one that had nothing to say. Success
/// already names its module, but a failure has only a reason — and a host with
/// two loads in flight cannot tell whose reason it is without this.
///
/// The path is taken out BEFORE the app guard: an unmounted app is the one
/// case where nothing is delivered, and leaving the entry behind would keep a
/// finished load's path alive for as long as the page.
fn notify(load_id : Int, name : String, args : Array[@tutuca.Value]) -> Unit {
  let at = notify_paths.get(load_id)
  notify_paths.remove(load_id) |> ignore
  guard current.val is Some(app) else { return }
  let args = [..args, @tutuca.Value::Num(load_id.to_double())]
  match at {
    Some(path) => {
      let _ = app.transactor.push_send(path, name, args)
      app.transactor.settle() |> ignore
    }
    None => app.send_at_root(name, args~) |> ignore
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
  let registered : Ref[@dyncomp.Bundle?] = { val: None, }
  let bundle = try {
    let manifest = @dyncomp.DynManifest::from_json_string(manifest_json)
    @dyncomp.register_bundle(
      app.scope,
      WasmGuest::{ bundle: bundle_id, registered, },
      manifest,
      policy=policy.val,
    )
  } catch {
    // Registration has ONE failure mode from a page's point of view — the
    // bundle was refused — and exactly one thing worth showing: why. The
    // reasons are a person's to act on ("this host takes no CSS from a
    // bundle", "no such component"), so they reach the page rather than
    // collapsing into a generic sentence.
    e => {
      load_errors[load_id] = e.message()
      notify(load_id, "dyncompError", [Str(e.message())])
      return
    }
  }
  registered.val = Some(bundle)
  // Before anything can construct an instance: the guest reads these through
  // `config.get`, and the first call that could reach it is a `create` from a
  // "dyncompLoaded" handler further down.
  tcomp_set_bundle_config(
    bundle_id,
    Json::object(
      Map::from_iter(
        bundle.config().iter().map(pair => (pair.0, Json::string(pair.1))),
      ),
    ).stringify(),
  )
  // A guest's views are the one part that never went through a build step, so
  // the lint findings are the only feedback its author gets. Console, not the
  // app: they are advice about the bundle, not a state change in the page.
  for line in bundle.diagnostics() {
    @core.log(@core.any("tutuca dyncomp [\{bundle.module_name()}]: \{line}"))
  }
  // Keyed on `Bundle::key()`, not the module name: a bundle's identity is the
  // code AND the variables it was registered with. Two readers of one archive
  // pointed at two servers are different components that happen to share a
  // module name, and keying on the name alone made loading the second retire
  // the first — which is not a hot swap, it is a page losing a card.
  //
  // Reloading with the SAME variables still replaces, because the key is the
  // same. That is what hot swap always meant; it just now says so.
  let old_bid = by_key.get(bundle.key())
  bundles[bundle_id] = bundle
  by_key[bundle.key()] = bundle_id
  // ...and the name index alongside it, not instead of it. Every entry point
  // this bridge publishes takes a module NAME — `make_instance("mastodonlib",
  // "Status", …)` is what a page writes — and `find_bundle` reads this map
  // when the string is not a key. Setting only `by_key` above left every one
  // of them answering None.
  by_name[bundle.module_name()] = bundle_id
  // The catalog is kept HERE rather than by whoever asks for it, because this
  // is the code that already knows about a load, a hot swap and a drop. A
  // second copy somewhere else would be a second thing to keep in sync.
  catalog.register(bundle)
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
/// Every component every loaded bundle declares, searchable.
///
/// A hot swap re-registers under the same module name, which is exactly what
/// `Registry::register` means, so the catalog answers with the new components
/// the moment the old bundle is retired.
let catalog : @registry.Registry = @registry.Registry::new()

///|
/// The catalog, for a page that wants to search it — the universal UI does.
pub fn registry() -> @registry.Registry {
  catalog
}

///|
/// Wire this to the demo's exported `dyncomp_on_load_error`.
pub fn on_load_error(load_id : Int, msg : String) -> Unit {
  load_errors[load_id] = msg
  notify(load_id, "dyncompError", [Str(msg)])
}

///|
/// Why load `load_id` was refused, or "" if it was not.
///
/// Answerable at any point after the load finishes, and answerable more than
/// once: the JS bridge asks the moment `dyncomp_on_loaded` returns, so it can
/// drop the bundle it registered on its side and say so in the console, and a
/// host asks whenever it wants to know whether the load it started actually
/// produced components. Both are the same question and neither consumes the
/// other's answer.
///
/// Only a REFUSED load leaves a row here, so the table holds one string per
/// bundle a page tried and failed to register — a handful over a session, and
/// nothing at all for a page whose loads all work.
pub fn load_error(load_id : Int) -> String {
  load_errors.get(load_id).unwrap_or("")
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
  guard find_bundle(module_name) is Some(bundle) else { return None }
  match bundle.migrate_instance(old, component) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// The component names a loaded module declares, in manifest order. Empty if
/// the module is not loaded. Lets a host mount every component of a freshly
/// loaded bundle without hard-coding names.
pub fn bundle_component_names(module_name : String) -> Array[String] {
  guard find_bundle(module_name) is Some(bundle) else { return [] }
  bundle.component_names()
}

///|
/// Every currently-loaded component as (module_name, component_name) pairs,
/// across all registered bundles, so a picker can enumerate what can be
/// mounted. Part of this bridge's published surface: no page in this repo
/// calls it — `dyncomp/storybook` walks the bundles itself — but a host that
/// wants a picker needs an enumeration it does not have to keep itself.
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
/// The named initial states a loaded component declares (see
/// `Bundle::init_names`). Empty when the module or component is unknown.
pub fn component_inits(
  module_name : String,
  component : String,
) -> Array[String] {
  guard find_bundle(module_name) is Some(bundle) else { return [] }
  bundle.init_names(component)
}

///|
/// Create an instance from one of the component's NAMED initial states.
pub fn make_init(
  module_name : String,
  component : String,
  init : String,
) -> @tutuca.Value? {
  guard find_bundle(module_name) is Some(bundle) else { return None }
  match bundle.make_init(component, init) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// Create an instance of a loaded bundle's component as a tree value.
pub fn make_instance(
  module_name : String,
  component : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value? {
  guard find_bundle(module_name) is Some(bundle) else { return None }
  match bundle.make_instance(component, args~) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// Create an instance with a persist id the CALLER chose — the name a store
/// keys it on. A page that knows where an instance lives (a slot in a saved
/// document, a row in a list) has a better name for it than the one a bundle
/// mints, and a name that survives a reload is the whole point.
pub fn make_instance_at(
  module_name : String,
  component : String,
  pid : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value? {
  guard find_bundle(module_name) is Some(bundle) else { return None }
  match bundle.make_instance(component, args~, pid~) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// What this instance would be stored as, or None for a value no loaded bundle
/// claims. The module is read off the instance's own schema, so a page holding
/// a mixed bag of components does not have to remember which bundle each one
/// came from.
pub fn snapshot(v : @tutuca.Value) -> @persist.Snapshot? {
  guard v is Obj(o) else { return None }
  guard o.obj_schema() is Some(schema) else { return None }
  for _, bundle in bundles {
    if bundle.def_of(schema.name) is Some(_) {
      return bundle.snapshot(v)
    }
  }
  None
}

///|
/// The inverse: a stored snapshot back into a live instance, through the
/// bundle it names. None when that bundle is not loaded — which is the honest
/// answer, and why a page that restores a session loads its bundles first.
///
/// `src` is where a component nested in the stored fields resolves — what a
/// person put in a placeholder, which may be standard, may be another
/// bundle's, and is not this bundle's to name. A page restoring a session has
/// one and should pass it; without it the placeholder comes back empty.
pub fn restore(
  snap : @persist.Snapshot,
  src? : &@tutuca.ComponentSource,
) -> @tutuca.Value? {
  // A snapshot names its bundle the way everything else here does — by key or
  // by module name. Sessions taken before config vars existed carry a module
  // name, and they still restore.
  guard find_bundle(snap.module_) is Some(bundle) else { return None }
  match bundle.restore(snap, src?) {
    Some(d) => Some(d.to_value())
    None => None
  }
}

///|
/// The live app's settled root value (for inspection/state display).
pub fn app_root_value() -> @tutuca.Value? {
  guard current.val is Some(app) else { return None }
  Some(app.root_value())
}

///|
/// Drop a whole bundle (guest instances included). Phase 3 will track live
/// instance handles; for now this only clears the tables and the JS side.
/// Takes a key or a module name, like every other lookup here. Dropping BY
/// NAME with two configurations loaded drops the one `by_name` points at — the
/// most recent — and leaves the other; a page that means a specific one says
/// so with its key.
pub fn drop_bundle(which : String) -> Unit {
  guard find_bundle(which) is Some(bundle) else { return }
  guard by_key.get(bundle.key()) is Some(bid) else { return }
  by_key.remove(bundle.key()) |> ignore
  bundles.remove(bid) |> ignore
  tcomp_drop_bundle(bid)
  // The name index and the catalog are keyed by module name, so they only
  // stop pointing at this bundle if no OTHER registration of the same name is
  // still live. Forgetting either unconditionally would take a sibling's
  // catalog entry down with this one.
  let name = bundle.module_name()
  let mut survivor : Int? = None
  for other_bid in by_key.values() {
    if bundles.get(other_bid) is Some(b) && b.module_name() == name {
      survivor = Some(other_bid)
    }
  }
  match survivor {
    Some(other) => by_name[name] = other
    None => {
      catalog.forget(name)
      by_name.remove(name) |> ignore
    }
  }
}
