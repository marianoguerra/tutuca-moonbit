// The twins have to agree.
//
// `ty_info` returns a value and `StateDef::ty_info_src` returns the SOURCE
// that builds the same value; `zero_of` returns a value and `zero_expr` the
// source. Two implementations of one projection is exactly the shape that
// rots, so these tests do not assert either side in isolation — they render
// the value back into the source spelling and compare it against the emitter's
// own output, for every case in the lattice.
//
// A case the emitter grows and this file does not will fail here rather than
// in a browser six weeks later.

///|
fn one(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// Render a `TyInfo` in the spelling `ty_info_src` emits.
fn show_ty(t : @tutuca.TyInfo) -> String {
  match t {
    TyBool => "TyBool"
    TyInt => "TyInt"
    TyFloat => "TyFloat"
    TyText => "TyText"
    TyList(e) => "TyList(" + show_ty(e) + ")"
    TyTuple(ts) => "TyTuple([" + ts.map(show_ty).join(", ") + "])"
    TyOption(e) => "TyOption(" + show_ty(e) + ")"
    TyOMap(v) => "TyOMap(" + show_ty(v) + ")"
    TyRecord(n) => "TyRecord(\"\{n}\")"
    TyEnum(n) => "TyEnum(\"\{n}\")"
    TyVariant(n) => "TyVariant(\"\{n}\")"
    TyFlags(n, ms) =>
      "TyFlags(\"\{n}\", [" + ms.map(m => "\"\{m}\"").join(", ") + "])"
    TySet => "TySet"
    TyComp(Some(c)) => "TyComp(Some(\"\{c}\"))"
    TyComp(None) => "TyComp(None)"
    TyTable => "TyTable"
    TyAny => "TyAny"
  }
}

///|
/// Every field of every component in a block, checked both ways at once.
fn agree(src : String) -> Unit raise {
  for def in @statedef.parse_state(src) {
    agree_def(def)
  }
}

///|
fn agree_def(def : @statedef.StateDef) -> Unit raise {
  for f in def.fields {
    assert_eq(show_ty(@info.ty_info(def, f.ty)), def.ty_info_src(f.ty))
  }
}

///|
test "the type projection agrees with the emitter over the whole lattice" {
  agree(
    (
      #|state Counter {
      #|  label   : String
      #|  count   : Int
      #|  small   : UInt8
      #|  ratio   : Double
      #|  ok      : Bool
      #|  history : Array[Int]
      #|  pick    : String?
      #|  pair    : (String, Int)
      #|  tags    : Set[String]
      #|  counts  : Map[String, String]
      #|  blob    : Any
      #|}
    ),
  )
}

///|
test "…including the named types, where the members are inlined" {
  agree(
    (
      #|enum Priority { Low, High }
      #|enum Visibility { Done, Active }
      #|struct Label { text: String, done: Bool }
      #|enum Due { Unscheduled, OnDay(Int) }
      #|state Post {
      #|  pri  : Priority
      #|  vis  : Set[Visibility]
      #|  tag  : Label
      #|  due  : Due
      #|}
    ),
  )
}

///|
test "…and the child-component slots, named and bare" {
  agree(
    (
      #|state Board { editor: Sheet, preview: Component }
      #|state Sheet { text: String }
    ),
  )
}

///|
test "the zero state is what a generated zero() would build" {
  let def = one(
    (
      #|state Counter {
      #|  label   : String
      #|  count   : Int
      #|  ratio   : Double
      #|  ok      : Bool
      #|  history : Array[Int]
      #|  pick    : String?
      #|  tags    : Set[String]
      #|  blob    : Any
      #|}
    ),
  )
  let z = @info.zero_value(def)
  assert_eq(z.get("label"), Some(Str("")))
  assert_eq(z.get("count"), Some(Num(0)))
  assert_eq(z.get("ratio"), Some(Num(0)))
  assert_eq(z.get("ok"), Some(Bool(false)))
  assert_eq(z.get("history"), Some(List([])))
  // An absent option is Null, which is what `None` encodes to.
  assert_eq(z.get("pick"), Some(Null))
  assert_eq(z.get("tags"), Some(Map(Map([]))))
  assert_eq(z.get("blob"), Some(Null))
}

///|
test "a record's zero opens it, which its TyInfo alone cannot" {
  // `TyRecord` keeps only a name — a record's fields are the instance's to
  // answer — so `TyInfo::zero` gives an empty map. With the DECLARATION in
  // hand the zero is the fields' zeros, matching what `zero_expr` writes.
  let def = one(
    (
      #|struct Label { text: String, done: Bool }
      #|state Post { tag: Label }
    ),
  )
  assert_eq(
    @info.zero_value(def).get("tag"),
    Some(Map({ "text": Str(""), "done": Bool(false) })),
  )
  assert_eq(def.zero_expr(def.fields[0].ty), "{ text: \"\", done: false }")
}

///|
test "an enum's zero is its first case, and a set starts EMPTY" {
  let def = one(
    (
      #|enum Priority { Low, High }
      #|enum Visibility { Done, Active }
      #|state Post { pri: Priority, vis: Set[Visibility] }
    ),
  )
  let z = @info.zero_value(def)
  // `Low`, the case as the enum declares it. The generated codec encodes an
  // enum as `Str("Low")`, and this zero has to match what that codec produces
  // or a card and a compiled component would disagree about the same state.
  // The same enum spelling feeds both scalar values and closed sets.
  assert_eq(z.get("pri"), Some(Str("Low")))
  // Empty: the container decides the zero and the enum decides membership.
  assert_eq(z.get("vis"), Some(Map(Map([]))))
}

///|
test "the schema description carries the declaration's own channels" {
  let def = one(
    (
      #|state Board { rows: Array[Any], loading: Bool }
      #|receive  Board { reset, focusRow(Int) }
      #|intent   Board { rowPicked(Int), loadRows }
    ),
  )
  let si = @info.schema_info(def, name="Board")
  assert_eq(si.name, "Board")
  assert_eq(si.field_names(), ["rows", "loading"])
  assert_eq(si.receives, ["reset", "focusRow"])
  assert_eq(si.intents, ["rowPicked", "loadRows"])
  // What the VIEWS contribute is absent until a caller supplies it — and
  // absent is the honest answer for a schema nobody has views for yet.
  assert_eq(si.view_handlers, [])
  assert_eq(si.view_names, [])
  // The fingerprint is the one-element one the emitter writes, so a card and
  // a generated component of the same schema land in the same bucket.
  assert_eq(si.fingerprint, @statedef.fingerprint([def]))
}

///|
test "the description takes the views' half from its caller" {
  let def = one("state C { n: Int }")
  let si = @info.schema_info(
    def,
    name="C",
    view_handlers=["add", "reset"],
    methods=["label"],
    ids=["count"],
    view_names=["main", "row"],
    init_names=["fresh"],
  )
  assert_eq(si.view_handlers, ["add", "reset"])
  assert_eq(si.methods, ["label"])
  assert_eq(si.ids, ["count"])
  assert_eq(si.view_names, ["main", "row"])
  assert_eq(si.init_names, ["fresh"])
}
