// The tagged codec's type table, over a generic instance.
//
// `Node` is what a component IS as far as this codec is concerned: a schema and
// a fields map. Using one rather than a real component is what lets the table
// be exercised type by type — `component()` needs a compile-time state struct,
// so a test written against real components could only cover the types those
// components happen to declare.

///|
priv struct Node {
  sc : @core.SchemaInfo
  fields : Map[String, @core.Value]
}

///|
impl @core.Obj for Node with fn obj_schema(self) {
  Some(self.sc)
}

///|
impl @core.Obj for Node with fn obj_field(self, name) {
  self.fields.get(name)
}

///|
/// The schemas this suite's source knows, by name.
fn schemas() -> Map[String, @core.SchemaInfo] {
  let out : Map[String, @core.SchemaInfo] = Map([])
  for
    sc in [
      @core.SchemaInfo::new(name="Leaf", fingerprint="fp-leaf", fields=[
        @core.FieldInfo::new("text", TyText),
        @core.FieldInfo::new("n", TyInt),
      ]),
      @core.SchemaInfo::new(name="Holder", fingerprint="fp-holder", fields=[
        @core.FieldInfo::new("named", TyComp(Some("Leaf"))),
        @core.FieldInfo::new("free", TyComp(None)),
      ]),
      @core.SchemaInfo::new(name="Box", fingerprint="fp-box", fields=[
        @core.FieldInfo::new("kids", TyList(TyAny)),
        @core.FieldInfo::new("slots", TyList(TyComp(None))),
        @core.FieldInfo::new("byName", TyOMap(TyComp(None))),
        @core.FieldInfo::new("loose", TyAny),
        @core.FieldInfo::new("maybe", TyOption(TyComp(None))),
        @core.FieldInfo::new("rec", TyRecord("Label")),
        @core.FieldInfo::new("tags", TySet),
      ]),
    ] {
    out[sc.name] = sc
  }
  out
}

///|
/// A source that builds `Node`s. Every declared field of the schema is filled:
/// what the document supplied, else the type's zero — which is the stand-in
/// here for the default a real component's `make` applies.
fn node_source() -> @core.FnSource {
  let table = schemas()
  @core.FnSource::new(
    (_m, name, args, _at) => {
      match table.get(name) {
        Some(sc) => {
          let fields : Map[String, @core.Value] = Map([])
          for f in sc.fields {
            fields[f.name] = match args.get(f.name) {
              // Stands in for `FieldSpec::coerce_or_default`, which is the
              // component layer's job and not this one's: a set travels as an
              // array and is HELD as a Map, and the real constructor is what
              // converts. Only that one rule is needed here.
              Some(List(items)) if f.ty is (TySet | TyFlags(_, _)) => {
                let m : Map[String, @core.Value] = Map([])
                for it in items {
                  m[it.to_display_string()] = Bool(true)
                }
                Map(m)
              }
              Some(v) => v
              None => f.ty.zero()
            }
          }
          Some(Obj(Node::{ sc, fields }))
        }
        None => None
      }
    },
    describe=(_m, name) => table.get(name),
  )
}

///|
fn node(name : String, fields : Map[String, @core.Value]) -> @core.Value {
  Obj(Node::{ sc: schemas().get(name).unwrap(), fields })
}

///|
fn wire(v : @core.Value) -> String {
  v.to_component_json().stringify()
}

///|
fn back(v : @core.Value) -> @core.Value {
  @core.Value::from_component_json(v.to_component_json(), node_source()).unwrap_or(
    Null,
  )
}

///|
test "an instance names itself, and its scalars travel as themselves" {
  let leaf = node("Leaf", { "text": Str("hi"), "n": Num(3.0) })
  inspect(
    wire(leaf),
    content=(
      #|{"$component":"Leaf","text":"hi","n":3}
    ),
  )
  assert_true(back(leaf) == leaf)
}

