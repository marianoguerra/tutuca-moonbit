// Ports of the four macro tutorial examples:
//
//   docs/examples/macro-static.js      — a macro with no parameters
//   docs/examples/macro-params.js      — ^params, static vs :dynamic passing
//   docs/examples/macro-slots.js       — <x:slot>, the default slot
//   docs/examples/macro-named-slots.js — named slots
//
// A macro is pure template expansion: no state, no lifecycle, no handlers of
// its own. `@on.click="$inc"` inside a macro calls `inc` on the COMPONENT the
// macro expands into — that is the key difference from a component.
//
// In MoonBit a macro is the plain record `@anode.Macro::{ defaults, raw_view }`;
// `defaults` maps a parameter name to its default *source text* (so a string
// default is written with its quotes: `"'New'"`).

///|
fn badge_macro() -> @anode.Macro {
  { defaults: Map([]), raw_view: "<span class=\"badge badge-info\">New</span>" }
}

///|
fn static_macro_comp() -> @component.Component {
  @component.component(
    name="StaticMacro",
    view=(
      #|<div class="grid grid-cols-[auto_auto] gap-x-4 gap-y-2 items-center justify-start">
      #|  <span>Feature A</span> <x:badge></x:badge>
      #|  <span>Feature B</span> <x:badge></x:badge>
      #|  <span>Feature C</span> <span></span>
      #|</div>
    ),
  )
}

///|
/// Registry keys are lowercased on insert (the HTML parser lowercases
/// `<x:Badge>` to `<x:badge>`), so a capitalized key would register as `badge`
/// too.
pub fn macro_static_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="macro-static",
    components=[static_macro_comp()],
    macros={ "badge": badge_macro() },
    examples=[
      { component: "StaticMacro", title: "Default", args: Map([]), view: None },
    ],
  )
}

///|
/// `^param` reads a macro parameter. A plain attribute passes a STATIC string
/// (`label="Sale"` — no quotes needed, like any HTML attribute); a `:`-prefixed
/// attribute passes an EXPRESSION (`:label="'Sale'"` a literal, `:label=".status"`
/// a field).
fn param_badge_macro() -> @anode.Macro {
  {
    defaults: { "label": "'New'", "kind": "'info'" },
    raw_view: "<span :class=\"$'badge badge-{^kind}'\" @text=\"^label\"></span>",
  }
}

///|
fn macro_params_comp() -> @component.Component {
  @component.component(
    name="MacroParams",
    view=(
      #|<div class="grid grid-cols-[auto_auto] gap-x-4 gap-y-2 items-center">
      #|  <span>Default:</span> <x:badge></x:badge>
      #|  <span>Static label:</span> <x:badge label="Sale"></x:badge>
      #|  <span>Dynamic label:</span> <x:badge :label="'Sale'"></x:badge>
      #|  <span>Custom kind:</span> <x:badge kind="success" label="OK"></x:badge>
      #|  <span>Dynamic:</span> <x:badge :label=".status" :kind="'warning'"></x:badge>
      #|</div>
    ),
    fields={ "status": @component.FieldSpec::of_default(Str("active")) },
  )
}

///|
pub fn macro_params_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="macro-params",
    components=[macro_params_comp()],
    macros={ "badge": param_badge_macro() },
    examples=[
      { component: "MacroParams", title: "Default", args: Map([]), view: None },
      {
        component: "MacroParams",
        title: "Archived",
        args: { "status": Str("archived") },
        view: None,
      },
    ],
  )
}

///|
/// `<x:slot>` is where the macro call's children land.
fn card_macro() -> @anode.Macro {
  {
    defaults: { "title": "'Card'" },
    raw_view: (
      #|<div class="card bg-base-200 shadow-sm">
      #|  <div class="card-body">
      #|    <h2 class="card-title" @text="^title"></h2>
      #|    <x:slot></x:slot>
      #|  </div>
      #|</div>
    ),
  }
}

///|
/// The `@on.click="$inc"` inside the second card's slot content calls `inc` on
/// MacroSlots — macros have no methods of their own.
fn macro_slots_comp() -> @component.Component {
  @component.component(
    name="MacroSlots",
    view=(
      #|<div class="flex gap-3">
      #|  <x:card title="Static Content">
      #|    <p>This content is passed into the card's slot.</p>
      #|  </x:card>
      #|  <x:card title="Interactive">
      #|    <button class="btn btn-soft btn-success bump" @on.click="$inc">+</button>
      #|    <p>Count: <span class="count" @text=".count"></span></p>
      #|  </x:card>
      #|</div>
    ),
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "inc": (inst, _args) => {
        match inst.get("count") {
          Num(n) => inst.set("count", Num(n + 1)).to_value()
          _ => inst.to_value()
        }
      },
    },
  )
}

///|
pub fn macro_slots_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="macro-slots",
    components=[macro_slots_comp()],
    macros={ "card": card_macro() },
    examples=[
      { component: "MacroSlots", title: "Default", args: Map([]), view: None },
    ],
  )
}

///|
/// Named slots: `<x:slot name="actions">` in the macro, `<x slot="actions">` at
/// the call site. Children with no `slot=` go to the default slot.
fn panel_macro() -> @anode.Macro {
  {
    defaults: { "title": "'Panel'" },
    raw_view: (
      #|<div class="card bg-base-200 shadow-sm">
      #|  <div class="card-body">
      #|    <div class="flex justify-between items-center head">
      #|      <h2 class="card-title" @text="^title"></h2>
      #|      <div class="actions"><x:slot name="actions"></x:slot></div>
      #|    </div>
      #|    <div class="body"><x:slot></x:slot></div>
      #|    <div class="card-actions justify-end foot"><x:slot name="footer"></x:slot></div>
      #|  </div>
      #|</div>
    ),
  }
}

///|
fn macro_named_slots_comp() -> @component.Component {
  @component.component(
    name="MacroNamedSlots",
    view=(
      #|<x:panel title="Dashboard">
      #|  <x slot="actions">
      #|    <button class="btn btn-sm btn-soft btn-success bump" @on.click="$inc">+</button>
      #|  </x>
      #|  <p>Count: <span class="count" @text=".count"></span></p>
      #|  <p>This is the default slot content.</p>
      #|  <x slot="footer">
      #|    <span class="text-sm opacity-60 foot-note">Footer content here</span>
      #|  </x>
      #|</x:panel>
    ),
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "inc": (inst, _args) => {
        match inst.get("count") {
          Num(n) => inst.set("count", Num(n + 1)).to_value()
          _ => inst.to_value()
        }
      },
    },
  )
}

///|
pub fn macro_named_slots_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="macro-named-slots",
    components=[macro_named_slots_comp()],
    macros={ "panel": panel_macro() },
    examples=[
      {
        component: "MacroNamedSlots",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}
