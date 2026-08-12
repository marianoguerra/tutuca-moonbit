// The generic-access layer: one lookup for every container shape, totals with
// defaults, sizes, entries, method calls, and the declared description.

///|
/// A described instance: three fields, one method, and a sequence side so the
/// item/size/entries paths have a custom collection to run against.
priv struct Row {
  title : String
  tags : Array[@core.Value]
}

///|
fn row_schema() -> @core.SchemaInfo {
  @core.SchemaInfo::new(
    name="Row",
    fingerprint="row1",
    fields=[
      @core.FieldInfo::new("title", TyText),
      @core.FieldInfo::new("tags", TyList(TyText)),
    ],
    methods=["shout"],
  )
}

///|
fn row(title : String, tags? : Array[@core.Value] = []) -> @core.Value {
  Obj(Row::{ title, tags })
}

///|
impl @core.Obj for Row with fn component_id(_self) {
  Some(91)
}

///|
impl @core.Obj for Row with fn obj_schema(_self) {
  Some(row_schema())
}

///|
impl @core.Obj for Row with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    "tags" => Some(List(self.tags))
    // a method surfaces as a self-pre-bound Fn that ignores args element 0
    "shout" => Some(Fn(args => Str("\{self.title}!\{args.length() - 1}")))
    _ => None
  }
}

///|
impl @core.Obj for Row with fn obj_with_field(self, name, v) {
  match (name, v) {
    ("title", Str(s)) => Some(row(s, tags=self.tags))
    _ => None
  }
}

///|
/// The tags, keyed by position — a custom sequence in the SEQ_INFO sense.
impl @core.Obj for Row with fn obj_seq_entries(self) {
  let out : Array[(@core.PathKey, @core.Value)] = []
  for i, t in self.tags {
    out.push((KInt(i), t))
  }
  Some(out)
}

///|
impl @core.Obj for Row with fn obj_item(self, key) {
  match key {
    KInt(i) => self.tags.get(i)
    KStr(_) => None
  }
}

// ---------------------------------------------------------------------------
// One-hop reads
// ---------------------------------------------------------------------------

///|
test "field reads answer for Map and Obj alike, and tell missing from Null" {
  let m : @core.Value = Map({ "a": Num(1), "n": Null })
  assert_eq(m.field("a"), Num(1))
  assert_eq(m.field("nope"), Null)
  // the distinction `field` cannot make
  assert_eq(m.field_opt("n"), Some(Null))
  assert_eq(m.field_opt("nope"), None)
  let r = row("hi")
  assert_eq(r.field("title"), Str("hi"))
  assert_eq(r.field_opt("nope"), None)
  // a scalar has no fields at all
  assert_eq((Num(3) : @core.Value).field_opt("a"), None)
}

///|
test "item reads cover list, map and custom collection through one call" {
  let l : @core.Value = List([Str("a"), Str("b")])
  assert_eq(l.index(1), Str("b"))
  assert_eq(l.index(9), Null)
  assert_eq(l.index(9, default=Str("fallback")), Str("fallback"))
  assert_eq(l.index(-1), Null)
  let m : @core.Value = Map({ "k": Num(7) })
  assert_eq(m.key("k"), Num(7))
  assert_eq(m.key("missing", default=Num(0)), Num(0))
  // ...and the arm that used to be written out per call site
  let r = row("x", tags=[Str("t0"), Str("t1")])
  assert_eq(r.index(1), Str("t1"))
  assert_eq(r.item_opt(KStr("t0")), None)
}

///|
test "a total write keeps THIS value when the write changes nothing" {
  let shared : @core.Value = List([Num(1)])
  let m : @core.Value = Map({ "a": shared })
  // writing back the very object already stored must not rebuild the map:
  // identity is what the transactor reads as "nothing happened"
  @test.assert_same_object(m.with_field("a", shared), m)
  assert_eq(m.with_field("a", Num(2)).field("a"), Num(2))
  // an unwritable target answers with itself rather than a None to unwrap
  let scalar : @core.Value = Num(1)
  @test.assert_same_object(scalar.with_field("a", Null), scalar)
  let r = row("x")
  @test.assert_same_object(r.with_field("tags", List([])), r)
  assert_eq(r.with_field("title", Str("y")).field("title"), Str("y"))
}

