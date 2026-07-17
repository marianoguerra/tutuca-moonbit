// Browser boot for the counter demo running as wasm-gc: the SAME ModuleDef the
// CLI and the js demo use, mounted as a live app whose DOM is driven from wasm.
// JS calls `mount()` after the page loads, then `on_event` on each DOM event.

///|
fn main {

}

///|
/// Mount the counter on #app. Called from JS once the DOM is ready.
pub fn mount() -> Unit {
  let _ = @wglue.mount_in(@counterlib.module_def(), "Counter")
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}
