// A field named 'open' gets a generated $toggleOpen mutator for free — no
// hand-written handler. @show/@hide read the field; compute derives the label.
// The view lives in the View tab (toggle.html), compiled ahead of time into
// `panel_views()`: no `@on` handler of its own, so no update at all.
struct PanelState {
  open : Bool
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let panel = @component.component(
    views=panel_views(),
    name="Panel",
    init=PanelState::{ open: false },
    compute={
      "label": (s : PanelState, _a) => Str(
        if s.open { "Hide details" } else { "Show details" },
      ),
    },
  )
  @component.ModuleDef::new(
    name="toggle",
    components=[panel],
    examples=[{ component: "Panel", title: "Closed", args: Map([]), view: None }],
  )
}