///|
test "a total item write keeps identity the same way" {
  let shared : @core.Value = Str("a")
  let l : @core.Value = List([shared])
  @test.assert_same_object(l.with_item(KInt(0), shared), l)
  assert_eq(l.with_item(KInt(0), Str("b")).index(0), Str("b"))
  // out of range is a no-op, not a panic and not a grow
  @test.assert_same_object(l.with_item(KInt(5), Str("b")), l)
}

// ---------------------------------------------------------------------------
// Sequences
// ---------------------------------------------------------------------------

///|
test "size answers for a custom collection, which it used to refuse" {
  assert_eq(@core.size_of(List([Num(1), Num(2)])), Some(2))
  assert_eq(@core.size_of(Str("abc")), Some(3))
  assert_eq(@core.size_of(Map({ "a": Null })), Some(1))
  let r = row("x", tags=[Str("a"), Str("b"), Str("c")])
  assert_eq(@core.size_of(r), Some(3))
  assert_eq(r.size(), 3)
  // an instance that is not a sequence still has no size: a component has
  // fields, not a length
  assert_eq(@core.size_of(row("x")), Some(0))
  assert_eq(@core.size_of(Num(1)), None)
  assert_eq((Num(1) : @core.Value).size(default=-1), -1)
}

///|
test "entries iterate every container in the order the renderer visits" {
  let l : @core.Value = List([Str("a"), Str("b")])
  assert_eq(l.entries().map(e => e.0), [KInt(0), KInt(1)])
  assert_eq(l.entries().map(e => e.1), [Str("a"), Str("b")])
  // A Map's entry order must match the `for k, _ in m` the renderer uses, or
  // every keyed vnode in an @each over a map moves.
  let m : Map[String, @core.Value] = Map([])
  m["z"] = Num(1)
  m["a"] = Num(2)
  m["k"] = Num(3)
  let direct : Array[String] = []
  for k, _ in m {
    direct.push(k)
  }
  assert_eq((Map(m) : @core.Value).entries().map(e => e.0.to_label()), direct)
  // a custom collection answers with its own keys
  assert_eq(row("x", tags=[Str("t")]).entries().map(e => e.1), [Str("t")])
  // and anything else iterates as empty (the unkIter default)
  assert_eq((Num(1) : @core.Value).entries().length(), 0)
}

// ---------------------------------------------------------------------------
// Calling
// ---------------------------------------------------------------------------

