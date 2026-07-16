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
    name="EmojiPicker",
    view=(
      #|<section @on.emoji-click="onEmojiClick value" class="join join-vertical gap-3 items-center">
      #|  <p class="hint" @hide="truthy? .current">
      #|    Select the <em>Toggle Picker</em> button and select an emoji, it will be
      #|    displayed here
      #|  </p>
      #|  <p class="label" @show="truthy? .current">Selected emoji:</p>
      #|  <span class="current text-9xl" @show="truthy? .current" @text=".current"></span>
      #|  <button class="btn btn-sm toggle-btn" @on.click="$toggleIsPickerVisible">
      #|    Toggle Picker
      #|  </button>
      #|  <emoji-picker @show=".isPickerVisible"></emoji-picker>
      #|</section>
    ),
    fields={
      "current": @component.FieldSpec::of_default(Null),
      "isPickerVisible": @component.FieldSpec::of_default(Bool(false)),
    },
    input={
      "onEmojiClick": (inst, args, _ctx) => {
        match args.get(0) {
          Some(Map(detail)) =>
            Some(inst.set("current", detail.get("unicode").unwrap_or(Null)))
          _ => None
        }
      },
    },
  )
}

///|
pub fn web_component_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="web-component-custom-event",
    components=[emoji_picker_comp()],
    examples=[
      { component: "EmojiPicker", title: "Default", args: {}, view: None },
    ],
  )
}
