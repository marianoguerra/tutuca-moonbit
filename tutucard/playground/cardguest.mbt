// The compiled card, mounted — the other half of the boundary `card-wasm.js`
// holds.
//
// The page next door compiles a card to a `tutuca:component@0.7.0` core module
// and hands you the archive. That proves the BYTES are right. It does not prove
// the module runs, and until something instantiated one and asked it for a
// field, "this page produced a real guest" was a claim about a download.
//
// So: `card-wasm.js` instantiates the module through the host's own `abi.mjs`
// and installs five calls on `globalThis.__cardguest`; this implements
// `dyncomp`'s `&Guest` over them, registers the manifest as an ordinary bundle
// and mounts an instance. Nothing here is card-specific once the module is
// running — `register_bundle` is the same call the universal host makes, and
// what it registers is what a `.tutuca.tar.gz` dropped on that page would be.
//
// It is the js-target twin of `dyncomp/host/wasm/glue.mbt`, minus everything a
// compiled card cannot reach: no bundle table (this page holds one card), no
// load lifecycle (the page already has the bytes), no `$dyn` child markers (the
// generator emits no `make-instance`, so a guest value is never another
// instance), and no capability plumbing (`loadGuest` binds an empty grants
// list, and `abi.mjs` screens the module's IMPORT SECTION rather than anything
// the manifest claims — so a card that asked for a clock is refused before any
// of this runs).

///|
/// Whether a compiled card has been instantiated on this page.
extern "js" fn cardguest_ready() -> Bool =
  #|() => !!globalThis.__cardguest

///|
extern "js" fn cardguest_create(component : String, args_json : String) -> Int =
  #|(component, args) => globalThis.__cardguest.create(component, args)

///|
extern "js" fn cardguest_get_field(handle : Int, name : String) -> String =
  #|(handle, name) => globalThis.__cardguest.getField(handle, name)

///|
extern "js" fn cardguest_dispatch(
  handle : Int,
  bucket : Int,
  name : String,
  args_json : String,
) -> String =
  #|(handle, bucket, name, args) => globalThis.__cardguest.dispatch(handle, bucket, name, args)

///|
extern "js" fn cardguest_call_method(
  handle : Int,
  name : String,
  args_json : String,
) -> String =
  #|(handle, name, args) => globalThis.__cardguest.callMethod(handle, name, args)

///|
extern "js" fn cardguest_with_field(
  handle : Int,
  name : String,
  value_json : String,
) -> Int =
  #|(handle, name, value) => globalThis.__cardguest.withField(handle, name, value)

// --- value codecs ----------------------------------------------------------
//
// Plain JSON in both directions, which is the whole codec. The wasm-gc bridge
// additionally decodes `{"$dyn": …}` markers into child instances at any depth;
// there is nothing to decode here, because a compiled card has no
// `make-instance` to produce one with.

///|
fn value_of(s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch { _ => return Null }
  @tutuca.Value::from_json(j)
}

///|
fn list_json(args : Array[@tutuca.Value]) -> String {
  Json::array(args.map(v => v.to_json())).stringify()
}

///|
fn fields_json(args : Map[String, @tutuca.Value]) -> String {
  let obj : Map[String, Json] = Map([])
  for name, v in args {
    obj[name] = v.to_json()
  }
  Json::object(obj).stringify()
}

///|
/// WIT order, which is what the bridge counts in: 0=input, 1=receive,
/// 2=response, 3=bubble.
fn bucket_int(bucket : @tutuca.HandlerBucket) -> Int {
  match bucket {
    Input => 0
    Receive => 1
    Response => 2
    Bubble => 3
  }
}

// --- the Guest impl over __cardguest ---------------------------------------

///|
/// A card has one instantiated module per page, so there is nothing to key on:
/// where `WasmGuest` carries a bundle id, this carries nothing at all.
struct CardGuest {}

///|
impl @dyncomp.Guest for CardGuest with fn create(_self, component, args) {
  cardguest_create(component, fields_json(args))
}

///|
impl @dyncomp.Guest for CardGuest with fn get_field(_self, handle, name) {
  let raw = cardguest_get_field(handle, name)
  if raw == "" {
    None
  } else {
    Some(value_of(raw))
  }
}

///|
impl @dyncomp.Guest for CardGuest with fn dispatch(
  _self,
  handle,
  bucket,
  name,
  args,
) {
  let raw = cardguest_dispatch(
    handle,
    bucket_int(bucket),
    name,
    list_json(args),
  )
  let empty : @dyncomp.DispatchResult = { handled: false, next: None, msgs: [] }
  let j = @json.parse(raw) catch { _ => return empty }
  guard j is Object(o) else { return empty }
  let handled = o.get("handled") is Some(True)
  let next = match o.get("next") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  // Three kinds, and three is all there is: the generator emits no `send-at`,
  // `bubble-at` or `request`, so `card-wasm.js` binds those imports to nothing
  // and they never reach this list.
  let msgs : Array[@dyncomp.ControlMsg] = []
  match o.get("msgs") {
    Some(Array(items)) =>
      for item in items {
        guard item is Object(m) else { continue }
        if m.get("kind") is Some(String("stopPropagation")) {
          msgs.push(StopPropagation)
          continue
        }
        let name = match m.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        let args = match m.get("args") {
          Some(Array(items)) => items.map(v => @tutuca.Value::from_json(v))
          _ => []
        }
        match m.get("kind") {
          Some(String("emit")) => msgs.push(Emit(name, args))
          Some(String("send")) => msgs.push(Send(name, args))
          _ => ()
        }
      }
    _ => ()
  }
  { handled, next, msgs }
}

