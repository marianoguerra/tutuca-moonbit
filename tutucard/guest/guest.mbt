// The compiled card, mounted — the other half of the boundary `card.js` holds.
//
// The page next door compiles a card to a core wasm module and hands you the
// file. That proves the BYTES are right. It does not prove the module runs, and
// until something instantiated one and asked it for a field, "this page
// produced a real component" was a claim about a download.
//
// So: `card.js` instantiates the module against the shared runtime and installs
// a handful of calls on `globalThis.__cardguest`; this implements `&Guest` over
// them, registers the module's own manifest and mounts an instance. Nothing
// here is card-specific once the module is running — `register_module` is the
// same call any host makes over a module it was handed.
//
// The module declares no memory and no table, so its IMPORT SECTION is its
// complete authority list: a card that imports something the runtime does not
// export fails to instantiate, before any of this runs. See `tgc/SECURITY.md`.

///|
/// Whether a compiled card has been instantiated on this page.
pub extern "js" fn ready(key : String) -> Bool =
  #|(key) => !!(globalThis.__cardguest && globalThis.__cardguest[key])

///|
/// Everything the instantiated card has logged since this was last asked.
///
/// `control.log` is the simplest call on the control interface,
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
pub extern "js" fn take_log(key : String) -> String =
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
  bindings_json : String,
) -> String =
  #|(key, handle, bucket, name, args, bindings) => globalThis.__cardguest[key].dispatch(handle, bucket, name, args, bindings)

///|
extern "js" fn cardguest_render_call(
  key : String,
  handle : Int,
  category : String,
  name : String,
  args_json : String,
  bindings_json : String,
) -> String =
  #|(key, handle, category, name, args, bindings) => globalThis.__cardguest[key].renderCall(handle, category, name, args, bindings)

///|
extern "js" fn cardguest_get_property(
  key : String,
  handle : Int,
  name : String,
) -> String =
  #|(key, handle, name) => globalThis.__cardguest[key].getProperty(handle, name)

///|
extern "js" fn cardguest_set_property(
  key : String,
  handle : Int,
  name : String,
  value_json : String,
) -> String =
  #|(key, handle, name, value) => globalThis.__cardguest[key].setProperty(handle, name, value)

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
// Plain JSON in both directions, with one exception in each — the `{"$dyn": …}`
// child marker, which is how an INSTANCE crosses. A compiled card has no
// `make-instance` of its own, so nothing here produces a child; but a host can
// hand it one, and that is the holder case.

///|
/// Arguments on their way INTO the card. `child_json` rather than `to_json`,
/// because `Value::to_json` has no form for an `Obj` and writes the object's
/// FIELDS instead — a copy of an instance's state under a name that no longer
/// refers to it. What has to cross is the handle. See the twin in
/// `tgc/host/glue.mbt`.
fn list_json(args : Array[@tutuca.Value]) -> String {
  Json::array(args.map(v => @host.child_json(v))).stringify()
}

///|
/// The same, keyed — a constructor's arguments. See `list_json`.
fn fields_json(args : Map[String, @tutuca.Value]) -> String {
  let obj : Map[String, Json] = Map([])
  for name, v in args {
    obj[name] = @host.child_json(v)
  }
  Json::object(obj).stringify()
}

///|
/// WIT order, which is what the bridge counts in: 0=receive, 1=intent.
fn bucket_int(bucket : @tutuca.HandlerBucket) -> Int {
  bucket.ordinal()
}

// --- the Guest impl over __cardguest ---------------------------------------

///|
/// Which instantiated module this guest speaks to.
///
/// The key is the MOUNT POINT's element id: a page with two `<mb-card>` embeds
/// has two modules with two instance tables, so a guest has to say which one it
/// means, exactly as `WasmGuest` carries a module id.
pub struct CardGuest {
  key : String
  /// The module this guest was registered as, once it has been.
  ///
  /// Set after `register_module` and before the first instance is made, which
  /// is the only order that works: a child token arriving from the guest is a
  /// handle and a component NAME, and only the module knows how to wrap that
  /// pair as a `DynObj` the render stack will place. A guest that has not been
  /// registered yet cannot receive one, because nothing has called it.
  registered : Ref[@host.Module?]
}

///|
/// Bridge JSON into a Value, wrapping a child marker as the instance it stands
/// for — at ANY depth, lists and maps included.
///
/// `{"$dyn": {"handle": n, "comp": s}}` is the shape both hosts write, so this
/// is `tgc/host/glue.mbt`'s `json_to_value` with a different module
/// behind it. The generator emits `make-instance`, so a guest value can be
/// another instance.
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
          let module_ = match m.get("module") {
            Some(String(x)) => x
            _ => ""
          }
          wrap_marked(module_, comp, handle, self.registered.val)
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
pub impl @host.Guest for CardGuest with fn create(self, component, args) {
  cardguest_create(self.key, component, fields_json(args))
}

