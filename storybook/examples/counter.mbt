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
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="join join-vertical">
          #|  <button class="btn btn-error" @on.click="dec">-</button>
          #|  <div class="stats">
          #|    <div class="stat text-center">
          #|      <div class="stat-title">Count</div>
          #|      <div class="stat-value" @text=".count"></div>
          #|      <div class="stat-desc">Current Count</div>
          #|    </div>
          #|  </div>
          #|  <button class="btn btn-success" @on.click="$inc">+</button>
          #|</div>
        ),
      ),
    },
    name="Counter",
    init=ExampleCounterState::{ count: 0 },
    mutate={
      // views call mutate handlers with a `$` prefix: @on.click="$inc"
      "inc": (s : ExampleCounterState, _args) => { count: s.count + 1 },
    },
    update=(s : ExampleCounterState, msg, _ctx) => {
      match msg {
        // views call input handlers by bare name: @on.click="dec"
        Input("dec", _) => Some({ count: s.count - 1 })
        _ => None
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
