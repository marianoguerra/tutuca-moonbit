// Counter component + module definition shared by the browser demo and the
// embedded-CLI demo.
//
// The view lives in counter.html, compiled ahead of time into
// counter_view_gen.mbt by
//
//   moon run --target native cmd/main -- gen-views demo/counterlib/counter.html --name Counter
//
// so the handler names below are checked against the view rather than
// matched as strings: adding an `@on` handler to counter.html and
// regenerating makes the `update` match non-exhaustive until it is handled.

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
    view=counter_main_view,
    views=counter_views(),
    style=counter_style,
    init=CounterState::{ label: "Counter", count: 0, history: [] },
    update=(s : CounterState, msg, _ctx) => {
      match CounterMsg::of_dispatch(msg) {
        Some(Add(d)) => {
          let next = s.count + d.to_int()
          Some({ ..s, count: next, history: s.history + [next] })
        }
        // Served by the mutators generated from the state's fields: returning
        // None here lets Input dispatch fall through to them
        // (component/instance.mbt obj_handler).
        Some(SetLabel(_)) | Some(ResetCount) => None
        // Not a name the view declares, or a Receive/Bubble/Response.
        Some(Unknown(_, _)) | None => None
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

///|
/// The generated field list against the state struct: a field the view reads
/// but the state does not carry would render as null at runtime.
test "the view's field reads all exist in CounterState" {
  assert_eq(
    counter_missing_fields(CounterState::{
      label: "Counter",
      count: 0,
      history: [],
    }),
    [],
  )
}
