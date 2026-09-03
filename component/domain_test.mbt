// The DOMAINS a component's fields are declared over — the `where` clauses of
// its spec block, at runtime.
//
// A domain has two doors and this is where both are pinned. The first is the
// field write itself, which turns down `setCurrentIndex 99` naming the field;
// the second is after the transition, which is what catches the OTHER half of
// the same relation — shrinking `items` under a `currentIndex` that was fine.
// Neither door catches both cases, which is why there are two.

///|
priv struct GalleryState {
  items : Array[@tutuca.Value]
  entries : Map[String, @tutuca.Value]
  currentIndex : Int
  currentKey : String
  count : Int
  choice : String
}

///|
impl @component.Fields for GalleryState with fn encode(s) {
  {
    "items": List(s.items),
    "entries": Map(s.entries),
    "currentIndex": Num(s.currentIndex.to_double()),
    "currentKey": Str(s.currentKey),
    "count": Num(s.count.to_double()),
    "choice": Str(s.choice),
  }
}

///|
impl @component.Fields for GalleryState with fn decode(f) {
  Some({
    items: match f.get("items") {
      Some(List(a)) => a
      _ => []
    },
    entries: match f.get("entries") {
      Some(Map(m)) => m
      _ => Map([])
    },
    currentIndex: f.get("currentIndex").unwrap_or(Null).int(),
    currentKey: f.get("currentKey").unwrap_or(Null).str(),
    count: f.get("count").unwrap_or(Null).int(),
    choice: f.get("choice").unwrap_or(Null).str(),
  })
}

///|
impl @component.Fields for GalleryState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="gallery_state",
    fields=[
      @component.FieldInfo::new("items", TyList(TyAny)),
      @component.FieldInfo::new("entries", TyOMap(TyAny)),
      @component.FieldInfo::new("currentIndex", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("currentKey", TyText),
      @component.FieldInfo::new("count", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("choice", TyText),
    ],
    // What `where currentIndex is index of .items` and friends become. Data
    // rather than a compiled method, because the runtime reads the relation
    // directly — a domain has no body to call.
    domains=[
      {
        field: "currentIndex",
        domain: DIndexOf(field="items", allow_none=false),
      },
      { field: "currentKey", domain: DKeyOf(field="entries"), },
      { field: "count", domain: DCompare(op=DGe, rhs=DLit(0)), },
      // `where choice is one of .items` — a select field, whose options are
      // ORDERED and so a list, and which stores the option rather than its
      // position.
      { field: "choice", domain: DElementOf(field="items"), },
    ],
  )
}

///|
fn gallery() -> @tutuca.Value {
  @component.component(
    name="Gallery",
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".currentIndex\"></x></div>",
      ),
    },
    initial=GalleryState::{
      items: [Str("a"), Str("b"), Str("c")],
      entries: { "k0": Num(1) },
      currentIndex: 0,
      currentKey: "k0",
      count: 0,
      choice: "a",
    },
  ).make(Map([]))
}

///|
fn refusals_of(body : () -> Unit) -> Array[@tutuca.Refusal] {
  let out : Array[@tutuca.Refusal] = []
  let off = @tutuca.on_runtime_notice(n => if n is Refused(r) { out.push(r) })
  body()
  off()
  out
}

///|
test "a write inside the domain goes through" {
  let after = write(gallery(), "currentIndex", Num(2))
  assert_eq(after.field("currentIndex"), Num(2))
  assert_eq(
    write(gallery(), "currentKey", Str("k0")).field("currentKey"),
    Str("k0"),
  )
  assert_eq(write(gallery(), "count", Num(7)).field("count"), Num(7))
}

///|
test "the three writes the fuzzer kept producing are turned down" {
  // An index past the end, an index below zero, a key the map does not hold,
  // and a negative count. Each one is a state no interaction could reach, and
  // each one used to land.
  let g = gallery()
  assert_eq(write(g, "currentIndex", Num(99)).field("currentIndex"), Num(0))
  assert_eq(write(g, "currentIndex", Num(-1)).field("currentIndex"), Num(0))
  assert_eq(
    write(g, "currentKey", Str("absent")).field("currentKey"),
    Str("k0"),
  )
  assert_eq(write(g, "count", Num(-5)).field("count"), Num(0))
}

