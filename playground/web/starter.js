// Starter modules for the playground picker. Each is authored against the
// tutuca-mb library (@component / @tutuca) and defines only `build()`, which
// returns a ModuleDef. The compiler worker injects the target-specific boot glue
// (js `main` self-mount, or the wasm-gc export wrappers) around it, so the SAME
// source runs on both backends. Ctrl/⌘+Enter to run.

const EXAMPLES = {
  Counter: `// A counter. Fields get generated mutators ($inc); custom logic is a method.
fn build() -> @component.ModuleDef {
  let counter = @component.component(
    name="Counter",
    view=(
      #|<div style="display:flex;gap:.5rem;align-items:center;font-size:1.5rem">
      #|  <button @on.click="dec">-</button>
      #|  <b @text=".count"></b>
      #|  <button @on.click="$inc">+</button>
      #|</div>
    ),
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "inc": (inst, _a) => match inst.get("count") {
        Num(n) => inst.set("count", Num(n + 1)).to_value()
        _ => inst.to_value()
      },
    },
    input={
      "dec": (inst, _a, _c) => match inst.get("count") {
        Num(n) => Some(inst.set("count", Num(n - 1)))
        _ => None
      },
    },
  )
  @component.ModuleDef::new(
    name="counter", components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
`,

  "Toggle (no logic)": `// A field named 'open' gets a generated \$toggleOpen mutator for free — no
// hand-written method. @show/@hide read the field; no MoonBit logic needed.
fn build() -> @component.ModuleDef {
  let panel = @component.component(
    name="Panel",
    view=(
      #|<section style="font-family:system-ui">
      #|  <button @on.click="\$toggleOpen" @text="\$label"></button>
      #|  <p @show=".open" style="padding:.5rem;border:1px solid #ccc;margin-top:.5rem">
      #|    Now you see me. Toggle again to hide.
      #|  </p>
      #|</section>
    ),
    fields={ "open": @component.FieldSpec::of_default(Bool(false)) },
    methods={
      "label": (inst, _a) => match inst.get("open") {
        Bool(true) => Str("Hide details")
        _ => Str("Show details")
      },
    },
  )
  @component.ModuleDef::new(
    name="toggle", components=[panel],
    examples=[{ component: "Panel", title: "Closed", args: Map([]), view: None }],
  )
}
`,

  "Text input": `// Two-way binding: :value reads the field, @on.input writes it via the
// generated \$setName mutator. @text mirrors it live.
fn build() -> @component.ModuleDef {
  let greeter = @component.component(
    name="Greeter",
    view=(
      #|<div style="font-family:system-ui;display:flex;flex-direction:column;gap:.5rem">
      #|  <input :value=".name" @on.input="\$setName value" placeholder="your name" />
      #|  <p>Hello, <b @text=".name"></b>!</p>
      #|</div>
    ),
    fields={ "name": @component.FieldSpec::of_default(Str("world")) },
  )
  @component.ModuleDef::new(
    name="greeter", components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
`,
};

// expose on window so the module driver can read them
window.EXAMPLES = EXAMPLES;
window.STARTER = EXAMPLES.Counter;
