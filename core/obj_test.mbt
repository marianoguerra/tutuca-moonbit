// Value::Obj foundation tests: a minimal Obj implementation flows through
// every Value seam — path traversal (COW spine rebuild), handler dispatch
// via Path::update, nesting inside List/Map spines, Eq/Debug/display.

///|
priv struct Card {
  title : String
  tags : Array[@core.Value]
}

///|
fn card(title : String, tags? : Array[@core.Value] = []) -> @core.Value {
  Obj(Card::{ title, tags })
}

///|
impl @core.Obj for Card with fn component_id(_self) {
  Some(77)
}

///|
impl @core.Obj for Card with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    "tags" => Some(List(self.tags))
    // methods surface as pre-bound Fns (JS prototype lookup)
    "shout" => Some(Fn(_args => Str("\{self.title}!")))
    _ => None
  }
}

///|
impl @core.Obj for Card with fn obj_with_field(self, name, v) {
  match (name, v) {
    ("title", Str(s)) => Some(card(s, tags=self.tags))
    ("tags", List(a)) => Some(card(self.title, tags=a))
    _ => None
  }
}

///|
impl @core.Obj for Card with fn obj_handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(card(s, tags=self.tags))
            _ => None
          }
        }),
      )
    _ => None
  }
}

///|
impl @core.Obj for Card with fn obj_eq(self, other) {
  other.component_id() == Some(77) &&
  other.obj_field("title") == Some(Str(self.title)) &&
  other.obj_field("tags") == Some(List(self.tags))
}

///|
impl @core.Obj for Card with fn obj_debug(self) {
  "Card{\{self.title}}"
}

///|
test "Obj fields traverse and rebuild through Path (COW)" {
  let root : @core.Value = Map({ "card": card("a") })
  let p = @core.Path::new(steps=[FieldStep("card"), FieldStep("title")])
  assert_true(p.lookup(root) is Some(Str("a")))
  let vb : @core.Value = Str("b")
  let root2 = p.set_value(root, vb)
  assert_true(p.lookup(root2) is Some(Str("b")))
  // old tree untouched; new card is a different instance
  assert_true(p.lookup(root) is Some(Str("a")))
}

///|
test "Obj handler dispatches through Path::update" {
  let root : @core.Value = Map({ "card": card("a") })
  let p = @core.Path::new(steps=[FieldStep("card")])
  let root2 = p.update(root, Receive, "rename", [Str("renamed")])
  assert_true(
    @core.Path::new(steps=[FieldStep("card"), FieldStep("title")]).lookup(root2)
    is Some(Str("renamed")),
  )
  // missing handler -> identity
  assert_true(physical_equal(p.update(root, Input, "rename", []), root))
}

///|
test "instances nest inside Map/List spines and in seq items" {
  let root : @core.Value = Map({
    "cards": Map({ "x": card("first"), "y": card("second") }),
    "stack": List([card("bottom"), card("top")]),
  })
  let by_key = @core.Path::new(steps=[
    SeqStep(field="cards", key=KStr("y")),
    FieldStep("title"),
  ])
  assert_true(by_key.lookup(root) is Some(Str("second")))
  let by_idx = @core.Path::new(steps=[
    SeqStep(field="stack", key=KInt(1)),
    FieldStep("title"),
  ])
  let vtop : @core.Value = Str("TOP")
  let root2 = by_idx.set_value(root, vtop)
  assert_true(by_idx.lookup(root2) is Some(Str("TOP")))
  // sibling instance physically shared after the COW rebuild
  let x_path = @core.Path::new(steps=[SeqStep(field="cards", key=KStr("x"))])
  guard (
      x_path.lookup(root),
      x_path.lookup(by_key.set_value(root, (Str("z") : @core.Value))),
    )
    is (Some(o1), Some(o2)) else {
    fail("card x missing")
  }
  assert_true(physical_equal(o1, o2))
}

///|
test "Obj equality, debug and method fields" {
  assert_true(card("a") == card("a"))
  assert_true(card("a") != card("b"))
  let c = card("hey")
  guard c is Obj(o) else { fail("not an obj") }
  debug_inspect(c, content="RObj(\"Card{hey}\")")
  // pre-bound method Fn ignores the this-slot
  guard o.obj_field("shout") is Some(Fn(f)) else { fail("no method") }
  assert_true(f([Null]) == Str("hey!"))
}