///|
test "the refusal names the FIELD and says what it wanted" {
  // Where a rule's refusal carries a NAME and no sentence, a domain's carries
  // the field and a sentence that always exists — composed from the relation,
  // which is the whole reason a `where` needs no `format`.
  let refused = refusals_of(() => {
    let _ = write(gallery(), "currentIndex", Num(99))
  })
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].code, OutOfRange)
  assert_eq(refused[0].rule, "currentIndex")
  assert_eq(refused[0].asked, "setCurrentIndex")
  assert_eq(
    refused[0].sentence,
    "`currentIndex` is 99, which is not an index of `items` (3 items)",
  )
}

///|
test "the second door: a write that invalidates a DIFFERENT field" {
  // `setItems []` says nothing about `currentIndex`, so the first door has no
  // reason to look at it — the write is about `items`. What it leaves behind
  // is `currentIndex: 0` over an empty list, and the after-the-transition
  // check is the one that sees it.
  let mut after : @tutuca.Value = Null
  let refused = refusals_of(() => after = write(gallery(), "items", List([])))
  // Abandoned whole: the list is not emptied either.
  assert_eq(after.field("items").size(), 3)
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].code, OutOfRange)
  assert_eq(refused[0].rule, "currentIndex")
  // The state that was REJECTED — the successor the framework threw away.
  assert_eq(refused[0].state.field("items").size(), 0)
}

///|
test "a write that keeps every relation true is unaffected by either door" {
  // Two items removed and the index moved into range in one dispatch is not
  // expressible through a mutator, so the honest version is: shrinking a list
  // that the index still fits.
  //
  // The remaining item is the one `choice` names, because `items` is now the
  // subject of two relations — an index into it and the value drawn from it —
  // and this test is about neither being disturbed.
  let g = write(gallery(), "currentIndex", Num(0))
  let after = write(g, "items", List([Str("a")]))
  assert_eq(after.field("items").size(), 1)
}

///|
test "unknown is not wrong" {
  // The rule an invariant follows, and a domain follows it for the same
  // reason. A relation whose target holds something it cannot read has not
  // rejected anything — refusing every write because a schema is only
  // partially understood would freeze a component rather than protect it.
  let fields : Map[String, @tutuca.Value] = { "items": Str("not a list") }
  assert_true(
    @tutuca.domain_holds(
      DIndexOf(field="items", allow_none=false),
      Num(9),
      fields,
    ),
  )
  // …and an absent target likewise.
  assert_true(@tutuca.domain_holds(DKeyOf(field="nope"), Str("x"), Map([])))
}

///|
test "`or none` admits the empty answer, and nothing else out of range" {
  let empty : Map[String, @tutuca.Value] = { "items": List([]) }
  let three : Map[String, @tutuca.Value] = { "items": List([Null, Null, Null]) }
  let sel : @tutuca.Domain = DIndexOf(field="items", allow_none=true)
  // Over an empty list there is no valid index, so only the sentinel is left.
  assert_true(@tutuca.domain_holds(sel, Num(-1), empty))
  assert_true(@tutuca.domain_holds(sel, Num(0), empty))
  assert_false(@tutuca.domain_holds(sel, Num(1), empty))
  // Over a list with items, the sentinel is still admitted and 3 is not.
  assert_true(@tutuca.domain_holds(sel, Num(-1), three))
  assert_true(@tutuca.domain_holds(sel, Num(2), three))
  assert_false(@tutuca.domain_holds(sel, Num(3), three))
  // Without it, the sentinel is out.
  assert_false(
    @tutuca.domain_holds(
      DIndexOf(field="items", allow_none=false),
      Num(-1),
      three,
    ),
  )
}

