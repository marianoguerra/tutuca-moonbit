///| A mounted universal UI, and everything it needs to keep running.
///
/// The page IS the app. Everything about searching, placing, arranging and
/// configuring is `dyncomp/ui`, backend-agnostic and driven by `moon test`;
/// what is here is the part that cannot be — the bridge that turns an archive
/// into registered components and a `ComponentRef` into a live guest instance,
/// and the store that keeps what was built.
///
///   drop / load a URL -> @dhw.load_* -> the JS bridge instantiates the guest
///     -> dyncompLoaded -> @dhw.registry() answers with the new components
///     -> the app re-runs whatever the command bar is showing
///
///   click a + -> the app opens the bar -> pick -> `make_instance` through the
///     bridge -> the instance is sent to the cell that asked
///
/// A host holds this and re-exports the five wasm-gc entry points; it cannot
/// be a dependency's job, because an export list is per-package link
/// configuration. See `demo/universal_wasm` for the ~90 lines that does it.

// One bundle a host offers to load by URL is a `@shell.LoaderBarSample`
// (`{ label, url }`), generated from the record `dyncomp/shell`'s loader bar
// declares. There is deliberately no friendlier alias for it: a public struct
// beside the view-facing one is two definitions that can disagree, and the alias
// syntax that would rename it in place is deprecated in favour of an attribute
// on the declaration — which is generated, and not ours to annotate.
//
// A published host knows no bundle's name. A page that ships with its own
// components, or a demo, passes them in; that is why they are a value rather
// than a compiled-in list.

///|
/// Where a session goes, and whether it goes anywhere.
///
/// `None` is a page that starts empty every time, which is the right default:
/// persistence has to be gated at BOTH ends, and a page that restores but does
/// not save — or the reverse — writes an empty tree over the thing it exists to
/// keep. One option makes that impossible to get half-right.
pub(all) struct Session {
  store : &@persist.Store
}

///|
/// A mounted host. Everything mutable about a running universal page lives
/// here rather than at module scope, so a page can hold one and a test can
/// hold another.
pub struct UniversalHost {
  app : @app.App[@wdom.WasmNode]
  ui : @ui.UniversalUi
  /// Where the session goes, or `None` for a page that starts empty.
  session : Session?
  /// The RESUMED loads still in flight, by load id. Saving while a session is
  /// being restored would write the empty page over the thing being restored
  /// INTO it, which is the one way this feature could destroy what it exists
  /// to keep.
  ///
  /// The ids rather than a count, because a count cannot tell a resumed load
  /// from a bundle somebody dropped while the resume was still running: the
  /// drop's completion would retire a slot the resume was waiting on, and the
  /// restore would fire over a page that is not ready for it. Only what
  /// `resume_session` started goes in here.
  pending : Set[Int]
  /// The URLs to load again next time. Only URLs: a dropped file has no name
  /// the page can fetch, so its components come back only if the same bundle
  /// is dropped again.
  loaded_urls : Array[String]
}

///|
/// The app's `UniversalUi`, so a restore can build standard components by
/// name. Module-scoped because `host_tools_comp` and the restore path run from
/// inside the component tree, where no `UniversalHost` is in hand — one live
/// app per wasm instance is the premise the exports already rest on.
let live : Ref[UniversalHost?] = { val: None }