///|
pub impl @host.Guest for CardGuest with fn get_field(self, handle, name) {
  let raw = cardguest_get_field(self.key, handle, name)
  if raw == "" {
    None
  } else {
    Some(self.value_of(raw))
  }
}

///|
pub impl @host.Guest for CardGuest with fn handle_dispatch(
  self,
  handle,
  bucket,
  name,
  args,
  bindings,
) {
  let raw = cardguest_dispatch(
    self.key,
    handle,
    bucket_int(bucket),
    name,
    list_json(args),
    bindings_json(bindings),
  )
  let empty : @host.DispatchResult = { handled: false, next: None, msgs: [], }
  let j = @json.parse(raw) catch { _ => return empty }
  guard j is Object(o) else { return empty }
  let handled = o.get("handled") is Some(True)
  let next = match o.get("next") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  // `intent-at` is the one the generator still cannot emit, so `card.js`
  // binds that import to nothing and it never reaches this list. An intent's
  // `opts` DOES cross, because the route is the one part of it a card writes
  // at the call site.
  let msgs : Array[@host.ControlMsg] = []
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
          Some(String("sendReply")) => msgs.push(SendReply(name, args))
          Some(String("sendAt")) =>
            msgs.push(SendAt(path_steps(m.get("path")), name, args))
          Some(String("setAt")) =>
            msgs.push(
              SetAt(
                path_steps(m.get("path")),
                name,
                match m.get("value") {
                  Some(j) => @tutuca.Value::from_json(j)
                  None => Null
                },
              ),
            )
          Some(String("intent")) =>
            msgs.push(Intent(name, args, intent_opts(m.get("opts"))))
          _ => ()
        }
      }
    _ => ()
  }
  { handled, next, msgs, }
}

///|
/// The one value a `reply` or a `fail` carries, as `card.js` sends it.
fn value_field(m : Map[String, Json], key : String) -> @tutuca.Value {
  match m.get(key) {
    Some(j) => @tutuca.Value::from_json(j)
    None => Null
  }
}

///|
/// An intent's routing (WIT `intent-opts`), as the bridge's JSON.
///
/// The twin of `tgc/host/glue.mbt`'s, and a copy for the same reason
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
      on_failed_name?=name("onFailed"),
      on_unhandled_name?=name("onUnhandled"),
      live_path=o.get("livePath") is Some(True),
    )
  }
  @tutuca.IntentOpts::new(
    route~,
    on_ok_name?=name("onOk"),
    on_failed_name?=name("onFailed"),
    on_unhandled_name?=name("onUnhandled"),
    live_path=o.get("livePath") is Some(True),
  )
}

///|
/// One relative path step of a `sendAt`, as `card.js` spells it:
/// `{"field": "left"}`, `{"item": ["seq", "k"]}` or `{"at": ["seq", 3]}`.
///
/// The twin of `tgc/host/glue.mbt`'s, and deliberately a copy rather
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
pub impl @host.Guest for CardGuest with fn render_call(
  self,
  handle,
  category,
  name,
  args,
  bindings,
) {
  self.value_of(
    cardguest_render_call(
      self.key,
      handle,
      category,
      name,
      list_json(args),
      bindings_json(bindings),
    ),
  )
}

///|
pub impl @host.Guest for CardGuest with fn get_property(self, handle, name) {
  let raw = cardguest_get_property(self.key, handle, name)
  if raw == "" {
    None
  } else {
    Some(self.value_of(raw))
  }
}

