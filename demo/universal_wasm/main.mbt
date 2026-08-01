///| Universal wasm-component host: drop a `.tutuca.tar.gz` bundle on the page,
/// search what it declared, and build a page out of it.
///
/// The page IS the app. Everything about searching, placing, arranging and
/// configuring is `dyncomp/ui`, backend-agnostic and driven by `moon test`;
/// what is here is the part that cannot be — the bridge that turns an archive
/// into registered components and a `ComponentRef` into a live guest instance,
/// and the store that keeps what you built.
///
///   drop / load a URL -> @dhw.load_* -> the JS bridge instantiates the guest
///     -> dyncompLoaded -> @dhw.registry() answers with the new components
///     -> the app re-runs whatever the command bar is showing
///
///   click a + -> the app opens the bar -> pick -> `make_instance` through the
///     bridge -> the instance is sent to the cell that asked

///|
fn main {

}

// --- the session: what survives the page ----------------------------------
//
// Two things. The TREE is the app's root component, written out as the shape
// `tree_json` describes: what each component is called, what its declared
// fields hold, and what its children are. And each GUEST instance in it also
// goes in as a `Snapshot` — the guest's own bytes when it has any, the
// declared fields when it does not — keyed by WHERE IT SITS in that tree,
// which is a name that still means something after a reload.
//
// The BUNDLES have to be named too, because an instance cannot come back
// before the code that answers for it: the samples by URL, since a dropped
// file is a thing the page cannot fetch again and saying so is better than
// pretending.

///|
/// Whether this page was opened for working ON it rather than for using it —
/// `?test` in the query string.
///
/// It gates two things, and they belong together: the sample-loading buttons,
/// and the SESSION. A first-time visitor should meet an empty page and a `+`,
/// not four buttons naming archives they have never heard of and whatever the
/// last person left behind.
///
/// The session has to be gated at BOTH ends. Restoring only under `?test` but
/// saving always would mean an ordinary visit — which starts empty — writing
/// that empty page over the one somebody was working on, and the store would
/// destroy exactly what it exists to keep.
///
/// Read once, because `location` cannot change under a page that never
/// navigates, and a flag read twice is a flag that can disagree with itself.
let dev_mode : Bool = has_test_param()

///|
/// `?test`, `?test=1`, `?a=1&test` — but not `?testing` or `?x=test`, which is
/// why this looks at parameter NAMES rather than at the string.
fn has_test_param() -> Bool {
  let loc = @core.global_this()._get("location")
  if @core.is_nullish(loc) {
    return false
  }
  let search = loc._get("search")
  if @core.is_nullish(search) {
    return false
  }
  let query = search.to_string()
  let body = if query.has_prefix("?") { query[1:].to_owned() } else { query }
  for part in body.split("&") {
    let pair = part.to_owned()
    let name = match pair.find("=") {
      Some(i) => pair[0:i].to_owned()
      None => pair
    }
    if name == "test" {
      return true
    }
  }
  false
}

///|
/// The browser's localStorage, under this page's own prefix.
let store : &@persist.Store = @pwasm.LocalStore::new(prefix="tutuca-universal:")

///|
/// Loads still in flight. Saving while a session is being restored would write
/// the empty page over the thing being restored INTO it, which is the one way
/// this feature could destroy what it exists to keep.
let pending : Ref[Int] = { val: 0 }

///|
/// The sample URLs to load again next time. Only URLs: a dropped file has no
/// name the page can fetch, so its components come back only if the same
/// bundle is dropped again.
let loaded_urls : Array[String] = []

///|
/// The app's own `UniversalUi`, kept so a restore can build standard
/// components by name. Filled at mount, because the module has to exist first.
let ui_ref : Ref[@ui.UniversalUi?] = { val: None }

///|
/// Whether a value is a component INSTANCE rather than data that happens to be
/// an object. Only an instance answers a schema.
fn is_instance(v : @tutuca.Value) -> Bool {
  v is Obj(_) && v.schema() is Some(_)
}

///|
/// The tree as a document, and every guest in it as a snapshot.
///
/// The shape is `{c, m, f, k, l}` — what it is Called, which Module it came
/// from, its scalar Fields, its component-valued fields (Kids), and its Lists
/// of components. Split that way because they come back differently: scalars
/// are constructor arguments, and the other two have to be rebuilt first.
///
/// A GUEST is written as its name and module and nothing else. Its fields are
/// its own, its children are its own, and what it kept privately is in the
/// snapshot beside it — walking into it here would be the host claiming to
/// know a shape the contract says it does not.
fn tree_json(
  v : @tutuca.Value,
  path : String,
  snaps : Map[String, @persist.Snapshot],
) -> Json {
  guard is_instance(v) else { return Json::null() }
  guard v.schema() is Some(sc) else { return Json::null() }
  match @dhw.snapshot(v) {
    Some(snap) => {
      snaps[path] = snap
      return Json::object({
        "c": Json::string(snap.component),
        "m": Json::string(snap.module_),
      })
    }
    None => ()
  }
  let f : Map[String, Json] = Map([])
  let k : Map[String, Json] = Map([])
  let l : Map[String, Json] = Map([])
  for field in sc.fields {
    let fv = v.field(field.name)
    if is_instance(fv) {
      k[field.name] = tree_json(fv, "\{path}/\{field.name}", snaps)
    } else if fv is List(items) {
      let mut any_inst = false
      for item in items {
        if is_instance(item) {
          any_inst = true
          break
        }
      }
      if any_inst {
        let out : Array[Json] = []
        for i, item in items {
          out.push(tree_json(item, "\{path}/\{field.name}/\{i}", snaps))
        }
        l[field.name] = Json::array(out)
      } else {
        f[field.name] = fv.to_json()
      }
    } else if fv is (Obj(_) | Fn(_)) {
      // A callable, or an object nothing can name. Skipping it is what keeps
      // the document to things that can come back.
      continue
    } else {
      f[field.name] = fv.to_json()
    }
  }
  Json::object({
    "c": Json::string(sc.name),
    "m": Json::string(@ui.builtin_module),
    "f": Json::object(f),
    "k": Json::object(k),
    "l": Json::object(l),
  })
}

