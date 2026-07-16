// Build the story set from the compiled example registry (examples/) and group
// it into ordered sidebar sections. Section assignment is metadata-only: a
// curated name -> section map, so the gallery reads like the tutorial rather
// than the raw registry order.

///|
/// The section order shown in the sidebar; any example whose name is not mapped
/// below falls into "Other" (appended last).
let section_order : Array[String] = [
  "Basics", "Lists & Data", "Composition & Views", "Macros & Styles", "Graphics",
  "Behavior", "Lint", "Inspectors", "Other",
]

///|
/// name -> section. Names match the example ids in examples/examples.mbt.
fn section_for(name : String) -> String {
  match name {
    "minimum-viable-component"
    | "static-view-component"
    | "text-directive"
    | "danger-set-inner-html"
    | "counter"
    | "attribute-binding"
    | "conditional-attributes"
    | "event-modifiers"
    | "show-hide"
    | "traffic-light"
    | "tabbed-ui" => "Basics"
    "list-iteration"
    | "list-and-filter"
    | "list-filter-enrich"
    | "list-filter-enrich-with"
    | "seq-item-access"
    | "pagination"
    | "todo"
    | "filter-paginate"
    | "custom-collection"
    | "json" => "Lists & Data"
    "render-with-scope"
    | "render-child"
    | "entry"
    | "multiple-views"
    | "push-view"
    | "dynamic-bindings"
    | "dynamic-path"
    | "dynamic-selected-edit"
    | "composability" => "Composition & Views"
    "styles-example"
    | "macro-static"
    | "macro-params"
    | "macro-slots"
    | "macro-named-slots"
    | "todo-macros"
    | "pseudo-x" => "Macros & Styles"
    "svg-interactive" | "svg-bar-chart" | "svg-icon-macro" | "mathml-formula" =>
      "Graphics"
    "dnd-example"
    | "send-receive"
    | "tree"
    | "request-example"
    | "file-picker"
    | "web-component-custom-event"
    | "personal-site"
    | "visual-wasm" => "Behavior"
    "lint-errors" => "Lint"
    "inspector" => "Inspectors"
    _ => "Other"
  }
}

