// The expression language, read out of a shrubbery term sequence.
//
// A shrubbery group is a flat list of terms — `it . n < 3` is five of them —
// so this is where the structure comes from. The grammar is the one the
// proposal states: operator families that do not mix without parentheses,
// which is shrubbery's own rule and means the levels below can be a fixed
// ladder rather than a precedence table anyone has to agree with.

///|
/// One expression.
pub(all) enum Ex {
  ENum(Double)
  EStr(String)
  EBool(Bool)
  ENone
  /// A bare identifier: a handler name, a binding, a macro parameter.
  EName(String)
  /// `it.name` — a property of the component this body belongs to.
  EIt(String)
  /// `it.state.name` — the raw stored field behind a property.
  EState(String)
  /// `dyn.name` — a dynamic binding.
  EDyn(String)
  /// `e.name`, for a binding member (`item.title`) or an event field.
  EMember(Ex, String)
  /// `e[k]`
  EIndex(Ex, Ex)
  /// `f(args)`, with keyword arguments kept in order.
  ECall(Ex, Array[Arg])
  EBin(String, Ex, Ex)
  EUn(String, Ex)
  EIf(Ex, Ex, Ex)
  /// `@str{…}` — text and holes, in source order.
  ETemplate(Array[TPart])
  EList(Array[Ex])
  EMap(Array[(String, Ex)])
}

///|
/// One argument of a call: positional, or `~name: value`.
pub(all) enum Arg {
  APos(Ex)
  AKw(String, Ex)
  /// `name: value` — a field of an aggregate being built, or an entry of a
  /// map. It is not a `~name:` option: one names a field and the other names
  /// an argument of the call itself, and the two keyspaces stay apart.
  AField(String, Ex)
  /// `~name` with no value — a flag option such as `~prevent`.
  AFlag(String)
}

///|
/// One piece of a string template.
pub(all) enum TPart {
  TText(String)
  THole(Ex)
}

///|
/// What went wrong reading an expression, with the span to point at.
pub(all) suberror ExError {
  ExError(message~ : String, help~ : String, span~ : @report.Span)
}

///|
/// Read one group's terms as an expression.
pub fn read_ex(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  // `if` takes the whole group: its condition is everything up to the arms,
  // so the operator ladder must not split the condition off first.
  if terms.length() > 0 && terms[0].it is Id("if") {
    return read_if(terms)
  }
  read_or(terms)
}

///|
/// `&&` and `||`, which chain freely with each other in shrubbery and are
/// kept apart here the way the target language keeps them apart.
fn read_or(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  match split_top(terms, ["||"]) {
    Some((l, op, r)) => EBin(op, read_or(l), read_and(r))
    None => read_and(terms)
  }
}

///|
fn read_and(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  match split_top(terms, ["&&"]) {
    Some((l, op, r)) => EBin(op, read_and(l), read_cmp(r))
    None => read_cmp(terms)
  }
}

///|
fn read_cmp(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  match split_top(terms, ["==", "!=", "<", "<=", ">", ">=", "implies"]) {
    Some((l, op, r)) => EBin(op, read_sum(l), read_sum(r))
    None => read_sum(terms)
  }
}

///|
fn read_sum(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  match split_top(terms, ["+", "-"]) {
    Some((l, op, r)) => EBin(op, read_sum(l), read_prod(r))
    None => read_prod(terms)
  }
}

///|
fn read_prod(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  match split_top(terms, ["*", "/", "mod"]) {
    Some((l, op, r)) => EBin(op, read_prod(l), read_unary(r))
    None => read_unary(terms)
  }
}

///|
fn read_unary(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  guard terms.length() > 0 else {
    raise ExError(
      message="an expression is missing",
      help="write a value here",
      span=@report.Span::at(0),
    )
  }
  if terms[0].it is Op(o) && (o == "!" || o == "-") {
    return EUn(o, read_unary(terms[1:]))
  }
  read_postfix(terms)
}

