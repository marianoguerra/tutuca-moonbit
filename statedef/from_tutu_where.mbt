// A `where` clause, read out of the shrubbery it is written in.
//
// The vocabulary is CLOSED — that is what makes it a `where` rather than a
// `pred` — so this is one arm per relation and no fallthrough. The words are
// the notation's; what they mean is `@tutuca.Domain`, which is shared.

///|
/// `where it.at >= 0`, `where it.k is_key_of it.rows`.
fn where_of(
  parts : Array[@ast.Node],
  at : Span,
  doc : String?,
) -> WhereDecl raise DefError {
  // The SUBJECT is the field the clause is about, written `it.<field>`.
  guard parts.length() >= 3 &&
    parts[1].it is Id("it") &&
    parts[2].it is Op(".") &&
    parts.length() >= 4 &&
    parts[3].it is Id(subject) else {
    raise Syntax(
      msg="a `where` states a relation about a field — write `where it.<field> <relation> <target>`",
      span=at,
    )
  }
  let refs : Array[(String, Span)] = []
  let relation = relation_of(parts, 4, at, refs)
  { subject, subject_span: at, relation, ref_spans: refs, doc, span: at, }
}

///|
/// The relation, from the term after the subject.
fn relation_of(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
  refs : Array[(String, Span)],
) -> @tutuca.Domain raise DefError {
  guard from < parts.length() && parts[from].it is Id(word) else {
    // `where it.n >= 0` — an ordering is written as the operator it is.
    return compare_of(parts, from, at, refs)
  }
  match word {
    "is_index_of" =>
      DIndexOf(
        field=field_after(parts, from + 1, at, refs),
        allow_none=has_flag(parts, "or_none"),
      )
    "is_key_of" => DKeyOf(field=field_after(parts, from + 1, at, refs))
    "is_member_of" => DMemberOf(field=field_after(parts, from + 1, at, refs))
    "is_element_of" => DElementOf(field=field_after(parts, from + 1, at, refs))
    "is_subset_of" => DSubsetOf(field=field_after(parts, from + 1, at, refs))
    "non_empty" => DNonEmpty
    "pattern" => DPattern(string_after(parts, from + 1, at))
    "format" => DFormat(string_after(parts, from + 1, at))
    // `where it.name len <= 100` states the inner relation about the LENGTH.
    "len" => DLen(relation_of(parts, from + 1, at, refs))
    "is_one_of" => one_of(parts, from + 1, at)
    "in_range" => in_range(parts, from, at, refs)
    _ =>
      raise Syntax(
        msg="`\{word}` is not a `where` relation — the vocabulary is `is_index_of`, `is_key_of`, `is_member_of`, `is_element_of`, `is_subset_of`, `is_one_of`, `in_range`, `non_empty`, `pattern`, `format` and `len`, plus the orderings",
        span=at,
      )
  }
}

///|
/// `>= 0`, `< it.total` — an ordering and what it is compared against.
fn compare_of(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
  refs : Array[(String, Span)],
) -> @tutuca.Domain raise DefError {
  guard from < parts.length() && parts[from].it is Op(o) else {
    raise Syntax(msg="a `where` states a relation about a field", span=at)
  }
  let op : @tutuca.DomainOp = match o {
    ">=" => DGe
    ">" => DGt
    "<=" => DLe
    "<" => DLt
    _ =>
      raise Syntax(
        msg="`\{o}` is not an ordering — a `where` compares with `>=`, `>`, `<=` or `<`",
        span=at,
      )
  }
  DCompare(op~, rhs=operand_at(parts, from + 1, at, refs))
}

///|
/// `in_range(0, 100)` — the one relation written as a call, because a bare
/// pair would read as two terms of one expression.
fn in_range(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
  refs : Array[(String, Span)],
) -> @tutuca.Domain raise DefError {
  guard from + 1 < parts.length() && parts[from + 1].it is Parens(gs) else {
    raise Syntax(msg="write `in_range(0, 100)`", span=at)
  }
  guard gs.length() == 2 else {
    raise Syntax(msg="`in_range` takes a low bound and a high one", span=at)
  }
  DBetween(lo=operand_of(gs[0], at, refs), hi=operand_of(gs[1], at, refs))
}

///|
/// `is_one_of ["a", "b"]` — the closed set a value is drawn from.
fn one_of(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
) -> @tutuca.Domain raise DefError {
  guard from < parts.length() && parts[from].it is Brackets(gs) else {
    raise Syntax(msg="write `is_one_of [\"a\", \"b\"]`", span=at)
  }
  let out : Array[@tutuca.Value] = []
  for g in gs {
    let ex = @sh.read_group(g) catch {
      e => {
        let @sh.ExError(message~, help~, ..) = e
        raise Syntax(msg=message + " — " + help, span=at)
      }
    }
    out.push(
      match ex {
        EStr(s) => Str(s)
        ENum(n) => Num(n)
        EBool(b) => Bool(b)
        _ => raise Syntax(msg="a member of a closed set is a literal", span=at)
      },
    )
  }
  DOneOf(out)
}

///|
/// `it.<field>` after a relation word, as the field it names.
fn field_after(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
  refs : Array[(String, Span)],
) -> String raise DefError {
  guard from + 2 < parts.length() &&
    parts[from].it is Id("it") &&
    parts[from + 1].it is Op(".") &&
    parts[from + 2].it is Id(f) else {
    raise Syntax(
      msg="this relation names a field — write `it.<field>`",
      span=at,
    )
  }
  refs.push((f, at))
  f
}

///|
fn string_after(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
) -> String raise DefError {
  guard from < parts.length() && parts[from].it is Lit(Str(s)) else {
    raise Syntax(msg="this relation names a string", span=at)
  }
  s
}

///|
/// A bound: a number, or another field of this state.
fn operand_at(
  parts : Array[@ast.Node],
  from : Int,
  at : Span,
  refs : Array[(String, Span)],
) -> @tutuca.DomainOperand raise DefError {
  guard from < parts.length() else {
    raise Syntax(msg="this relation has nothing on its right", span=at)
  }
  // `it.total` is three terms; a number is one.
  if from + 2 < parts.length() &&
    parts[from].it is Id("it") &&
    parts[from + 1].it is Op(".") &&
    parts[from + 2].it is Id(f) {
    refs.push((f, at))
    return DField(f)
  }
  num_operand(parts[from], at)
}

///|
fn operand_of(
  g : @ast.Node,
  at : Span,
  refs : Array[(String, Span)],
) -> @tutuca.DomainOperand raise DefError {
  let ex = @sh.read_group(g) catch {
    e => {
      let @sh.ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  match ex {
    ENum(n) => DLit(n)
    EIt(f) => {
      refs.push((f, at))
      DField(f)
    }
    _ =>
      raise Syntax(
        msg="a bound is a number or another field — write `0` or `it.total`",
        span=at,
      )
  }
}

///|
fn num_operand(
  node : @ast.Node,
  at : Span,
) -> @tutuca.DomainOperand raise DefError {
  match node.it {
    Lit(Flo(f)) => DLit(f)
    Lit(Int_(i)) =>
      DLit((@string.parse_int(i.to_string()) catch { _ => 0 }).to_double())
    _ =>
      raise Syntax(
        msg="a bound is a number or another field — write `0` or `it.total`",
        span=at,
      )
  }
}

///|
/// A bare `~name` flag among a clause's terms.
fn has_flag(parts : Array[@ast.Node], name : String) -> Bool {
  for p in parts {
    if p.it is Kw(k) && k == name {
      return true
    }
  }
  false
}
