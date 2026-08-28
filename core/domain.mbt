// A declared field DOMAIN, as data the runtime can check a value against.
//
// The `where` clauses of a spec block, projected into the value world the same
// way `TyInfo` projects a declared type. It lives here rather than beside the
// generator for the reason every type in `schema_spec.mbt` does: a holder of a
// bare `Value` has to be able to ask, and the dynamic-component host has no
// `@statedef` to consult.
//
// The one thing that makes this different from every other check the runtime
// does: a relation reads OTHER FIELDS. `.currentIndex` is only wrong relative
// to `.items`, so every entry point here takes the whole field map rather than
// the one value — which is why the check lives at `TypedInstance::set`, the
// one write path that has the map in hand, and not in `FieldSpec`, which sees
// a value alone.

///|
/// How a `where` compares. The runtime twin of `@statedef.CmpOp`.
pub(all) enum DomainOp {
  DGe
  DGt
  DLe
  DLt
} derive(Eq, Debug)

///|
/// A comparison's right-hand side: a literal, or another field of this state.
pub(all) enum DomainOperand {
  DLit(Double)
  DField(String)
} derive(Eq, Debug)

///|
/// What a field's declared domain is.
///
/// The vocabulary is CLOSED, and the reason is what the whole feature is for:
/// every arm can be read backwards as well as forwards. Forwards it rejects a
/// value; backwards it produces one, which is what lets a generator draw
/// states a component could actually reach instead of filtering for them.
/// A relation that can only be read forwards is a `pred` — that is the line,
/// and it is drawn at the declaration rather than here.
pub(all) enum Domain {
  /// `0 <= v < len(field)`. `allow_none` additionally admits the type's
  /// empty answer — `Null`, or the zero a selection field parks at.
  DIndexOf(field~ : String, allow_none~ : Bool)
  DKeyOf(field~ : String)
  DMemberOf(field~ : String)
  DCompare(op~ : DomainOp, rhs~ : DomainOperand)
  /// Inclusive at both ends.
  DBetween(lo~ : DomainOperand, hi~ : DomainOperand)
  DOneOf(Array[String])
  /// The inner domain applies to the value's LENGTH.
  DLen(Domain)
  DNonEmpty
  DSubsetOf(field~ : String)
} derive(Eq, Debug)

///|
/// One field's domain, as the schema carries it.
///
/// A flat list of pairs and not a map, because several clauses may name one
/// field and they CONJOIN: `where n >= 0` beside `where n <= 100` is one field
/// with two entries, and a map would have made the second silently replace the
/// first.
pub(all) struct FieldDomain {
  field : String
  domain : Domain
} derive(Eq, Debug)

///|
/// Whether `v` is in `domain`, read against the state it would live in.
///
/// UNKNOWN IS NOT WRONG — the same rule an invariant follows. A relation whose
/// target field is absent, or holds something the relation cannot read, answers
/// `true`: a domain that could not be evaluated has not rejected anything. The
/// alternative would turn a schema this package cannot fully see — a dynamic
/// component, a partially decoded state — into a component that refuses every
/// write.
pub fn domain_holds(
  domain : Domain,
  v : Value,
  fields : Map[String, Value],
) -> Bool {
  match domain {
    DIndexOf(field~, allow_none~) => {
      // Not a number: unknown, and unknown is not wrong. `Null` in particular
      // is a legal value of an `Int?`, so a field that means to forbid it says
      // so by not being nullable rather than by a relation about indices.
      guard v is Num(n) else { return true }
      if n != n.trunc() {
        return false
      }
      let i = n.to_int()
      guard fields.get(field) is Some(seq) && size_of(seq) is Some(len) else {
        return true
      }
      // The sentinel first: an empty list has no valid index at all, so a
      // selection field over one can ONLY hold the empty answer.
      if allow_none && (i == -1 || (i == 0 && len == 0)) {
        return true
      }
      i >= 0 && i < len
    }
    DKeyOf(field~) => {
      guard v is Str(k) else { return true }
      guard fields.get(field) is Some(Map(m)) else { return true }
      m.contains(k)
    }
    // A set is Map-backed: a member is a key whose value is true. An absent
    // key and a key holding false are the same non-membership, which is what
    // `toggleIn` produces on the way out.
    DMemberOf(field~) => {
      guard v is Str(k) else { return true }
      guard fields.get(field) is Some(Map(m)) else { return true }
      m.get(k) is Some(Bool(true))
    }
    DSubsetOf(field~) => {
      guard v is Map(mine) else { return true }
      guard fields.get(field) is Some(Map(theirs)) else { return true }
      for k, held in mine {
        if held is Bool(true) && !(theirs.get(k) is Some(Bool(true))) {
          return false
        }
      }
      true
    }
    DOneOf(members) => {
      guard v is Str(s) else { return true }
      members.contains(s)
    }
    DNonEmpty =>
      match size_of(v) {
        Some(n) => n > 0
        None => true
      }
    DLen(inner) =>
      match size_of(v) {
        Some(n) => domain_holds(inner, Num(n.to_double()), fields)
        None => true
      }
    DCompare(op~, rhs~) => {
      guard v is Num(n) else { return true }
      guard operand_value(rhs, fields) is Some(r) else { return true }
      match op {
        DGe => n >= r
        DGt => n > r
        DLe => n <= r
        DLt => n < r
      }
    }
    DBetween(lo~, hi~) => {
      guard v is Num(n) else { return true }
      guard operand_value(lo, fields) is Some(a) &&
        operand_value(hi, fields) is Some(b) else {
        return true
      }
      n >= a && n <= b
    }
  }
}

