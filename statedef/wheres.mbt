// The `where` layer's second pass: resolve, type-check and order.
//
// Parsing a clause only records what was written. Three things have to be
// true before a `where` means anything, and none of them is knowable while
// the clause is being read — a `where` may precede the field it is about:
//
//   1. every name it mentions is a field of THIS state
//   2. the relation can mean something for the types involved
//   3. the clauses, taken together, have no cycle
//
// The third is not a tidiness rule. A constrained field is drawn AFTER the
// fields its domain names, and a cycle has no such order — so refusing one
// here is what lets `@arb`'s topological walk be total rather than partial.

///|
/// Resolve and check every `where` clause of one state.
///
/// Returns the clauses with any enum spelling expanded to its members. The
/// order is source order, untouched: the dependency order is a property of
/// the whole set and is computed where it is used, not baked in here.
fn resolve_wheres(
  raw : Array[WhereDecl],
  fields : Array[FieldDef],
  types : Array[UserTy],
  state_span : Span,
) -> Array[WhereDecl] raise DefError {
  guard !raw.is_empty() else { return [] }
  let names = fields.map(f => f.name)
  let ty_of : Map[String, StateTy] = Map([])
  for f in fields {
    ty_of[f.name] = f.ty
  }
  let out : Array[WhereDecl] = []
  for w in raw {
    guard ty_of.get(w.subject) is Some(subject_ty) else {
      raise UnknownWhereSubject(
        name=w.subject,
        hint=did_you_mean(w.subject, names),
        span=w.subject_span,
      )
    }
    // Every `.field` the relation names, before anything asks what it holds.
    for pair in w.ref_spans {
      if !ty_of.contains(pair.0) {
        raise UnknownWhereTarget(
          name=pair.0,
          hint=did_you_mean(pair.0, names),
          span=pair.1,
        )
      }
    }
    out.push({
      ..w,
      relation: check_relation(w, subject_ty, ty_of, types, w.subject),
    })
  }
  check_where_cycles(out, state_span)
  out
}

///|
/// `, did you mean `count`?` — or nothing.
///
/// A sentence fragment rather than a `String?`, because every caller splices
/// it onto the end of a message and an `Option` would make each of them say
/// so.
fn did_you_mean(name : String, names : Array[String]) -> String {
  match nearest(name, names) {
    Some(n) => ", did you mean `\{n}`?"
    None => ""
  }
}

