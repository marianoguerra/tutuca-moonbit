// Drag flow on the in-memory DOM: dragstart captures the teleport-resolved
// value + the source render's binds; dragover/drop manage droptarget attrs;
// the drop handler reads dragInfo (type/value/lookupBind); dragend cleans up.

///|
priv struct BoardState {
  cards : Map[String, String]
  received : String
  from : String
  kind : String
} derive(ToJson, FromJson)

///|
fn board_comp() -> @component.Component {
  @component.component(
    name="Board",
    view="<div>" +
      "<ul><li @each=\".cards\" draggable=\"true\" data-dragtype=\"card\"><x text=\"@value\"></x></li></ul>" +
      "<div id=\"zone\" data-droptarget=\"\" @on.drop=\"dropped dragInfo\">zone</div>" +
      "</div>",
    init=BoardState::{ cards: Map([]), received: "", from: "", kind: "" },
    update=(s : BoardState, msg, _ctx) => {
      match msg {
        Input("dropped", [Obj(info)]) => {
          // a plain @each li contributes only a frame-only step, so the
          // teleported dragInfo.value is the COMPONENT instance (JS
          // semantics); the dragged item comes from the source render's
          // binds through the kept frame steps
          let bind = (name : String) => {
            match info.obj_field("lookupBind") {
              Some(Fn(f)) =>
                match f([Null, Str(name)]) {
                  Str(v) => v
                  _ => "?"
                }
              _ => "?"
            }
          }
          let kind = match info.obj_field("type") {
            Some(Str(k)) => k
            _ => "?"
          }
          let dragged_is_board = match info.obj_field("value") {
            Some(Obj(_)) => "yes"
            _ => "no"
          }
          Some({
            ..s,
            received: bind("value") + "/" + dragged_is_board,
            kind,
            from: bind("key"),
          })
        }
        _ => None
      }
    },
  )
}

///|
test "drag lifecycle: capture, dragover attrs, drop with dragInfo, cleanup" {
  let (a, container) = mk_app(board_comp(), {
    "cards": Map({ "x": Str("first"), "y": Str("second") }),
  })
  guard find_el(container, "LI", nth=1) is Some(li) else { fail("no li") }
  guard find_el(container, "DIV", nth=2) is Some(zone) else { fail("no zone") }
  assert_true(zone.get_attribute("data-droptarget") is Some(_))
  // dragstart on the second card captures value/type/binds
  assert_true(a.dispatch(li, @render.DomEvent::new(name="dragstart")))
  assert_true(li.get_attribute("data-dragging") == Some("1"))
  // dragover a droptarget marks it with the drag's type
  assert_true(a.dispatch(zone, @render.DomEvent::new(name="dragover")))
  assert_true(zone.get_attribute("data-draggingover") == Some("card"))
  // drop: handler reads dragInfo (teleported value, type, source @each bind)
  assert_true(a.dispatch(zone, @render.DomEvent::new(name="drop")))
  assert_true(field_v(a, "received") == Str("second/yes"))
  assert_true(field_v(a, "kind") == Str("card"))
  assert_true(field_v(a, "from") == Str("y"))
  // drop cleaned the droptarget attr; dragend clears the capture
  guard find_el(container, "DIV", nth=2) is Some(zone2) else {
    fail("no zone after rerender")
  }
  assert_true(zone2.get_attribute("data-draggingover") is None)
  assert_true(a.dispatch(li, @render.DomEvent::new(name="dragend")))
  assert_true(li.get_attribute("data-dragging") is None)
  // after dragend, dragInfo is gone for later dispatches
  assert_true(a.drag is None)
}

///|
test "dragover from outside the app marks droptargets as _external" {
  let (a, container) = mk_app(board_comp(), {
    "cards": Map({ "x": Str("first") }),
  })
  guard find_el(container, "DIV", nth=2) is Some(zone) else { fail("no zone") }
  // no dragstart happened: external drag
  assert_true(a.dispatch(zone, @render.DomEvent::new(name="dragover")))
  assert_true(zone.get_attribute("data-draggingover") == Some("_external"))
}
