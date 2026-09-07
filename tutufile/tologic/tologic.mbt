// The `logic:` section, read into `@tscript.Decl`s.
//
// One member per declaration, in file order. What each kind means is stated
// where `DeclKind` is declared; what is here is only how the section spells it.

///|
/// Where a doc comment sits: shrubbery hangs a `///` written between two
/// members off the FIRST one's suffix, so reading a member's doc needs its
/// predecessor. Same rule as everywhere else a member is read.
pub fn read_logic(
  decl : @tutufile.Decl,
  rows? : Array[String] = [],
) -> Array[@tscript.Decl] raise @sh.ExError {
  let out = []
  let members = @sh.body_groups(decl)
  for at, group in members {
    let prev = if at > 0 { Some(members[at - 1]) } else { None }
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    let m = @sh.read_member(group, prev~)
    let span = @sh.span_of(group)
    try {
      match word {
        "receive" => out.push(transition(m, DReceive, span))
        "answer" => out.push(transition(m, DAnswer, span))
        "compute" => out.push(value_decl(m, DCompute, span, row_binds(m, rows)))
        "pred" => out.push(value_decl(m, DPred, span, row_binds(m, rows)))
        "enrich" =>
          out.push(
            binding_decl(m, DEnrich, span, row_binds(m, rows, always=true)),
          )
        "bind_with" =>
          out.push(
            binding_decl(m, DBindWith, span, row_binds(m, rows, always=true)),
          )
        "property" =>
          for a in accessors(m, span) {
            out.push(a)
          }
        _ =>
          raise @sh.ExError(
            message="`\{word}` is not a logic member",
            help="a component's behaviour is `receive`, `answer`, `compute`, `pred`, `enrich`, `bind_with` and `property`",
            span=@sh.span_of(parts[0]),
          )
      }
    } catch {
      e => raise at_span(e, span)
    }
  }
  out
}

///|
/// Re-raise a failure against a place, when it has none of its own.
///
/// An expression carries no span of its own, so the enclosing member is the
/// narrowest thing that can point anywhere.
pub fn at_span(e : @sh.ExError, at : @report.Span) -> @sh.ExError {
  let @sh.ExError(message~, help~, span~) = e
  if span.start == 0 && span.len == 0 {
    @sh.ExError(message~, help~, span=at)
  } else {
    e
  }
}

///|
/// `receive add(d):` — a body of statements, with the contracts it attaches.
fn transition(
  m : @sh.Member,
  kind : @tscript.DeclKind,
  span : @report.Span,
) -> @tscript.Decl raise @sh.ExError {
  {
    kind,
    name: m.name,
    params: params_of(m),
    requires_: attach(m, "requires"),
    ensures_: attach(m, "ensures"),
    format: None,
    body: Stmts(read_stmts(m.block(), Map([]))),
    doc: m.doc.unwrap_or(""),
    span: sp(span),
    name_span: sp(m.span),
  }
}

///|
/// `compute caption(): <expr>` and `pred room: <expr>` — one expression.
fn value_decl(
  m : @sh.Member,
  kind : @tscript.DeclKind,
  span : @report.Span,
  binds : Map[String, String],
) -> @tscript.Decl raise @sh.ExError {
  {
    kind,
    name: m.name,
    // A ROW member is handed its row, and the renderer's names for it are
    // fixed — so its own parameter names are the binding and there is nothing
    // left to declare. See `row_binds`.
    params: if binds.is_empty() {
      params_of(m)
    } else {
      []
    },
    requires_: None,
    ensures_: None,
    format: match m.option("format") {
      Some(f) => Some(@sh.to_expr(f, @sh.ExCtx::in_body(binds), span))
      None => None
    },
    body: Value(value_body(m, span, binds)),
    doc: m.doc.unwrap_or(""),
    span: sp(span),
    name_span: sp(m.span),
  }
}

///|
/// `enrich row(value, key):` — statements that bind names rather than write
/// state.
fn binding_decl(
  m : @sh.Member,
  kind : @tscript.DeclKind,
  span : @report.Span,
  binds : Map[String, String],
) -> @tscript.Decl raise @sh.ExError {
  {
    kind,
    name: m.name,
    params: if binds.is_empty() {
      params_of(m)
    } else {
      []
    },
    requires_: None,
    ensures_: None,
    format: None,
    body: Stmts(read_binds(m.block(), binds)),
    doc: m.doc.unwrap_or(""),
    span: sp(span),
    name_span: sp(m.span),
  }
}

