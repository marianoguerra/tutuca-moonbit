// A counter with no `update` at all. The views live in the View tab
// (counter.html) and are compiled ahead of time: `counter_component` is the
// wrapper generated from that file, with the name, the views, the styles, the
// codec and the schema already filled in.
//
// State is declared in the View tab too, in the `<script type="tutuca/state">`
// block: `CounterState` is generated from it, its fields get generated
// mutators, and a view that reads a field the schema does not declare fails
// generation instead of rendering null.
//
// So is the BEHAVIOUR, in the `<script type="tutuca/script">` block: `inc` and
// `dec` compile into a match over the same dispatch a hand-written arm takes,
// composed ahead of `update~`. Write a handler the block cannot compile and the
// generator says so by name — and that one goes here, as an `update~`.

fn build() -> @component.ModuleDef {
  let counter = counter_component(initial=CounterState::{ count: 0 })
  @component.ModuleDef::new(
    name="counter",
    components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
