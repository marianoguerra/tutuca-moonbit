// A struct-based PathNode implementation: typed component instances (the
// MoonBit analogue of tutuca's Immutable Records) mixed with Value scalars in
// one tree, proving the traversal is trait-generic and that leaf handlers
// drive updates (test/transactor.test.js scenarios).
//
// Pattern for struct impls: container children are STORED as &PathNode boxes
// (trait objects cannot be downcast, so write-back must not need to recover a
// concrete type); scalar fields round-trip through as_value.

///|
priv struct Sheet {
  title : String
}

///|
fn sheet(title : String) -> &@tutuca.PathNode {
  Sheet::{ title, }
}

///|
impl @tutuca.PathNode for Sheet with fn field(self, name) {
  match name {
    "title" => Some(@tutuca.Value::Str(self.title) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for Sheet with fn with_field(self, name, v) {
  ignore(self)
  match (name, v.as_value()) {
    ("title", Some(Str(s))) => Some(sheet(s))
    _ => None
  }
}

///|
impl @tutuca.PathNode for Sheet with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(sheet(s))
            _ => None
          }
        }),
      )
    // a handler that decides nothing changed answers None
    (Receive, "noop") => Some(@tutuca.Handler((_args, _ctx) => None))
    (Receive, "$unknown") =>
      Some(@tutuca.Handler((_args, _ctx) => Some(sheet("\{self.title}?"))))
    _ => None
  }
}

///|
priv struct Sheets {
  items : Map[String, &@tutuca.PathNode]
}

///|
impl @tutuca.PathNode for Sheets with fn item(self, key) {
  match key {
    KStr(k) => self.items.get(k)
    KInt(_) => None
  }
}

///|
impl @tutuca.PathNode for Sheets with fn with_item(self, key, v) {
  match key {
    KStr(k) =>
      if self.items.contains(k) {
        let items = self.items.copy()
        items[k] = v
        Some(Sheets::{ items, } as &@tutuca.PathNode)
      } else {
        None
      }
    KInt(_) => None
  }
}

///|
priv struct App {
  sheets : &@tutuca.PathNode // a Sheets box
  sel_id : String
}

///|
impl @tutuca.PathNode for App with fn field(self, name) {
  match name {
    "sheets" => Some(self.sheets)
    "selId" => Some(@tutuca.Value::Str(self.sel_id) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for App with fn with_field(self, name, v) {
  match name {
    "sheets" =>
      Some(App::{ sheets: v, sel_id: self.sel_id } as &@tutuca.PathNode)
    "selId" =>
      match v.as_value() {
        Some(Str(s)) =>
          Some(App::{ sheets: self.sheets, sel_id: s } as &@tutuca.PathNode)
        _ => None
      }
    _ => None
  }
}

///|
fn make_app(sel_id : String) -> &@tutuca.PathNode {
  App::{
    sheets: Sheets::{ items: { "a": sheet("first"), "b": sheet("second") } },
    sel_id,
  }
}

///|
fn sel_path() -> @tutuca.Path {
  @tutuca.Path::new(steps=[SeqAccessStep(seq_field="sheets", key_field="selId")])
}

///|
fn title_of(root : &@tutuca.PathNode, key : String) -> @tutuca.Value? {
  match
    @tutuca.Path::new(steps=[
      SeqStep(field="sheets", key=KStr(key)),
      FieldStep("title"),
    ]).lookup(root) {
    Some(n) => n.as_value()
    None => None
  }
}

///|
test "SeqAccessStep traverses typed structs like Value trees" {
  let root = make_app("b")
  guard sel_path().lookup(root) is Some(leaf) else { fail("leaf not found") }
  assert_true(
    leaf.field("title") is Some(t) && t.as_value() is Some(Str("second")),
  )
}

///|
test "update invokes the leaf handler and rebuilds the spine" {
  let root = make_app("b")
  let root2 = sel_path().update(root, Receive, "rename", [
    @tutuca.Value::Str("renamed"),
  ])
  assert_true(!physical_equal(root2, root))
  assert_true(title_of(root2, "b") is Some(Str("renamed")))
  // the old tree is untouched
  assert_true(title_of(root, "b") is Some(Str("second")))
  // the off-path sibling sheet is physically shared between old and new root
  let old_a = @tutuca.Path::new(steps=[SeqStep(field="sheets", key=KStr("a"))]).lookup(
    root,
  )
  let new_a = @tutuca.Path::new(steps=[SeqStep(field="sheets", key=KStr("a"))]).lookup(
    root2,
  )
  guard (old_a, new_a) is (Some(oa), Some(na)) else { fail("sheet a missing") }
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
test "an unregistered name falls back to the $unknown handler" {
  let root = make_app("b")
  let root2 = sel_path().update(root, Receive, "does-not-exist", [])
  assert_true(title_of(root2, "b") is Some(Str("second?")))
}

///|
test "a missing bucket is an identity no-op" {
  let root = make_app("b")
  assert_true(
    physical_equal(sel_path().update(root, Input, "rename", []), root),
  )
}

///|
test "pin_keys works across struct impls" {
  let root = make_app("b")
  let pinned = sel_path().pin_keys(root)
  assert_true(pinned.steps is [SeqStep(field="sheets", key=KStr("b"))])
  // the selection moves; the pinned path still updates the request-time item
  let moved = make_app("a")
  let moved2 = pinned.update(moved, Receive, "rename", [
    @tutuca.Value::Str("late-response"),
  ])
  assert_true(title_of(moved2, "b") is Some(Str("late-response")))
  assert_true(title_of(moved2, "a") is Some(Str("first")))
}