///|
/// A comparison operand as a number, or None when nothing can be read.
fn operand_value(o : DomainOperand, fields : Map[String, Value]) -> Double? {
  match o {
    DLit(n) => Some(n)
    DField(f) =>
      match fields.get(f) {
        Some(Num(n)) => Some(n)
        _ => None
      }
  }
}

///|
/// The domains a write to `field` has to satisfy, conjoined.
pub fn domains_of(all : Array[FieldDomain], field : String) -> Array[Domain] {
  let out : Array[Domain] = []
  for d in all {
    if d.field == field {
      out.push(d.domain)
    }
  }
  out
}

///|
/// The first domain of `field` that `v` breaks, or None.
///
/// The FIRST rather than all of them, because a rejection needs one reason to
/// report and a reader fixes them one at a time.
pub fn broken_domain(
  all : Array[FieldDomain],
  field : String,
  v : Value,
  fields : Map[String, Value],
) -> Domain? {
  for d in all {
    if d.field == field && !domain_holds(d.domain, v, fields) {
      return Some(d.domain)
    }
  }
  None
}

///|
/// The first domain the WHOLE state breaks, with the field it is about.
///
/// One function and not three, because there are three places that ask it and
/// they have to get the same answer: the runtime's post-transition door, the
/// guard `gen-views` weaves into a generated arm, and the dynamic-component
/// host holding a guest's successor. A domain the woven guard admitted and the
/// runtime then refused would be a component that abandons a transition its own
/// compiled code said was fine — which is exactly the class of bug a second
/// reading of one declaration produces.
///
/// Source order, not sorted: this answers WHICH ONE to report, and a reader
/// fixes them one at a time. `broken_domains` is the other question — every
/// field at once — and sorts for its own reasons.
pub fn first_broken_domain(
  all : Array[FieldDomain],
  fields : Map[String, Value],
) -> FieldDomain? {
  for d in all {
    if !domain_holds(d.domain, fields.get(d.field).unwrap_or(Null), fields) {
      return Some(d)
    }
  }
  None
}

///|
/// What `first_broken_domain` found, as the sentence to say about it.
///
/// A convenience over `domain_sentence` and worth its line: every caller of the
/// first has the pair in hand and has to dig the value back out of the map to
/// call the second, and three callers digging it out three times is three
/// chances to dig out the wrong one.
pub fn broken_domain_sentence(
  d : FieldDomain,
  fields : Map[String, Value],
) -> String {
  domain_sentence(
    d.domain,
    d.field,
    fields.get(d.field).unwrap_or(Null),
    fields,
  )
}

///|
/// Every field whose CURRENT value is outside its declared domain.
///
/// The whole-state question, asked after a transition so a hand-written
/// handler that assigns a field directly is held to the same declaration a
/// generated setter is. Sorted, for the reason `SchemaInfo.invariants` is:
/// which domain broke is part of the answer, and a report that depended on
/// declaration order would move when an unrelated clause was added above it.
pub fn broken_domains(
  all : Array[FieldDomain],
  fields : Map[String, Value],
) -> Array[String] {
  let out : Array[String] = []
  for d in all {
    let v = fields.get(d.field).unwrap_or(Null)
    if !domain_holds(d.domain, v, fields) && !out.contains(d.field) {
      out.push(d.field)
    }
  }
  out.sort()
  out
}

