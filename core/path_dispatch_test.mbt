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
      plain(EachRenderItStep(field="items", key=KInt(0)), origin=1),
    ])
    .push_frame(@core.Path::new(steps=[FieldStep("x")]))
    .concat([FieldStep("child")])
    .compact()
  assert_true(
    p.frames
    is [
      {
        base: { steps: [], },
        items: [Plain(step=SeqStep(field="items", key=KInt(0)), origin=Some(1))],
        binds: [],
      },
      {
        base: { steps: [FieldStep("x")], },
        items: [Plain(step=FieldStep("child"), origin=None)],
        binds: [],
      },
    ],
  )
}

///|
test "a bind keeps its place among the items, and goes with the one it followed" {
  // A bind is placed by how many items came before it, which is the whole of
  // what it needs to be replayed in order — and what tells `pop_step` that a
  // bind entered after the item it just removed has nothing left to scope.
  let p = @core.DispatchPath::new(items=[plain(FieldStep("rows"))])
    .push_bind(Scope(val=@core.Expr::field("enrich")))
    .push_item(plain(FieldStep("cell")))
    .push_bind(Scope(val=@core.Expr::field("inner")))
  assert_eq(p.frames[0].binds.map(b => b.0), [1, 2])
  let popped = p.pop_step()
  assert_eq(popped.frames[0].items.length(), 1)
  assert_eq(popped.frames[0].binds.map(b => b.0), [1])
  // Addressing never saw either of them.
  assert_true(
    p.to_transaction_path().steps is [FieldStep("rows"), FieldStep("cell")],
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

///|
test "the bucket ordinals ARE the wire's case order" {
  // A numbering rather than a vocabulary, and the one thing about it that is a
  // contract: the guest dispatch variant lists `receive` first and
  // `intent` second, and a guest compiled against that order is a binary
  // nothing here can recompile. It was written down three times — here, in the
  // host's guest bridge, and in the card compiler's ABI constants — and a
  // number stated three times is a number that can disagree with itself.
  assert_eq(@core.HandlerBucket::ordinal(Receive), 0)
  assert_eq(@core.HandlerBucket::ordinal(Intent), 1)
  // A dispatch knows its own bucket, which is what folding the two enums
  // bought: a reader who has one and wants the other stops writing a match.
  assert_eq(@core.Dispatch::Receive("inc", []).bucket(), Receive)
  assert_eq(@core.Dispatch::Intent("loadData", []).bucket(), Intent)
  assert_eq(@core.Dispatch::Receive("inc", [Num(1.0)]).name(), "inc")
  assert_eq(@core.Dispatch::Intent("x", [Num(2.0)]).args(), [Num(2.0)])
}
