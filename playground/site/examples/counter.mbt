// A counter. The views live in the View tab (counter.html) and are compiled
// ahead of time: `counter_views()` is the built tree, and `CounterMsg` is the
// message enum generated from the view's `@on` handlers — add one there and
// this match stops being exhaustive until you handle it.
//
// State is a typed struct; its fields get generated mutators, and custom
// $-logic goes in mutate.
struct CounterState {
  count : Int
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
    views=counter_views(),
    name="Counter",
    init=CounterState::{ count: 0 },
    update=(s : CounterState, msg, _ctx) => match CounterMsg::of_dispatch(msg) {
      Some(Dec) => Some({ count: s.count - 1 })
      Some(Unknown(_, _)) | None => None
    },
    mutate={ "inc": (s : CounterState, _a) => { count: s.count + 1 } },
  )
  @component.ModuleDef::new(
    name="counter",
    components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
