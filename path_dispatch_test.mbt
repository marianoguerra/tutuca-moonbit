// Dyn teleporting tests, ported from test/path.test.js (DynStep internals +
// the workspace/panel/toolbar/sheet end-to-end scenario, data-side).

///|
fn plain(step : @tutuca.Step, origin? : Int) -> @tutuca.DispatchStep {
  @tutuca.DispatchStep::Plain(step~, origin~)
}

///|
test "to_transaction_path without dynamics keeps the plain steps" {
  let p = @tutuca.DispatchPath::of_steps([FieldStep("a"), FieldStep("b")])
  assert_true(p.to_transaction_path().steps is [FieldStep("a"), FieldStep("b")])
}

///|
test "a Dyn marker rewinds the interior span and splices the producer steps" {
  // producer 0 provides `.sheet`; components 1,2,3 are interior hops
  let p = @tutuca.DispatchPath::new(items=[
    plain(FieldStep("s1"), origin=1),
    plain(FieldStep("s2"), origin=2),
    plain(FieldStep("s3"), origin=3),
    Dyn(producer=0, steps=[FieldStep("sheet")], interior=[1, 2, 3]),
  ])
  assert_true(p.to_transaction_path().steps is [FieldStep("sheet")])
}

///|
test "steps outside the interior span survive the rewind" {
  // the producer (9) sits below a root-level step that must be kept
  let p = @tutuca.DispatchPath::new(items=[
    plain(FieldStep("app"), origin=9),
    plain(FieldStep("panel"), origin=1),
    Dyn(producer=9, steps=[FieldStep("sheet")], interior=[1]),
  ])
  assert_true(
    p.to_transaction_path().steps is [FieldStep("app"), FieldStep("sheet")],
  )
}

///|
test "DynEach splices a keyed SeqStep for the producer's field" {
  let p = @tutuca.DispatchPath::new(items=[
    plain(FieldStep("s1"), origin=1),
    DynEach(producer=0, steps=[FieldStep("rows")], interior=[1], key=KStr("b")),
  ])
  assert_true(
    p.to_transaction_path().steps is [SeqStep(field="rows", key=KStr("b"))],
  )
}

///|
test "DynEach over a seq-access dynamic splices unchanged (cannot be iterated)" {
  let p = @tutuca.DispatchPath::new(items=[
    DynEach(
      producer=0,
      steps=[SeqAccessStep(seq_field="a", key_field="b")],
      interior=[],
      key=KStr("k"),
    ),
  ])
  assert_true(
    p.to_transaction_path().steps
    is [SeqAccessStep(seq_field="a", key_field="b")],
  )
}

///|
test "nested dynamics: spliced steps carry the producer id for outer rewinds" {
  // inner Dyn teleports to producer 5; the outer Dyn's interior includes 5,
  // so the spliced steps are rewound again (JS stamps _originCid on splices)
  let p = @tutuca.DispatchPath::new(items=[
    plain(FieldStep("root"), origin=9),
    plain(FieldStep("mid"), origin=5),
    Dyn(producer=5, steps=[FieldStep("inner")], interior=[]),
    Dyn(producer=9, steps=[FieldStep("outer")], interior=[5]),
  ])
  assert_true(
    p.to_transaction_path().steps is [FieldStep("root"), FieldStep("outer")],
  )
}

///|
test "teleported path addresses the producer's data (end to end)" {
  // Workspace(cid 0) provides active=.sheet; Toolbar(cid 2) renders *active.
  // The event path walks Toolbar's tree but the mutation must land on
  // Workspace.sheet (semantics.md §7).
  let root : &@tutuca.PathNode = @tutuca.Value::Map({
    "sheet": @tutuca.Value::Map({ "title": @tutuca.Value::Str("Q1") }),
    "panel": @tutuca.Value::Map({ "toolbar": @tutuca.Value::Null }),
  })
  let dispatch = @tutuca.DispatchPath::new(items=[
    plain(FieldStep("panel"), origin=1),
    plain(FieldStep("toolbar"), origin=2),
    Dyn(producer=0, steps=[FieldStep("sheet")], interior=[1, 2]),
    plain(FieldStep("title"), origin=0),
  ])
  let txn = dispatch.to_transaction_path()
  assert_true(txn.steps is [FieldStep("sheet"), FieldStep("title")])
  assert_true(txn.lookup(root) is Some(n) && n.as_value() is Some(Str("Q1")))
  let root2 = txn.set_value(root, @tutuca.Value::Str("Q2"))
  assert_true(txn.lookup(root2) is Some(n2) && n2.as_value() is Some(Str("Q2")))
}

///|
test "compact drops frame-only plains, keeps Dyn markers, preserves origins" {
  let p = @tutuca.DispatchPath::new(items=[
    plain(BindStep(binds={})),
    plain(EachRenderItStep(field="items", key=KInt(0)), origin=1),
    Dyn(producer=0, steps=[FieldStep("x")], interior=[1]),
  ])
  assert_true(
    p.compact().items
    is [
      Plain(step=SeqStep(field="items", key=KInt(0)), origin=Some(1)),
      Dyn(producer=0, steps=[FieldStep("x")], interior=[1]),
    ],
  )
}

///|
test "pop_step drops one component hop" {
  let p = @tutuca.DispatchPath::of_steps([FieldStep("a"), FieldStep("b")])
  assert_true(p.pop_step().items is [Plain(step=FieldStep("a"), origin=None)])
  assert_true(@tutuca.DispatchPath::new().pop_step().items is [])
}
