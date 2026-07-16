// Browser host for the ported docs examples.
//
// The SAME ModuleDef values the headless tests drive (examples/) are mounted
// here as live apps, so a passing test and a working page are the same thing.

///|
extern "js" fn query_param_ffi(name : String) -> String =
  #|(n) => new URLSearchParams(globalThis.location.search).get(n) ?? ""

///|
extern "js" fn set_html_ffi(el : @core.Any, html : String) -> Unit =
  #|(el, html) => { el.innerHTML = html }

///|
/// Hand the collected class set to index.html's margaui step, which imports
/// margaui's `compile` from the CDN and injects the compiled CSS (the
/// browser-side half of JS compileClassesToStyleText).
extern "js" fn publish_classes_ffi(classes : String) -> Unit =
  #|(s) => { globalThis.__tutuca_classes = s ? s.split(" ") : [] }

///|
fn main {
  let doc = @dom.window().document()
  guard doc.getElementById("app") is Some(root_el) else {
    println("no #app element")
    return
  }

  // the index of every ported example, so the page is navigable
  match doc.getElementById("index") {
    Some(nav) => {
      let sb = StringBuilder()
      for e in @ex.all_examples() {
        sb.write_string("<a href=\"?name=\{e.name}\">\{e.name}</a>")
      }
      set_html_ffi(
        @bdom.BrowserNode::from_element(nav).as_any(),
        sb.to_string(),
      )
    }
    None => ()
  }
  let name = match query_param_ffi("name") {
    "" => "counter"
    n => n
  }
  guard @ex.find_example(name) is Some(e) else {
    set_html_ffi(
      @bdom.BrowserNode::from_element(root_el).as_any(),
      "<p>unknown example: <code>\{name}</code> — pick one from the index above.</p>",
    )
    return
  }
  match doc.getElementById("title") {
    Some(t) => set_html_ffi(@bdom.BrowserNode::from_element(t).as_any(), e.name)
    None => ()
  }
  let app = try! @app.App::from_module(
    e.module_,
    e.root,
    @bdom.BrowserNode::from_element(root_el),
    @bdom.opts_for(doc),
    args=e.root_args(),
  )
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  // margaui: collect every class the compiled views can show (literal class
  // attrs, literal fragments of :class / @if.class) and publish the set for
  // index.html's margaui compile step.
  publish_classes_ffi(app.scope.comps.collect_classes().join(" "))
  // tutuca has no lifecycle: the HOST dispatches `init` (JS: app.sendAtRoot)
  if e.init {
    app.send_at_root("init")
  }
}
