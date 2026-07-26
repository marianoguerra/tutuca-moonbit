// Two-way binding: :value reads the field, @on.input writes it via the
// generated $setName mutator. @text mirrors it live. The view lives in the
// View tab (text_input.html) and arrives here as `greeter_views()`.

fn build() -> @component.ModuleDef {
  let greeter = @component.component(
    views=greeter_views(),
    name="Greeter",
    init=GreeterState::{ name: "world" },
    encode=greeter_encode,
    decode=greeter_decode,
  
  )
  @component.ModuleDef::new(
    name="greeter",
    components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: Map([]), view: None }],
  )
}