///|
/// Whether a relation can mean anything for the types it was written over,
/// and — for `one of` — what its members actually are.
///
/// The check is deliberately shallow. It refuses what CANNOT work rather than
/// insisting on what usually does: `TAny` passes everywhere, because a field
/// declared `Any` is one whose shape is decided at runtime and a static no
/// would be a false one.
fn check_relation(
  w : WhereDecl,
  subject_ty : StateTy,
  ty_of : Map[String, StateTy],
  types : Array[UserTy],
  subject : String,
) -> Relation raise DefError {
  let bad = (why : String) => WhereTypeMismatch(subject~, why~, span=w.span)
  match w.relation {
    RIndexOf(field~, allow_none~) => {
      if !is_index_like(subject_ty) {
        raise bad(
          "an index is a whole number, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      let target = ty_of.get(field).unwrap()
      if !is_ordered_seq(target) {
        raise bad(
          "`index of` needs something with positions, and `.\{field}` is \{show_ty(target)}. A map is keyed rather than positioned — say `key of` instead",
        )
      }
      RIndexOf(field~, allow_none~)
    }
    RKeyOf(field~) => {
      if !is_text_like(subject_ty) {
        raise bad(
          "a map key is text, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      guard ty_of.get(field) is Some(TOMap(_) | TAny) else {
        raise bad(
          "`key of` needs a map, and `.\{field}` is \{show_ty(ty_of.get(field).unwrap())}",
        )
      }
      RKeyOf(field~)
    }
    RMemberOf(field~) => {
      if !is_text_like(subject_ty) {
        raise bad(
          "a set member is text, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      guard ty_of.get(field) is Some(TSet | TFlags(_) | TAny) else {
        raise bad(
          "`member of` needs a set, and `.\{field}` is \{show_ty(ty_of.get(field).unwrap())}",
        )
      }
      RMemberOf(field~)
    }
    RSubsetOf(field~) => {
      guard subject_ty is (TSet | TFlags(_) | TAny) else {
        raise bad(
          "a subset is a set, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      guard ty_of.get(field) is Some(TSet | TFlags(_) | TAny) else {
        raise bad(
          "`subset of` needs a set, and `.\{field}` is \{show_ty(ty_of.get(field).unwrap())}",
        )
      }
      RSubsetOf(field~)
    }
    RNonEmpty => {
      if !is_sized(subject_ty) {
        raise bad(
          "`nonempty` is about a length, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      RNonEmpty
    }
    // The length is a number whatever the collection is, so the inner
    // relation is checked against a number rather than against the subject.
    RLen(inner) => {
      if !is_sized(subject_ty) {
        raise bad(
          "`len` is about a length, and `\{subject}` is \{show_ty(subject_ty)}",
        )
      }
      RLen(check_numeric(w, inner, ty_of, subject, "a length"))
    }
    // A closed set of literals. Its own arm and not part of the ordering
    // check below, because `one of` is the one relation that is about
    // MEMBERSHIP rather than about magnitude — it is what a text field
    // reaches for, and routing it through a numeric gate would refuse
    // exactly the case it exists for.
    ROneOf(_) => {
      // The members are written quoted, so they are text and so must the
      // field be. A closed set of NUMBERS is `between`, which already exists
      // and which a generator can draw from without listing every value.
      if !is_text_like(subject_ty) {
        raise bad(
          "the members of a `one of` are written quoted, and `\{subject}` is \{show_ty(subject_ty)}. For a closed range of numbers, write `between a and b`",
        )
      }
      resolve_one_of(w, w.relation, types, subject)
    }
    other => {
      if !is_numeric(subject_ty) {
        raise bad(
          "an ordering compares numbers, and `\{subject}` is \{show_ty(subject_ty)}. For a closed set of values, write `is one of […]`",
        )
      }
      check_numeric(w, other, ty_of, subject, "`\{subject}`")
    }
  }
}

///|
/// A comparison's operands, when the left-hand side is known to be a number.
fn check_numeric(
  w : WhereDecl,
  rel : Relation,
  ty_of : Map[String, StateTy],
  subject : String,
  what : String,
) -> Relation raise DefError {
  let check = (o : Operand) => {
    match o {
      OLit(_) => ()
      OField(f) =>
        if !is_numeric(ty_of.get(f).unwrap_or(TAny)) {
          raise WhereTypeMismatch(
            subject~,
            why="\{what} is compared against `.\{f}`, which is \{show_ty(ty_of.get(f).unwrap())} rather than a number",
            span=w.span,
          )
        }
    }
  }
  match rel {
    RCompare(rhs~, ..) => check(rhs)
    RBetween(lo~, hi~) => {
      check(lo)
      check(hi)
      // Written the wrong way round: the clause admits nothing, which is
      // never what an author meant and is silent at every later stage.
      if lo is OLit(a) && hi is OLit(b) && a > b {
        raise WhereTypeMismatch(
          subject~,
          why="`between \{a} and \{b}` admits nothing; the low bound comes first",
          span=w.span,
        )
      }
    }
    _ => ()
  }
  rel
}

///|
/// `is one of Priority` becomes `is one of ["low", "high"]`.
///
/// The parser could not do this: an enum is a declaration, and a `where` may
/// be written above the `enum` it names. By the time this runs the state's
/// user types are resolved, so the members are simply there to be read.
fn resolve_one_of(
  w : WhereDecl,
  rel : Relation,
  types : Array[UserTy],
  subject : String,
) -> Relation raise DefError {
  guard rel is ROneOf(members) else { return rel }
  guard members is [one, ..] && one.has_prefix(ENUM_MEMBERS_OF) else {
    return rel
  }
  let name = one[ENUM_MEMBERS_OF.length():].to_owned()
  for t in types {
    if t.source_name != name {
      continue
    }
    guard t.kind is UEnum(cases) else {
      raise WhereTypeMismatch(
        subject~,
        why="`one of \{name}` needs an enum whose cases carry no payload",
        span=w.span,
      )
    }
    return ROneOf(cases.map(c => c.1))
  }
  raise WhereTypeMismatch(
    subject~,
    why="`one of \{name}` names no enum this block declares\{did_you_mean(name, types.map(t => t.source_name))}",
    span=w.span,
  )
}

///|
/// Refuse a set of clauses whose dependencies cycle.
///
/// Plain DFS with a colour per field rather than a full topological sort: the
/// order itself is `@arb`'s to compute, and what has to be decided here is
/// only whether one exists.
fn check_where_cycles(
  wheres : Array[WhereDecl],
  span : Span,
) -> Unit raise DefError {
  let deps : Map[String, Array[String]] = Map([])
  for w in wheres {
    let into = match deps.get(w.subject) {
      Some(a) => a
      None => {
        let a : Array[String] = []
        deps[w.subject] = a
        a
      }
    }
    for pair in w.ref_spans {
      into.push(pair.0)
    }
  }
  // 0 unvisited, 1 on the stack, 2 done.
  let mark : Map[String, Int] = Map([])
  let stack : Array[String] = []
  fn walk(name : String) -> Unit raise DefError {
    if mark.get(name) is Some(2) {
      return
    }
    if mark.get(name) is Some(1) {
      // The cycle is the tail of the stack from where this name first
      // appeared — the names an author has to look at, and not the whole
      // walk that led here.
      let names : Array[String] = []
      let mut seen = false
      for s in stack {
        if s == name {
          seen = true
        }
        if seen {
          names.push(s)
        }
      }
      raise CyclicWhere(names~, span~)
    }
    mark[name] = 1
    stack.push(name)
    for d in deps.get(name).unwrap_or([]) {
      walk(d)
    }
    let _ = stack.pop()
    mark[name] = 2
  }

  for w in wheres {
    walk(w.subject)
  }
}

///|
/// Whether a type can hold a position into a sequence.
fn is_index_like(ty : StateTy) -> Bool {
  match ty {
    TInt(..) | TAny => true
    TOption(inner) => is_index_like(inner)
    _ => false
  }
}

///|
fn is_text_like(ty : StateTy) -> Bool {
  match ty {
    TText | TEnum(_) | TAny => true
    TOption(inner) => is_text_like(inner)
    _ => false
  }
}

///|
/// Whether a type has positions — which a MAP does not, however sized it is.
fn is_ordered_seq(ty : StateTy) -> Bool {
  match ty {
    TList(_) | TTuple(_) | TAny => true
    _ => false
  }
}

///|
fn is_numeric(ty : StateTy) -> Bool {
  match ty {
    TInt(..) | TFloat | TAny => true
    TOption(inner) => is_numeric(inner)
    _ => false
  }
}

///|
/// Whether asking for a length is meaningful.
fn is_sized(ty : StateTy) -> Bool {
  match ty {
    TList(_) | TTuple(_) | TOMap(_) | TSet | TFlags(_) | TText | TAny => true
    TOption(inner) => is_sized(inner)
    _ => false
  }
}

///|
/// A type as an article plus its source spelling, for a message that reads as
/// a sentence: "`count` is a `String`".
fn show_ty(ty : StateTy) -> String {
  "a `" + ty.show_source() + "`"
}
