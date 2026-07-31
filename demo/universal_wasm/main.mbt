///| Universal wasm-component host: drop a `.tutuca.tar.gz` bundle on the page,
/// search what it declared, fill in a form, and arrange what you placed.
///
/// The page is a shell around `dyncomp/ui`. Everything the editor does —
/// the catalog search, the schema-generated form, the layout algebra, import
/// and export — is backend-agnostic and driven by `moon test`; what is here is
/// the part that cannot be, which is the bridge that turns an archive into
/// registered components and a `ComponentRef` into a live guest instance.
///
///   drop / load a URL -> @dhw.load_* -> the JS bridge instantiates the guest
///     -> dyncomp_on_loaded -> register_bundle + @dhw.registry().register
///     -> shell.dyncompLoaded -> editor.catalogChanged (the palette re-runs)
///
///   pick in the palette -> the editor generates a form from the component's
///     declared arguments -> place -> `make_instance` through the bridge
///     -> BindInstance into the surface document

///|
fn main {

}

// --- the session: what survives the page ----------------------------------
//
// Three things, and each one is stored where it belongs. The LAYOUT is a
// document, so it goes in as JSON. Each PLACED COMPONENT goes in as a
// `Snapshot` — the guest's own bytes when it has any, the declared fields
// when it does not — keyed by the slot that holds it, which is a name that
// still means something after a reload. And the BUNDLES have to be named too,
// because an instance cannot come back before the code that answers for it:
// the samples by URL, since a dropped file is a thing the page cannot fetch
// again and saying so is better than pretending.

///|
/// The browser's localStorage, under this page's own prefix.
let store : &@persist.Store = @pwasm.LocalStore::new(prefix="tutuca-universal:")

///|
/// Loads still in flight. Saving while a session is being restored would
/// write the empty editor over the thing being restored INTO it, which is the
/// one way this feature could destroy what it exists to keep.
let pending : Ref[Int] = { val: 0 }

///|
/// The sample URLs to load again next time. Only URLs: a dropped file has no
/// name the page can fetch, so its components come back only if the same
/// bundle is dropped again.
let loaded_urls : Array[String] = []

///|
/// Write the whole session. Runs on the transactor's drained cascade, so it
/// sees settled state and never a half-applied edit.
fn save_session() -> Unit {
  if pending.val > 0 {
    return
  }
  guard @dhw.app_root_value() is Some(root) else { return }
  let editor = root.field("editor")
  guard editor is Obj(_) else { return }
  store.set("doc", editor.field("doc").to_json().stringify())
  store.set(
    "urls",
    Json::array(loaded_urls.map(u => Json::string(u))).stringify(),
  )
  // Slots are re-keyed by the node that holds them, which is what makes a
  // restore able to put each one back where it was. Whatever was saved under
  // a slot that no longer exists is forgotten, so the store follows the
  // document rather than accumulating everything ever placed.
  let live : Array[String] = []
  // From the editor's TREE (`@ui.live_slots`), never from a map beside it: a
  // component that has been USED has a successor there, and storing the copy
  // would store the state it had when it was placed.
  for id, inst in @ui.live_slots(editor) {
    match @dhw.snapshot(inst) {
      Some(snap) => {
        let key = "slot/\{id}"
        if @persist.save(store, { ..snap, id: key }) {
          live.push(key)
        }
      }
      None => ()
    }
  }
  for id in @persist.saved_ids(store) {
    if id.has_prefix("slot/") && !live.contains(id) {
      @persist.forget(store, id)
    }
  }
}

///|
/// Load the bundles the last session used. Called once at mount; each one
/// finishing pushes a `dyncompLoaded` message, and the last of them triggers
/// the restore below.
fn resume_session() -> Unit {
  guard store.get("urls") is Some(text) else { return }
  let parsed = @json.parse(text) catch { _ => return }
  guard parsed is Array(items) else { return }
  for item in items {
    if item is String(url) {
      pending.val = pending.val + 1
      loaded_urls.push(url)
      @dhw.load_url(@tutuca.DispatchPath::new(), url) |> ignore
    }
  }
}

///|
/// The saved layout, and every instance a loaded bundle can rebuild.
///
/// A slot whose bundle is missing simply stays empty: the document still says
/// what belongs there, so dropping that bundle later and restoring again fills
/// it in. Refusing the whole session because one component is unavailable
/// would be the wrong trade for a page whose bundles arrive by hand.
fn restored_session() -> @tutuca.Value? {
  guard store.get("doc") is Some(text) else { return None }
  let doc = @json.parse(text) catch { _ => return None }
  let slots : Map[String, @tutuca.Value] = Map([])
  for id in @persist.saved_ids(store) {
    guard id.has_prefix("slot/") else { continue }
    guard @persist.load(store, id) is Some(snap) else { continue }
    match @dhw.restore(snap) {
      Some(v) => slots[id[5:].to_owned()] = v
      None => ()
    }
  }
  Some(Map({ "doc": @tutuca.Value::from_json(doc), "slots": Map(slots) }))
}

