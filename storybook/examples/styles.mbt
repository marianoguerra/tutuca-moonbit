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
