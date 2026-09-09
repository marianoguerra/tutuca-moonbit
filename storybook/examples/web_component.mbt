///|
fn emoji_picker_comp() -> @component.Component {
  emoji_picker_component(initial={ current: Null, is_picker_visible: false, }, update=(
    s,
    msg,
    _ctx,
  ) => {
    match msg {
      Receive("on_emoji_click", [Map(detail), ..]) =>
        Next({ ..s, current: detail.get("unicode").unwrap_or(Null), })
      _ => Unhandled
    }
  })
}

///|
pub fn web_component_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="web-component-custom-event",
    components=[emoji_picker_comp()],
    examples=[
      { component: "EmojiPicker", title: "Default", args: Map([]), view: None, },
    ],
  )
}
