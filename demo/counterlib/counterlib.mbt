// Counter component + module definition shared by the browser demo and the
// embedded-CLI demo.

///|
priv struct CounterState {
  label : String
  count : Int
  history : Array[Int]
} derive(ToJson, FromJson)

///|
pub fn counter_comp() -> @component.Component {
  @component.component(
    name="Counter",
    view="<div class=\"counter\">" +
      "<h1><x text=\".label\"></x>: <span id=\"count\"><x text=\".count\"></x></span></h1>" +
      "<button id=\"inc\" @on.click=\"add 1\">+1</button>" +
      "<button id=\"dec\" @on.click=\"add -1\">-1</button>" +
      "<button id=\"reset\" @on.click=\"resetCount\">reset</button>" +
      "<input id=\"label\" :value=\".label\" @on.input=\"setLabel value\" @on.keydown+send=\"setLabel 'sent!'\">" +
      "<ul id=\"history\"><li @each=\".history\"><x text=\"@value\"></x></li></ul>" +
      "</div>",
    style="font-family: sans-serif",
    init=CounterState::{ label: "Counter", count: 0, history: [] },
    update=(s : CounterState, msg, _ctx) => {
      match msg {
        Input("add", [Num(d)]) => {
          let next = s.count + d.to_int()
          Some({ ..s, count: next, history: s.history + [next] })
        }
        _ => None
      }
    },
  )
}

///|
pub fn module_def() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter-demo", components=[counter_comp()], examples=[
    { component: "Counter", title: "fresh", args: Map([]), view: None },
    {
      component: "Counter",
      title: "with history",
      args: {
        "label": Str("Demo"),
        "count": Num(3),
        "history": List([Num(1), Num(2), Num(3)]),
      },
      view: None,
    },
  ])
}
