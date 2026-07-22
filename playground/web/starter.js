// Starter modules for the playground picker. Each is authored against the
// tutuca-mb library (@component / @tutuca) and defines only `build()`, which
// returns a ModuleDef. The compiler worker injects the target-specific boot glue
// (js `main` self-mount, or the wasm-gc export wrappers) around it, so the SAME
// source runs on both backends. Ctrl/⌘+Enter to run.

const EXAMPLES = {
  Counter: `// A counter. State is a typed struct; fields get generated mutators ($inc
// could also be written as \$updateCount) and update handles bare-name events.
struct CounterState {
  count : Int
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
  compiled_views={
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

  "Toggle (no logic)": `// A field named 'open' gets a generated \$toggleOpen mutator for free — no
// hand-written handler. @show/@hide read the field; compute derives the label.
struct PanelState {
  open : Bool
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let panel = @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<section style="font-family:system-ui">
      #|  <button @on.click="\$toggleOpen" @text="\$label"></button>
      #|  <p @show=".open" style="padding:.5rem;border:1px solid #ccc;margin-top:.5rem">
      #|    Now you see me. Toggle again to hide.
      #|  </p>
      #|</section>
    )),
  },
  name="Panel",
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

  "Text input": `// Two-way binding: :value reads the field, @on.input writes it via the
// generated \$setName mutator. @text mirrors it live. No handlers needed.
struct GreeterState {
  name : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let greeter = @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div style="font-family:system-ui;display:flex;flex-direction:column;gap:.5rem">
      #|  <input :value=".name" @on.input="\$setName value" placeholder="your name" />
      #|  <p>Hello, <b @text=".name"></b>!</p>
      #|</div>
    )),
  },
  name="Greeter",
  init=GreeterState::{ name: "world" },
)
  @component.ModuleDef::new(
    name="greeter", components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
`,

  // An example carrying a View tab: `code` is the component, `view` the HTML
  // it is generated from. The generated module joins the same package, so the
  // names below (counter_main_view, CounterMsg, CounterId) need no import.
  "Counter (view tab)": {
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
// so counter_main_view, CounterMsg and CounterId are all in scope here.
struct CounterState {
  count : Int
  label : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
    name="Counter",
    // the compiled tree from the View tab: no template parsing at startup
    compiled_views=counter_compiled_views(),
    init=CounterState::{ count: 0, label: "clicks" },
    // CounterMsg is generated from the @on handlers in the View tab, with
    // payload types read off the call sites — \`add 1\` makes Add(Double).
    update=(s : CounterState, msg, _ctx) => match CounterMsg::of_dispatch(msg) {
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
};

// expose on window so the module driver can read them
window.EXAMPLES = EXAMPLES;
window.STARTER = EXAMPLES.Counter;
window.STARTER_VIEW = "";
