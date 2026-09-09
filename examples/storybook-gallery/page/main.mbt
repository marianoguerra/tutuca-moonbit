///|
fn main {

}

///|
/// The gallery's sections, in the order the sidebar shows them. Add a module
/// to the list and every example it declares becomes a story.
fn sections() -> Array[@sb.Section] {
  let stories = @sb.stories_of_modules([quantity_picker_module()], section_of=m => match
    m.name {
      "quantity-picker" => "Learn"
      _ => "Other"
    })
  @sb.sections_of(stories, order=["Learn", "Other"])
}

///|
/// Mount the gallery on #app. Called from JS once the DOM is ready.
///
/// `panels~` is asked for by name because `storybook/ui/wasm` links no panel
/// layer of its own: this line is what puts the Instance, Trace, Fuzz, Spec and
/// Raw tabs in the page. Drop it (and the `@panelsw` import) and the gallery is
/// stories only — and megabytes lighter.
pub fn mount() -> Unit {
  let sections = sections()
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

///|
/// The page's answer to a file the Trace tab asked to read.
///
/// An export for the reason `on_fuzz_tick` is one: a closure cannot cross into
/// JS on wasm-gc, so the browser answers an asynchronous read by calling back
/// in. Drop it and the Trace tab's Download still works — a download is
/// one-way — but Load reads the file and never delivers it.
pub fn on_file_text(req_id : Int, ok : Bool, text : String) -> Unit {
  @panelsw.on_file_text(req_id, ok, text)
}
