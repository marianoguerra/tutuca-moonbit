// A field named 'open' gets a generated $toggleOpen mutator for free — no
// hand-written method. @show/@hide read the field; no MoonBit logic needed.
fn build() -> @component.ModuleDef {
  let panel = @component.component(
    name="Panel",
    view=(
      #|<section style="font-family:system-ui">
      #|  <button @on.click="$toggleOpen" @text="$label"></button>
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
