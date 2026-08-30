// The domain WIRE format, both directions.
//
// A `where` is read from a spec block by two compilers and enforced by three
// runtimes, and the one hop where none of them share a type is the manifest: a
// dynamic component arrives as JSON and a wasm module, and its declared
// domains have to survive that trip or the host has nothing to enforce.
//
// So the claim here is a round trip over the WHOLE vocabulary, one case per
// arm, and the one thing a reader of an unknown document must do with a
// relation it has never heard of.

///|
/// Every arm of the vocabulary, once, with both operand shapes.
fn all_domains() -> Array[@core.FieldDomain] {
  [
    { field: "sel", domain: DIndexOf(field="items", allow_none=false), },
    { field: "cur", domain: DIndexOf(field="items", allow_none=true), },
    { field: "key", domain: DKeyOf(field="entries"), },
    { field: "tag", domain: DMemberOf(field="tags"), },
    { field: "some", domain: DSubsetOf(field="allTags"), },
    { field: "n", domain: DCompare(op=DGe, rhs=DLit(0)), },
    { field: "hi", domain: DCompare(op=DGt, rhs=DField("lo")), },
    { field: "a", domain: DCompare(op=DLe, rhs=DLit(9)), },
    { field: "b", domain: DCompare(op=DLt, rhs=DField("a")), },
    { field: "p", domain: DBetween(lo=DLit(0), hi=DLit(100)), },
    { field: "q", domain: DBetween(lo=DField("lo"), hi=DField("hi")), },
    { field: "level", domain: DOneOf(["debug", "info"]), },
    { field: "choice", domain: DElementOf(field="options"), },
    { field: "items", domain: DNonEmpty, },
    { field: "tags", domain: DLen(DCompare(op=DLe, rhs=DLit(10))), },
    { field: "rows", domain: DLen(DBetween(lo=DLit(1), hi=DLit(9))), },
  ]
}

///|
test "every relation survives the trip through a manifest" {
  let there = @core.domains_to_json(all_domains())
  let back = @core.domains_of_json(there)
  assert_eq(back, all_domains())
  // And again from the TEXT, which is what actually crosses: a manifest is a
  // string in the archive, not a `Json` handed over in memory.
  let reparsed = @core.domains_of_json(
    @json.parse(there.stringify()) catch {
      _ => Json::null()
    },
  )
  assert_eq(reparsed, all_domains())
}

///|
test "a relation the reader has never heard of is dropped, not raised" {
  // The compatibility claim. A guest built against a later vocabulary names a
  // relation this host cannot evaluate; enforcing a guess would refuse writes
  // the guest holds to be legal, and refusing the bundle would make every
  // addition to the vocabulary a breaking change.
  let mixed : Json = Json::array([
    Json::object({
      "field": Json::string("n"),
      "domain": Json::object({
        "rel": Json::string("ge"),
        "rhs": Json::object({ "lit": Json::number(0) }),
      }),
    }),
    Json::object({
      "field": Json::string("email"),
      "domain": Json::object({
        "rel": Json::string("matchesTheRegexWeAddInV12"),
        "pattern": Json::string(".+@.+"),
      }),
    }),
  ])
  let read = @core.domains_of_json(mixed)
  assert_eq(read.length(), 1)
  assert_eq(read[0].field, "n")
}

///|
test "a malformed entry is dropped rather than half-read" {
  // Each of these is missing exactly one thing the relation needs. A domain
  // built from what survived would be a domain nobody wrote.
  let bad : Json = Json::array([
    // no `field`
    Json::object({ "domain": Json::object({ "rel": Json::string("nonempty") }) }),
    // `indexOf` with nothing to be an index OF
    Json::object({
      "field": Json::string("i"),
      "domain": Json::object({ "rel": Json::string("indexOf") }),
    }),
    // a comparison with no right-hand side
    Json::object({
      "field": Json::string("n"),
      "domain": Json::object({ "rel": Json::string("lt") }),
    }),
    // `len` wrapping nothing
    Json::object({
      "field": Json::string("xs"),
      "domain": Json::object({ "rel": Json::string("len") }),
    }),
    // an operand that is neither a literal nor a field
    Json::object({
      "field": Json::string("n"),
      "domain": Json::object({
        "rel": Json::string("ge"),
        "rhs": Json::object({ "whatever": Json::string("x") }),
      }),
    }),
  ])
  assert_eq(@core.domains_of_json(bad), [])
  // Not an array at all — a manifest key holding the wrong shape.
  assert_eq(@core.domains_of_json(Json::string("nope")), [])
}

///|
test "the whole-state question answers the first break, in source order" {
  let all : Array[@core.FieldDomain] = [
    { field: "n", domain: DCompare(op=DGe, rhs=DLit(0)), },
    { field: "level", domain: DOneOf(["debug", "info"]), },
  ]
  let fields : Map[String, @core.Value] = {
    "n": Num(-1),
    "level": Str("shout"),
  }
  guard @core.first_broken_domain(all, fields) is Some(d) else {
    fail("both are broken, so one of them is the answer")
  }
  // Source order, because a reader fixes them one at a time and the first
  // clause they wrote is the first thing to look at.
  assert_eq(d.field, "n")
  assert_eq(
    @core.broken_domain_sentence(d, fields),
    "`n` is -1, and it must be >= 0",
  )
  // Nothing broken is None rather than an empty list: there is one answer.
  assert_true(
    @core.first_broken_domain(all, { "n": Num(0), "level": Str("info") })
    is None,
  )
}
