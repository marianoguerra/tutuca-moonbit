// Port of docs/examples/counter.js.
//
// Teaches: one `update` match over every event the views raise. `inc` and
// `dec` are both bare `@on` handler names, so both arrive as Inputs and both
// are answered here — there is no second place to put a handler. `setCount`
// is a GENERATED mutator (every field gets setX/updateX/resetX), so neither
// arm writes a setter by hand.

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views=counter_views(),
    name="Counter",
    init=CounterState::{ count: 0 },
    update=(s : CounterState, msg, _ctx) => {
      match CounterMsg::from_dispatch(msg) {
        Some(Inc) => Some({ count: s.count + 1 })
        Some(Dec) => Some({ count: s.count - 1 })
        Some(Unknown(_, _)) | None => None
      }
    },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=counter_encode,
    decode=counter_decode,
  )
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