///|
/// What a broken domain says, with the values that broke it.
///
/// Composed rather than authored, and that is why a `where` carries no
/// `format`. A rule needs a hand-written sentence because an arbitrary boolean
/// cannot say why it failed; a relation knows exactly what it wanted and what
/// it got, so a sentence written by hand could only be less specific than this
/// one.
pub fn domain_sentence(
  domain : Domain,
  field : String,
  v : Value,
  fields : Map[String, Value],
) -> String {
  let got = v.to_display_string()
  let len_of = (name : String) => {
    match fields.get(name) {
      Some(x) =>
        match size_of(x) {
          Some(n) => n.to_string()
          None => "?"
        }
      None => "?"
    }
  }
  match domain {
    DIndexOf(field=seq, ..) =>
      "`\{field}` is \{got}, which is not an index of `\{seq}` (\{len_of(seq)} items)"
    DKeyOf(field=map) => "`\{field}` is \{got}, which is not a key of `\{map}`"
    DMemberOf(field=set) =>
      "`\{field}` is \{got}, which is not a member of `\{set}`"
    DSubsetOf(field=set) => "`\{field}` holds a member `\{set}` does not"
    DOneOf(members) =>
      "`\{field}` is \{got}, and it is one of \{members.map(m => "`" + m + "`").join(", ")}"
    DNonEmpty => "`\{field}` is empty"
    DLen(inner) =>
      "the length of `\{field}` is \{len_of(field)}, and " +
      bound_words(inner, fields)
    other => "`\{field}` is \{got}, and " + bound_words(other, fields)
  }
}

///|
/// The bound half of a sentence: "it must be >= 0".
fn bound_words(domain : Domain, fields : Map[String, Value]) -> String {
  let show = (o : DomainOperand) => {
    match o {
      DLit(n) => trim_num(n)
      DField(f) =>
        match operand_value(DField(f), fields) {
          Some(n) => "`\{f}` (\{trim_num(n)})"
          None => "`\{f}`"
        }
    }
  }
  match domain {
    DCompare(op~, rhs~) => {
      let word = match op {
        DGe => ">="
        DGt => ">"
        DLe => "<="
        DLt => "<"
      }
      "it must be \{word} \{show(rhs)}"
    }
    DBetween(lo~, hi~) => "it must be between \{show(lo)} and \{show(hi)}"
    _ => "it is outside its declared domain"
  }
}

///|
/// `3` rather than `3.0` for a whole number, since every bound an author
/// writes is one.
fn trim_num(n : Double) -> String {
  if n == n.trunc() && n.abs() < 1.0e15 {
    n.to_int64().to_string()
  } else {
    n.to_string()
  }
}

// The WIRE form.
//
// A `where` is declared in a spec block, which the MoonBit generator reads at
// build time and the card compiler reads in a browser — and then it has to
// reach a HOST that has neither. A dynamic component arrives as a manifest and
// a wasm module: the host never sees the block, so a domain that stayed in
// `@statedef` would be a declaration the guest kept to itself.
//
// One codec, in `core`, because both ends are here: the card compiler writes
// this and the dynamic-component host reads it, and a format written twice is
// a format that disagrees with itself the first time either end grows a case.

///|
/// Every domain as JSON, for a manifest.
pub fn domains_to_json(all : Array[FieldDomain]) -> Json {
  Json::array(
    all.map(d => {
      Json::object({
        "field": Json::string(d.field),
        "domain": domain_to_json(d.domain),
      })
    }),
  )
}

