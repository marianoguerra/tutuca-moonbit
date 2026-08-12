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
      #|interface counter {
      #|  record state {
      #|    label: string,
      #|    count: s32,
      #|    small: u8,
      #|    ratio: f64,
      #|    ok: bool,
      #|    history: list<s32>,
      #|    pick: option<string>,
      #|    pair: tuple<string, s32>,
      #|    tags: text-set,
      #|    counts: text-omap,
      #|    blob: any,
      #|  }
      #|}
    ),
  )
}

///|
test "…including the named types, where the members are inlined" {
  agree(
    (
      #|interface post {
      #|  enum priority { low, high }
      #|  flags visibility { done, active }
      #|  record label { text: string, done: bool }
      #|  variant due { unscheduled, on-day(s32) }
      #|  record state {
      #|    pri: priority,
      #|    vis: visibility,
      #|    tag: label,
      #|    when_: due,
      #|  }
      #|}
    ),
  )
}

///|
test "…and the child-component slots, named and bare" {
  agree(
    (
      #|interface board {
      #|  record state { editor: sheet, preview: component }
      #|}
      #|interface sheet {
      #|  record state { text: string }
      #|}
    ),
  )
}

///|
test "the zero state is what a generated zero() would build" {
  let def = one(
    (
      #|interface counter {
      #|  record state {
      #|    label: string,
      #|    count: s32,
      #|    ratio: f64,
      #|    ok: bool,
      #|    history: list<s32>,
      #|    pick: option<string>,
      #|    tags: text-set,
      #|    blob: any,
      #|  }
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
      #|interface post {
      #|  record label { text: string, done: bool }
      #|  record state { tag: label }
      #|}
    ),
  )
  assert_eq(
    @info.zero_value(def).get("tag"),
    Some(Map({ "text": Str(""), "done": Bool(false) })),
  )
  assert_eq(def.zero_expr(def.fields[0].ty), "{ text: \"\", done: false }")
}

///|
test "an enum's zero is its first case, and a closed set starts full" {
  let def = one(
    (
      #|interface post {
      #|  enum priority { low, high }
      #|  flags visibility { done, active }
      #|  record state { pri: priority, vis: visibility }
      #|}
    ),
  )
  let z = @info.zero_value(def)
  // `Low`, not `low` — and the asymmetry with the flags below is real rather
  // than a slip. An enum case maps through `upper_name` and a flag through
  // `camel_name` (`statedef/from_wit.mbt`), so the generated codec encodes an
  // enum as `Str("Low")` while a set keys on `"done"`. This zero has to match
  // what that codec produces or a card and a compiled component would disagree
  // about the same state.
  assert_eq(z.get("pri"), Some(Str("Low")))
  // A closed set starts as its declared membership: the one thing about a set
  // that only the schema knows, since the encoded value is just a Map.
  assert_eq(
    z.get("vis"),
    Some(Map({ "done": Bool(true), "active": Bool(true) })),
  )
}

///|
test "the schema description carries the declaration's own channels" {
  let def = one(
    (
      #|interface board {
      #|  record state { rows: values, loading: bool }
      #|  variant receive { reset, focus-row(s32) }
      #|  variant bubble { row-picked(s32) }
      #|  variant response { load-rows(values) }
      #|}
    ),
  )
  let si = @info.schema_info(def, name="Board")
  assert_eq(si.name, "Board")
  assert_eq(si.field_names(), ["rows", "loading"])
  assert_eq(si.receives, ["reset", "focusRow"])
  assert_eq(si.bubbles, ["rowPicked"])
  assert_eq(si.responses, ["loadRows"])
  // What the VIEWS contribute is absent until a caller supplies it — and
  // absent is the honest answer for a schema nobody has views for yet.
  assert_eq(si.inputs, [])
  assert_eq(si.view_names, [])
  // The fingerprint is the one-element one the emitter writes, so a card and
  // a generated component of the same schema land in the same bucket.
  assert_eq(si.fingerprint, @statedef.fingerprint([def]))
}

///|
test "the description takes the views' half from its caller" {
  let def = one("interface c { record state { n: s32 } }")
  let si = @info.schema_info(
    def,
    name="C",
    inputs=["add", "reset"],
    methods=["label"],
    ids=["count"],
    view_names=["main", "row"],
    init_names=["fresh"],
  )
  assert_eq(si.inputs, ["add", "reset"])
  assert_eq(si.methods, ["label"])
  assert_eq(si.ids, ["count"])
  assert_eq(si.view_names, ["main", "row"])
  assert_eq(si.init_names, ["fresh"])
}
