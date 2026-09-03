// A write to an option-typed field reaches the STATE STRUCT, not only the
// fields map.
//
// The bug this is from: `s_fields` — the names a write re-decodes — was read
// off `encode(init)`, and a generated `encode` omits an option that is None.
// A component slot seeded `None` was therefore absent from that list forever
// after, so a child's successor updated the map (the child re-rendered, since
// a view renders from the map) while every `compute`, `loop_with` and `update`
// arm reading `s.kid` saw the child the parent was born with.

///|
priv struct ParentState {
  label : String
  kid : @tutuca.Value?
}

///|
impl @component.Fields for ParentState with fn schema() {
  @component.SchemaInfo::new(fingerprint="parent_state", fields=[
    @component.FieldInfo::new("label", TyText),
    @component.FieldInfo::new("kid", TyOption(TyComp(Some("Kid")))),
  ])
}

///|
impl @component.Fields for ParentState with fn encode(s) {
  // Exactly what `gen-views` writes for an option: the key is ABSENT when the
  // value is None, which is the shape that made the old `s_fields` wrong.
  let out : Map[String, @tutuca.Value] = { "label": Str(s.label) }
  match s.kid {
    Some(v) => out["kid"] = v
    None => ()
  }
  out
}

///|
impl @component.Fields for ParentState with fn decode(f) {
  guard f.get("label") is Some(Str(label)) else { return None }
  Some({
    label,
    kid: match f.get("kid") {
      None | Some(Null) => None
      Some(v) => Some(v)
    },
  })
}

///|
priv struct KidState {
  n : Int
}

///|
impl @component.Fields for KidState with fn schema() {
  @component.SchemaInfo::new(fingerprint="kid_state", fields=[
    @component.FieldInfo::new("n", TyInt(width=32, signed=true)),
  ])
}

///|
impl @component.Fields for KidState with fn encode(s) {
  { "n": Num(s.n.to_double()) }
}

///|
impl @component.Fields for KidState with fn decode(f) {
  guard f.get("n") is Some(Num(v)) else { return None }
  Some({ n: v.to_int(), })
}

///|
fn kid_comp() -> @component.Component {
  @component.component(
    views={ "main": @anode.View::new("main", raw_view="<b></b>") },
    name="Kid",
    initial=KidState::{ n: 0, },
  )
}

///|
fn parent_comp() -> @component.Component {
  @component.component(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Parent",
    // Seeded None — the state the old code read `s_fields` off.
    initial=ParentState::{ label: "p", kid: None, },
    // What a `compute` or a `loop_with` does: derive from the slot. It reads
    // the STRUCT, which is the half that used to go stale.
    compute={
      "kidN": (s : ParentState, _args, _stack) => {
        match s.kid {
          Some(kid) => kid.field("n")
          None => Str("none")
        }
      },
    },
  )
}

///|
test "a write to an optional slot reaches the state struct" {
  let scope = @component.ComponentStack::new()
  scope.register_components([kid_comp(), parent_comp()])
  let kid = kid_comp().make({ "n": Num(1) })
  let parent = parent_comp().make({ "kid": kid })
  // the derived read sees the child it was made with
  guard parent is Obj(p0) else { fail("not obj") }
  guard p0.field("kidN") is Some(Fn(f0)) else { fail("no compute") }
  assert_eq(f0([parent]), Num(1))
  // …and the successor, once the child is replaced through the ordinary
  // field write the runtime performs when a child transitions
  let next = parent.with_field("kid", kid_comp().make({ "n": Num(7) }))
  guard next is Obj(p1) else { fail("not obj") }
  guard p1.field("kidN") is Some(Fn(f1)) else { fail("no compute") }
  assert_eq(f1([next]), Num(7))
}

///|
test "an optional slot seeded None takes its first child" {
  let scope = @component.ComponentStack::new()
  scope.register_components([kid_comp(), parent_comp()])
  let parent = parent_comp().make(Map([]))
  guard parent is Obj(p0) else { fail("not obj") }
  guard p0.field("kidN") is Some(Fn(f0)) else { fail("no compute") }
  // absent, and it stays absent — an option-typed slot is not built for you,
  // which is the difference from `Instance[Kid]` and the reason to spell it
  assert_eq(f0([parent]), Str("none"))
  let next = parent.with_field("kid", kid_comp().make({ "n": Num(3) }))
  guard next is Obj(p1) else { fail("not obj") }
  guard p1.field("kidN") is Some(Fn(f1)) else { fail("no compute") }
  assert_eq(f1([next]), Num(3))
}
