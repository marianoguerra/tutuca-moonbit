// Counter component + module definition shared by the browser demo and the
// embedded-CLI demo.

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
    fields={
      "label": @component.FieldSpec::of_default(Str("Counter")),
      "count": @component.FieldSpec::of_default(Num(0)),
      "history": @component.FieldSpec::of_default(List([])),
    },
    input={
      "add": (inst, args, _ctx) => {
        match (inst.get("count"), args) {
          (Num(c), [Num(d)]) => {
            let next = c + d
            let hist = match inst.get("history") {
              List(a) => {
                let out = a.copy()
                out.push(Num(next))
                out
              }
              _ => [Num(next)]
            }
            Some(inst.set("count", Num(next)).set("history", List(hist)))
          }
          _ => None
        }
      },
    },
  )
}

///|
pub fn module_def() -> @component.ModuleDef {
  @component.ModuleDef::new(name="counter-demo", components=[counter_comp()], examples=[
    @component.ExampleDef::{
      component: "Counter",
      title: "fresh",
      args: {},
      view: None,
    },
    @component.ExampleDef::{
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