///|
/// `property n :: Int:` with `get:` and `set:` under it — one declaration per
/// accessor, which is what the script language has and what a backend emits.
///
/// A property whose accessors are field reads is declared in `spec:` and has
/// nothing here; only one with a BODY reaches this.
fn accessors(
  m : @sh.Member,
  span : @report.Span,
) -> Array[@tscript.Decl] raise @sh.ExError {
  let out = []
  for g in m.block() {
    guard g.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    let kind : @tscript.DeclKind = match word {
      "get" => DGet
      "set" => DSet
      _ =>
        raise @sh.ExError(
          message="`\{word}` is not a property accessor",
          help="a property with a body writes `get:` and `set:`",
          span=@sh.span_of(parts[0]),
        )
    }
    let acc = @sh.read_member(g, prev=None)
    let body : @tscript.Body = if kind is DGet {
      Value(value_body(acc, span, Map([])))
    } else {
      Stmts(read_stmts(acc.block(), Map([])))
    }
    let d : @tscript.Decl = {
      kind,
      name: m.name,
      // A SETTER sees exactly `value`, fixed by the property's type, and an
      // author never restates or renames it — so nothing in the notation
      // declares it and the reader has to. Leaving it out made every `set:`
      // body refuse with "`value` is not a parameter of this handler", and a
      // refused declaration is DROPPED: the counter's `magnitude` setter
      // vanished from the generated module and the property stopped writing.
      params: if kind is DSet {
        [({ name: "value", span: sp(m.span), } : @tscript.Param)]
      } else {
        []
      },
      requires_: None,
      ensures_: None,
      format: None,
      body,
      doc: "",
      span: sp(span),
      name_span: sp(m.span),
    }
    out.push(d)
  }
  out
}

///|
/// The one expression a value body holds, written after the `:` or under it.
fn value_body(
  m : @sh.Member,
  span : @report.Span,
  binds : Map[String, String],
) -> @tutuca.Expr raise @sh.ExError {
  let groups = m.block()
  guard groups.length() == 1 else {
    raise @sh.ExError(
      message="a value body is one expression",
      help="write the expression after the `:`, or one line under it",
      span~,
    )
  }
  @sh.to_expr(
    @sh.read_group(groups[0]),
    @sh.ExCtx::in_body(binds),
    @sh.span_of(groups[0]),
  )
}

///|
/// A row member's parameters, as the bindings the renderer hands it.
///
/// `enrich_item(value, key)` is given ITS row, and the renderer's names for a
/// row are fixed — `value`, `key`, `iter` — so the author's parameter names
/// are two spellings of one thing and the body reads a BINDING. The old
/// notation wrote none: a filter and an in-loop enricher read `@value` out of
/// the air, which is what this replaces.
///
/// `always` for `enrich` and `bind_with`, whose KIND says they take a row. A
/// `pred` has two shapes and the declaration cannot say which — `pred room:
/// it.n < 10` is called from a slot and `pred matches(row)` filters one — so
/// for those the VIEW decides, and `rows` is what it said.
fn row_binds(
  m : @sh.Member,
  rows : Array[String],
  always? : Bool = false,
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  guard always || rows.contains(m.name) else { return out }
  for i, name in ["value", "key", "iter"] {
    if i < m.params.length() {
      out[m.params[i].name] = name
    }
  }
  out
}

///|
fn params_of(m : @sh.Member) -> Array[@tscript.Param] {
  let out : Array[@tscript.Param] = []
  for p in m.params {
    // A parameter has no span of its own in the reader: the member's does,
    // and a diagnostic about a parameter points at the declaration that names
    // it, which is where a reader looks anyway.
    out.push({ name: p.name, span: sp(m.span), })
  }
  out
}

///|
/// `~requires: room` — a `pred` attached by NAME, which is the whole value of
/// a contract.
fn attach(m : @sh.Member, word : String) -> @tscript.Attach? {
  match m.option(word) {
    Some(EName(n)) => Some(({ name: n, span: sp(m.span), } : @tscript.Attach))
    _ => None
  }
}

///|
fn sp(s : @report.Span) -> @tutuca.Span {
  { start: s.start, end_: s.end(), }
}