///|
test "a method call fills the this slot the callee ignores" {
  let r = row("hey")
  // one arg passed, so the callee sees two: the this slot plus it
  assert_eq(r.call_field("shout", [Num(1)]), Str("hey!1"))
  assert_eq(r.call_field("shout", []), Str("hey!0"))
  // a name that is not callable is Null, not a crash
  assert_eq(r.call_field("title", []), Null)
  assert_eq(r.call_field("nope", []), Null)
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

///|
test "an instance names its own fields, with no registry in hand" {
  let r = row("hi", tags=[Str("a")])
  assert_eq(r.field_names(), ["title", "tags"])
  guard! r.field_info("tags") is Some(fi)
  assert_eq(fi.ty, TyList(TyText))
  assert_eq(fi.ty.show_wit(), "list<string>")
  assert_eq(fi.ty.elem(), Some(TyText))
  assert_true(fi.kind() is FList)
  assert_true(r.field_info("nope") is None)
  guard! r.schema() is Some(s)
  assert_eq(s.name, "Row")
  // the snapshot every consumer was faking with an out-of-band name list
  assert_eq(r.snapshot().get("title"), Some(Str("hi")))
  assert_eq(r.snapshot().length(), 2)
  // a Map names its keys; a scalar names nothing
  assert_eq((Map({ "a": Null }) : @core.Value).field_names(), ["a"])
  assert_eq((Num(1) : @core.Value).field_names().length(), 0)
}

///|
test "equality and debug come off the schema, not a hand-written probe loop" {
  assert_eq(row("a", tags=[Str("t")]), row("a", tags=[Str("t")]))
  assert_not_eq(row("a"), row("b"))
  debug_inspect(
    row("a", tags=[Str("t")]),
    content=(
      #|RObj("Row{title: RStr(\"a\"), tags: RList([RStr(\"t\")])}")
    ),
  )
}

// ---------------------------------------------------------------------------
// By path
// ---------------------------------------------------------------------------

///|
test "a path read is the composition of the one-hop reads" {
  let root : @core.Value = Map({
    "rows": List([row("first", tags=[Str("x")]), row("second")]),
  })
  let p = @core.Path::new().index("rows", 0).field("title")
  assert_eq(root.at(p), Str("first"))
  assert_eq(root.at(@core.Path::new().index("rows", 9)), Null)
  // the distinction `at` cannot make
  assert_eq(root.at_opt(@core.Path::new().index("rows", 9)), None)
  assert_true(root.at_opt(p) is Some(_))
  // the label a diagnostic prints
  assert_eq(p.to_label(), "rows[0].title")
}

///|
test "a path write rebuilds the spine and leaves a dead path alone" {
  let root : @core.Value = Map({ "rows": List([row("first")]) })
  let p = @core.Path::new().index("rows", 0).field("title")
  assert_eq(root.with_at(p, Str("changed")).at(p), Str("changed"))
  // ...and the original is untouched (copy-on-write, not mutation)
  assert_eq(root.at(p), Str("first"))
  // a path that does not resolve hands back the SAME root
  let dead = @core.Path::new().field("nope").field("deeper")
  @test.assert_same_object(root.with_at(dead, Str("x")), root)
}

///|
test "the relative and absolute builders spell a step the same way" {
  let p = @core.Path::new().field("a").index("b", 1).key("c", "k")
  assert_eq(p.steps.length(), 3)
  assert_eq(p.to_label(), "a.b[1].c[k]")
  assert_eq(@core.PathKey::KInt(2).to_value(), Num(2))
  assert_eq(@core.PathKey::KStr("t").to_value(), Str("t"))
}

// ---------------------------------------------------------------------------
// The regression this consolidation fixes
// ---------------------------------------------------------------------------

///|
/// A stack whose `.name` reads come from a map, so a parsed `.seq[.key]` can
/// be evaluated against real values.
priv struct DynFieldStack {
  fields : Map[String, @core.Value]
}

///|
impl @core.Stack for DynFieldStack with fn lookup_field_raw(self, name) {
  self.fields.get(name).unwrap_or(Null)
}

///|
/// `.seq[.key]` on a CUSTOM collection.
///
/// The seq-access evaluator used to spell the container match out itself and
/// its copy had lost the `Obj` arm, so an instance that `@each` iterated fine
/// answered Null here. Both go through one lookup now.
test "seq-access resolves through a custom collection, not only List and Map" {
  let stack = DynFieldStack::{
    fields: {
      "rows": row("holder", tags=[Str("zero"), Str("one")]),
      "idx": Num(1),
      "plainList": List([Str("a"), Str("b")]),
      "plainMap": Map({ "k": Str("v") }),
      "name": Str("k"),
    },
  }
  let v : @core.Val = SeqAccess(seq="rows", key="idx")
  assert_eq(v.eval(stack), Str("one"))
  // ...and the two shapes that always worked still do
  let l : @core.Val = SeqAccess(seq="plainList", key="idx")
  assert_eq(l.eval(stack), Str("b"))
  let m : @core.Val = SeqAccess(seq="plainMap", key="name")
  assert_eq(m.eval(stack), Str("v"))
  // a key that is neither an index nor a name resolves to nothing
  let x : @core.Val = SeqAccess(seq="rows", key="missing")
  assert_eq(x.eval(stack), Null)
}
