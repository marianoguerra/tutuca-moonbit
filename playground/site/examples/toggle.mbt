fn build() -> @component.ModuleDef {
  let panel = panel_component(
    initial=PanelState::{ open: false },
    compute=m => match m {
      Label =>
        Some((s, _a, _stack) => Str(
          if s.open { "Hide details" } else { "Show details" },
        ))
    },
  )
  @component.ModuleDef::new(
    name="toggle",
    components=[panel],
    examples=[{ component: "Panel", title: "Closed", args: Map([]), view: None }],
  )
}
