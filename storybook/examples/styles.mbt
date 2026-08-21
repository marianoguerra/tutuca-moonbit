// Three style slots, each scoped differently:
//   style       — this component + THIS view   ([data-cid=N][data-vid="main"])
//   commonStyle — this component, every view   ([data-cid=N])
//   globalStyle — injected verbatim, no scoping
//
// A handy consequence of the scoping wrapper: BARE declarations with no selector
// (`padding: …`) land directly inside it, so they style the component's ROOT
// element. Rules written with a selector target descendants instead.
//
// A per-view style lives on the view itself — each @anode.View in `views`
// carries its own style.

///|
fn styles_example_comp() -> @component.Component {
  styles_example_component()
}

///|
fn styles_example_root_comp() -> @component.Component {
  styles_example_root_component()
}

///|
pub fn styles_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="styles-example",
    components=[styles_example_root_comp(), styles_example_comp()],
    examples=[
      {
        component: "StylesExampleRoot",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}