///|
impl @dyncomp.Guest for CardGuest with fn call_method(_self, handle, name, args) {
  value_of(cardguest_call_method(handle, name, list_json(args)))
}

///|
impl @dyncomp.Guest for CardGuest with fn with_field(_self, handle, name, v) {
  let next = cardguest_with_field(
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
/// A card declares no `requests`, so there is no name this could answer to.
/// Refusing by name is the honest reply, and it is what the host does with any
/// request nobody claimed.
impl @dyncomp.Guest for CardGuest with fn handle_request(_self, name, _args) {
  Err(
    Str("a compiled card answers no requests, and this one asked for '\{name}'"),
  )
}

///|
/// A compiled card exports no `persist`, so it has no state of its own to hand
/// over and none to take back. Empty bytes are what a guest that does not
/// persist answers, and `None` is the guest refusing them — which is what the
/// host expects from one that never wrote any.
impl @dyncomp.Guest for CardGuest with fn persist(_self, _handle) {
  b""
}

///|
impl @dyncomp.Guest for CardGuest with fn restore(_self, _component, _state) {
  None
}

///|
/// The JS side holds instances in a table keyed by handle and drops the whole
/// table with the module, so there is nothing to free one at a time.
impl @dyncomp.Guest for CardGuest with fn drop_instance(_self, _handle) {

}

// --- mounting --------------------------------------------------------------

///|
/// What this page will accept from a compiled card.
///
/// `granted` rather than `untrusted`, and the difference is one thing: an
/// untrusted bundle may carry no `<style>` block, and most cards on this page
/// have one. That rule is right where it is — a host taking an archive from
/// somewhere has no reason to let it write CSS — and wrong here, because the
/// bundle was compiled from the source in the editor two panes away. The reader
/// wrote it; there is nobody else to vouch.
///
/// What it does NOT widen is what the module can do, because that was settled
/// before this ran: `loadGuest` binds an empty grants list and `abi.mjs` checks
/// the module's import section, so a card asking for a capability is refused at
/// instantiation whatever this says.
fn card_policy() -> @policy.Policy {
  @policy.Policy::granted()
}

///|
fn mount_failed(msg : String) -> String {
  Json::object({ "ok": Json::boolean(false), "error": Json::string(msg) }).stringify()
}

///|
/// Register the instantiated card as a dyncomp bundle and mount an instance
/// into the element with this id.
///
/// The page calls `loadGuest` first — that is what puts the module behind
/// `globalThis.__cardguest` — and passes the manifest the SAME compile
/// produced. They travel together on purpose: a manifest's field list is the
/// order `get-field` answers in, so a manifest paired with a different module is
/// a bundle whose halves disagree.
///
/// The instance is the app's ROOT rather than a child of some host component,
/// which is what `App::new` taking a value makes possible. There is nothing for
/// a wrapper to do here: the card is the whole of what this pane shows.
///
/// Answers the same shape the other entry points do — `ok: false` with a reason
/// a person can act on, since every failure here is either the module being
/// refused or a manifest the host will not take.
pub fn mount_compiled(id : String, manifest_json : String) -> String {
  // The same teardown-first order every mount here uses, and for the same
  // reason: the app holds transactor subscriptions and DOM listeners, and
  // pressing the button twice would otherwise leave the first set behind.
  teardown(id)
  guard cardguest_ready() else {
    return mount_failed("no compiled card is instantiated on this page")
  }
  let doc = @dom.window().document()
  guard doc.getElementById(id) is Some(root_el) else {
    return mount_failed("there is no element with id '\{id}' to mount into")
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  root_node.replace_children()
  let scope = @component.ComponentStack::new()
  let policy = card_policy()
  let bundle = try {
    let manifest = @dyncomp.DynManifest::from_json_string(manifest_json)
    @dyncomp.register_bundle(scope, CardGuest::{  }, manifest, policy~)
  } catch {
    // Registration has one failure mode from a page's point of view — the
    // bundle was refused — and one thing worth showing: why. The reasons are a
    // person's to act on, so they reach the page rather than collapsing into a
    // sentence about mounting.
    e => return mount_failed(e.message())
  }
  guard bundle.component_names() is [component, ..] else {
    return mount_failed("the manifest declares no component to mount")
  }
  guard bundle.make_instance(component) is Some(inst) else {
    return mount_failed("the guest would not create a '\{component}'")
  }
  let app = @app.App::new(
    scope,
    inst.to_value(),
    root_node,
    @bdom.opts_for(doc),
  ) catch {
    _ => return mount_failed("the bundle's views did not compile into an app")
  }
  // The policy decides what a view may NAME; the same sanitizer makes the
  // render-time chain enforce it, so a policy is not half-applied by being
  // checked at registration and forgotten at render.
  app.set_sanitizer(policy.sanitizer)
  @dyncomp.install_gc(app.transactor)
  app.start()
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  // Into the same slot table the interpreted cards use, which is what makes
  // `unmount` and `classesAt` work over this mount without knowing it is a
  // compiled one.
  slot_of(id).app = Some(app)
  // tutuca has no lifecycle: the HOST dispatches `init`, exactly as it does for
  // the interpreted card in the pane beside this one.
  app.send_at_root("init") |> ignore
  Json::object({
    "ok": Json::boolean(true),
    "component": Json::string(component),
    "module": Json::string(bundle.module_name()),
    // A guest's views went through no build step, so these findings are the
    // only feedback its author gets.
    "diagnostics": Json::array(bundle.diagnostics().map(Json::string)),
  }).stringify()
}
