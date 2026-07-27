// Counter component + module definition shared by the browser demo and the
// embedded-CLI demo.
//
// BOTH halves of the contract live in counter.html: the state schema in its
// `<script type="tutuca/state">` block and the views in its templates. They
// compile ahead of time into counter_view_gen.mbt by
//
//   moon run --target native cmd/main -- gen-views demo/counterlib/counter.html --name Counter
//
// so neither the handler names nor the field names below are matched as
// strings. Adding an `@on` handler to counter.html and regenerating makes
// the `update` match non-exhaustive until it is handled; adding a field to
// the schema adds it to CounterState; and a view that reads a field the
// schema does not declare fails generation outright.
//
// It emits two modules: counter_view_gen.mbt (the state type and the view
// types) and counter_view_ir_gen.mbt (the already-compiled @anode tree, plus
// the `counter_component` wrapper called below — which is why the name, the
// views, the styles, the codec and the schema are nowhere in this file).

///|
/// Move the counter to `n`, remembering where it landed.
fn counter_at(s : CounterState, n : Int) -> CounterState {
  { ..s, count: n, history: s.history + [n] }
}

///|
pub fn counter_comp() -> @component.Component {
  counter_component(
    // The named `fresh` state from the init block, in place of the zero state
    // the wrapper would otherwise use. Fixtures live in that block rather
    // than in the schema because a default is a value, not a type — and each
    // is checked against the schema at generation time.
    init=CounterState::fresh(),
    update=(s, msg, _ctx) => {
      // The Input bucket, typed from the views' `@on` attributes.
      match CounterMsg::from_dispatch(msg) {
        Some(Add(d)) => return Some(counter_at(s, s.count + d.to_int()))
        // Served by the mutators generated from the state's fields: returning
        // None here lets Input dispatch fall through to them
        // (component/instance.mbt obj_handler).
        Some(SetLabel(_)) | Some(ResetCount) => return None
        // Not a name the view declares — try the other buckets below.
        Some(Unknown(_, _)) | None => ()
      }
      // The Receive bucket, typed from the schema. The views never write
      // these names, so before the schema this arm could only match a string.
      match CounterReceive::from_dispatch(msg) {
        Some(ResetTo(n)) => Some(counter_at(s, n))
        Some(Unknown(_, _)) | None => None
      }
    },
  )
}

///|
/// The examples take their args from the init block rather than restating its
/// values: `counter_init_args` is the encoded form of the same fixture the
/// component seeds from, so the two cannot drift.
pub fn module_def() -> @component.ModuleDef {
  let args = (name : String) => counter_init_args(name).unwrap_or(Map([]))
  @component.ModuleDef::new(name="counter-demo", components=[counter_comp()], examples=[
    { component: "Counter", title: "fresh", args: Map([]), view: None },
    {
      component: "Counter",
      title: "with history",
      args: args("with-history"),
      view: None,
    },
  ])
}

///|
/// The state and the views now come from one schema, so the field reads
/// cannot disagree with the struct — `gen-views` fails outright rather than
/// letting a missing field render as null. What is worth pinning is that the
/// schema gives each field the kind the runtime will act on, which the old
/// `FieldSpec::of_default` had to guess from the seed value.
///
/// Asserted through `SchemaInfo` and not through a generated `CounterField`
/// enum, because the descriptor is what the inspector and the state editor
/// actually read: they hold a bare `@tutuca.Value` and no component registry,
/// so anything they cannot reach this way is not really declared.
test "the component takes its kinds from the schema, not the seed value" {
  let comp = counter_comp()
  let si = comp.schema
  // Computed, not merely present: the structural fingerprint is 64 bits of
  // hex, and it is what notices that a stored state can no longer be read back.
  assert_eq(si.fingerprint.length(), 16)
  assert_eq(si.field_names(), ["label", "count", "history"])
  // The names `update` answers — unknowable by reflection, since update is
  // one opaque pattern match.
  assert_eq(si.inputs, ["add", "resetCount", "setLabel"])
  assert_eq(si.receives, ["resetTo"])
  assert_eq(si.init_names, ["fresh", "with-history"])
  assert_eq(si.view_names, ["main"])
  // `count` seeds at 0, which `FieldSpec::of_default` would also call FInt —
  // but for the wrong reason. The schema says s32.
  //
  // Matched rather than compared: FieldKind carries a Map[String, Value] in its
  // FComp arm, and Value holds Fn and &Obj, so it cannot derive Eq.
  guard si.field("count") is Some(fi)
  assert_eq(fi.ty, "s32")
  assert_true(fi.kind is FInt)
  guard si.field("label") is Some(lf)
  assert_true(lf.kind is FText)
  // ...and an element type, which a runtime spec has no room for.
  guard si.field("history") is Some(hf)
  assert_eq(hf.ty, "list<s32>")
  assert_true(hf.kind is FList)
  assert_eq(hf.elem, Some("s32"))
  // The specs the runtime actually built agree with it.
  guard comp.specs.get("count") is Some(sp)
  assert_true(sp.kind is FInt)
}
