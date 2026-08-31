// Render-path stack tests: ordinary descent extends the active frame, a
// located render target pushes an absolute base, and bubbling pops back to the
// saved visual caller.

///|
fn plain(step : @core.Step, origin? : Int) -> @core.DispatchStep {
  Plain(step~, origin~)
}

///|
test "to_transaction_path without a resume keeps the plain steps" {
  let p = @core.DispatchPath::of_steps([FieldStep("a"), FieldStep("b")])
  assert_true(p.to_transaction_path().steps is [FieldStep("a"), FieldStep("b")])
}

///|
test "a pushed frame changes the active transaction path" {
  let caller = @core.DispatchPath::of_steps([
    FieldStep("panel"),
    FieldStep("toolbar"),
  ])
  let resumed = caller
    .push_frame(@core.Path::new(steps=[FieldStep("sheet")]))
    .concat([FieldStep("title")])
  assert_true(
    resumed.to_transaction_path().steps
    is [FieldStep("sheet"), FieldStep("title")],
  )
  assert_eq(resumed.frames.length(), 2)
}

///|
test "popping a resumed root returns directly to its visual caller" {
  let caller = @core.DispatchPath::of_steps([
    FieldStep("panel"),
    FieldStep("toolbar"),
  ])
  let leaf = caller
    .push_frame(@core.Path::new(steps=[FieldStep("sheet")]))
    .concat([FieldStep("child")])
  let resumed_root = leaf.pop_step()
  assert_true(resumed_root.to_transaction_path().steps is [FieldStep("sheet")])
  assert_true(
    resumed_root.pop_step().to_transaction_path().steps
    is [FieldStep("panel"), FieldStep("toolbar")],
  )
}

///|
test "nested resumes restore each saved caller" {
  let first = @core.DispatchPath::of_steps([FieldStep("visual")])
    .push_frame(@core.Path::new(steps=[FieldStep("outer")]))
    .concat([FieldStep("inside")])
  let second = first.push_frame(@core.Path::new(steps=[FieldStep("inner")]))
  assert_true(second.to_transaction_path().steps is [FieldStep("inner")])
  assert_true(
    second.pop_step().to_transaction_path().steps
    is [FieldStep("outer"), FieldStep("inside")],
  )
  assert_true(
    second.pop_step().pop_step().to_transaction_path().steps
    is [FieldStep("outer")],
  )
  assert_true(
    second.pop_step().pop_step().pop_step().to_transaction_path().steps
    is [FieldStep("visual")],
  )
}

///|
test "a resumed path addresses the located data end to end" {
  let root : @core.Value = Map({
    "sheet": Map({ "title": Str("Q1") }),
    "panel": Map({ "toolbar": Null }),
  })
  let dispatch = @core.DispatchPath::of_steps([
      FieldStep("panel"),
      FieldStep("toolbar"),
    ])
    .push_frame(@core.Path::new(steps=[FieldStep("sheet")]))
    .concat([FieldStep("title")])
  let txn = dispatch.to_transaction_path()
  assert_true(txn.lookup(root) is Some(Str("Q1")))
  assert_true(txn.lookup(txn.set_value(root, Str("Q2"))) is Some(Str("Q2")))
}

///|
test "compact projects every frame independently" {
  let p = @core.DispatchPath::new(items=[
      plain(BindStep(binds=Map([]))),
      plain(EachRenderItStep(field="items", key=KInt(0)), origin=1),
    ])
    .push_frame(@core.Path::new(steps=[FieldStep("x")]))
    .concat([ScopeBindStep(val=Field("ignored")), FieldStep("child")])
    .compact()
  assert_true(
    p.frames
    is [
      {
        base: { steps: [], },
        items: [Plain(step=SeqStep(field="items", key=KInt(0)), origin=Some(1))],
      },
      {
        base: { steps: [FieldStep("x")], },
        items: [Plain(step=FieldStep("child"), origin=None)],
      },
    ],
  )
}

///|
test "root and bubbling predicates include saved frames" {
  let root = @core.DispatchPath::new()
  assert_true(root.is_root())
  assert_false(root.can_pop())
  let child = root.concat([FieldStep("a")])
  assert_false(child.is_root())
  assert_true(child.can_pop())
  let resumed_root = child.push_frame(@core.Path::new())
  assert_true(resumed_root.is_root())
  assert_true(resumed_root.can_pop())
}
