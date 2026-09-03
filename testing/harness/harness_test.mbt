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
}

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
          #|  <input class="label-input" :value=".label" @on.input=".label = e.value">
          #|</div>
        ),
      ),
    },
    name="Counter",
    initial=CounterState::{ count: 0, label: "", },
    // Hand-written and complete. A fixture is not exempt: `component` takes a
    // schema because the runtime should be told a component's shape rather
    // than reconstruct it, and that holds whether the shape came from
    // `gen-views` or from here.
    update=(s : CounterState, msg, _ctx) => {
      match msg {
        Receive("inc", _) => Next({ ..s, count: s.count + 1, })
        Receive("dec", _) => Next({ ..s, count: s.count - 1, })
        _ => Unhandled
      }
    },
  )
  @component.ModuleDef::new(name="counter", components=[comp], examples=[
    { component: "Counter", title: "Basic Counter", args: Map([]), view: None, },
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

///|
/// The state <-> fields codec, written by hand the way a generated module
/// writes it. A fixture is not exempt: there is no bridge to fall back to.
impl @component.Fields for CounterState with fn encode(s) {
  { "count": Num(s.count.to_double()), "label": Str(s.label) }
}

///|
impl @component.Fields for CounterState with fn decode(f) {
  guard f.get("count") is Some(Num(n_count)) else { return None }
  guard f.get("label") is Some(Str(v_label)) else { return None }
  Some({ count: n_count.to_int(), label: v_label, })
}

///|
impl @component.Fields for CounterState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="harness-counter",
    fields=[
      @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("label", TyText),
    ],
    view_handlers=["dec", "inc", "setLabel"],
    view_names=["main"],
  )
}

///|
test "the channel tells a refused click apart from one that did nothing" {
  let h = @harness.mount(counter_module(), "Counter")
  // A name the module answers refuses nothing, and `no_refusals` is how a test
  // says so out loud.
  @harness.no_refusals(() => h.click(".btn-success"))
  inspect(h.text(".stat-value"), content="1")
  // A name nothing claims — no `update` arm, no mutator — looks exactly like
  // the click above from the DOM's side: nothing moved. This is the difference,
  // and it is the shape a typo in a view takes.
  let refused = @harness.refusals_while(() => h.send_at_root("nope"))
  assert_eq(refused.map(r => r.to_line()), ["NO_HANDLER at `nope`"])
  inspect(h.text(".stat-value"), content="1")
}

///|
/// The gated component: a view whose ROOT element carries the `@show`, so a
/// hidden state renders nothing at all — the whole tree drops out, not just a
/// subtree of it.
priv struct GateState {
  on : Bool
}

///|
impl @component.Fields for GateState with fn encode(s) {
  { "on": Bool(s.on) }
}

///|
impl @component.Fields for GateState with fn decode(f) {
  guard f.get("on") is Some(Bool(v)) else { return None }
  Some({ on: v, })
}

///|
impl @component.Fields for GateState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="harness-gate",
    fields=[@component.FieldInfo::new("on", TyBool)],
    view_handlers=["hide", "show"],
    view_names=["main"],
  )
}

///|
fn gate_module() -> @component.ModuleDef {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="gate" @show=".on">
          #|  <button class="hide" @on.click="hide">hide</button>
          #|  <span class="label">visible</span>
          #|</div>
        ),
      ),
    },
    name="Gate",
    initial=GateState::{ on: true, },
    update=(_s : GateState, msg, _ctx) => {
      match msg {
        Receive("hide", _) => Next(({ on: false, } : GateState))
        Receive("show", _) => Next(({ on: true, } : GateState))
        _ => Unhandled
      }
    },
  )
  @component.ModuleDef::new(name="gate", components=[comp])
}

///|
test "a root whose view renders nothing takes its DOM with it" {
  // Regression: a pass where render_root answered None used to leave the
  // mount point untouched — a component whose root element an `@show` omitted
  // kept its previous DOM standing, which read exactly like a handler that
  // had stopped answering.
  let h = @harness.mount(gate_module(), "Gate")
  assert_true(h.html().contains("visible"))
  h.click(".hide")
  assert_false(h.html().contains("visible"))
  // And the mount point still works after an empty pass: showing again
  // renders fresh rather than morphing against a stale result.
  h.send_at_root("show")
  assert_true(h.html().contains("visible"))
}