///|
pub impl @host.Guest for CardGuest with fn set_property(
  self,
  handle,
  name,
  value,
) {
  let raw = cardguest_set_property(
    self.key,
    handle,
    name,
    @host.child_json(value).stringify(),
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
pub impl @host.Guest for CardGuest with fn with_field(self, handle, name, v) {
  let next = cardguest_with_field(
    self.key,
    handle,
    name,
    @host.child_json(v).stringify(),
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
pub impl @host.Guest for CardGuest with fn serve_intent(_self, name, _args) {
  Err(
    Str("a compiled card answers no requests, and this one asked for '\{name}'"),
  )
}

///|
/// A compiled card exports no `persist`, so it has no state of its own to hand
/// over and none to take back. Empty bytes are what a guest that does not
/// persist answers, and `None` is the guest refusing them — which is what the
/// host expects from one that never wrote any.
pub impl @host.Guest for CardGuest with fn persist(_self, _handle) {
  b""
}

///|
pub impl @host.Guest for CardGuest with fn restore(_self, _component, _state) {
  None
}

///|
/// Release one instance.
///
/// A card is copy-on-write, so EVERY keystroke supersedes a handle: the host's
/// GC collects them and hands them to a guest that must drop them, or a card
/// left open grows a table entry per interaction.
pub impl @host.Guest for CardGuest with fn drop_instance(self, handle) {
  cardguest_drop(self.key, handle)
}

///|
/// What each app on one instance table could still reach, the last time it
/// drained.
///
/// A LIST rather than one set, because `globalThis.__cardguest[key]` is ONE
/// instance table and more than one app can be reading it: the page mounts the
/// card, and then `drive` mounts the SAME module again — once per scene, on the
/// in-memory DOM — under the same key, because the key names the module and
/// there is only one of those. A sweep that kept what the app that raised it
/// could reach and nothing else would collect every instance the others hold,
/// which is exactly what a card with a `tutuca/test` block did: driving its
/// scenes dropped the handle the preview was holding, and the card on the page
/// went dead while every field read back null.
///
/// Each app writes its OWN entry when its own cascade drains, and the sweep
/// keeps the union. Walking someone else's tree instead would mean calling
/// `get-field` on their instances in the middle of this app's cascade, and a
/// guest call drains the pending children and clears the arena the call in
/// flight is holding — which loses a row being built. So a foreign app's
/// reachability is READ from what it recorded, never recomputed here.
///
/// Emptied by `teardown`, which is the first thing a mount into that key does:
/// the apps that recorded these are gone, and so is the table they read.
let sweep_live : Map[String, Array[Ref[Array[Int]]]] = Map([])

///|
/// Forget what an id's sweep was keeping alive. `teardown` calls this.
pub fn forget_sweep_roots(key : String) -> Unit {
  sweep_live.remove(key)
}

///|
/// Collect what nothing points at, at the end of every drained cascade.
///
/// Installed AFTER `install_gc`, and after the App's own re-render: subscribers
/// run in subscription order, so by the time this reads the root the superseded
/// handles are gone and the render that needed them has happened.
pub fn install_sweep(
  key : String,
  root : () -> @tutuca.Value,
  tx : @transactor.Transactor,
) -> Unit {
  let mine : Ref[Array[Int]] = Ref([])
  let sets = match sweep_live.get(key) {
    Some(sets) => sets
    None => {
      let sets : Array[Ref[Array[Int]]] = []
      sweep_live[key] = sets
      sets
    }
  }
  sets.push(mine)
  tx.on_drained(() => {
    let live : Array[Int] = []
    live_handles(root(), live)
    mine.val = live
    // …and everything the other apps on this table recorded when they last
    // drained. One table, several readers: a handle is garbage only when none
    // of them can reach it.
    let keep : Array[Int] = []
    for set in sets {
      for handle in set.val {
        if !keep.contains(handle) {
          keep.push(handle)
        }
      }
    }
    cardguest_retain(
      key,
      Json::array(keep.map(h => Json::number(h.to_double()))).stringify(),
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
/// holds the root: walk the tree, keep what is found. A card is one module with
/// one table, which is what makes a sweep affordable here and not in general.
pub fn live_handles(v : @tutuca.Value, out : Array[Int]) -> Unit {
  match v {
    Obj(o) => {
      match o.field(@host.handle_field) {
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
      match o.schema() {
        Some(sc) =>
          for f in sc.fields {
            match o.field(f.name) {
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

///|
/// The bindings a guest's `control.lookup` reads, as the JSON the bridge takes.
fn bindings_json(bindings : Map[String, @tutuca.Value]) -> String {
  let m : Map[String, Json] = Map([])
  for k, v in bindings {
    m[k] = v.to_json()
  }
  Json::object(m).stringify()
}

///|
/// A bridge over one loaded module, before it has been registered.
///
/// `register` is the ordinary door and does both halves. This is for a caller
/// that has to hold the guest first and be told the module afterwards —
/// `tutucard/drive` takes the guest, builds the module, and hands it back
/// through `on_bundle`.
pub fn CardGuest::new(key : String) -> CardGuest {
  { key, registered: Ref(None), }
}

///|
/// Tell a guest which module it was registered as, and the page's table too.
pub fn CardGuest::adopted(self : CardGuest, loaded : @host.Module) -> Unit {
  self.registered.val = Some(loaded)
  adopt(self.key, loaded)
}
