// Port of docs/examples/counter.js.
//
// Teaches: `methods` ($-prefixed in views) vs `input` (bare name) — the only
// difference is how a template references them; both take the instance and
// return a new one. `setCount` is a GENERATED mutator (every field gets
// setX/updateX/resetX), so neither handler writes a setter by hand.

///|
fn counter_comp() -> @component.Component {
  @component.component(
    name="Counter",
    view=(
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
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      // views call methods with a `$` prefix: @on.click="$inc"
      "inc": (inst, _args) => {
        match inst.get("count") {
          Num(n) => inst.set("count", Num(n + 1)).to_value()
          _ => inst.to_value()
        }
      },
    },
    input={
      // views call input handlers by bare name: @on.click="dec"
      "dec": (inst, _args, _ctx) => {
        match inst.get("count") {
          Num(n) => Some(inst.set("count", Num(n - 1)))
          _ => None
        }
      },
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
