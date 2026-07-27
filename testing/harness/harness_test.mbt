// End-to-end demo: mount a module, fire a real event, and read both the
// re-rendered DOM and the settled root value back. This is the shape an app
// author's own `moon test` blocks take — built-in assertions (`inspect`,
// `assert_eq`, `assert_true(x is Pattern)`) over the harness.
//
// The module under test is defined right here rather than borrowed from
// storybook/examples: this package IS published, and the storybook packages
// are repo demos excluded from the archive (see moon.mod). A self-contained
// module also makes the demo readable without opening another package — which
// is the point, since this file doubles as the harness's documentation.

///|
priv struct CounterState {
  count : Int
  label : String
} derive(ToJson, FromJson)

///|
/// A counter with one mutate handler (`$inc`, `$`-prefixed in views) and one
/// update Input arm (`dec`, bare name) — the two ways a view names a handler.
fn counter_module() -> @component.ModuleDef {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <button class="btn-error" @on.click="dec">-</button>
          #|  <div class="stat-value" @text=".count"></div>
          #|  <button class="btn-success" @on.click="inc">+</button>
          #|  <input class="label-input" :value=".label" @on.input="setLabel value">
          #|</div>
        ),
      ),
    },
    name="Counter",
    init=CounterState::{ count: 0, label: "" },
    // Hand-written and complete. A fixture is not exempt: `component` takes a
    // schema because the runtime should be told a component's shape rather
    // than reconstruct it, and that holds whether the shape came from
    // `gen-views` or from here.
    schema=@component.SchemaInfo::new(
      fingerprint="harness-counter",
      fields=[
        @component.FieldInfo::new("count", "s32", FInt),
        @component.FieldInfo::new("label", "string", FText),
      ],
      inputs=["dec", "inc", "setLabel"],
      view_names=["main"],
    ),
    update=(s : CounterState, msg, _ctx) => {
      match msg {
        Input("inc", _) => Some({ ..s, count: s.count + 1 })
        Input("dec", _) => Some({ ..s, count: s.count - 1 })
        _ => None
      }
    },
  )
  @component.ModuleDef::new(name="counter", components=[comp], examples=[
    { component: "Counter", title: "Basic Counter", args: Map([]), view: None },
  ])
}

///|
test "harness drives a module: click re-renders the DOM" {
  let h = @harness.mount(counter_module(), "Counter")
  inspect(h.text(".stat-value"), content="0")
  h.click(".btn-success") // @on.click="inc"
  inspect(h.text(".stat-value"), content="1")
  h.click(".btn-error") // @on.click="dec"
  inspect(h.text(".stat-value"), content="0")
}

///|
test "mount_example mounts a named example" {
  let h = @harness.mount_example(counter_module(), "Basic Counter")
  inspect(h.text(".stat-value"), content="0")
}

///|
test "drive_value exposes the settled root value" {
  let h = @harness.mount(counter_module(), "Counter")
  // the root is a live component instance, not a plain value
  assert_true(h.drive_value() is Obj(_))
  h.click(".btn-success")
  assert_true(h.drive_value() is Obj(_))
}

///|
test "harness batches one re-render per interaction" {
  let h = @harness.mount(counter_module(), "Counter")
  let before = h.render_count()
  h.click(".btn-success")
  assert_eq(h.render_count(), before + 1)
}

///|
test "a no-op interaction re-renders nothing at all" {
  // An input that re-sends the value it already holds settles to the SAME
  // root object, so the app never reaches render_now — the shape a real
  // `input` event takes when nothing about the value changed. See
  // component/instance.mbt.
  let h = @harness.mount(counter_module(), "Counter")
  h.type_into(".label-input", "hello")
  let root = h.drive_value()
  let before = h.render_count()
  h.type_into(".label-input", "hello") // same value again
  assert_true(physical_equal(h.drive_value(), root))
  assert_eq(h.render_count(), before)
  // …and a real change still renders
  h.type_into(".label-input", "world")
  assert_eq(h.value_of(".label-input"), "world")
  assert_eq(h.render_count(), before + 1)
  assert_false(physical_equal(h.drive_value(), root))
}
