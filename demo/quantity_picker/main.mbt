///|
fn main {
  let m = @showcase.quantity_picker_module()
  let doc = @dom.window().document()
  guard doc.getElementById("app") is Some(root_el) else {
    println("no #app element")
    return
  }
  let root_node = @bdom.BrowserNode::from_element(root_el)
  let app = try! @app.App::from_module(
    m,
    "QuantityPicker",
    root_node,
    @bdom.opts_for(doc),
  )
  @glue.install(app)
  @glue.install_styles(app, @bdom.BrowserNode::from_document(doc))
  @glue.inject_style(
    @bdom.BrowserNode::from_document(doc),
    "margaui-css",
    try! @css.compile_margaui(app.scope.comps.collect_classes()),
  )
}
