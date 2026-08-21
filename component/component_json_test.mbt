// The tagged codec across the `make_typed` seam — the half `@tutuca`'s own
// suite cannot reach, because it is about what a real constructor does with the
// args map the codec hands it.
//
// Three things are settled here and nowhere else: a value the declared type
// cannot hold falls back to the component's default rather than to the type's
// zero; an unresolvable `$component` does the same, which for a NAMED slot
// means a fresh child and for a free one means Null; and an explicitly empty
// slot stays empty, because the encoder writes the key and a PRESENT null is a
// different answer from an absent one.

///|
priv struct JLeaf {
  text : String
  n : Int
} derive(Default)

///|
impl @component.Fields for JLeaf with fn schema() {
  @component.SchemaInfo::new(fingerprint="jleaf", fields=[
    @component.FieldInfo::new("text", TyText),
    @component.FieldInfo::new("n", TyInt),
  ])
}

///|
impl @component.Fields for JLeaf with fn encode(s) {
  { "text": Str(s.text), "n": Num(s.n.to_double()) }
}

///|
impl @component.Fields for JLeaf with fn decode(f) {
  guard f.get("text") is Some(Str(text)) else { return None }
  guard f.get("n") is Some(Num(n)) else { return None }
  Some({ text, n: n.to_int() })
}

///|
priv struct JHolder {
  named : @tutuca.Value
  free : @tutuca.Value
  kids : Array[@tutuca.Value]
  tags : @tutuca.Value
}

///|
fn JHolder::zero() -> JHolder {
  { named: Null, free: Null, kids: [], tags: Map(Map([])) }
}

///|
impl @component.Fields for JHolder with fn schema() {
  @component.SchemaInfo::new(fingerprint="jholder", fields=[
    @component.FieldInfo::new("named", TyComp(Some("JLeaf"))),
    @component.FieldInfo::new("free", TyComp(None)),
    @component.FieldInfo::new("kids", TyList(TyAny)),
    @component.FieldInfo::new("tags", TySet),
  ])
}

///|
impl @component.Fields for JHolder with fn encode(s) {
  { "named": s.named, "free": s.free, "kids": List(s.kids), "tags": s.tags }
}

///|
impl @component.Fields for JHolder with fn decode(f) {
  guard f.get("named") is Some(named) else { return None }
  guard f.get("free") is Some(free) else { return None }
  guard f.get("kids") is Some(List(kids)) else { return None }
  guard f.get("tags") is Some(tags) else { return None }
  Some({ named, free, kids, tags })
}

///|
fn view(body : String) -> Map[String, @anode.View] {
  { "main": @anode.View::new("main", raw_view=body) }
}

///|
/// A scope holding `JLeaf` and `JHolder`, plus the two components themselves.
fn json_scope() -> (
  @component.ComponentStack,
  @component.Component,
  @component.Component,
) {
  let scope = @component.ComponentStack::new()
  let leaf = @component.component(views=view("<i>leaf</i>"), name="JLeaf", init=JLeaf::{
    text: "seeded",
    n: 42,
  })
  let holder = @component.component(
    views=view("<i>holder</i>"),
    name="JHolder",
    init=JHolder::zero(),
  )
  scope.register_components([leaf, holder], aliases={ "Alias": "JLeaf" })
  (scope, leaf, holder)
}

///|
test "a component round-trips through its own registration scope" {
  let (_scope, leaf, _h) = json_scope()
  let v = leaf.make({ "text": Str("hi"), "n": Num(3.0) })
  inspect(
    v.to_component_json().stringify(),
    content=(
      #|{"$component":"JLeaf","text":"hi","n":3}
    ),
  )
  guard leaf.from_json(v.to_component_json()) is Some(back) else {
    fail("the document did not resolve")
  }
  assert_true(back == v)
}

///|
test "an empty slot stays empty; an ABSENT one takes the declared default" {
  let (_scope, _leaf, holder) = json_scope()
  // `make` with no args: the NAMED slot auto-constructs, the free one is Null.
  let v = holder.make(Map([]))
  assert_true(v.field("named").schema().unwrap().name == "JLeaf")
  assert_true(v.field("free") is Null)

  // A document written from an instance whose named slot is empty keeps it
  // empty, because the key is present and holds null.
  let emptied = holder.make({ "named": Null })
  assert_true(emptied.field("named") is Null)
  inspect(
    emptied.to_component_json().stringify(),
    content=(
      #|{"$component":"JHolder","named":null,"free":null,"kids":[],"tags":[]}
    ),
  )
  guard holder.from_json(emptied.to_component_json()) is Some(back) else {
    fail("the document did not resolve")
  }
  assert_true(back.field("named") is Null)

  // Drop the key instead, and the constructor's own default comes back.
  let doc : Json = { "$component": "JHolder" }
  guard holder.from_json(doc) is Some(defaulted) else {
    fail("the document did not resolve")
  }
  assert_true(defaulted.field("named").schema().unwrap().name == "JLeaf")
}

