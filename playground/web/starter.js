// Starter modules for the playground picker. Each is a complete MoonBit source
// authored against the tutuca-mb library (@component / @tutuca) plus the mount
// host (@host), compiled in the browser. `build()` returns a ModuleDef; `main`
// mounts it. Ctrl/⌘+Enter to run.

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

fn main {
  @host.mount(build(), "app")
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

fn main {
  @host.mount(build(), "app")
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

fn main {
  @host.mount(build(), "app")
}
`,
};

// wasm-gc-shaped starters. The wasm backend has no JS-callable `main`: the user
// module imports the wasm mount host (@host_wasm) plus mizchi's @core (needed to
// name @core.Any in the on_event signature) and EXPORTS thin wrappers the driver
// calls after instantiating the module — mount(), on_event(), state_json(),
// classes_json(). (See playground/host_wasm/host.mbt.) Same component API as js.
const EXAMPLES_WASM = {
  Counter: `// wasm-gc counter. Identical component to the js Counter; only the mount
// plumbing differs: export wrappers that delegate to the wasm host (@host_wasm).
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

// exported wrappers the wasm driver calls (JS has no way to run \`main\`):
pub fn mount() -> Unit { @host_wasm.mount(build(), "app") }
pub fn on_event(ev : @core.Any) -> Unit { @host_wasm.on_event(ev) }
pub fn state_json() -> String { @host_wasm.state_json() }
pub fn classes_json() -> String { @host_wasm.classes_json() }

fn main {

}
`,
};

// expose on window so the module driver can read them
window.EXAMPLES = EXAMPLES;
window.EXAMPLES_WASM = EXAMPLES_WASM;
window.STARTER = EXAMPLES.Counter;
