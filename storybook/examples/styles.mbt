// Port of docs/examples/styles-example.js.
//
// Three style slots, each scoped differently:
//   style       — this component + THIS view   ([data-cid=N][data-vid="main"])
//   commonStyle — this component, every view   ([data-cid=N])
//   globalStyle — injected verbatim, no scoping
//
// A handy consequence of the scoping wrapper: BARE declarations with no selector
// (`padding: …`) land directly inside it, so they style the component's ROOT
// element. Rules written with a selector target descendants instead.
//
// JS spells a per-view style as `views: { two: { view, style } }`; MoonBit keeps
// the two maps separate — `views` and `view_styles`, keyed by the same name.

///|
priv struct StylesNoState {} derive(ToJson, FromJson)

///|
fn styles_example_comp() -> @component.Component {
  @component.component(
    views=styles_example_views(),
    name="StylesExample",
    common_style=styles_example_common_style,
    global_style=styles_example_global_style,
    init=StylesNoState::{  },
  )
}

///|
fn styles_example_root_comp() -> @component.Component {
  @component.component(
    views=styles_example_root_views(),
    name="StylesExampleRoot",
    init=StylesNoState::{  },
    specs={ "value": @component.FieldSpec::comp("StylesExample") },
  )
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