///|
/// The session after a bundle (re)loads: the same layout, with every instance
/// of THAT module carried across.
///
/// A reload of a module already loaded is a HOT SWAP — the old bundle is
/// retired the moment this handler returns — so anything the editor is holding
/// from it becomes a dead handle unless it is rebuilt here. The rebuild goes
/// through the same snapshot the store uses, which means a swap keeps what a
/// reload keeps: the guest's own bytes when it has them, the declared fields
/// when it does not. A hot swap is a save and a load with no store in between.
///
/// None when nothing needs carrying, which is the usual case (a first load).
fn session_after_load(module_name : String) -> @tutuca.Value? {
  guard @dhw.app_root_value() is Some(root) else { return None }
  let editor = root.field("editor")
  guard editor is Obj(_) else { return None }
  let slots : Map[String, @tutuca.Value] = Map([])
  let mut carried = false
  for id, inst in @ui.live_slots(editor) {
    match @dhw.snapshot(inst) {
      Some(snap) if snap.module_ == module_name =>
        match @dhw.restore(snap) {
          Some(fresh) => {
            slots[id] = fresh
            carried = true
          }
          // Nothing from the new bundle answers for it: leaving the slot empty
          // is the only honest answer, since the instance it held belongs to a
          // bundle that is about to be retired.
          None => ()
        }
      _ => slots[id] = inst
    }
  }
  if carried {
    Some(Map({ "doc": editor.field("doc"), "slots": Map(slots) }))
  } else {
    None
  }
}

///|
/// Build a guest instance for the editor to place.
///
/// The one thing `dyncomp/ui` cannot do for itself: a named fixture goes
/// through `make_init`, everything else through the bare constructor with the
/// arguments the form validated.
fn make_instance(
  ref_ : @registry.ComponentRef,
  init : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value? {
  let made = if init == "" {
    @dhw.make_instance(ref_.module_, ref_.name, args~)
  } else {
    @dhw.make_init(ref_.module_, ref_.name, init)
  }
  match made {
    Some(v) => Some(v)
    None => None
  }
}

///|
/// The page shell: a drop target, a status line, and the editor.
///
/// `editor` is a NAMED slot, so the framework constructs it from the editor's
/// own `init` — an empty surface with its palette already showing the catalog.
/// Nothing here has to know what a seeded editor looks like.
fn universal_shell_comp(
  seed : Map[String, @tutuca.Value],
) -> @component.Component {
  universal_wasm_component(
    init={
      status: "drop a .tutuca.tar.gz bundle, or load one of the samples",
      editor: Null,
    },
    // The state block cannot NAME this slot: `surface-editor` is declared in
    // another package, and the generator resolves a sibling component only
    // within one file — so the schema says `component` and `slots~` is what
    // fills in which one. `slot_args~` then carries what it is built with,
    // because a component-typed field takes its value from construction args
    // rather than from `init`.
    slots={ "editor": "SurfaceEditor" },
    slot_args={ "editor": seed },
    update=(s, msg, ctx) => {
      match msg {
        // A dropped file: `value` is the list of descriptors the drop event
        // carried, and the id names the file the browser still holds. No
        // page-level JS is involved — this is an ordinary input handler.
        Input("loadDropped", [List(files), ..]) => {
          for f in files {
            match f.field("id") {
              Num(id) => @dhw.load_dropped(ctx.path(), id.to_int()) |> ignore
              _ => ()
            }
          }
          Some({ ..s, status: "loading…" })
        }
        // the same archive, fetched instead of dropped
        Input("loadSample", [Str(url), ..]) => {
          if !loaded_urls.contains(url) {
            loaded_urls.push(url)
          }
          @dhw.load_url(ctx.path(), url) |> ignore
          Some({ ..s, status: "loading \{url}…" })
        }
        _ =>
          match UniversalWasmReceive::from_dispatch(msg) {
            // The catalog changed under whatever the palette is showing, so
            // the editor is told rather than left stale. A reload of a module
            // already registered is a HOT SWAP: the registry replaces it in
            // place, keeping its position in the palette.
            Some(DyncompLoaded(module_name)) => {
              let editor = ctx.path().concat([FieldStep("editor")])
              ctx.send_at_path(editor, "catalogChanged", [Str(module_name)])
              // The last of the resumed loads is what makes a restore
              // possible: every bundle the saved slots name is now here.
              if pending.val > 0 {
                pending.val = pending.val - 1
                if pending.val == 0 {
                  match restored_session() {
                    Some(session) =>
                      ctx.send_at_path(editor, "restoreSession", [session])
                    None => ()
                  }
                }
              } else {
                // Not a resume: a load of something already mounted, which is
                // a hot swap and has to carry what it replaces.
                match session_after_load(module_name) {
                  Some(session) =>
                    ctx.send_at_path(editor, "restoreSession", [session])
                  None => ()
                }
              }
              Some({ ..s, status: "loaded \{module_name}" })
            }
            // The refusal's own words: "this host takes no CSS from a bundle",
            // "no such component". A generic sentence here would throw away
            // the one thing a person can act on.
            Some(DyncompError(why)) => {
              if pending.val > 0 {
                pending.val = pending.val - 1
              }
              Some({ ..s, status: why })
            }
            Some(Unknown(_, _)) | None => None
          }
      }
    },
  )
}

///|
/// The module: the editor's components plus this page's shell.
///
/// One ModuleDef because one app mounts one module — and because the guest
/// components a bundle registers land in the same scope, which is what lets
/// `<x render=".slot">` resolve them.
fn universal_module() -> @component.ModuleDef {
  let (editor_module, seed) = @ui.seeded_editor(@dhw.registry(), make_instance)
  @component.ModuleDef::new(
    name="universalwasm",
    components=[universal_shell_comp(seed)] + editor_module.components,
    requests=host_requests(),
  )
}

///|
/// Services this HOST provides to whatever it hosts.
///
/// `double` is the one the sample counter calls (`control.request "double"`),
/// and it is here to demonstrate the seam rather than because doubling is
/// interesting: it is a guest asking the page for something it cannot compute
/// for itself. A bundle that serves a request of the same NAME answers its own
/// components first — the counter's `triple` is served by its own bundle and
/// never reaches this map.
///
/// Whether a guest should be able to reach these at all is the open question
/// in dyncomp/SECURITY.md §5: the answer wants the requester's path, which
/// `RequestFn` does not carry yet.
fn host_requests() -> Map[String, @component.RequestFn] {
  {
    "double": RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("double: expected one number")))
      }
    }),
  }
}