///|
fn domain_to_json(d : Domain) -> Json {
  let of = (rel : String, field : String) => {
    Json::object({ "rel": Json::string(rel), "of": Json::string(field) })
  }
  match d {
    DIndexOf(field~, allow_none~) =>
      Json::object({
        "rel": Json::string("indexOf"),
        "of": Json::string(field),
        "orNone": Json::boolean(allow_none),
      })
    DKeyOf(field~) => of("keyOf", field)
    DMemberOf(field~) => of("memberOf", field)
    DSubsetOf(field~) => of("subsetOf", field)
    DNonEmpty => Json::object({ "rel": Json::string("nonempty") })
    DLen(inner) =>
      Json::object({
        "rel": Json::string("len"),
        "inner": domain_to_json(inner),
      })
    DOneOf(members) =>
      Json::object({
        "rel": Json::string("oneOf"),
        "members": Json::array(members.map(m => Json::string(m))),
      })
    DCompare(op~, rhs~) =>
      Json::object({
        "rel": Json::string(
          match op {
            DGe => "ge"
            DGt => "gt"
            DLe => "le"
            DLt => "lt"
          },
        ),
        "rhs": operand_to_json(rhs),
      })
    DBetween(lo~, hi~) =>
      Json::object({
        "rel": Json::string("between"),
        "lo": operand_to_json(lo),
        "hi": operand_to_json(hi),
      })
  }
}

///|
fn operand_to_json(o : DomainOperand) -> Json {
  match o {
    DLit(n) => Json::object({ "lit": Json::number(n) })
    DField(f) => Json::object({ "field": Json::string(f) })
  }
}

///|
/// The domains a manifest declares.
///
/// UNKNOWN IS NOT WRONG, the same rule the evaluator follows and for a sharper
/// reason here: this reads a document a GUEST wrote, and a guest built against
/// a later version of this vocabulary will name relations this host has never
/// heard of. An entry that cannot be read is DROPPED rather than raised — a
/// host that refused to load a bundle over a clause it could not enforce would
/// turn every addition to the vocabulary into a compatibility break, and one
/// that enforced a guess would refuse writes the guest holds to be legal.
pub fn domains_of_json(j : Json) -> Array[FieldDomain] {
  let out : Array[FieldDomain] = []
  guard j is Array(items) else { return out }
  for item in items {
    guard item is Object(m) else { continue }
    guard m.get("field") is Some(String(field)) else { continue }
    guard m.get("domain") is Some(d) else { continue }
    match domain_of_json(d) {
      Some(domain) => out.push({ field, domain, })
      None => ()
    }
  }
  out
}

///|
fn domain_of_json(j : Json) -> Domain? {
  guard j is Object(m) else { return None }
  guard m.get("rel") is Some(String(rel)) else { return None }
  let field_of = () => {
    match m.get("of") {
      Some(String(s)) => Some(s)
      _ => None
    }
  }
  match rel {
    "indexOf" => {
      guard field_of() is Some(field) else { return None }
      Some(DIndexOf(field~, allow_none=m.get("orNone") is Some(True)))
    }
    "keyOf" =>
      match field_of() {
        Some(field) => Some(DKeyOf(field~))
        None => None
      }
    "memberOf" =>
      match field_of() {
        Some(field) => Some(DMemberOf(field~))
        None => None
      }
    "subsetOf" =>
      match field_of() {
        Some(field) => Some(DSubsetOf(field~))
        None => None
      }
    "nonempty" => Some(DNonEmpty)
    "len" =>
      match m.get("inner") {
        Some(inner) =>
          match domain_of_json(inner) {
            Some(d) => Some(DLen(d))
            None => None
          }
        None => None
      }
    "oneOf" => {
      guard m.get("members") is Some(Array(ms)) else { return None }
      let members : Array[String] = []
      for x in ms {
        guard x is String(s) else { continue }
        members.push(s)
      }
      Some(DOneOf(members))
    }
    "between" => {
      guard m.get("lo") is Some(lo) && m.get("hi") is Some(hi) else {
        return None
      }
      guard operand_of_json(lo) is Some(lo) && operand_of_json(hi) is Some(hi) else {
        return None
      }
      Some(DBetween(lo~, hi~))
    }
    "ge" | "gt" | "le" | "lt" => {
      guard m.get("rhs") is Some(r) && operand_of_json(r) is Some(rhs) else {
        return None
      }
      let op = match rel {
        "ge" => DGe
        "gt" => DGt
        "le" => DLe
        _ => DLt
      }
      Some(DCompare(op~, rhs~))
    }
    // A relation this host has never heard of. Dropped, not raised.
    _ => None
  }
}

///|
fn operand_of_json(j : Json) -> DomainOperand? {
  guard j is Object(m) else { return None }
  match (m.get("lit"), m.get("field")) {
    (Some(Number(n, ..)), _) => Some(DLit(n))
    (_, Some(String(f))) => Some(DField(f))
    _ => None
  }
}
