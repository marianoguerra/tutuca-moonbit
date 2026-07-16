// The playground mount facade. The user's freshly-compiled `main` calls
// `@host.mount(build(), "app")`; this file does everything a browser host
// normally does (App::from_module + the app/browser event glue + style
// injection), holds the live app so the inspector can read its state, and
// publishes the margaui class set for the page to compile.

///|
/// The mounted app, held so `state_json` / `classes_json` can reach it after
/// events have morphed the DOM. One app per page, which is the playground shape.
let current : Ref[@app.App[@bdom.BrowserNode]?] = Ref(None)

///|
/// Mount a user-authored module on `#<root_id>` and wire events + styles.
///
/// `root` names the component to mount; when omitted it defaults to the first
/// example's component (and that example's args), matching how demo/examples
/// picks a root. Raises nothing to the caller — mount problems are reported to
/// the console so a broken module can't take the whole page down.
pub fn mount(
  m : @component.ModuleDef,
  root_id : String,
  root? : String,
  args? : Map[String, @tutuca.Value],
) -> Unit {
  let doc = @dom.window().document()
  guard doc.getElementById(root_id) is Some(root_el) else {
    println("playground: no #\{root_id} element")
    return
  }
  // pick the root component + args (explicit > first example > first component)
  let (root_name, root_args) = match root {
    Some(r) => (r, args.unwrap_or({}))
    None =>
      match m.examples {
        [ex, ..] => (ex.component, args.unwrap_or(ex.args))
        [] =>
          // no examples: fall back to the module name; the module must contain a
          // component of that name, else from_module raises below.
          (m.name, args.unwrap_or({}))
      }
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  let app = @app.App::from_module(
    m,
    root_name,
    root_node,
    @bdom.opts_for(doc),
    args=root_args,
  ) catch {
    e => {
      println("playground: mount failed: \{e}")
      return
    }
  }
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  current.val = Some(app)
  // hand the inspector getters to the page (globalThis.__tutuca.state() etc.)
  publish_inspector(() => state_json(), () => classes_json())
  // tutuca has no lifecycle: the HOST dispatches `init` (JS app.sendAtRoot).
  app.send_at_root("init")
}

///|
/// Publish live-app getters on the page so the playground shell's inspector can
/// read current state / margaui classes at any time, and after any event.
extern "js" fn publish_inspector(
  state : () -> String,
  classes : () -> String,
) -> Unit =
  #|(state, classes) => { globalThis.__tutuca = { state, classes } }

///|
/// Current root state for the inspector's "State" panel, as tutuca's own
/// readable value syntax (e.g. `Counter{count: 1}`). A component instance is an
/// `Obj`, which has no JSON form, so we use the Value's Show rendering — the
/// same representation the CLI and tests print — rather than `to_json` (which
/// would flatten the instance to null).
pub fn state_json() -> String {
  match current.val {
    Some(app) =>
      match app.root_value() {
        Some(v) => v.to_display_string()
        None => "—"
      }
    None => "—"
  }
}

///|
/// The margaui class set the mounted views can show, as a JSON array string,
/// so the page can compile it to CSS (the browser-side half of the js host's
/// publish_classes_ffi).
pub fn classes_json() -> String {
  match current.val {
    Some(app) => {
      let arr = app.scope.comps.collect_classes()
      Json::array(arr.map(c => Json::string(c))).stringify()
    }
    None => "[]"
  }
}
