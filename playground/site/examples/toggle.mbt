// A field named 'open' gets a generated $toggleOpen mutator for free — no
// hand-written handler. @show/@hide read the field; compute derives the label.
struct PanelState {
  open : Bool
} derive(ToJson, FromJson)

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
