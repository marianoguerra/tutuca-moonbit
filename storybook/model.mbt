// The storybook data model: a Story wraps one compiled example (its ModuleDef
// + root component + seed args) with gallery metadata (section, title). A
// Section is a named, ordered group of stories for the sidebar.
//
// Both are `pub(all)`, so a consumer can write a Story literal or update one
// with `{ ..s, init: true }`. The usual way to GET stories is not to write
// them at all — `project.mbt` derives them from a module's own `examples`.

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
  /// the root's view name, empty for the component's default resolution
  /// (`ExampleDef.view`, which the gallery honours through `@push-view`)
  view : String
  /// false for a fixture that is meant to be listed but never mounted —
  /// a view that deliberately contains malformed or self-referential
  /// bindings. Its pane shows a note instead of an instance.
  renderable : Bool
  /// tutuca has no lifecycle, so a story whose root loads its data on `init`
  /// needs the host to say so: the gallery forwards `init` into these panes
  /// after mount. No ExampleDef field implies it — set it yourself.
  init : Bool
}

///|
pub(all) struct Section {
  title : String
  stories : Array[Story]
}
