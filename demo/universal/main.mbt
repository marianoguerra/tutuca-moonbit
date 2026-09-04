///|
/// Boot.
///
/// An executable rather than a library because the page loads one script and
/// expects the entry points to be there afterwards, with nothing to call first.
fn main {
  install()
}

///|
extern "js" fn install_entry_points(
  boot : () -> Unit,
  finish : (String, String) -> String,
  fetched : (String, String) -> Unit,
  dropped_ : (String, String) -> Unit,
  library_ : (String, String) -> Unit,
  drain_ : (String, String) -> Unit,
) -> Unit =
  #|(boot, finish, fetched, dropped, library, drain) => {
  #|  globalThis.__universalHost = { boot, finish, fetched, dropped, library, drain };
  #|}

///|
fn install() -> Unit {
  install_entry_points(
    () => boot(),
    (key, manifest) => finish_load(key, manifest),
    (tag, source) => card_fetched(tag, source),
    (name, text) => dropped(name, text),
    (names, paths) => set_library(names, paths),
    (verb, argument) => drain(verb, argument),
  )
}

///|
/// Mount the shell, then load the kit.
///
/// The KIT IS LOADED, not compiled in. Until it arrives there is no `Hole` to
/// put on the canvas — which is why `canvas` starts null and the page says so
/// rather than drawing an empty box that means nothing.
fn boot() -> Unit {
  let doc = @dom.window().document()
  guard doc.getElementById("app") is Some(root_el) else {
    println("no #app element")
    return
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  // ONE SCOPE, shared with every module that will be loaded. `from_module`
  // would build a registry of its own, and a canvas holding a component from a
  // module that registry never heard of renders as nothing — silently, because
  // a view the renderer cannot resolve is not an error.
  scope.register_components(@ui.components())
  let app = @app.App::new(
    scope,
    @ui.root_value(),
    root_node,
    @bdom.opts_for(doc),
  ) catch {
    e => {
      println("could not mount: \{e}")
      return
    }
  }
  live.val = Some(app)
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  refresh_margaui()
  // Every instance the host stops holding, released. Both halves: `install_gc`
  // frees the predecessor a successor replaced — which is every interaction,
  // since an instance is immutable — and the sweep frees a cell that was
  // REMOVED, which is superseded by nothing and which only reachability can
  // find. A composition demo does both constantly.
  @host.install_gc(app.transactor)
  @guest.install_sweep("std", () => app.root_value(), app.transactor)
  // THE PUMP. The shell posts a verb and one argument into its own state and
  // this reads them once the cascade that posted them has settled — which is
  // the only moment it is safe to answer, because answering means dispatching
  // again. A component cannot call out here itself: the catalog, the compiler
  // and the registry are the page's, and a view can reach none of them.
  app.transactor.on_drained(() => pump(app))
  // The one thing that must be loaded before anything can be placed.
  load_card(@std.card_source(), "std") |> ignore
}

///|
/// The margaui classes every component on the page uses, compiled here.
///
/// Compiled rather than fetched: the class compiler is a MoonBit library in
/// this bundle, so there is no CDN build and no `globalThis` class hand-off.
/// It has to be re-run after a MODULE LOADS as well as at mount, because a
/// card that arrives ten seconds in brings class names nothing has compiled —
/// and a component whose classes were never compiled renders with no styling
/// at all rather than failing.
pub fn refresh_margaui() -> Unit {
  guard live.val is Some(app) else { return }
  let doc = @dom.window().document()
  let css = @css.compile_margaui(app.scope.comps.collect_classes()[:]) catch {
    e => {
      println("margaui: \{e}")
      return
    }
  }
  @glue.inject_style(@bdom.BrowserNode::from_document(doc), "margaui-css", css)
}

///|
/// Read the shell's pump, once, and answer it.
///
/// Guarded against re-entry: answering a verb dispatches, dispatching drains,
/// and draining runs this again. The guard is what turns that into one answer
/// rather than a loop.
let pumping : Ref[Bool] = Ref(false)

///|
fn pump(app : @app.App[@bdom.BrowserNode]) -> Unit {
  if pumping.val {
    return
  }
  let root = app.root_value()
  guard root.field("pending") is Str(verb) && verb != "" else { return }
  let argument = match root.field("argument") {
    Str(a) => a
    _ => ""
  }
  pumping.val = true
  drain(verb, argument)
  pumping.val = false
}

///|
/// The layout kit is up: put its empty hole on the canvas.
///
/// Called from `finish_load` for the kit and nothing else, because the canvas
/// starting as a hole is a fact about the KIT rather than about loading.
fn seed_canvas() -> Unit {
  guard live.val is Some(app) else { return }
  if app.root_value().field("canvas") is Obj(_) {
    return
  }
  match @guest.make_instance(@std.module_name(), "Hole") {
    Some(hole) => {
      @ui.forget_cell()
      app.send_at_root("placeBuilt", args=[hole, Bool(false)]) |> ignore
    }
    None => note("the layout kit has no Hole in it", tone="error")
  }
}
