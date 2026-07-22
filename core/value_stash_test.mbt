// The with_value_stash contract: inside the stash, the ToJson/FromJson trait
// impls carry Obj/Fn Values through Json losslessly (typed-state encode/
// decode); outside it they keep the plain semantics (Obj/Fn -> null).

///|
priv struct Pin {
  label : String
}

///|
impl @core.Obj for Pin with fn component_id(_self) {
  Some(9001)
}

///|
impl @core.Obj for Pin with fn obj_field(self, name) {
  if name == "label" {
    Some(Str(self.label))
  } else {
    None
  }
}

///|
priv struct StashState {
  n : Int
  items : Array[@core.Value]
  slot : @core.Value
} derive(ToJson, FromJson)

///|
test "stash round-trips Obj and Fn identically" {
  let pin : @core.Value = Obj(Pin::{ label: "a" })
  let f : @core.Value = Fn(_args => Str("hi"))
  let s = StashState::{ n: 3, items: [pin, Num(1), f], slot: pin }
  let out : StashState? = @core.with_value_stash(() => {
    Some(@json.from_json(ToJson::to_json(s))) catch {
      _ => None
    }
  })
  let out = out.unwrap()
  assert_eq(out.n, 3)
  assert_true(out.items[0] is Obj(_))
  assert_eq(out.items[0].field("label"), Str("a"))
  assert_eq(out.items[1], Num(1))
  guard out.items[2] is Fn(g) else { fail("expected Fn") }
  assert_eq(g([]), Str("hi"))
  assert_true(out.slot is Obj(_))
}

///|
test "outside the stash Obj and Fn degrade to null" {
  let pin : @core.Value = Obj(Pin::{ label: "a" })
  let s = StashState::{ n: 1, items: [pin], slot: Fn(_a => Null) }
  let j = ToJson::to_json(s)
  let out : StashState = @json.from_json(j)
  assert_eq(out.items[0], Null)
  assert_eq(out.slot, Null)
}

///|
test "coercing accessors" {
  let n : @core.Value = Num(3.7)
  let s : @core.Value = Str("x")
  let b : @core.Value = Bool(true)
  let nil : @core.Value = Null
  let m : @core.Value = Map({ "a": @core.Value::Num(1) })
  assert_eq(n.int(), 3)
  assert_eq(s.int(default=5), 5)
  assert_eq(s.str(), "x")
  assert_eq(b.bool(), true)
  assert_eq(nil.list().length(), 0)
  assert_eq(m.field("a"), Num(1))
  assert_eq(n.field("a"), Null)
}
