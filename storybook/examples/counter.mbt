// Port of docs/examples/counter.js.
//
// Teaches: one `update` match over every event the views raise. `inc` and
// `dec` are both bare `@on` handler names, so both arrive as Inputs and both
// are answered here — there is no second place to put a handler. `setCount`
// is a GENERATED mutator (every field gets setX/updateX/resetX), so neither
// arm writes a setter by hand.
//
// The whole definition is the update: `counter_component` is generated from
// counter.html and already carries the name, the compiled views, the styles,
// the direct codec and the schema. Nothing here restates the view file.

///|
fn counter_comp() -> @component.Component {
  counter_component(update=(s, msg, _ctx) => {
    match CounterMsg::from_dispatch(msg) {
      Some(Inc) => Some({ count: s.count + 1 })
      Some(Dec) => Some({ count: s.count - 1 })
      Some(Unknown(_, _)) | None => None
    }
  })
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
