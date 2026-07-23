// Ports of:
//   docs/examples/traffic-light.js  — @show + the binary `equals?` predicate
//   docs/examples/tabbed-ui.js      — one string field drives the whole UI
//   docs/examples/list-and-filter.js — @each + @when (a `when` predicate)

///|
let traffic_lights : Array[String] = ["red", "orange", "green"]

///|
priv struct TrafficLightState {
  lightIndex : Int
} derive(ToJson, FromJson)

///|
/// The React traffic-light exercise. The colour is DERIVED from a single
/// `lightIndex` field by the `light` method; per-colour visibility uses the
/// built-in binary predicate `equals?` (written predicate-first) in place of
/// React's inline `&&`.
fn traffic_light_comp() -> @component.Component {
  @component.component(
    views=traffic_light_views(),
    name="TrafficLight",
    init=TrafficLightState::{ lightIndex: 0 },
    compute={
      "light": (s : TrafficLightState, _args) => {
        Str(traffic_lights[s.lightIndex % traffic_lights.length()])
      },
    },
    mutate={
      "nextLight": (s : TrafficLightState, _args) => {
        lightIndex: (s.lightIndex + 1) % traffic_lights.length(),
      },
    },
  )
}

///|
pub fn traffic_light_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="traffic-light",
    components=[traffic_light_comp()],
    examples=[
      { component: "TrafficLight", title: "Red", args: Map([]), view: None },
      {
        component: "TrafficLight",
        title: "Orange",
        args: { "lightIndex": Num(1) },
        view: None,
      },
      {
        component: "TrafficLight",
        title: "Green",
        args: { "lightIndex": Num(2) },
        view: None,
      },
    ],
  )
}

///|
priv struct TabbedUiState {
  tab : String
} derive(ToJson, FromJson)

///|
/// A whole tabbed UI out of one string field: `equals?` in `@show` picks the
/// visible panel, and the same predicate in `@if.class` highlights the active
/// button. No per-tab flags, no component per tab.
fn tabbed_ui_comp() -> @component.Component {
  @component.component(views=tabbed_u_i_views(), name="TabbedUI", init=TabbedUiState::{
    tab: "overview",
  })
}

///|
pub fn tabbed_ui_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="tabbed-ui", components=[tabbed_ui_comp()], examples=[
    { component: "TabbedUI", title: "Overview", args: Map([]), view: None },
    {
      component: "TabbedUI",
      title: "Pricing",
      args: { "tab": Str("pricing") },
      view: None,
    },
  ])
}

///|
priv struct ListAndFilterState {
  items : Array[@tutuca.Value]
  query : String
} derive(ToJson, FromJson)

///|
/// `@when="filterItem"` calls the `when.filterItem` predicate per entry;
/// returning false skips the item. `when` handlers receive the typed state,
/// so the predicate reads `s.query` to filter against the live search string.
///
/// Call convention (the renderer, render/render.mbt): a @when handler gets
/// (key, value, iterData).
fn list_and_filter_comp() -> @component.Component {
  @component.component(
    views=list_and_filter_views(),
    name="ListAndFilter",
    init=ListAndFilterState::{ items: [], query: "" },
    when={
      "filterItem": (s : ListAndFilterState, _key, value, _iter) => {
        match value {
          Str(item) => item.to_lower().contains(s.query.to_lower())
          _ => true
        }
      },
    },
  )
}

///|
pub fn list_and_filter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-and-filter",
    components=[list_and_filter_comp()],
    examples=[
      {
        component: "ListAndFilter",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
      {
        component: "ListAndFilter",
        title: "Filtered",
        args: { "items": List(items()), "query": Str("those") },
        view: None,
      },
    ],
  )
}