///|
test "an empty slot survives, because the key is written and read as present" {
  let h = node("Holder", { "named": Null, "free": Null })
  inspect(
    wire(h),
    content=(
      #|{"$component":"Holder","named":null,"free":null}
    ),
  )
  let round = back(h)
  assert_true(round.field("named") is Null)
  assert_true(round.field("free") is Null)
}

///|
test "a named slot may omit the tag; a free one must carry it" {
  let leaf = node("Leaf", { "text": Str("a"), "n": Num(1.0) })
  let h = node("Holder", { "named": leaf, "free": leaf })
  inspect(
    wire(h),
    content=(
      #|{"$component":"Holder","named":{"$component":"Leaf","text":"a","n":1},"free":{"$component":"Leaf","text":"a","n":1}}
    ),
  )
  assert_true(back(h) == h)
  // Untagged at a named slot: the TYPE says what to build.
  let doc : Json = { "$component": "Holder", "named": { "text": "b", "n": 2 } }
  let v = @core.Value::from_component_json(doc, node_source()).unwrap()
  debug_inspect(
    v.field("named").field("text"),
    content=(
      #|RStr("b")
    ),
  )
  // Untagged at a free slot: nothing names it, so the field takes its default.
  let doc2 : Json = { "$component": "Holder", "free": { "text": "b" } }
  let v2 = @core.Value::from_component_json(doc2, node_source()).unwrap()
  assert_true(v2.field("free") is Null)
}

///|
test "a tag the type disagrees with wins — the document is the specific claim" {
  let doc : Json = {
    "$component": "Holder",
    "named": { "$component": "Holder", "named": null, "free": null },
  }
  let v = @core.Value::from_component_json(doc, node_source()).unwrap()
  inspect(v.field("named").schema().unwrap().name, content="Holder")
}

///|
test "containers recurse by ELEMENT type, which coerce_or_default never does" {
  let leaf = node("Leaf", { "text": Str("x"), "n": Num(9.0) })
  let b = node("Box", {
    "kids": List([leaf, Str("plain")]),
    "slots": List([leaf]),
    "byName": Map({ "a": leaf }),
    "loose": leaf,
    "maybe": leaf,
    "rec": Map({ "k": Str("v") }),
    "tags": Map({ "red": Bool(true), "blue": Bool(true) }),
  })
  inspect(
    wire(b),
    content=(
      #|{"$component":"Box","kids":[{"$component":"Leaf","text":"x","n":9},"plain"],"slots":[{"$component":"Leaf","text":"x","n":9}],"byName":{"a":{"$component":"Leaf","text":"x","n":9}},"loose":{"$component":"Leaf","text":"x","n":9},"maybe":{"$component":"Leaf","text":"x","n":9},"rec":{"k":"v"},"tags":["red","blue"]}
    ),
  )
  assert_true(back(b) == b)
}

///|
test "an empty container stays empty" {
  let b = node("Box", { "kids": List([]), "slots": List([]) })
  let round = back(b)
  debug_inspect(
    round.field("kids"),
    content=(
      #|RList([])
    ),
  )
  debug_inspect(
    round.field("slots"),
    content=(
      #|RList([])
    ),
  )
}

///|
test "an unresolvable element becomes Null rather than shifting its neighbours" {
  let doc : Json = {
    "$component": "Box",
    "slots": [
      { "$component": "Leaf", "text": "a", "n": 1 },
      { "$component": "Gone" },
      { "$component": "Leaf", "text": "c", "n": 3 },
    ],
  }
  let v = @core.Value::from_component_json(doc, node_source()).unwrap()
  guard v.field("slots") is List(items) else { fail("slots is not a list") }
  inspect(items.length(), content="3")
  debug_inspect(
    items[1],
    content=(
      #|RNull
    ),
  )
  debug_inspect(
    items[2].field("text"),
    content=(
      #|RStr("c")
    ),
  )
}