///|
/// A primary followed by any number of `.name`, `(args)` and `[k]`.
fn read_postfix(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  // `if c | a | b` is a whole group, not a primary with a tail.
  if terms[0].it is Id("if") {
    return read_if(terms)
  }
  // `@str{…}` reads as `str([…])`, and its argument list is the template.
  if terms[0].it is Id("str") && terms.length() == 2 {
    match template_parts(terms[1]) {
      Some(parts) => return ETemplate(parts)
      None => ()
    }
  }
  let head = terms[0]
  let mut ex = match head.it {
    Id("it") => read_it_head(terms)
    Id("dyn") => read_dyn_head(terms)
    Id("true") => EBool(true)
    Id("false") => EBool(false)
    Id("none") => ENone
    Id(n) => EName(n)
    Lit(d) => datum_ex(d, head)
    Parens(gs) => read_parens(gs, head)
    Brackets(gs) => EList(read_each(gs))
    Braces(gs) => read_map(gs, head)
    _ =>
      raise ExError(
        message="this is not a value",
        help="an expression is a name, a literal, a call, or a parenthesised expression",
        span=span_of(head),
      )
  }
  // `it.` and `dyn.` consumed two extra terms; everything else consumed one.
  let mut i = match head.it {
    Id("it") =>
      if terms.length() > 3 && terms[3].it is Id("state") {
        5
      } else {
        3
      }
    Id("dyn") => 3
    _ => 1
  }
  if head.it is Id("it") && terms.length() > 2 && terms[2].it is Id("state") {
    i = 5
  }
  while i < terms.length() {
    let t = terms[i]
    match t.it {
      Op(".") => {
        guard i + 1 < terms.length() && terms[i + 1].it is Id(name) else {
          raise ExError(
            message="a name has to follow `.`",
            help="write the member you mean",
            span=span_of(t),
          )
        }
        ex = EMember(ex, name)
        i = i + 2
      }
      Parens(gs) => {
        ex = ECall(ex, read_args(gs))
        i = i + 1
      }
      Brackets(gs) => {
        guard gs.length() == 1 else {
          raise ExError(
            message="an index takes one expression",
            help="write one key between the brackets",
            span=span_of(t),
          )
        }
        ex = EIndex(ex, read_group(gs[0]))
        i = i + 1
      }
      _ =>
        raise ExError(
          message="`\{node_text(t)}` cannot follow a value",
          help="an operator between two values needs a value on each side",
          span=span_of(t),
        )
    }
  }
  ex
}

///|
/// The pieces of an at-notation body, if this node is one.
///
/// `@str{a @(b) c}` parses as a call whose one argument is a bracketed list of
/// text literals and parenthesised holes; anything else is an ordinary call.
fn template_parts(node : @ast.Node) -> Array[TPart]? {
  guard node.it is Parens(gs) && gs.length() == 1 else { return None }
  guard gs[0].it is Group(inner) && inner.length() == 1 else { return None }
  guard inner[0].it is Brackets(items) else { return None }
  let out = []
  for item in items {
    guard item.it is Group(parts) && parts.length() == 1 else { return None }
    match parts[0].it {
      Lit(Str(t)) => out.push(TText(t))
      Parens(hole) => {
        guard hole.length() == 1 else { return None }
        let ex = read_group(hole[0]) catch { _ => return None }
        out.push(THole(ex))
      }
      _ => return None
    }
  }
  Some(out)
}

///|
/// `it.name`, or `it.state.name`.
fn read_it_head(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  guard terms.length() >= 3 && terms[1].it is Op(".") && terms[2].it is Id(a) else {
    raise ExError(
      message="`it` names the component, so a member has to follow it",
      help="write `it.<field>` — `it` on its own is not a value",
      span=span_of(terms[0]),
    )
  }
  if a == "state" {
    guard terms.length() >= 5 && terms[3].it is Op(".") && terms[4].it is Id(b) else {
      raise ExError(
        message="`it.state` names the stored fields, so a field has to follow it",
        help="write `it.state.<field>`, or `it.<name>` for the property",
        span=span_of(terms[0]),
      )
    }
    return EState(b)
  }
  EIt(a)
}

///|
fn read_dyn_head(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  guard terms.length() >= 3 && terms[1].it is Op(".") && terms[2].it is Id(a) else {
    raise ExError(
      message="`dyn` names a dynamic binding, so a name has to follow it",
      help="write `dyn.<name>`, and declare it with `lookup <name>`",
      span=span_of(terms[0]),
    )
  }
  EDyn(a)
}

///|
/// `if cond | then | else`.
fn read_if(terms : ArrayView[@ast.Node]) -> Ex raise ExError {
  let last = terms[terms.length() - 1]
  guard last.it is Alts(arms) else {
    raise ExError(
      message="an `if` needs both arms",
      help="write `if <cond> | <then> | <else>` — an expression has to have a value",
      span=span_of(terms[0]),
    )
  }
  guard arms.length() == 2 else {
    raise ExError(
      message="an `if` takes exactly two arms, and this has \{arms.length()}",
      help="write `if <cond> | <then> | <else>`",
      span=span_of(last),
    )
  }
  let cond = read_ex(terms[1:terms.length() - 1])
  EIf(cond, read_block_ex(arms[0]), read_block_ex(arms[1]))
}

///|
/// One arm of an `if`: a block holding one group.
fn read_block_ex(node : @ast.Node) -> Ex raise ExError {
  guard node.it is Block(gs) && gs.length() == 1 else {
    raise ExError(
      message="an `if` arm is one expression",
      help="write one value in each arm",
      span=span_of(node),
    )
  }
  read_group(gs[0])
}

