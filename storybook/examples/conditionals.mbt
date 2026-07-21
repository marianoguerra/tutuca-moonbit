// Ports of:
//   docs/examples/traffic-light.js  — @show + the binary `equals?` predicate
//   docs/examples/tabbed-ui.js      — one string field drives the whole UI
//   docs/examples/list-and-filter.js — @each + @when (an `alter` predicate)

///|
let traffic_lights : Array[String] = ["red", "orange", "green"]

///|
/// The React traffic-light exercise. The colour is DERIVED from a single
/// `lightIndex` field by the `light` method; per-colour visibility uses the
/// built-in binary predicate `equals?` (written predicate-first) in place of
/// React's inline `&&`.
fn traffic_light_comp() -> @component.Component {
  @component.component(
    name="TrafficLight",
    view=(
      #|<section class="flex flex-col gap-2">
      #|  <button class="btn btn-primary" @on.click="$nextLight">Next light</button>
      #|  <p>Light is: <code @text="$light"></code></p>
      #|  <p class="advice">
      #|    You must
      #|    <span @show="equals? $light 'red'">STOP</span>
      #|    <span @show="equals? $light 'orange'">SLOW DOWN</span>
      #|    <span @show="equals? $light 'green'">GO</span>
      #|  </p>
      #|</section>
    ),
    fields={ "lightIndex": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "light": (inst, _args) => {
        match inst.get("lightIndex") {
          Num(n) => Str(traffic_lights[n.to_int() % traffic_lights.length()])
          _ => Null
        }
      },
      "nextLight": (inst, _args) => {
        match inst.get("lightIndex") {
          Num(n) =>
            inst
            .set(
              "lightIndex",
              Num(((n.to_int() + 1) % traffic_lights.length()).to_double()),
            )
            .to_value()
          _ => inst.to_value()
        }
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
/// A whole tabbed UI out of one string field: `equals?` in `@show` picks the
/// visible panel, and the same predicate in `@if.class` highlights the active
/// button. No per-tab flags, no component per tab.
fn tabbed_ui_comp() -> @component.Component {
  @component.component(
    name="TabbedUI",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <div role="tablist" class="tabs tabs-border">
      #|    <button role="tab" id="t-overview"
      #|      @if.class="equals? .tab 'overview'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setTab 'overview'">Overview</button>
      #|    <button role="tab" id="t-features"
      #|      @if.class="equals? .tab 'features'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setTab 'features'">Features</button>
      #|    <button role="tab" id="t-pricing"
      #|      @if.class="equals? .tab 'pricing'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setTab 'pricing'">Pricing</button>
      #|  </div>
      #|  <div class="card p-3 border panel" @show="equals? .tab 'overview'">
      #|    <h4>Overview</h4><p>A short summary of what this product does.</p>
      #|  </div>
      #|  <div class="card p-3 border panel" @show="equals? .tab 'features'">
      #|    <h4>Features</h4><p>The list of features lives on this tab.</p>
      #|  </div>
      #|  <div class="card p-3 border panel" @show="equals? .tab 'pricing'">
      #|    <h4>Pricing</h4><p>What it costs.</p>
      #|  </div>
      #|</section>
    ),
    fields={ "tab": @component.FieldSpec::of_default(Str("overview")) },
  )
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
/// `@when="filterItem"` calls `alter.filterItem` per entry; returning false
/// skips the item. `alter` functions receive the instance as `this`, so the
/// predicate reads `.query` to filter against the live search string.
///
/// Call convention (the renderer, render/render.mbt): a @when handler gets
/// args `[key, value, iterData]`.
fn list_and_filter_comp() -> @component.Component {
  @component.component(
    name="ListAndFilter",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input type="search" class="input" :value=".query"
      #|    @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|    placeholder="Filter entries" />
      #|  <ul>
      #|    <li @each=".items" @when="filterItem">
      #|      <span @text="@key"></span>: <x text="@value"></x>
      #|    </li>
      #|  </ul>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "query": @component.FieldSpec::of_default(Str("")),
    },
    alter={
      "filterItem": (inst, args) => {
        match (inst.get("query"), args) {
          (Str(q), [_key, Str(item), ..]) =>
            Bool(item.to_lower().contains(q.to_lower()))
          _ => Bool(true)
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