///|
/// Human title + one-line description for a story, keyed by example name.
/// Carried here (not on the compiled ExampleModule, which tests and the CLI
/// share) because it is gallery display metadata — the same reason `section_for`
/// lives here. Values mirror each JS example's `getExamples()` section
/// title/description (docs/examples/<name>.js). Unmapped names fall back to the
/// id as title with no description.
fn meta_for(name : String) -> (String, String) {
  match name {
    "minimum-viable-component" =>
      ("Minimum Viable Component", "Smallest possible component definition")
    "static-view-component" =>
      ("Static View Component", "Component with only a static view")
    "text-directive" =>
      ("Text Directive", "@text and <x text> render field and method values")
    "danger-set-inner-html" =>
      ("Dangerously Set Inner HTML", "Renders raw HTML content into the DOM")
    "counter" =>
      ("Counter", "A counter component that can be increased and decreased")
    "attribute-binding" =>
      (
        "Attribute Binding", "Two-way binding for string, number and boolean fields",
      )
    "conditional-attributes" =>
      (
        "Conditional Attributes", "@if/@then/@else for class and title attributes",
      )
    "event-modifiers" =>
      ("Event Modifiers", "Send/cancel keyboard modifiers on input events")
    "show-hide" =>
      (
        "Show / Hide", "Conditional display with @show, @hide, and the <x> wrapper form",
      )
    "traffic-light" =>
      ("Traffic Light", "Cycle a light through red, orange, and green")
    "tabbed-ui" =>
      (
        "Tabbed UI", "Switch tabs with the equals? predicate, @show and @if.class",
      )
    "list-iteration" => ("List Iteration", "@each renders one element per item")
    "list-and-filter" =>
      ("List and Filter", "Render a list with a search filter")
    "list-filter-enrich" =>
      (
        "List Filter + Enrich", "@when filter combined with @enrich-with bindings",
      )
    "list-filter-enrich-with" =>
      ("List Filter + Enrich With", "@loop-with provides shared iteration data")
    "seq-item-access" =>
      (
        "Sequence Item Access", "Render specific items by index or key into a sequence",
      )
    "pagination" =>
      (
        "Pagination", "@loop-with slices the sequence so off-page items are never iterated",
      )
    "todo" => ("To Do", "A to-do list with add, complete, and remove")
    "filter-paginate" =>
      (
        "Filter + Paginate — three strategies", "Same feature, scanned 2x / 1.x× / 1x per render — all keep key identity",
      )
    "custom-collection" =>
      (
        "Custom Collection", "@each over a custom keyed collection registered via SEQ_INFO",
      )
    "json" =>
      ("JSON Editor", "Composable JSON editor built from typed primitives")
    "render-with-scope" =>
      ("Render With Scope", "@enrich-with adds derived bindings to a sub-tree")
    "render-child" =>
      (
        "Rendering a Child Component", "A parent renders a child via <x render=...>",
      )
    "entry" => ("Entry", "Card-style entry with a title and description")
    "multiple-views" =>
      (
        "Multiple Views", "Render the same component twice using different views",
      )
    "push-view" =>
      (
        "Push View", "@push-view forces children to render under a different view",
      )
    "dynamic-bindings" =>
      (
        "Dynamic Bindings", "Bind a field through a dynamic variable resolved at render time",
      )
    "dynamic-path" =>
      (
        "Dynamic Variable in a Path", "A dynamic variable used as a <x render> target",
      )
    "dynamic-selected-edit" =>
      (
        "Dynamic Selected Entry — Edit in a Child", "The root owns a keyed list and a selected key, exposed as two dynamics",
      )
    "composability" =>
      (
        "Composability", "Tabbed view that composes several independent example components",
      )
    "styles-example" => ("Styles", "Local, common, global and per-view styles")
    "macro-static" =>
      ("Macro Static", "Macros without parameters expand to static markup")
    "macro-params" =>
      ("Macro Params", "Static and dynamic macro parameter passing")
    "macro-slots" =>
      ("Macro Slots", "Macros with default slots receive component content")
    "macro-named-slots" =>
      (
        "Macro Named Slots", "Macros with multiple named slots (header, body, footer)",
      )
    "todo-macros" =>
      (
        "To Do (Macros)", "To-Do list built using reusable layout/control macros",
      )
    "pseudo-x" =>
      (
        "Pseudo-x (@x)", "Escape the HTML parser by attaching @x as the first attribute on a legal child tag",
      )
    "svg-interactive" =>
      ("Interactive SVG", "Clickable SVG swatches bound to component state")
    "svg-bar-chart" =>
      ("SVG Bar Chart", "A reactive SVG bar chart driven by a list field")
    "svg-icon-macro" =>
      ("SVG Icon Macro", "Parametrized SVG icons defined as macros")
    "mathml-formula" =>
      ("MathML Formula", "A quadratic equation rendered with reactive MathML")
    "dnd-example" => ("Drag and Drop", "Reorder list items via drag and drop")
    "send-receive" => ("Send / Receive", "Targeted messages between components")
    "tree" => ("Tree", "Recursive tree component with bubble events")
    "request-example" =>
      ("Request Example", "Triggers a request on init and renders the response")
    "file-picker" =>
      ("File Picker", "Show metadata about a file chosen with @on.change")
    "web-component-custom-event" =>
      (
        "Web Component & Custom Event", "A Component that shows how to use web component and custom events",
      )
    "personal-site" =>
      ("Personal Site", "Filterable list of entries with categories and roles")
    "visual-wasm" => ("Visual Wasm", "Visual editor for WebAssembly modules")
    "lint-errors" =>
      (
        "Lint Errors", "Components with intentional lint errors for the linter demo",
      )
    "inspector" =>
      (
        "Instance Explorer", "Browse a component's structure and live instance state",
      )
    _ => (name, "")
  }
}

///|
/// Every compiled example as a Story, in registry order. Title and description
/// come from `meta_for` (the human metadata from the JS example's getExamples).
pub fn stories() -> Array[Story] {
  let out : Array[Story] = []
  for e in @ex.all_examples() {
    let (title, description) = meta_for(e.name)
    out.push({
      id: e.name,
      title,
      section: section_for(e.name),
      description,
      module_: e.module_,
      root: e.root,
      args: e.root_args(),
      // the lint-errors module is a linter fixture — its views intentionally
      // trip rules and self-reference, so it is shown for its Lint panel only.
      renderable: e.name != "lint-errors",
      init: e.init,
    })
  }
  out
}

///|
/// Group stories into ordered sections (section_order first, then any
/// leftover sections in first-seen order). Empty sections are dropped.
pub fn sections_of(stories : Array[Story]) -> Array[Section] {
  let by_name : Map[String, Array[Story]] = {}
  let seen_order : Array[String] = []
  for s in stories {
    match by_name.get(s.section) {
      Some(arr) => arr.push(s)
      None => {
        by_name[s.section] = [s]
        seen_order.push(s.section)
      }
    }
  }
  let out : Array[Section] = []
  let emitted : Map[String, Bool] = {}
  for name in section_order {
    match by_name.get(name) {
      Some(arr) => {
        out.push({ title: name, stories: arr })
        emitted[name] = true
      }
      None => ()
    }
  }
  // any section not in the curated order, appended in first-seen order
  for name in seen_order {
    if !emitted.contains(name) {
      match by_name.get(name) {
        Some(arr) => out.push({ title: name, stories: arr })
        None => ()
      }
    }
  }
  out
}