///|
fn json_at(j : Json, key : String) -> Json? {
  if j is Object(m) {
    m.get(key)
  } else {
    None
  }
}

///|
/// A tree back out of its document, with every guest restored from the
/// snapshot stored beside it.
///
/// A guest whose bundle is missing comes back as nothing, which the cell
/// holding it draws as an empty `+`. The rest of the page still returns, and
/// dropping that bundle later and reloading fills it in: refusing the whole
/// session because one component is unavailable would be the wrong trade for
/// a page whose bundles arrive by hand.
fn tree_of_json(
  ui : @ui.UniversalUi,
  j : Json,
  path : String,
  snaps : Map[String, @persist.Snapshot],
) -> @tutuca.Value {
  guard json_at(j, "c") is Some(String(name)) else { return Null }
  let module_ = match json_at(j, "m") {
    Some(String(m)) => m
    _ => @ui.builtin_module
  }
  if module_ != @ui.builtin_module {
    return match snaps.get(path) {
      Some(snap) => @dhw.restore(snap).unwrap_or(Null)
      None => @dhw.make_instance(module_, name).unwrap_or(Null)
    }
  }
  let args : Map[String, @tutuca.Value] = Map([])
  if json_at(j, "f") is Some(Object(f)) {
    for key, val in f {
      args[key] = @tutuca.Value::from_json(val)
    }
  }
  if json_at(j, "k") is Some(Object(k)) {
    for key, val in k {
      args[key] = tree_of_json(ui, val, "\{path}/\{key}", snaps)
    }
  }
  if json_at(j, "l") is Some(Object(l)) {
    for key, val in l {
      guard val is Array(items) else { continue }
      let out : Array[@tutuca.Value] = []
      for i, item in items {
        out.push(tree_of_json(ui, item, "\{path}/\{key}/\{i}", snaps))
      }
      args[key] = List(out)
    }
  }
  ui.build_standard(name, args)
}

///|
/// Write the whole session. Runs on the transactor's drained cascade, so it
/// sees settled state and never a half-applied edit.
fn save_session() -> Unit {
  if !dev_mode || pending.val > 0 {
    return
  }
  guard @dhw.app_root_value() is Some(app) else { return }
  let root = app.field("root")
  guard is_instance(root) else { return }
  let snaps : Map[String, @persist.Snapshot] = Map([])
  store.set("tree", tree_json(root, "", snaps).stringify())
  store.set(
    "urls",
    Json::array(loaded_urls.map(u => Json::string(u))).stringify(),
  )
  // Snapshots are keyed by where the instance sits, which is what makes a
  // restore able to put each one back. Whatever was saved under a place that
  // no longer exists is forgotten, so the store follows the page rather than
  // accumulating everything ever placed.
  let live : Array[String] = []
  for at, snap in snaps {
    let key = "at/\{at}"
    if @persist.save(store, { ..snap, id: key }) {
      live.push(key)
    }
  }
  for id in @persist.saved_ids(store) {
    if id.has_prefix("at/") && !live.contains(id) {
      @persist.forget(store, id)
    }
  }
}

///|
/// Load the bundles the last session used. Called once at mount; each one
/// finishing pushes a `dyncompLoaded`, and the last of them triggers the
/// restore below.
fn resume_session(at : @tutuca.DispatchPath) -> Unit {
  if !dev_mode {
    return
  }
  guard store.get("urls") is Some(text) else { return }
  let parsed = @json.parse(text) catch { _ => return }
  guard parsed is Array(items) else { return }
  for item in items {
    if item is String(url) {
      pending.val = pending.val + 1
      loaded_urls.push(url)
      @dhw.load_url(at, url) |> ignore
    }
  }
}