///|
/// The browser's localStorage under `prefix`, as a `Session`. The prefix is
/// the caller's because two universal pages on one origin should not read each
/// other's tree.
pub fn session_in_local_storage(prefix~ : String) -> Session {
  { store: @pwasm.LocalStore::new(prefix~) }
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
// before the code that answers for it: by URL, since a dropped file is a thing
// the page cannot fetch again and saying so is better than pretending.

///|
/// The tree as a document, and every guest in it as a snapshot.
///
/// The walk itself is `@tutuca.Value::to_component_json`, which reads each
/// field's DECLARED type; what is host-specific is the one thing below, and it
/// is the reason the hook exists at all.
///
/// A GUEST is written as its name and module and nothing else. Its fields are
/// its own, its children are its own, and what it kept privately is in the
/// snapshot beside it — walking into it here would be the host claiming to know
/// a shape the contract says it does not. `claim~` runs BEFORE any field of an
/// instance is read, which is what keeps that promise: a hook that ran after
/// would already have crossed the boundary once per field.
pub fn tree_json(
  v : @tutuca.Value,
  snaps : Map[String, @persist.Snapshot],
) -> Json {
  v.to_component_json(claim=(inst, at) => {
    match @dhw.snapshot(inst) {
      Some(snap) => {
        snaps[at] = snap
        let tag : Map[String, Json] = Map([])
        tag[@tutuca.component_key] = Json::string(snap.component)
        tag[@tutuca.module_key] = Json::string(snap.module_)
        Some(Json::object(tag))
      }
      None => None
    }
  })
}

///|
/// A tree back out of its document, with every guest restored from the snapshot
/// stored beside it.
///
/// A guest whose bundle is missing comes back as nothing, which the cell holding
/// it draws as an empty `+`. The rest of the page still returns, and dropping
/// that bundle later and reloading fills it in: refusing the whole session
/// because one component is unavailable would be the wrong trade for a page
/// whose bundles arrive by hand.
pub fn tree_of_json(
  ui : @ui.UniversalUi,
  j : Json,
  snaps : Map[String, @persist.Snapshot],
) -> @tutuca.Value {
  ui.tree_of_json(
    j,
    // Keyed by WHERE the instance sits, which is the one name that still means
    // something after a reload. Nothing saved there falls through to a fresh
    // one, which is what a guest that persists nothing wants anyway.
    restore=(at, ref_) => {
      match snaps.get(at) {
        Some(snap) => @dhw.restore(snap)
        None => @dhw.make_instance(ref_.module_, ref_.name)
      }
    },
  )
}

///|
/// Write the whole session. Runs on the transactor's drained cascade, so it
/// sees settled state and never a half-applied edit.
fn save_session() -> Unit {
  guard live.val is Some(host) else { return }
  guard host.session is Some(session) else { return }
  if !host.pending.is_empty() {
    return
  }
  let store = session.store
  guard @dhw.app_root_value() is Some(app) else { return }
  let root = app.field("root")
  // Nothing mounted yet: writing an empty tree over a good one is the
  // failure this guard is here to prevent.
  guard root is Obj(_) && root.schema() is Some(_) else { return }
  let snaps : Map[String, @persist.Snapshot] = Map([])
  store.set("tree", tree_json(root, snaps).stringify())
  store.set(
    "urls",
    Json::array(host.loaded_urls.map(u => Json::string(u))).stringify(),
  )
  // Snapshots are keyed by where the instance sits, which is what makes a
  // restore able to put each one back. Whatever was saved under a place that
  // no longer exists is forgotten, so the store follows the page rather than
  // accumulating everything ever placed.
  let saved : Array[String] = []
  for at, snap in snaps {
    let key = "at/\{at}"
    if @persist.save(store, { ..snap, id: key }) {
      saved.push(key)
    }
  }
  for id in @persist.saved_ids(store) {
    if id.has_prefix("at/") && !saved.contains(id) {
      @persist.forget(store, id)
    }
  }
}

///|
/// Load the bundles the last session used. Called once at mount; each one
/// finishing pushes a `dyncompLoaded`, and the last of them triggers the
/// restore below.
fn resume_session(host : UniversalHost, at : @tutuca.DispatchPath) -> Unit {
  guard host.session is Some(session) else { return }
  guard session.store.get("urls") is Some(text) else { return }
  let parsed = @json.parse(text) catch { _ => return }
  guard parsed is Array(items) else { return }
  for item in items {
    if item is String(url) {
      host.loaded_urls.push(url)
      host.pending.add(@dhw.load_url(at, url))
    }
  }
}

///|
/// The saved page, rebuilt. None when there is nothing stored.
fn restored_tree() -> @tutuca.Value? {
  guard live.val is Some(host) else { return None }
  guard host.session is Some(session) else { return None }
  guard session.store.get("tree") is Some(text) else { return None }
  let doc = @json.parse(text) catch { _ => return None }
  let snaps : Map[String, @persist.Snapshot] = Map([])
  for id in @persist.saved_ids(session.store) {
    guard id.has_prefix("at/") else { continue }
    guard @persist.load(session.store, id) is Some(snap) else { continue }
    snaps[id[3:].to_owned()] = snap
  }
  match tree_of_json(host.ui, doc, snaps) {
    Null => None
    v => Some(v)
  }
}

// --- the bridge -------------------------------------------------------------

///|
/// The bar a bundle arrives through, with the bookkeeping a SESSION needs.
///
/// The loading itself is `dyncomp/shell`, shared with the storybook because both
/// pages need exactly it. What is here is the half that is this host's: a URL
/// worth writing down, a count of loads still in flight, and the moment the last
/// of them lands — which is when a saved page can finally be put back.
fn host_tools_comp(
  samples : Array[@shell.LoaderBarSample],
) -> @component.Component {
  @shell.loader_bar_comp(
    samples~,
    status=if samples.is_empty() {
      "drop a .tutuca.tar.gz to add its components"
    } else {
      "drop a .tutuca.tar.gz, or load a sample"
    },
    notify=(ev, ctx) => {
      guard live.val is Some(host) else { return }
      match ev {
        // Only URLs: a dropped file has no name the page can fetch, so its
        // components come back only if the same bundle is dropped again.
        Started(url, _) =>
          if url != "" && !host.loaded_urls.contains(url) {
            host.loaded_urls.push(url)
          }
        // Retired BY ID, and only if this host resumed it. A count could not
        // tell a resumed load from a bundle somebody dropped while the resume
        // was still running: the drop's completion would retire a slot the
        // resume was waiting on, and the restore would fire over a page that
        // is not ready for it.
        //
        // A FAILED load retires too, and the last one still restores. Waiting
        // forever for a bundle that will not load is not caution: `pending`
        // also gates `save_session`, so a page stuck waiting goes on to write
        // its empty self over the session it was trying to restore — the one
        // outcome this whole mechanism exists to prevent. Restoring without
        // that bundle loses the components it owned and keeps everything else,
        // which is the honest answer and the recoverable one.
        Loaded(_, load) | Failed(_, load) =>
          if host.pending.contains(load) {
            host.pending.remove(load)
            if host.pending.is_empty() {
              match restored_tree() {
                Some(root) =>
                  ctx.intent(
                    "restoreTree",
                    [root],
                    @tutuca.IntentOpts::new(route=[Dyn]),
                  )
                None => ()
              }
            }
          }
      }
    },
  )
}

///|
/// The module: the app, its chrome, the standard components, and the bar tools.
///
/// One ModuleDef because one app mounts one module — and because the guest
/// components a bundle registers land in the same scope, which is what lets a
/// universal's `<x render=".child">` resolve one. `requests` are the services
/// this HOST offers to whatever it hosts; a bundle that serves a request of the
/// same name answers its own components first.
pub fn universal_module(
  samples? : Array[@shell.LoaderBarSample] = [],
  intents? : Map[String, Array[@component.IntentFn]] = {},
) -> (@component.ModuleDef, @ui.UniversalUi) {
  let (module_, ui) = @ui.seeded_app(
    @dhw.registry(),
    @shell.make_instance,
    dev_tools="LoaderBar",
  )
  (
    @component.ModuleDef::new(
      name="universalwasm",
      components=[..module_.components, host_tools_comp(samples)],
      intents~,
    ),
    ui,
  )
}

// --- margaui class publishing -------------------------------------------

///|
/// Recompile + reinject margaui CSS after a guest bundle registers new views
/// (and thus new utility classes). A host exports this for its loader to call
/// post-load. One implementation, in `dyncomp/shell`, because getting it wrong
/// looks identical on both pages: the guest renders completely unstyled.
pub fn refresh_margaui() -> Unit {
  @shell.refresh_margaui()
}

// --- lifecycle ------------------------------------------------------------

///|
/// Mount the universal UI over the whole page.
///
/// `session` decides persistence at BOTH ends at once — a page that restores
/// but does not save, or the reverse, writes an empty tree over the thing it
/// exists to keep, so one option rather than two flags is the point.
/// `samples` are bundles to offer as buttons; empty draws none. `requests` are
/// services this host offers to what it hosts.
///
/// `policy` is what this page will accept from a bundle, and it defaults to
/// `untrusted`: no capabilities, no bundle CSS, stock quotas. A page that wants
/// a bundle to be able to read a clock or draw a random number has to say so —
/// `@policy.Policy::granted()` is a person having said yes — and a bundle that
/// asks for something ungranted is refused rather than handed a plausible lie,
/// which is why this is the page's decision and not a default anyone can drift
/// into. See `dyncomp/SECURITY.md`.
///
/// Returns `None` if the app could not mount, which on wasm-gc means the page
/// had no `#app` to mount into.
pub fn mount(
  session? : Session? = None,
  samples? : Array[@shell.LoaderBarSample] = [],
  intents? : Map[String, Array[@component.IntentFn]] = {},
  policy? : @policy.Policy = @policy.Policy::untrusted(),
) -> UniversalHost? {
  let (module_, ui) = universal_module(samples~, intents~)
  guard @wglue.mount_in(module_, "UniversalApp") is Some(app) else {
    return None
  }
  let host : UniversalHost = {
    app,
    ui,
    session,
    pending: Set([]),
    loaded_urls: [],
  }
  live.val = Some(host)
  // BEFORE `set_app`, which installs the superseded-handle sweep: drained
  // subscribers run in subscription order, so saving first means every handle
  // this walks is still alive. After the sweep, a component that was just used
  // can be a handle the host has already collected — and a snapshot taken
  // through one is not a snapshot at all.
  app.transactor.on_drained(save_session)
  @shell.set_live_app(app)
  @dhw.set_app(app, @wglue.document(), policy~)
  @shell.refresh_margaui()
  // The bar tools are where a load's answers arrive, so that is the path a
  // resume asks from.
  resume_session(host, @tutuca.DispatchPath::of_steps([FieldStep("devTools")]))
  // A page built entirely out of standard components names no bundles, so
  // nothing is in flight and no load will ever arrive to trigger the restore
  // below. Doing it here is the whole of that case — and it has to be HERE
  // rather than inside `resume_session`, because a page that DOES name bundles
  // must wait for the last of them.
  if host.pending.is_empty() {
    match restored_tree() {
      Some(root) => app.send_at_root("restoreTree", args=[root]) |> ignore
      None => ()
    }
  }
  Some(host)
}

///|
/// Forward a DOM event into the app. A host exports this; JS calls it on every
/// event, since a MoonBit closure cannot cross into JS on wasm-gc.
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
/// The app's whole state as text, for poking at the page from the console.
pub fn state_json() -> String {
  match @dhw.app_root_value() {
    Some(v) => v.to_display_string()
    None => "null"
  }
}
