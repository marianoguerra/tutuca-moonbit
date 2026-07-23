// Port of docs/examples/counter.js.
//
// Teaches: `mutate` ($-prefixed in views) vs `update` Input arms (bare name)
// — the only difference is how a template references them. `setCount` is a
// GENERATED mutator (every field gets setX/updateX/resetX), so neither
// handler writes a setter by hand.

///|
priv struct ExampleCounterState {
  count : Int
} derive(ToJson, FromJson)

///|
fn counter_comp() -> @component.Component {
  @component.component(
    views=counter_views(),
    name="Counter",
    init=ExampleCounterState::{ count: 0 },
    // views call mutate handlers with a `$` prefix: @on.click="$inc"
    mutate=counter_mutate(m => {
      match m {
        Inc => Some((s : ExampleCounterState, _args) => { count: s.count + 1 })
      }
    }),
    update=(s : ExampleCounterState, msg, _ctx) => {
      match CounterMsg::of_dispatch(msg) {
        // views call input handlers by bare name: @on.click="dec"
        Some(Dec) => Some({ count: s.count - 1 })
        Some(Unknown(_, _)) | None => None
      }
    },
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
