// A counter. The views live in the View tab (counter.html) and are compiled
// ahead of time: `counter_views()` is the built tree, and `CounterMsg` is the
// message enum generated from the view's `@on` handlers — add one there and
// this match stops being exhaustive until you handle it.
//
// State is declared in the View tab too, in the `<script type="tutuca/state">`
// block: `CounterState` is generated from it, its fields get generated
// mutators, and a view that reads a field the schema does not declare fails
// generation instead of rendering null. Custom $-logic goes in compute — `$`
// is refused at an @on site, so a `$name` only ever reads a value.

fn build() -> @component.ModuleDef {
  let counter = counter_component(
    init=CounterState::{ count: 0 },
    update=(s, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
      Some(Dec) => Some({ count: s.count - 1 })
      Some(Inc) => Some({ count: s.count + 1 })
      Some(Unknown(_, _)) | None => None
    },
  )
  @component.ModuleDef::new(
    name="counter",
    components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
