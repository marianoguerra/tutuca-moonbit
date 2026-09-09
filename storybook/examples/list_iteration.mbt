///|
fn list_iteration_comp() -> @component.Component {
  list_iteration_component(initial={ items: [], })
}

///|
pub fn list_iteration_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-iteration",
    components=[list_iteration_comp()],
    examples=[
      {
        component: "ListIteration",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
      {
        component: "ListIteration",
        title: "Empty",
        args: { "items": List([]) },
        view: None,
      },
      {
        component: "ListIteration",
        title: "Custom Items",
        args: { "items": List([Str("one"), Str("two"), Str("three")]) },
        view: None,
      },
    ],
  )
}
