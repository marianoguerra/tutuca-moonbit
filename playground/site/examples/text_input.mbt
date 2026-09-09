fn build() -> @component.ModuleDef {
  let greeter = greeter_component(
    initial=GreeterState::{ name: "world" },
  )
  @component.ModuleDef::new(
    name="greeter",
    components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
