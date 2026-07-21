// The registry of ported examples: name -> (ModuleDef, root component).
//
// One list, consumed by three things:
//   - the storybook gallery (storybook/ + storybook/ui) — grouped into sections
//     and mounted as one live app (demo/storybook_wasm)
//   - the headless tests    (*_test.mbt) — mount and drive them
//   - the CLI               (plan_with_module) — `render` / `lint` / `show`
//
// Names match the JS file they were ported from (docs/examples/<name>.js).

///|
pub struct ExampleModule {
  name : String
  /// the component to mount as the root of the app
  root : String
  module_ : @component.ModuleDef
  /// examples whose root component needs seeded args use their own ExampleDef;
  /// the browser host mounts this one by title
  example_title : String?
  /// dispatched at the root after start() — tutuca has no lifecycle, the host
  /// decides (JS: app.sendAtRoot("init"))
  init : Bool
}

///|
/// Every ported example, ordered the way the tutorial introduces them:
/// simplest first.
pub fn all_examples() -> Array[ExampleModule] {
  [
    ex(
      "minimum-viable-component",
      "MinimumViableComponent",
      minimum_viable_module(),
    ),
    ex("static-view-component", "StaticViewComponent", static_view_module()),
    ex("text-directive", "TextDirective", text_directive_module()),
    ex(
      "danger-set-inner-html",
      "DangerSetInnerHtml",
      danger_set_inner_html_module(),
    ),
    ex("counter", "Counter", counter_module()),
    ex("attribute-binding", "AttributeBinding", attribute_binding_module()),
    ex(
      "conditional-attributes",
      "ConditionalAttributes",
      conditional_attributes_module(),
    ),
    ex("event-modifiers", "EventModifiers", event_modifiers_module()),
    ex("show-hide", "ShowHide", show_hide_module()),
    ex("traffic-light", "TrafficLight", traffic_light_module()),
    ex("tabbed-ui", "TabbedUI", tabbed_ui_module()),
    ex(
      "list-iteration",
      "ListIteration",
      list_iteration_module(),
      title="Default",
    ),
    ex(
      "list-and-filter",
      "ListAndFilter",
      list_and_filter_module(),
      title="Default",
    ),
    ex(
      "list-filter-enrich",
      "ListFilterEnrich",
      list_filter_enrich_module(),
      title="Default",
    ),
    ex(
      "list-filter-enrich-with",
      "ListFilterEnrichWith",
      list_filter_enrich_with_module(),
      title="Default",
    ),
    ex("render-with-scope", "RenderWithScope", render_with_scope_module()),
    ex("render-child", "Page", render_child_module()),
    ex("entry", "Entry", entry_module()),
    ex("multiple-views", "MultipleViews", multiple_views_module()),
    ex(
      "seq-item-access",
      "SeqItemAccess",
      seq_item_access_module(),
      title="Default",
    ),
    ex("push-view", "PushView", push_view_module(), title="Read Only"),
    ex("pagination", "Pagination", pagination_module(), title="First Page"),
    ex("todo", "Items", todo_module()),
    ex("styles-example", "StylesExampleRoot", styles_module()),
    ex("macro-static", "StaticMacro", macro_static_module()),
    ex("macro-params", "MacroParams", macro_params_module()),
    ex("macro-slots", "MacroSlots", macro_slots_module()),
    ex("macro-named-slots", "MacroNamedSlots", macro_named_slots_module()),
    ex("todo-macros", "Items", todo_macros_module()),
    ex("pseudo-x", "PseudoXDemo", pseudo_x_module(), title="Default"),
    ex(
      "filter-paginate",
      "Strategies",
      filter_paginate_module(),
      title="Default",
    ),
    ex("svg-interactive", "SwatchPicker", svg_interactive_module()),
    ex("svg-bar-chart", "BarChart", svg_bar_chart_module()),
    ex("svg-icon-macro", "IconGallery", svg_icon_macro_module()),
    ex("mathml-formula", "Quadratic", mathml_formula_module()),
    ex("dnd-example", "DnDExample", dnd_module(), title="Default"),
    ex("send-receive", "SendReceive", send_receive_module()),
    ex("tree", "TreeRoot", tree_module(), title="Default"),
    ex("request-example", "RequestExample", request_module(), init=true),
    ex("dynamic-bindings", "EntryEditorAndSelector", dynamic_bindings_module()),
    ex("dynamic-path", "Workspace", dynamic_path_module()),
    ex(
      "dynamic-selected-edit",
      "Root",
      dynamic_selected_edit_module(),
      title="First selected",
    ),
    ex(
      "custom-collection",
      "Playlist",
      custom_collection_module(),
      title="Playlist",
    ),
    ex("file-picker", "FilePicker", file_picker_module()),
    ex("web-component-custom-event", "EmojiPicker", web_component_module()),
    ex("lint-errors", "LintDemo", lint_errors_module()),
    ex("json", "JsonArray", json_module(), title="Empty Array With Selector"),
    ex("personal-site", "Root", personal_site_module(), init=true),
    ex("visual-wasm", "Module", visual_wasm_module()),
    ex(
      "composability",
      "Composability",
      composability_module(),
      title="Default (To-Do tab)",
      init=true,
    ),
    // the tutuca/components inspector library, browsable like any example
    ex(
      "inspector",
      "InstanceExplorer",
      @inspector.inspector_module(),
      title="Instance Explorer",
    ),
  ]
}

///|
fn ex(
  name : String,
  root : String,
  module_ : @component.ModuleDef,
  title? : String,
  init? : Bool = false,
) -> ExampleModule {
  { name, root, module_, example_title: title, init }
}

///|
/// The args to mount the example's root with: its named ExampleDef's, if it has
/// one (that is where child-component instances are correctly built from the
/// module's OWN registered components), otherwise empty.
pub fn ExampleModule::root_args(
  self : ExampleModule,
) -> Map[String, @tutuca.Value] {
  match self.example_title {
    Some(t) =>
      for e in self.module_.examples {
        if e.title == t {
          return e.args
        }
      } nobreak {
        Map([])
      }
    None => Map([])
  }
}
