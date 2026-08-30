// wasm-gc host for the storybook gallery: this repo's own story set, mounted
// through the shipped browser host (`storybook/ui/wasm`).
//
// What is left here is the one thing a library cannot supply — a wasm-gc export
// list is per-package `link` configuration and cannot come from a dependency —
// plus the choice of which stories to show. `tutuca new-storybook` writes the
// same five forwards for a downstream page.

///|
fn main {

}

///|
/// Mount the whole gallery on #app. Called from JS once the DOM is ready.
pub fn mount() -> Unit {
  let sections = @sb.sections_of(@ex.stories(), order=@ex.section_order)
  // The standard tabs, asked for by name: `storybook/ui/wasm` links no panel
  // layer of its own, so this is what puts the inspector, the recorder and the
  // fuzz driver in the page.
  @sbw.mount(sections, panels=@panelsw.all(sections)) |> ignore
}

///|
/// The delegated DOM event entry point JS calls (via tdom.add_listener).
pub fn on_event(ev : @core.Any) -> Unit {
  @panelsw.on_event(ev)
}

///|
/// Back/Forward: re-read the URL and restore the selection/filter/focus.
pub fn on_popstate() -> Unit {
  @sbw.on_popstate()
}

///|
/// One animation frame of a playing fuzz run.
pub fn on_fuzz_tick() -> Unit {
  @panelsw.on_fuzz_tick()
}

///|
/// Recompile + reinject the margaui sheet for the mounted gallery.
pub fn refresh_margaui() -> Unit {
  @sbw.refresh_margaui()
}