///|
test "a value the declared type cannot hold falls back to the default" {
  let (_scope, leaf, _h) = json_scope()
  let doc : Json = { "$component": "JLeaf", "text": 7, "n": "not a number" }
  guard leaf.from_json(doc) is Some(v) else {
    fail("the document did not resolve")
  }
  // The component's `init` seed, not the type's zero — which is the whole
  // point of routing through `make` rather than filling the map here.
  assert_true(v.field("text") == Str("seeded"))
  assert_true(v.field("n") == Num(42))
}

///|
test "an unresolvable $component falls back the same way" {
  let (_scope, _leaf, holder) = json_scope()
  let doc : Json = {
    "$component": "JHolder",
    "named": { "$component": "NotLoaded" },
    "free": { "$component": "NotLoaded" },
  }
  guard holder.from_json(doc) is Some(v) else {
    fail("the document did not resolve")
  }
  // A NAMED slot's default is a fresh child...
  assert_true(v.field("named").schema().unwrap().name == "JLeaf")
  // ...and a free slot's is Null, because there is no name to construct.
  assert_true(v.field("free") is Null)
}

///|
test "children recurse, and an alias resolves the way a template's would" {
  let (_scope, _leaf, holder) = json_scope()
  let doc : Json = {
    "$component": "JHolder",
    "kids": [
      { "$component": "JLeaf", "text": "a", "n": 1 },
      { "$component": "Alias", "text": "b", "n": 2 },
    ],
  }
  guard holder.from_json(doc) is Some(v) else {
    fail("the document did not resolve")
  }
  guard v.field("kids") is List(kids) else { fail("kids is not a list") }
  inspect(kids.length(), content="2")
  assert_true(kids[0].field("text") == Str("a"))
  assert_true(kids[1].field("text") == Str("b"))
  assert_true(kids[1].schema().unwrap().name == "JLeaf")
}

///|
test "an unresolvable child keeps its place rather than shifting its siblings" {
  let (_scope, _leaf, holder) = json_scope()
  let doc : Json = {
    "$component": "JHolder",
    "kids": [
      { "$component": "JLeaf", "text": "a", "n": 1 },
      { "$component": "NotLoaded" },
      { "$component": "JLeaf", "text": "c", "n": 3 },
    ],
  }
  guard holder.from_json(doc) is Some(v) else {
    fail("the document did not resolve")
  }
  guard v.field("kids") is List(kids) else { fail("kids is not a list") }
  inspect(kids.length(), content="3")
  assert_true(kids[1] is Null)
  assert_true(kids[2].field("text") == Str("c"))
}

///|
test "a set travels as an array and is held as a Map" {
  let (_scope, _leaf, holder) = json_scope()
  let v = holder.make({ "tags": Map({ "red": Bool(true) }) })
  inspect(
    v.to_component_json().stringify(),
    content=(
      #|{"$component":"JHolder","named":{"$component":"JLeaf","text":"seeded","n":42},"free":null,"kids":[],"tags":["red"]}
    ),
  )
  guard holder.from_json(v.to_component_json()) is Some(back) else {
    fail("the document did not resolve")
  }
  // Back to the Map form, through `coerce_or_default`'s list-to-set rule.
  assert_true(back.field("tags") == Map({ "red": Bool(true) }))
}

///|
test "a component with no scope has nowhere to resolve a name" {
  let unregistered = @component.component(
    views=view("<i>x</i>"),
    name="JLeaf",
    init=(Default::default() : JLeaf),
  )
  let doc : Json = { "$component": "JLeaf" }
  assert_true(unregistered.from_json(doc) is None)
}

///|
test "to_json on Component is the same projection as on the value" {
  let (_scope, leaf, _h) = json_scope()
  let v = leaf.make({ "text": Str("q"), "n": Num(1.0) })
  assert_true(leaf.to_json(v).stringify() == v.to_component_json().stringify())
}
