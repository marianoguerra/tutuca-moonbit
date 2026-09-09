///|
fn main {

}

///|
/// Mount the quantity picker on #app. Called from JS once the DOM is ready.
pub fn mount() -> Unit {
  if @wglue.mount_in(@showcase.quantity_picker_module(), "QuantityPicker")
    is Some(app) {
    @wglue.inject_style(
      @wglue.document(),
      "margaui-css",
      try! @css.compile_margaui(app.scope.comps.collect_classes()),
    )
  }
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}
