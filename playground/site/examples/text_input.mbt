// Two-way binding: :value reads the field, @on.input writes it via the
// generated $setName mutator. @text mirrors it live. The view lives in the
// View tab (text_input.html) and arrives here as `greeter_views()`.
struct GreeterState {
  name : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let greeter = @component.component(
    views=greeter_views(),
    name="Greeter",
    init=GreeterState::{ name: "world" },
  )
  @component.ModuleDef::new(
    name="greeter",
    components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
