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
/// Every compiled example as a Story, in registry order. The title is the
/// example's own ExampleDef title when it has a seeded one, else the id.
pub fn stories() -> Array[Story] {
  let out : Array[Story] = []
  for e in @ex.all_examples() {
    out.push({
      id: e.name,
      title: e.name,
      section: section_for(e.name),
      description: "",
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
