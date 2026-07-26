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
// types) and counter_view_ir_gen.mbt (the already-compiled @anode tree,
// taken by `views~`, which is why no view source is passed below).

///|
/// Move the counter to `n`, remembering where it landed.
fn counter_at(s : CounterState, n : Int) -> CounterState {
  { ..s, count: n, history: s.history + [n] }
}

///|
pub fn counter_comp() -> @component.Component {
  @component.component(
    name="Counter",
    // The views, already compiled (counter_view_ir_gen.mbt) — no template
    // parsing at startup. For a runtime-parsed view instead, build the map
    // with @anode.View::new.
    views=counter_views(),
    // The named `fresh` state from the init block. Fixtures live there
    // rather than in the schema because a default is a value, not a type —
    // and each is checked against the schema at generation time.
    init=CounterState::fresh(),
    update=(s : CounterState, msg, _ctx) => {
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
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=counter_encode,
    decode=counter_decode,
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
/// The state and the views now come from one schema, so the field reads
/// cannot disagree with the struct — `gen-views` fails outright rather than
/// letting a missing field render as null. What is worth pinning is that the
/// schema gives each field the kind the runtime will act on, which the old
/// `FieldSpec::of_default` had to guess from the seed value.
test "the schema declares each field's kind rather than inferring it" {
  // Matched rather than compared: FieldKind carries a Map[String, Value] in
  // its FComp arm, and Value holds Fn and &Obj, so it cannot derive Eq.
  assert_true(CounterField::Count.kind() is FInt)
  assert_true(CounterField::Label.kind() is FText)
  assert_true(CounterField::History.kind() is FList)
  assert_eq(counter_field_names, ["label", "count", "history"])
}
