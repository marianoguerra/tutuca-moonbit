fn build() -> @component.ModuleDef {
  let counter = counter_component(initial=CounterState::{ count: 0 })
  @component.ModuleDef::new(
    name="counter",
    components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