///|
/// The saved page, rebuilt. None when there is nothing stored.
fn restored_tree() -> @tutuca.Value? {
  if !dev_mode {
    return None
  }
  guard store.get("tree") is Some(text) else { return None }
  guard ui_ref.val is Some(ui) else { return None }
  let doc = @json.parse(text) catch { _ => return None }
  let snaps : Map[String, @persist.Snapshot] = Map([])
  for id in @persist.saved_ids(store) {
    guard id.has_prefix("at/") else { continue }
    guard @persist.load(store, id) is Some(snap) else { continue }
    snaps[id[3:].to_owned()] = snap
  }
  match tree_of_json(ui, doc, "", snaps) {
    Null => None
    v => Some(v)
  }
}

// --- the bridge -------------------------------------------------------------

///|
/// Build a guest instance for the app to place.
///
/// The one thing `dyncomp/ui` cannot do for itself: a named fixture goes
/// through `make_init`, everything else through the bare constructor with the
/// arguments the form validated. Standard components never reach here — they
/// are compiled in, and the app builds them directly.
fn make_instance(
  ref_ : @registry.ComponentRef,
  init : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value? {
  if init == "" {
    @dhw.make_instance(ref_.module_, ref_.name, args~)
  } else {
    @dhw.make_init(ref_.module_, ref_.name, init)
  }
}

///|
/// The bar's development conveniences: fetch a sample, or take a dropped file.
///
/// The bridge answers at the path that ASKED for a load, which is this
/// component's — so it hears its own results and tells the app the catalog
/// changed. Nothing above it has to know what a bundle is.
fn host_tools_comp() -> @component.Component {
  host_tools_component(
    init={
      status: if dev_mode {
        "drop a .tutuca.tar.gz, or load a sample"
      } else {
        "drop a .tutuca.tar.gz to add its components"
      },
      samples: dev_mode,
    },
    update=(s, msg, ctx) => {
      match HostToolsMsg::from_dispatch(msg) {
        Some(LoadSample(url)) => {
          if !loaded_urls.contains(url) {
            loaded_urls.push(url)
          }
          @dhw.load_url(ctx.path(), url) |> ignore
          return Some({ ..s, status: "loading \{url}…" })
        }
        Some(Unknown(_, _)) | None => ()
      }
      match HostToolsReceive::from_dispatch(msg) {
        // A dropped file: the payload is the list of descriptors the drop
        // event carried, and the id names the file the browser still holds. No
        // page-level JS is involved — this is an ordinary handler.
        Some(FilesDropped(files)) => {
          guard files is List(items) else { return None }
          for f in items {
            match f.field("id") {
              Num(id) => @dhw.load_dropped(ctx.path(), id.to_int()) |> ignore
              _ => ()
            }
          }
          Some({ ..s, status: "loading…" })
        }
        Some(DyncompLoaded(module_name)) => {
          HostToolsBubble::CatalogChanged(module_name).bubble(ctx)
          // The last of the resumed loads is what makes a restore possible:
          // every bundle the saved page names is now here.
          if pending.val > 0 {
            pending.val = pending.val - 1
            if pending.val == 0 {
              match restored_tree() {
                Some(root) => ctx.bubble("restoreTree", [root])
                None => ()
              }
            }
          }
          Some({ ..s, status: "loaded \{module_name}" })
        }
        // The refusal's own words: "this host takes no CSS from a bundle",
        // "no such component". A generic sentence here would throw away the
        // one thing a person can act on.
        Some(DyncompError(why)) => {
          if pending.val > 0 {
            pending.val = pending.val - 1
          }
          Some({ ..s, status: why })
        }
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
/// The module: the app, its chrome, the standard components, and this page's
/// own bar tools.
///
/// One ModuleDef because one app mounts one module — and because the guest
/// components a bundle registers land in the same scope, which is what lets a
/// universal's `<x render=".child">` resolve one.
fn universal_module() -> @component.ModuleDef {
  let (module_, ui) = @ui.seeded_app(
    @dhw.registry(),
    make_instance,
    dev_tools="HostTools",
  )
  ui_ref.val = Some(ui)
  @component.ModuleDef::new(
    name="universalwasm",
    components=[..module_.components, host_tools_comp()],
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
  guard @wglue.mount_in(universal_module(), "UniversalApp") is Some(app) else {
    return
  }
  app_ref.val = Some(app)
  // BEFORE `set_app`, which installs the superseded-handle sweep: drained
  // subscribers run in subscription order, so saving first means every handle
  // this walks is still alive. After the sweep, a component that was just used
  // can be a handle the host has already collected — and a snapshot taken
  // through one is not a snapshot at all.
  app.transactor.on_drained(save_session)
  @dhw.set_app(app, @wglue.document())
  apply_margaui()
  // The bar tools are where a load's answers arrive, so that is the path a
  // resume asks from.
  resume_session(@tutuca.DispatchPath::of_steps([FieldStep("devTools")]))
  // A page built entirely out of standard components names no bundles, so
  // nothing is in flight and no load will ever arrive to trigger the restore
  // below. Doing it here is the whole of that case — and it has to be HERE
  // rather than inside `resume_session`, because a page that DOES name bundles
  // must wait for the last of them.
  if pending.val == 0 {
    match restored_tree() {
      Some(root) => app.send_at_root("restoreTree", args=[root]) |> ignore
      None => ()
    }
  }
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
