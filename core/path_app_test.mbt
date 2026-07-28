// A typed struct mixed with Value containers in one tree, driving the
// scenarios test/transactor.test.js exercises: a live-key selection
// (SeqAccessStep), leaf handlers rebuilding the spine, and pinning a live key
// so a late response lands where the request was issued.
//
// This used to be written against a `PathNode` TRAIT, so that `Sheets` and
// `App` could be structs too. They are ordinary `Value` containers now: the
// trait's only production implementation was `Value` itself, and a typed leaf
// reaches the tree through `Value::Obj` — which is what `Sheet` does here, and
// what every generated component instance does.

///|
priv struct Sheet {
  title : String
}

///|
fn sheet(title : String) -> @core.Value {
  Obj(Sheet::{ title, })
}

///|
impl @core.Obj for Sheet with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    _ => None
  }
}

///|
impl @core.Obj for Sheet with fn obj_with_field(_self, name, v) {
  match (name, v) {
    ("title", Str(s)) => Some(sheet(s))
    _ => None
  }
}

///|
impl @core.Obj for Sheet with fn obj_handler(_self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(sheet(s))
            _ => None
          }
        }),
      )
    // a handler that decides nothing changed answers None
    (Receive, "noop") => Some(Handler((_args, _ctx) => None))
    _ => None
  }
}

///|
fn make_app(sel_id : String) -> @core.Value {
  Map({
    "sheets": Map({ "a": sheet("first"), "b": sheet("second") }),
    "selId": Str(sel_id),
  })
}

///|
fn sel_path() -> @core.Path {
  @core.Path::new(steps=[SeqAccessStep(seq_field="sheets", key_field="selId")])
}

///|
fn title_of(root : @core.Value, key : String) -> @core.Value? {
  @core.Path::new(steps=[
    SeqStep(field="sheets", key=KStr(key)),
    FieldStep("title"),
  ]).lookup(root)
}

///|
test "SeqAccessStep resolves its key field against the tree" {
  let root = make_app("b")
  guard sel_path().lookup(root) is Some(leaf) else { fail("leaf not found") }
  assert_true(leaf.field_opt("title") is Some(Str("second")))
}

///|
test "update invokes the leaf handler and rebuilds the spine" {
  let root = make_app("b")
  let root2 = sel_path().update(root, Receive, "rename", [Str("renamed")])
  assert_true(!physical_equal(root2, root))
  assert_true(title_of(root2, "b") is Some(Str("renamed")))
  // the old tree is untouched
  assert_true(title_of(root, "b") is Some(Str("second")))
  // the off-path sibling sheet is physically shared between old and new root
  let a_path = @core.Path::new(steps=[SeqStep(field="sheets", key=KStr("a"))])
  guard (a_path.lookup(root), a_path.lookup(root2)) is (Some(oa), Some(na)) else {
    fail("sheet a missing")
  }
  assert_true(physical_equal(oa, na))
}

///|
test "a handler answering None leaves the root physically unchanged" {
  let root = make_app("b")
  // no new leaf -> no spine rebuild -> the SAME root object comes back
  assert_true(
    physical_equal(sel_path().update(root, Receive, "noop", []), root),
  )
}

///|
/// There is no `$unknown` catch-all any more: dispatch does ONE lookup, and a
/// name nothing registered changes nothing. A component that wants a catch-all
/// writes the wildcard arm of its own `update` match, which is the same thing
/// with the name statically bound.
test "an unregistered name is a no-op" {
  let root = make_app("b")
  let root2 = sel_path().update(root, Receive, "does-not-exist", [])
  assert_true(physical_equal(root2, root))
}

///|
test "a missing bucket is an identity no-op" {
  let root = make_app("b")
  assert_true(
    physical_equal(sel_path().update(root, Input, "rename", []), root),
  )
}

///|
test "pin_keys freezes the live key" {
  let root = make_app("b")
  let pinned = sel_path().pin_keys(root)
  assert_true(pinned.steps is [SeqStep(field="sheets", key=KStr("b"))])
  // the selection moves; the pinned path still updates the request-time item
  let moved = make_app("a")
  let moved2 = pinned.update(moved, Receive, "rename", [Str("late-response")])
  assert_true(title_of(moved2, "b") is Some(Str("late-response")))
  assert_true(title_of(moved2, "a") is Some(Str("first")))
}
