// Two-way binding: :value reads the field, @on.input writes it via the
// generated $setName mutator. @text mirrors it live.
fn build() -> @component.ModuleDef {
  let greeter = @component.component(
    name="Greeter",
    view=(
      #|<div style="font-family:system-ui;display:flex;flex-direction:column;gap:.5rem">
      #|  <input :value=".name" @on.input="$setName value" placeholder="your name" />
      #|  <p>Hello, <b @text=".name"></b>!</p>
      #|</div>
    ),
    fields={ "name": @component.FieldSpec::of_default(Str("world")) },
  )
  @component.ModuleDef::new(
    name="greeter", components=[greeter],
    examples=[{ component: "Greeter", title: "Default", args: {}, view: None }],
  )
}

fn main {
  @host.mount(build(), "app")
}
