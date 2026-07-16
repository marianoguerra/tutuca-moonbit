// A counter. Fields get generated mutators; custom logic is a method.
fn build() -> @component.ModuleDef {
  let counter = @component.component(
    name="Counter",
    view=(
      #|<div style="display:flex;gap:.5rem;align-items:center;font-size:1.5rem">
      #|  <button @on.click="dec">-</button>
      #|  <b @text=".count"></b>
      #|  <button @on.click="$inc">+</button>
      #|</div>
    ),
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "inc": (inst, _a) => match inst.get("count") {
        Num(n) => inst.set("count", Num(n + 1)).to_value()
        _ => inst.to_value()
      },
    },
    input={
      "dec": (inst, _a, _c) => match inst.get("count") {
        Num(n) => Some(inst.set("count", Num(n - 1)))
        _ => None
      },
    },
  )
  @component.ModuleDef::new(
    name="counter", components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}

fn main {
  @host.mount(build(), "app")
}
