// Port of docs/examples/counter.js.
//
// Teaches: the `mutate` bucket vs an `update` Input arm. BOTH are reached by
// a bare name in a view — a `$` at an `@on` site is the same dispatch, so it
// is refused — which means the choice is about what the handler needs, not
// about how the template spells it. `mutate` is pure `(S, args) -> S`;
// `update` also gets a `ctx` to send and bubble with. `setCount` is a
// GENERATED mutator (every field gets setX/updateX/resetX), so neither
// handler writes a setter by hand.

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views=counter_views(),
    name="Counter",
    init=CounterState::{ count: 0 },
    // A pure state change: no ctx, so it provably cannot send or bubble.
    mutate={ "inc": (s : CounterState, _args) => { count: s.count + 1 } },
    update=(s : CounterState, msg, _ctx) => {
      match CounterMsg::from_dispatch(msg) {
        Some(Dec) => Some({ count: s.count - 1 })
        // `inc` is an Input now that the view spells it bare, so it appears
        // here too. Returning None lets the dispatch fall through to the
        // `mutate` entry above (component/instance.mbt obj_handler).
        Some(Inc) => None
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
