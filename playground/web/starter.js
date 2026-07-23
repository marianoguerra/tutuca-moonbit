// Starter modules for the playground picker. Each is authored against the
// tutuca-mb library (@component / @tutuca) and defines only `build()`, which
// returns a ModuleDef. The compiler worker injects the target-specific boot glue
// (js `main` self-mount, or the wasm-gc export wrappers) around it, so the SAME
// source runs on both backends. Ctrl/⌘+Enter to run.
//
// The default idiom is AHEAD-OF-TIME views: the View tab holds the `.html`,
// `tutuca gen-views` turns it into the module shown in the Generated tab
// (compiled as part of THIS package), and the Component tab references the
// generated `<comp>_views()` builder and the typed `<Comp>Msg` it declares.
// An example is `{ view, code }` for that split, or a plain string for the one
// runtime-compiled escape-hatch example at the end.

const EXAMPLES = {
  // The default example. The view lives in the View tab; the component reads
  // the compiled tree and the message enum generated from its @on handlers.
  Counter: {
    view: `<!-- name: Counter -->
<!-- Edit this and the Generated tab updates; the component tab sees the
     names it declares. Adding an @on handler here breaks the match below
     until you handle it — that is the point. -->
<template>
  <style>display:flex;gap:.5rem;align-items:center;font-size:1.5rem</style>
  <div>
    <button id="dec" @on.click="add -1">-</button>
    <b id="count" @text=".count"></b>
    <button id="inc" @on.click="add 1">+</button>
    <span style="font-size:.8rem;opacity:.6" @text=".label"></span>
  </div>
</template>
`,
    code: `// The view lives in the View tab. \`tutuca gen-views\` turns it into the
// module in the Generated tab, which is compiled as part of THIS package —
// so counter_views(), CounterMsg and CounterId are all in scope here.
struct CounterState {
  count : Int
  label : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
    name="Counter",
    // the compiled tree from the View tab: no template parsing at startup
    views=counter_views(),
    init=CounterState::{ count: 0, label: "clicks" },
    // CounterMsg is generated from the @on handlers in the View tab, with
    // payload types read off the call sites — \`add 1\` makes Add(Double).
    update=(s : CounterState, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
      Some(Add(d)) => Some({ ..s, count: s.count + d.to_int() })
      Some(Unknown(_, _)) | None => None
    },
  )
  @component.ModuleDef::new(
    name="counter", components=[counter],
    examples=[{ component: "Counter", title: "Default", args: Map([]), view: None }],
  )
}
`,
  },

  // A field named 'open' gets a generated $toggleOpen mutator for free, and
  // compute derives the label — so the component has no @on Input handlers at
  // all, and no update. The View tab still compiles ahead of time.
  Toggle: {
    view: `<!-- name: Panel -->
<template>
  <style>font-family:system-ui</style>
  <section>
    <button @on.click="\$toggleOpen" @text="\$label"></button>
    <p @show=".open" style="padding:.5rem;border:1px solid #ccc;margin-top:.5rem">
      Now you see me. Toggle again to hide.
    </p>
  </section>
</template>
`,
    code: `// 'open' is a Bool field, so \$toggleOpen is generated; \$label is a compute.
// No hand-written handlers, no update — the view drives it all.
struct PanelState {
  open : Bool
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let panel = @component.component(
    name="Panel",
    views=panel_views(),
    init=PanelState::{ open: false },
    compute={
      "label": (s : PanelState, _a) => Str(
        if s.open { "Hide details" } else { "Show details" },
      ),
    },
  )
  @component.ModuleDef::new(
    name="toggle", components=[panel],
    examples=[{ component: "Panel", title: "Closed", args: Map([]), view: None }],
  )
}
`,
  },

  // Two-way binding: :value reads the field, @on.input writes it via the
  // generated $setName mutator. @text mirrors it live. No handlers needed.
  "Text input": {
    view: `<!-- name: Greeter -->
<template>
  <div style="font-family:system-ui;display:flex;flex-direction:column;gap:.5rem">
    <input :value=".name" @on.input="\$setName value" placeholder="your name">
    <p>Hello, <b @text=".name"></b>!</p>
  </div>
</template>
`,
    code: `// :value + @on.input="\$setName value" is a two-way bind through the field's
// generated \$setName mutator. @text mirrors it live. No handlers needed.
struct GreeterState {
  name : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let greeter = @component.component(
    name="Greeter",
    views=greeter_views(),
    init=GreeterState::{ name: "world" },
  )
  @component.ModuleDef::new(
    name="greeter", components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
`,
  },

  // The escape hatch: no View tab, so the view is a runtime string compiled by
  // @anode.View::new, and update matches the raw Dispatch with NO type help —
  // \`Input("dec", _)\` is a bare string, and a typo just silently never fires.
  // Prefer the AOT examples above; reach for this only for a genuinely dynamic
  // or throwaway view.
  "Dynamic view (raw handlers)": `// Runtime-compiled view + untyped handlers — the escape hatch. The AOT
// examples above turn the View tab into a checked module instead.
struct CounterState {
  count : Int
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<div style="display:flex;gap:.5rem;align-items:center;font-size:1.5rem">
      #|  <button @on.click="dec">-</button>
      #|  <b @text=".count"></b>
      #|  <button @on.click="\$inc">+</button>
      #|</div>
    )),
  },
  name="Counter",
  init=CounterState::{ count: 0 },
  update=(s : CounterState, msg, _ctx) => match msg {
      Input("dec", _) => Some({ count: s.count - 1 })
      _ => None
    },
  mutate={ "inc": (s : CounterState, _a) => { count: s.count + 1 } },
)
  @component.ModuleDef::new(
    name="counter", components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
`,
};

// expose on window so the module driver can read them
window.EXAMPLES = EXAMPLES;
// default to the ahead-of-time Counter (component + its View tab)
window.STARTER = EXAMPLES.Counter.code;
window.STARTER_VIEW = EXAMPLES.Counter.view;
