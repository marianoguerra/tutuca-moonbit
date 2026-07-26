// Port of docs/examples/web-component-custom-event.js.
//
// Teaches: hosting a web component (<emoji-picker> from
// emoji-picker-element, loaded by the demo page) and reacting to its
// CustomEvent. `@on.emoji-click="onEmojiClick value"` — the app glue maps a
// CustomEvent's `detail` object to `value` as a Value::Map, so the handler
// reads `.unicode` off it like the JS handler read `detail.unicode`.

///|
fn emoji_picker_comp() -> @component.Component {
  @component.component(
    views=emoji_picker_views(),
    name="EmojiPicker",
    init=EmojiPickerState::{ current: Null, isPickerVisible: false },
    update=(s : EmojiPickerState, msg, _ctx) => {
      match msg {
        Input("onEmojiClick", [Map(detail), ..]) =>
          Some({ ..s, current: detail.get("unicode").unwrap_or(Null) })
        _ => None
      }
    },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=emoji_picker_encode,
    decode=emoji_picker_decode,
  )
}

///|
pub fn web_component_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="web-component-custom-event",
    components=[emoji_picker_comp()],
    examples=[
      { component: "EmojiPicker", title: "Default", args: Map([]), view: None },
    ],
  )
}
