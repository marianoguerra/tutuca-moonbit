// Browser boot for the counter demo: the SAME ModuleDef that drives the
// embedded CLI (demo/counter_cli) mounted as a live app.

///|
fn main {
  let m = @counterlib.module_def()
  let doc = @dom.window().document()
  guard doc.getElementById("app") is Some(root_el) else {
    println("no #app element")
    return
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  let app = try! @app.App::from_module(
    m,
    "Counter",
    root_node,
    @bdom.opts_for(doc),
  )
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
}
