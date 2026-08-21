// The compiled card, mounted — the other half of the boundary `card-wasm.js`
// holds.
//
// The page next door compiles a card to a `tutuca:component@0.9.0` core module
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
extern "js" fn cardguest_ready(key : String) -> Bool =
  #|(key) => !!(globalThis.__cardguest && globalThis.__cardguest[key])

///|
/// Everything the instantiated card has logged since this was last asked.
///
/// `control.log` is the one call on the control interface no capability gates,
/// and for a compiled card it carries the thing an author is most likely to get
/// wrong: a `requires`, an `ensures` or an `invariant` that did not hold, with
/// the rule's own `format` sentence evaluated over the state that was rejected.
/// A host component raises a structured `Refusal` for the same event; a guest
/// has no shape to put one in, so this is the whole of what a card can say —
/// and a driver that could not read it could not tell a declined guard from a
/// click that missed.
extern "js" fn cardguest_drop(key : String, handle : Int) -> Unit =
  #|(key, handle) => globalThis.__cardguest[key].dropInstance(handle)

///|
/// Keep only these handles; drop the rest. Answers how many went.
extern "js" fn cardguest_retain(key : String, handles_json : String) -> Int =
  #|(key, handles) => globalThis.__cardguest[key].retain(handles)

///|
extern "js" fn cardguest_take_log(key : String) -> String =
  #|(key) => globalThis.__cardguest[key].takeLog()

///|
extern "js" fn cardguest_create(
  key : String,
  component : String,
  args_json : String,
) -> Int =
  #|(key, component, args) => globalThis.__cardguest[key].create(component, args)

///|
extern "js" fn cardguest_get_field(
  key : String,
  handle : Int,
  name : String,
) -> String =
  #|(key, handle, name) => globalThis.__cardguest[key].getField(handle, name)

///|
extern "js" fn cardguest_dispatch(
  key : String,
  handle : Int,
  bucket : Int,
  name : String,
  args_json : String,
) -> String =
  #|(key, handle, bucket, name, args) => globalThis.__cardguest[key].dispatch(handle, bucket, name, args)

///|
extern "js" fn cardguest_call_method(
  key : String,
  handle : Int,
  name : String,
  args_json : String,
) -> String =
  #|(key, handle, name, args) => globalThis.__cardguest[key].callMethod(handle, name, args)

///|
extern "js" fn cardguest_with_field(
  key : String,
  handle : Int,
  name : String,
  value_json : String,
) -> Int =
  #|(key, handle, name, value) => globalThis.__cardguest[key].withField(handle, name, value)

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
/// WIT order, which is what the bridge counts in: 0=receive, 1=intent.
fn bucket_int(bucket : @tutuca.HandlerBucket) -> Int {
  @dyncomp.bucket_ordinal(bucket)
}

// --- the Guest impl over __cardguest ---------------------------------------

///|
/// Which instantiated module this guest speaks to.
///
/// The key is the MOUNT POINT's element id, and there used to be no key at all:
/// a page held one compiled card, deliberately loaded by pressing a button, so
/// `globalThis.__cardguest` could be one object. Every card is compiled now, and
/// a page with two `<mb-card>` embeds has two modules with two instance tables
/// — so a guest has to say which one it means, exactly as `WasmGuest` carries a
/// bundle id.
struct CardGuest {
  key : String
  /// The bundle this guest was registered as, once it has been.
  ///
  /// Set after `register_bundle` and before the first instance is made, which
  /// is the only order that works: a child token arriving from the guest is a
  /// handle and a component NAME, and only the bundle knows how to wrap that
  /// pair as a `DynObj` the render stack will place. A guest that has not been
  /// registered yet cannot receive one, because nothing has called it.
  registered : Ref[@dyncomp.Bundle?]
}

