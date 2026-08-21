// Teaches: a component with no `update` at all. `inc` and `dec` are both bare
// `@on` handler names, and both are answered in the file's
// `<script type="tutuca/script">` block, which `gen-views` compiles into
// `counter_inline_update` and the wrapper composes ahead of `update~`.
// `setCount` is a GENERATED mutator (every field gets setX/resetX), so it is
// not written anywhere either.
//
// What is left is the module definition: `counter_component` is generated from
// counter.html and already carries the name, the compiled views, the styles,
// the direct codec and the schema. Nothing here restates the view file.

///|
fn counter_comp() -> @component.Component {
  counter_component()
}

///|
pub fn counter_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter", components=[counter_comp()], examples=[
    { component: "Counter", title: "Basic Counter", args: Map([]), view: None },
    {
      component: "Counter",
      title: "Counter with negative initial value",
      args: { "count": Num(-5) },
      view: None,
    },
  ])
}
