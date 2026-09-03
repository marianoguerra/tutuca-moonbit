// Counter component + module definition shared by the browser demo and the
// embedded-CLI demo.
//
// BOTH halves of the contract live in counter.html: the state schema in its
// `<script type="tutuca/spec">` block and the views in its templates. They
// compile ahead of time into counter_view_gen.mbt by
//
//   moon run --target native cmd/tutuca -- gen-views demo/counterlib/counter.html --name Counter
//
// so neither the handler names nor the field names below are matched as
// strings. Adding a field to the schema adds it to CounterState, and a view
// that reads a field the schema does not declare fails generation outright.
//
// The BEHAVIOUR is in the file too now, in its `<script type="tutuca/script">`
// block. What is left in this file is the one thing no generator can write:
// which named fixture the component seeds from.
//
// It emits two modules: counter_view_gen.mbt (the state type and the view
// types) and counter_view_ir_gen.mbt (the already-compiled @anode tree, plus
// the `counter_component` wrapper called below — which is why the name, the
// views, the styles, the codec and the schema are nowhere in this file).

///|
/// The whole component, in one argument.
///
/// `add` and `resetTo` are in the file's `<script type="tutuca/script">`
/// block, and `gen-views` compiles them into `counter_inline_update`, which
/// the wrapper composes ahead of `update~`. `setLabel` and `resetCount` were
/// never written here either — they fall through to the mutators the schema's
/// fields generate.
///
/// What is left is `init`: the named `fresh` state from the init block, in
/// place of the zero state the wrapper would otherwise use. Fixtures live in
/// that block rather than in the schema because a default is a value, not a
/// type — and each is checked against the schema at generation time.
pub fn counter_comp() -> @component.Component {
  counter_component(init=CounterState::fresh())
}

///|
/// The examples take their args from the init block rather than restating its
/// values: `counter_init_args` is the encoded form of the same fixture the
/// component seeds from, so the two cannot drift.
pub fn module_def() -> @component.ModuleDef {
  let args = (name : String) => counter_init_args(name).unwrap_or(Map([]))
  @component.ModuleDef::new(name="counter-demo", components=[counter_comp()], examples=[
    { component: "Counter", title: "fresh", args: Map([]), view: None, },
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
  // one opaque pattern match. The view's other two buttons write a property
  // outright (`.count = default`, `.label = e.value`), so they raise no name
  // at all and nothing has to answer for them.
  assert_eq(si.view_handlers, ["add"])
  assert_eq(si.receives, ["resetTo"])
  assert_eq(si.init_names, ["fresh", "with-history"])
  assert_eq(si.view_names, ["main"])
  // `count` seeds at 0, which `FieldSpec::of_default` would also call FInt —
  // but for the wrong reason. The schema says Int.
  //
  // Matched rather than compared: FieldKind carries a Map[String, Value] in its
  // FComp arm, and Value holds Fn and &Obj, so it cannot derive Eq.
  guard! si.field("count") is Some(fi)
  assert_eq(fi.ty, TyInt(width=32, signed=true))
  assert_true(fi.kind() is FInt)
  guard! si.field("label") is Some(lf)
  assert_true(lf.kind() is FText)
  // ...and an element type, which a runtime spec has no room for. Structural,
  // so a reader can descend rather than receive the string "Int" and stop.
  guard! si.field("history") is Some(hf)
  assert_eq(hf.ty, TyList(TyInt(width=32, signed=true)))
  assert_eq(hf.ty.show_source(), "Array[Int]")
  assert_true(hf.kind() is FList)
  assert_eq(hf.ty.elem(), Some(TyInt(width=32, signed=true)))
  // ...and the default the inspector shows is the type's zero, reachable
  // without a component registry.
  assert_eq(fi.default(), Num(0.0))
  assert_eq(hf.default(), List([]))
}
