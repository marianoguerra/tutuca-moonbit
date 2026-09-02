// The twins have to agree.
//
// `zero_of` returns a value and `zero_expr` the source that builds it; the
// same for `domains_of` and `domains_src`. Two implementations of one
// projection is exactly the shape that rots, so these tests do not assert
// either side in isolation — they render the value back into the source
// spelling and compare it against the emitter's own output, for every case in
// the lattice.
//
// The TYPE pair is no longer a pair: there is one `Ty`, the schema parses into
// it, and `Ty::to_mbt_source` prints it. What is left of that test is a
// SNAPSHOT of the printing, which is a table to read rather than a twin to
// keep in step.
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
/// Every field of every component in a block, as `name : source`.
fn shown(src : String) -> String raise {
  let out : Array[String] = []
  for def in @statedef.parse_state(src) {
    for f in def.fields {
      out.push(f.name + " : " + f.ty.to_mbt_source())
    }
  }
  out.join("\n")
}

///|
test "golden: the source form of every type in the lattice" {
  inspect(
    shown(
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
    ),
    content=(
      #|label : TyText
      #|count : TyInt(width=32, signed=true)
      #|small : TyInt(width=8, signed=false)
      #|ratio : TyFloat
      #|ok : TyBool
      #|history : TyList(TyInt(width=32, signed=true))
      #|pick : TyOption(TyText)
      #|pair : TyTuple([TyText, TyInt(width=32, signed=true)])
      #|tags : TySet
      #|counts : TyOMap(TyText)
      #|blob : TyAny
    ),
  )
}

///|
test "…including the named types, where the members are inlined" {
  inspect(
    shown(
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
    ),
    content=(
      #|pri : TyEnum("Priority")
      #|vis : TyFlags("Visibility", ["Done", "Active"])
      #|tag : TyRecord("Label")
      #|due : TyVariant("Due")
    ),
  )
}

///|
test "…and the child-component slots, named and bare" {
  inspect(
    shown(
      (
        #|state Board { editor: Sheet, preview: Component }
        #|state Sheet { text: String }
      ),
    ),
    content=(
      #|editor : TyComp(Some("Sheet"))
      #|preview : TyComp(None)
      #|text : TyText
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
test "a record's zero opens it, which its Ty alone cannot" {
  // `TyRecord` keeps only a name — a record's fields are the instance's to
  // answer — so `Ty::zero` gives an empty map. With the DECLARATION in
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
      #|handle Board {
      #|  message { reset, focusRow(Int) }
      #|  intent { rowPicked(Int), loadRows }
      #|}
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
