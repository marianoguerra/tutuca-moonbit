// The storybook data model: a Story wraps one compiled example (its ModuleDef
// + root component + seed args) with gallery metadata (section, title). A
// Section is a named, ordered group of stories for the sidebar.

///|
pub(all) struct Story {
  /// stable, unique slug — the sidebar selection key and the example name
  id : String
  /// display title shown in the sidebar and pane header
  title : String
  /// sidebar group label
  section : String
  /// short blurb shown under the pane header (may be empty)
  description : String
  module_ : @component.ModuleDef
  /// the component mounted as the story's root
  root : String
  /// args the root is made with (from the example's own ExampleDef)
  args : Map[String, @tutuca.Value]
  /// false for lint fixtures (e.g. lint-errors) whose views intentionally
  /// contain malformed/self-referential bindings — they are meant to be
  /// LINTED, not rendered, so the pane shows only the Lint panel.
  renderable : Bool
  /// examples with no lifecycle that need a host-dispatched `init` to load
  /// their data (JS `app.sendAtRoot("init")`); the gallery forwards `init` to
  /// these panes after mount. Mirrors examples/ ExampleModule.init.
  init : Bool
}

///|
pub(all) struct Section {
  title : String
  stories : Array[Story]
}