// --- margaui class publishing -------------------------------------------

///|
let app_ref : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
/// Compile the app's utility-class set to CSS in MoonBit (via the
/// marianoguerra/tailwindcss port) and inject it as <style id="margaui-css">
/// (mirrors demo/storybook_wasm). Called at mount and again (via the exported
/// refresh_margaui) after a bundle loads, so guest-view classes get compiled
/// too. index.html pre-places an empty <style id="margaui-css"> early in <head>
/// so the upsert keeps it ahead of any lazily-loaded palette <link>.
fn apply_margaui() -> Unit {
  guard app_ref.val is Some(app) else { return }
  let css = @css.compile_margaui(app.scope.comps.collect_classes()) catch {
    err => {
      @tutuca.warn("margaui compile failed: \{err}")
      return
    }
  }
  @wglue.inject_style(@wglue.document(), "margaui-css", css)
}

///|
/// Recompile + reinject margaui CSS after a guest bundle registers new views
/// (and thus new utility classes). Exported; the loader calls it post-load.
pub fn refresh_margaui() -> Unit {
  apply_margaui()
}

// --- lifecycle exports ---------------------------------------------------

///|
pub fn mount() -> Unit {
  guard @wglue.mount_in(universal_module(), "UniversalWasm") is Some(app) else {
    return
  }
  app_ref.val = Some(app)
  // BEFORE `set_app`, which installs the superseded-handle sweep: drained
  // subscribers run in subscription order, so saving first means every handle
  // this walks is still alive. After the sweep, a slot whose component was
  // just used can be a handle the host has already collected — and a snapshot
  // taken through one is not a snapshot at all.
  app.transactor.on_drained(save_session)
  @dhw.set_app(app, @wglue.document())
  apply_margaui()
  resume_session()
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
/// The JS bridge calls this once a dropped/fetched bundle is instantiated.
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @dhw.on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @dhw.on_load_error(load_id, msg)
}

///|
/// The app's whole state as JSON, for poking at the page from the console.
pub fn state_json() -> String {
  match @dhw.app_root_value() {
    Some(v) => v.to_display_string()
    None => "null"
  }
}