///|
/// Bridge JSON into a Value, wrapping a child marker as the instance it stands
/// for — at ANY depth, lists and maps included.
///
/// `{"$dyn": {"handle": n, "comp": s}}` is the shape both hosts write, so this
/// is `dyncomp/host/wasm/glue.mbt`'s `json_to_value` with a different bundle
/// behind it. A card used to need none of it: the generator emitted no
/// `make-instance`, so a guest value was never another instance.
fn CardGuest::json_to_value(self : CardGuest, j : Json) -> @tutuca.Value {
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
/// The same, from the bridge's raw string.
fn CardGuest::value_of(self : CardGuest, s : String) -> @tutuca.Value {
  let j = @json.parse(s) catch { _ => return Null }
  self.json_to_value(j)
}

///|
impl @dyncomp.Guest for CardGuest with fn create(self, component, args) {
  cardguest_create(self.key, component, fields_json(args))
}

///|
impl @dyncomp.Guest for CardGuest with fn get_field(self, handle, name) {
  let raw = cardguest_get_field(self.key, handle, name)
  if raw == "" {
    None
  } else {
    Some(self.value_of(raw))
  }
}

///|
impl @dyncomp.Guest for CardGuest with fn dispatch(
  self,
  handle,
  bucket,
  name,
  args,
) {
  let raw = cardguest_dispatch(
    self.key,
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
  // `intent-at` is the one the generator still cannot emit, so `card-wasm.js`
  // binds that import to nothing and it never reaches this list. An intent's
  // `opts` DOES cross, because the route is the one part of it a card writes
  // at the call site.
  let msgs : Array[@dyncomp.ControlMsg] = []
  match o.get("msgs") {
    Some(Array(items)) =>
      for item in items {
        guard item is Object(m) else { continue }
        if m.get("kind") is Some(String("stopPropagation")) {
          msgs.push(StopPropagation)
          continue
        }
        let args = match m.get("args") {
          Some(Array(items)) => items.map(v => @tutuca.Value::from_json(v))
          _ => []
        }
        // The three that carry no NAME, because they act on the intent that
        // arrived rather than starting one. Handled before the name guard, or
        // a `reply` would be dropped for lacking a field it never has.
        match m.get("kind") {
          Some(String("forward")) => {
            msgs.push(Forward(args, intent_opts(m.get("opts"))))
            continue
          }
          Some(String("reply")) => {
            msgs.push(Reply(value_field(m, "value")))
            continue
          }
          Some(String("fail")) => {
            msgs.push(Fail(value_field(m, "value")))
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
          Some(String("sendAt")) =>
            msgs.push(SendAt(path_steps(m.get("path")), name, args))
          Some(String("intent")) =>
            msgs.push(Intent(name, args, intent_opts(m.get("opts"))))
          _ => ()
        }
      }
    _ => ()
  }
  { handled, next, msgs }
}

///|
/// The one value a `reply` or a `fail` carries, as `card-wasm.js` sends it.
fn value_field(m : Map[String, Json], key : String) -> @tutuca.Value {
  match m.get(key) {
    Some(j) => @tutuca.Value::from_json(j)
    None => Null
  }
}

///|
/// An intent's routing (WIT `intent-opts`), as the bridge's JSON.
///
/// The twin of `dyncomp/host/wasm/glue.mbt`'s, and a copy for the same reason
/// `path_step` is one: that one is the wasm-gc host's and this page is the js
/// one, and what they share is the JSON rather than the code.
///
/// An empty `route` means the DEFAULT, and the default is the host's to
/// supply — `IntentOpts::new()` with no argument is the one place `dyn lex` is
/// written down, so a card that wrote no leg cannot disagree with it. A card
/// never names an answer arm, but the names are read anyway: the shape is the
/// contract's, not the generator's.
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
/// One relative path step of a `sendAt`, as `card-wasm.js` spells it:
/// `{"field": "left"}`, `{"item": ["seq", "k"]}` or `{"at": ["seq", 3]}`.
///
/// The twin of `dyncomp/host/wasm/glue.mbt`'s, and deliberately a copy rather
/// than a shared function: that one is the wasm-gc host's and this page is the
/// js one, and the thing they share is the JSON rather than the code. Three
/// cases is a small enough thing to say twice; the spelling is what has to
/// agree, and `stepToJson` in both loaders is where it is said once.
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
impl @dyncomp.Guest for CardGuest with fn call_method(self, handle, name, args) {
  self.value_of(cardguest_call_method(self.key, handle, name, list_json(args)))
}

///|
impl @dyncomp.Guest for CardGuest with fn with_field(self, handle, name, v) {
  let next = cardguest_with_field(
    self.key,
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
impl @dyncomp.Guest for CardGuest with fn serve_intent(_self, name, _args) {
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
/// Release one instance.
///
/// It used to do nothing, on the grounds that the table goes with the module —
/// which is true and was never the whole story. A card is copy-on-write, so
/// EVERY keystroke supersedes a handle: the host's GC has been collecting them
/// since it was written and handing them to a guest that dropped nothing, and
/// a card left open grew a table entry per interaction.
impl @dyncomp.Guest for CardGuest with fn drop_instance(self, handle) {
  cardguest_drop(self.key, handle)
}

///|
/// Collect what nothing points at, at the end of every drained cascade.
///
/// Installed AFTER `install_gc`, and after the App's own re-render: subscribers
/// run in subscription order, so by the time this reads the root the superseded
/// handles are gone and the render that needed them has happened.
fn install_sweep(
  key : String,
  root : () -> @tutuca.Value,
  tx : @transactor.Transactor,
) -> Unit {
  tx.on_drained(() => {
    let live : Array[Int] = []
    live_handles(root(), live)
    cardguest_retain(
      key,
      Json::array(live.map(h => Json::number(h.to_double()))).stringify(),
    )
    |> ignore
  })
}

///|
/// Every instance handle still reachable from `root`.
///
/// The superseded GC collects a handle a SUCCESSOR replaced, which is the
/// churn. It cannot collect one that was simply dropped: `.items.deleteAt 0`
/// gives the list a successor and the removed child was never superseded by
/// anything — it is just gone, and nothing was watching the place it left.
///
/// So the other half is reachability, which the host can answer because it
/// holds the root: walk the tree, keep what is found. A card is one bundle with
/// one table, which is what makes a sweep affordable here and not in general.
fn live_handles(v : @tutuca.Value, out : Array[Int]) -> Unit {
  match v {
    Obj(o) => {
      match o.obj_field(@dyncomp.handle_field) {
        Some(Num(h)) => {
          let handle = h.to_int()
          // A cycle cannot happen — a child is made before its parent holds it
          // — but a diamond can: two fields naming one child. Stopping at a
          // handle already seen keeps the walk linear either way.
          if out.contains(handle) {
            return
          }
          out.push(handle)
        }
        _ => ()
      }
      // Into its DECLARED fields, which is the only list of them there is.
      match o.obj_schema() {
        Some(sc) =>
          for f in sc.fields {
            match o.obj_field(f.name) {
              Some(fv) => live_handles(fv, out)
              None => ()
            }
          }
        None => ()
      }
    }
    List(items) =>
      for item in items {
        live_handles(item, out)
      }
    Map(entries) =>
      for _k, item in entries {
        live_handles(item, out)
      }
    _ => ()
  }
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
  guard cardguest_ready(id) else {
    return mount_failed("no compiled card is instantiated on this page")
  }
  let doc = @dom.window().document()
  guard doc.getElementById(id) is Some(root_el) else {
    return mount_failed("there is no element with id '\{id}' to mount into")
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  root_node.replace_children()
  let scope = @component.ComponentStack::new()
  // The page's intent fixtures, in the scope OUTSIDE the bundle's own. The
  // `lex` leg walks child -> parent, so a compiled card's `intent lex 'rows'`
  // is offered to its bundle's own handlers first — it registers none — and
  // then to these.
  let slot = slot_of(id)
  scope.register_intent_handlers(playground_intents(slot, slot.gen))
  let policy = card_policy()
  // The guest is built BEFORE it is registered and told about the bundle
  // afterwards, which is the only order available: `register_bundle` takes the
  // guest, and the guest needs the bundle to wrap a child token. Nothing can
  // call the guest in between.
  let guest = CardGuest::{ key: id, registered: Ref::new(None) }
  let bundle = try {
    let manifest = @dyncomp.DynManifest::from_json_string(manifest_json)
    @dyncomp.register_bundle(scope, guest, manifest, policy~)
  } catch {
    // Registration has one failure mode from a page's point of view — the
    // bundle was refused — and one thing worth showing: why. The reasons are a
    // person's to act on, so they reach the page rather than collapsing into a
    // sentence about mounting.
    e => return mount_failed(e.message())
  }
  guest.registered.val = Some(bundle)
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
  // …and the sweep, after it. `install_gc` drops what a successor replaced;
  // this drops what nothing points at any more. Subscribers run in
  // subscription order, so by the time this reads the root the superseded ones
  // are already gone and the render that needed them has run.
  install_sweep(id, () => app.root_value(), app.transactor)
  app.start()
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  // Into the same slot table `unmount` and `classesAt` read, which is what lets
  // those two work over this mount without knowing anything about it.
  slot.app = Some(app)
  // …and the activity panel, which reads what the transactor saw. This used to
  // be installed by the interpreted mount next door, and there is no
  // interpreted mount any more.
  app.transactor.observe(record => {
    slot.activity.push(record.to_json())
    if slot.activity.length() > ACTIVITY_CAP {
      slot.activity.remove(0) |> ignore
    }
  })
  |> ignore
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

///|
/// Drive the instantiated card's scenes, headless, and answer the report.
///
/// The other thing a compiled card is good for, and the one a page cannot do:
/// `mount_compiled` puts a card on a SCREEN, which proves it renders and
/// proves nothing about what it does when pressed. This mounts the same
/// bundle on the in-memory DOM instead, runs the block's steps through the
/// same transactor, and hands back the rendered HTML — so a card can be
/// checked by something with no page at all, which is what a build step and an
/// agent both are.
///
/// `scenes_json` overrides the card's own `<script type="tutuca/test">` block.
/// Empty means "use the block", and an override is what lets a card that
/// declares no tests be driven anyway — the case an agent is in when it has
/// just written one and wants to see what it does.
///
/// The manifest travels from the SAME compile the module came from, for the
/// reason `mount_compiled` gives: a manifest's field list is the order
/// `get-field` answers in, so one paired with a different module is a bundle
/// whose halves disagree.
pub fn drive(
  key : String,
  manifest_json : String,
  source : String,
  scenes_json : String,
) -> String {
  guard cardguest_ready(key) else {
    return drive_failed("no compiled card is instantiated on this page")
  }
  let scenes = if scenes_json != "" {
    @scenedef.parse_scenes(scenes_json) catch {
      e => return drive_failed(e.message())
    }
  } else {
    let file = @viewfile.split_file(source, name="Card") catch {
      e => return drive_failed(e.message())
    }
    file.tests
  }
  let manifest = @dyncomp.DynManifest::from_json_string(manifest_json) catch {
    e => return drive_failed(e.message())
  }
  let guest = CardGuest::{ key, registered: Ref::new(None) }
  @drive.report_json(
    @drive.run(
      guest,
      manifest,
      scenes,
      on_bundle=b => guest.registered.val = Some(b),
      on_app=a => install_sweep(key, () => a.root_value(), a.transactor),
      take_log=() => {
        let raw = cardguest_take_log(key)
        if raw == "" {
          []
        } else {
          raw.split("\n").map(l => l.to_string()).collect()
        }
      },
    ),
  ).stringify()
}

///|
/// A failure that stopped every scene, in the shape the report has — so a
/// caller reads one thing rather than two.
fn drive_failed(msg : String) -> String {
  Json::object({
    "ok": Json::boolean(false),
    "ran": Json::number(0),
    "failed": Json::number(0),
    "error": Json::string(msg),
    "scenes": Json::object({}),
  }).stringify()
}
