// A counter. State is a typed struct; fields get generated mutators and
// update handles bare-name events; custom $-logic goes in mutate.
struct CounterState {
  count : Int
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let counter = @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<div style="display:flex;gap:.5rem;align-items:center;font-size:1.5rem">
      #|  <button @on.click="dec">-</button>
      #|  <b @text=".count"></b>
      #|  <button @on.click="$inc">+</button>
      #|</div>
    )),
  },
  name="Counter",
  init=CounterState::{ count: 0 },
  update=(s : CounterState, msg, _ctx) => match msg {
      Input("dec", _) => Some({ count: s.count - 1 })
      _ => None
    },
  mutate={ "inc": (s : CounterState, _a) => { count: s.count + 1 } },
)
  @component.ModuleDef::new(
    name="counter", components=[counter],
    examples=[{ component: "Counter", title: "Basic", args: Map([]), view: None }],
  )
}
