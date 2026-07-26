// A counter. The views live in the View tab (counter.html) and are compiled
// ahead of time: `counter_views()` is the built tree, and `CounterMsg` is the
// message enum generated from the view's `@on` handlers — add one there and
// this match stops being exhaustive until you handle it.
//
// State is declared in the View tab too, in the `<script type="tutuca/state">`
// block: `CounterState` is generated from it, its fields get generated
// mutators, and a view that reads a field the schema does not declare fails
// generation instead of rendering null. Custom $-logic goes in mutate.

fn build() -> @component.ModuleDef {
  let counter = @component.component(
    views=counter_views(),
    name="Counter",
    init=CounterState::{ count: 0 },
    update=(s : CounterState, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
      Some(Dec) => Some({ count: s.count - 1 })
      Some(Unknown(_, _)) | None => None
    },
    mutate={ "inc": (s : CounterState, _a) => { count: s.count + 1 } },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=counter_encode,
    decode=counter_decode,
  )
  @component.ModuleDef::new(
    name="counter",
    components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