///|
test "an unresolvable field is OMITTED, so the constructor's default applies" {
  let doc : Json = {
    "$component": "Holder",
    "named": { "$component": "Gone" },
    "free": { "$component": "Gone" },
  }
  let v = @core.Value::from_component_json(doc, node_source()).unwrap()
  // The source fills every declared field with the type's zero when the args
  // map does not carry it, which is what an omission routes to.
  assert_true(v.field("named") is Null)
  assert_true(v.field("free") is Null)
}

///|
test "a $component inside a record is data, not an instance" {
  let doc : Json = {
    "$component": "Box",
    "rec": { "$component": "Leaf", "text": "not an instance" },
  }
  let v = @core.Value::from_component_json(doc, node_source()).unwrap()
  guard v.field("rec") is Map(m) else { fail("rec is not a map") }
  debug_inspect(
    m.get("$component"),
    content=(
      #|Some(RStr("Leaf"))
    ),
  )
}

///|
test "a Fn and a schema-less Obj both project to null" {
  let sc = @core.SchemaInfo::new(name="Leaf", fingerprint="fp-leaf", fields=[
    @core.FieldInfo::new("text", TyAny),
    @core.FieldInfo::new("n", TyAny),
  ])
  let v : @core.Value = Obj(Node::{
    sc,
    fields: { "text": Fn(_args => Null), "n": Obj(Bare::{  }) },
  })
  inspect(
    v.to_component_json().stringify(),
    content=(
      #|{"$component":"Leaf","text":null,"n":null}
    ),
  )
}

///|
priv struct Bare {}

///|
impl @core.Obj for Bare with fn obj_debug(_self) {
  "bare"
}

///|
test "a field the schema does not name is not written" {
  let leaf = node("Leaf", {
    "text": Str("a"),
    "n": Num(1.0),
    "undeclared": Str("gone"),
  })
  inspect(
    wire(leaf),
    content=(
      #|{"$component":"Leaf","text":"a","n":1}
    ),
  )
}

///|
test "a module rides along and comes back" {
  let seen : Ref[String?] = { val: None }
  let src = @core.FnSource::new((m, name, _args, _at) => {
    seen.val = m
    if name == "Far" {
      Some(Str("built"))
    } else {
      None
    }
  })
  let doc : Json = { "$component": "Far", "$module": "some/bundle" }
  debug_inspect(
    @core.Value::from_component_json(doc, src),
    content=(
      #|Some(RStr("built"))
    ),
  )
  debug_inspect(
    seen.val,
    content=(
      #|Some("some/bundle")
    ),
  )
}

///|
test "claim stops the walk before a field is read, and gets the pointer" {
  let leaf = node("Leaf", { "text": Str("a"), "n": Num(1.0) })
  let h = node("Holder", { "named": leaf, "free": Null })
  let seen : Array[String] = []
  let j = h.to_component_json(claim=(_v, at) => {
    seen.push(at)
    if at == "/named" {
      Some({ "$component": "Leaf", "$module": "far" })
    } else {
      None
    }
  })
  debug_inspect(
    seen,
    content=(
      #|["", "/named"]
    ),
  )
  inspect(
    j.stringify(),
    content=(
      #|{"$component":"Holder","named":{"$component":"Leaf","$module":"far"},"free":null}
    ),
  )
}

///|
test "a key holding a slash or a tilde is escaped, per RFC 6901" {
  let sc = @core.SchemaInfo::new(name="Odd", fingerprint="fp-odd", fields=[
    @core.FieldInfo::new("a/b", TyComp(None)),
    @core.FieldInfo::new("c~d", TyComp(None)),
  ])
  let leaf = node("Leaf", { "text": Str("a"), "n": Num(1.0) })
  let v : @core.Value = Obj(Node::{ sc, fields: { "a/b": leaf, "c~d": leaf } })
  let seen : Array[String] = []
  v.to_component_json(claim=(_v, at) => {
    seen.push(at)
    None
  })
  |> ignore
  debug_inspect(
    seen,
    content=(
      #|["", "/a~1b", "/c~0d"]
    ),
  )
}
