// Two-way binding: :value reads the field, @on.input writes it via the
// generated $setName mutator. @text mirrors it live. The view lives in the
// View tab (text_input.html) and arrives here as `greeter_views()`.

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