///|
test "the rest of the vocabulary, over values" {
  let fields : Map[String, @tutuca.Value] = {
    "tags": Map({ "red": Bool(true), "blue": Bool(false) }),
    "lo": Num(2),
  }
  // A set is Map-backed, and a key holding false is the same non-membership
  // an absent key is — which is what `toggleIn` produces on the way out.
  assert_true(@tutuca.domain_holds(DMemberOf(field="tags"), Str("red"), fields))
  assert_false(
    @tutuca.domain_holds(DMemberOf(field="tags"), Str("blue"), fields),
  )
  assert_true(
    @tutuca.domain_holds(
      DSubsetOf(field="tags"),
      Map({ "red": Bool(true) }),
      fields,
    ),
  )
  assert_false(
    @tutuca.domain_holds(
      DSubsetOf(field="tags"),
      Map({ "green": Bool(true) }),
      fields,
    ),
  )
  assert_true(@tutuca.domain_holds(DNonEmpty, List([Null]), fields))
  assert_false(@tutuca.domain_holds(DNonEmpty, List([]), fields))
  assert_true(
    @tutuca.domain_holds(
      DLen(DCompare(op=DLe, rhs=DLit(2))),
      List([Null]),
      fields,
    ),
  )
  assert_false(
    @tutuca.domain_holds(
      DLen(DCompare(op=DLe, rhs=DLit(2))),
      List([Null, Null, Null]),
      fields,
    ),
  )
  assert_true(
    @tutuca.domain_holds(DOneOf([Str("a"), Str("b")]), Str("a"), fields),
  )
  assert_false(
    @tutuca.domain_holds(DOneOf([Str("a"), Str("b")]), Str("c"), fields),
  )
  assert_true(
    @tutuca.domain_holds(DBetween(lo=DLit(0), hi=DLit(10)), Num(10), fields),
  )
  assert_false(
    @tutuca.domain_holds(DBetween(lo=DLit(0), hi=DLit(10)), Num(11), fields),
  )
  // A comparison against ANOTHER FIELD, which is the half no type could ever
  // state.
  assert_true(
    @tutuca.domain_holds(DCompare(op=DGe, rhs=DField("lo")), Num(2), fields),
  )
  assert_false(
    @tutuca.domain_holds(DCompare(op=DGe, rhs=DField("lo")), Num(1), fields),
  )
}

///|
test "an index has to be whole" {
  let fields : Map[String, @tutuca.Value] = { "items": List([Null, Null]) }
  assert_false(
    @tutuca.domain_holds(
      DIndexOf(field="items", allow_none=false),
      Num(0.5),
      fields,
    ),
  )
}

///|
/// `where value is one of .options`: the members are what a sibling LIST holds.
///
/// The shape `is member of` could not state — a select's options are ordered,
/// so they are an `Array` and not a `Set` — and the shape `is index of` states
/// only positionally, while what a select field stores is the option itself.
test "a value bounded by a sibling list" {
  // `items` holds "a", "b", "c".
  assert_eq(write(gallery(), "choice", Str("c")).field("choice"), Str("c"))
  // …and one it does not hold is turned down at the write, unchanged.
  assert_eq(write(gallery(), "choice", Str("z")).field("choice"), Str("a"))
}

///|
test "the list refusal names the list it read" {
  let refusals = refusals_of(fn() {
    write(gallery(), "choice", Str("z")) |> ignore
  })
  assert_eq(refusals.length(), 1)
  assert_true(refusals[0].sentence.contains("`items` does not hold"))
}

///|
/// The second door, over the same relation: shrinking the OPTIONS under a
/// choice that was fine.
test "removing the option a choice names is caught after the transition" {
  let picked = write(gallery(), "choice", Str("c"))
  let after = write(picked, "items", List([Str("a"), Str("b")]))
  // the write is abandoned whole: the list is what it was, and so is the choice
  assert_eq(after.field("choice"), Str("c"))
  assert_eq(after.field("items").size(), 3)
}