///|
/// A parenthesised expression, or an `@str{…}` template's argument list.
fn read_parens(groups : Array[@ast.Node], at : @ast.Node) -> Ex raise ExError {
  guard groups.length() == 1 else {
    raise ExError(
      message="a parenthesised expression holds one value",
      help="a call's arguments belong after the name it calls",
      span=span_of(at),
    )
  }
  read_group(groups[0])
}

///|
/// `{ a: 1, b: 2 }`.
fn read_map(groups : Array[@ast.Node], at : @ast.Node) -> Ex raise ExError {
  let out = []
  for g in groups {
    guard g.it is Group(parts) && parts.length() >= 2 else {
      raise ExError(
        message="a map entry is `key: value`",
        help="write `{ count: 2 }`",
        span=span_of(at),
      )
    }
    let key = match parts[0].it {
      Id(k) => k
      Lit(Str(k)) => k
      _ =>
        raise ExError(
          message="a map key is a name or a string",
          help="write `{ count: 2 }` or `{ \"count\": 2 }`",
          span=span_of(parts[0]),
        )
    }
    guard parts[1].it is Block(bgs) && bgs.length() == 1 else {
      raise ExError(
        message="a map entry is `key: value`",
        help="write a value after the `:`",
        span=span_of(parts[0]),
      )
    }
    out.push((key, read_group(bgs[0])))
  }
  EMap(out)
}

///|
/// A call's arguments, keyword ones kept where they were written.
fn read_args(groups : Array[@ast.Node]) -> Array[Arg] raise ExError {
  let out = []
  for g in groups {
    guard g.it is Group(parts) else {
      out.push(APos(read_group(g)))
      continue
    }
    if parts.length() >= 1 && parts[0].it is Kw(name) {
      if parts.length() == 1 {
        out.push(AFlag(name))
      } else if parts[1].it is Block(bgs) && bgs.length() == 1 {
        out.push(AKw(name, read_group(bgs[0])))
      } else {
        raise ExError(
          message="`~\{name}` needs a value",
          help="write `~\{name}: <value>`, or drop the `:` for a flag",
          span=span_of(parts[0]),
        )
      }
    } else if parts.length() == 2 &&
      parts[0].it is Id(field) &&
      parts[1].it is Block(bgs) &&
      bgs.length() == 1 {
      out.push(AField(field, read_group(bgs[0])))
    } else {
      out.push(APos(read_ex(parts[:])))
    }
  }
  out
}

///|
/// Every group in a bracketed list, as expressions.
fn read_each(groups : Array[@ast.Node]) -> Array[Ex] raise ExError {
  let out = []
  for g in groups {
    out.push(read_group(g))
  }
  out
}

///|
/// One group as an expression.
pub fn read_group(node : @ast.Node) -> Ex raise ExError {
  match node.it {
    Group(parts) => read_ex(parts[:])
    _ => read_ex([node][:])
  }
}

///|
/// A literal datum.
fn datum_ex(d : @sexp.Datum, at : @ast.Node) -> Ex raise ExError {
  match d {
    Str(s) => EStr(s)
    Flo(f) => ENum(f)
    Int_(i) =>
      ENum((@string.parse_int(i.to_string()) catch { _ => 0 }).to_double())
    Bool_(b) => EBool(b)
    _ =>
      raise ExError(
        message="this literal has no place in a tutuca expression",
        help="the values are numbers, strings, `true`, `false` and `none`",
        span=span_of(at),
      )
  }
}

///|
/// The lowest operator of one family in a term sequence, right to left, so
/// the ladder above builds left-associative trees.
fn split_top(
  terms : ArrayView[@ast.Node],
  ops : Array[String],
) -> (ArrayView[@ast.Node], String, ArrayView[@ast.Node])? {
  let mut i = terms.length() - 1
  while i > 0 {
    // an operator directly after another operator is a unary sign, not a split
    let word = match terms[i].it {
      Op(o) => Some(o)
      // `implies` is a word rather than a symbol, and shrubbery reads a word
      // as an identifier — so an infix one is matched by name.
      Id(o) => if o == "implies" { Some(o) } else { None }
      _ => None
    }
    if word is Some(o) && ops.contains(o) && !(terms[i - 1].it is Op(_)) {
      return Some((terms[:i], o, terms[i + 1:]))
    }
    i = i - 1
  }
  None
}

///|
/// A node's span as an offset span into the file.
pub fn span_of(node : @ast.Node) -> @report.Span {
  @report.Span::of_range(node.span.start.idx, node.span.end.idx)
}

///|
/// What a node reads as, for a message that has to quote it.
pub fn node_text(node : @ast.Node) -> String {
  match node.it {
    Id(s) | Op(s) | Kw(s) => s
    Lit(Str(s)) => s
    _ => node.it.tag()
  }
}
