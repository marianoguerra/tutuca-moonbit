// Value::Obj foundation tests: a minimal Obj implementation flows through
// every Value seam — path traversal (COW spine rebuild), handler dispatch
// via Path::update, nesting inside List/Map spines, Eq/Debug/display.

///|
priv struct Card {
  title : String
  tags : Array[@tutuca.Value]
}

///|
fn card(title : String, tags? : Array[@tutuca.Value] = []) -> @tutuca.Value {
  Obj(Card::{ title, tags })
}

///|
impl @tutuca.Obj for Card with fn component_id(_self) {
  Some(77)
}

///|
impl @tutuca.Obj for Card with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    "tags" => Some(List(self.tags))
    // methods surface as pre-bound Fns (JS prototype lookup)
    "shout" => Some(Fn(_args => Str("\{self.title}!")))
    _ => None
  }
}

///|
impl @tutuca.Obj for Card with fn obj_with_field(self, name, v) {
  match (name, v) {
    ("title", Str(s)) => Some(card(s, tags=self.tags))
    ("tags", List(a)) => Some(card(self.title, tags=a))
    _ => None
  }
}

///|
impl @tutuca.Obj for Card with fn obj_handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
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
impl @tutuca.Obj for Card with fn obj_eq(self, other) {
  other.component_id() == Some(77) &&
  other.obj_field("title") == Some(Str(self.title)) &&
  other.obj_field("tags") == Some(List(self.tags))
}

///|
impl @tutuca.Obj for Card with fn obj_debug(self) {
  "Card{\{self.title}}"
}

///|
test "Obj fields traverse and rebuild through Path (COW)" {
  let root : @tutuca.Value = Map({ "card": card("a") })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("card"), FieldStep("title")])
  assert_true(p.lookup(node) is Some(n) && n.as_value() == Some(Str("a")))
  let vb : @tutuca.Value = Str("b")
  let node2 = p.set_value(node, vb)
  assert_true(p.lookup(node2) is Some(n2) && n2.as_value() == Some(Str("b")))
  // old tree untouched; new card is a different instance
  assert_true(p.lookup(node) is Some(n3) && n3.as_value() == Some(Str("a")))
}

///|
test "Obj handler dispatches through Path::update" {
  let root : @tutuca.Value = Map({ "card": card("a") })
  let node : &@tutuca.PathNode = root
  let p = @tutuca.Path::new(steps=[FieldStep("card")])
  let node2 = p.update(node, Receive, "rename", [Str("renamed")])
  assert_true(
    @tutuca.Path::new(steps=[FieldStep("card"), FieldStep("title")]).lookup(
      node2,
    )
    is Some(n) &&
    n.as_value() == Some(Str("renamed")),
  )
  // missing handler -> identity
  assert_true(physical_equal(p.update(node, Input, "rename", []), node))
}

///|
test "instances nest inside Map/List spines and in seq items" {
  let root : @tutuca.Value = Map({
    "cards": Map({ "x": card("first"), "y": card("second") }),
    "stack": List([card("bottom"), card("top")]),
  })
  let node : &@tutuca.PathNode = root
  let by_key = @tutuca.Path::new(steps=[
    SeqStep(field="cards", key=KStr("y")),
    FieldStep("title"),
  ])
  assert_true(
    by_key.lookup(node) is Some(a) && a.as_value() == Some(Str("second")),
  )
  let by_idx = @tutuca.Path::new(steps=[
    SeqStep(field="stack", key=KInt(1)),
    FieldStep("title"),
  ])
  let vtop : @tutuca.Value = Str("TOP")
  let node2 = by_idx.set_value(node, vtop)
  assert_true(
    by_idx.lookup(node2) is Some(b) && b.as_value() == Some(Str("TOP")),
  )
  // sibling instance physically shared after the COW rebuild
  let x_path = @tutuca.Path::new(steps=[SeqStep(field="cards", key=KStr("x"))])
  guard (
      x_path.lookup(node),
      x_path.lookup(by_key.set_value(node, (Str("z") : @tutuca.Value))),
    )
    is (Some(o1), Some(o2)) else {
    fail("card x missing")
  }
  assert_true(physical_equal(o1.as_value().unwrap(), o2.as_value().unwrap()))
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
  assert_true(f([@tutuca.Value::Null]) == Str("hey!"))
}
