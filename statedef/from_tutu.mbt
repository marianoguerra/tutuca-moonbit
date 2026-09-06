// The second front end: a `.tutu` file's `spec:` section, read into the same
// declarations the block parser produces.
//
// Everything that decides what a declaration MEANS is `defs_of`, below the two
// of them. What is here is only how shrubbery spells one — and it spells the
// same things, because the two notations describe one language.

///|
/// The components a `spec:` section declares.
///
/// `name` is what a bare component would be called, exactly as the block front
/// end takes it: a `.tutu` file always names its components, so it is only the
/// fallback the shared half asks for.
pub fn state_of_tutu(
  decls : Array[@tutufile.Decl],
  name? : String = "",
) -> Array[StateDef] raise DefError {
  let raw : Array[RawDecl] = []
  for at, d in decls {
    let prev = if at > 0 { Some(decls[at - 1]) } else { None }
    raw.push(raw_of(d, prev))
    // A component's channels are members of its body in the new notation and
    // separate blocks in the old, so the surfaces come out beside it.
  }
  defs_of(raw, name)
}

///|
/// One top-level declaration.
fn raw_of(d : @tutufile.Decl, prev : @tutufile.Decl?) -> RawDecl raise DefError {
  let doc = decl_doc(d, prev)
  match d.kind {
    Component => component_of_tutu(d, doc)
    Struct => struct_of_tutu(d, doc)
    Enum => enum_of_tutu(d, doc)
    Protocol => protocol_of_tutu(d, doc)
    _ =>
      raise Syntax(
        msg="`\{d.name}` is not a spec declaration — the section declares components, `struct`, `enum` and `protocol`",
        span=at_of(d.span),
      )
  }
}

///|
/// A component: its fields, properties, rules, domains and channels.
fn component_of_tutu(
  d : @tutufile.Decl,
  doc : String?,
) -> RawDecl raise DefError {
  let fields : Array[RawField] = []
  let properties : Array[RawProperty] = []
  let bindings : Array[RawBinding] = []
  let implements : Array[(String, Span)] = []
  let rules : Array[RuleDecl] = []
  let wheres : Array[WhereDecl] = []
  let handle_message : Array[RawCase] = []
  let handle_intent : Array[RawCase] = []
  let express_message : Array[RawCase] = []
  let express_intent : Array[RawCase] = []
  let members = @sh.body_groups(d)
  for at, g in members {
    let prev = if at > 0 { Some(members[at - 1]) } else { None }
    guard g.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    let at_ = at_of(@sh.span_of(g))
    match word {
      "field" => fields.push(field_of(read_one(g, prev), at_))
      "property" =>
        match binding_of(parts, "property", at_) {
          Some(b) => bindings.push(b)
          None => properties.push(property_of(read_one(g, prev), at_))
        }
      "view" =>
        match binding_of(parts, "view", at_) {
          Some(b) => bindings.push(b)
          None =>
            raise Syntax(
              msg="a `view` in a component binds a protocol role — write `view <Protocol>::<role> = <local view>`",
              span=at_,
            )
        }
      "pred" | "invariant" => rules.push(rule_of(read_one(g, prev), word, at_))
      "where" => wheres.push(where_of(parts, at_, @sh.member_doc(g, prev)))
      "implements" =>
        for i in 1..<parts.length() {
          if parts[i].it is Id(n) {
            implements.push((n, at_))
          }
        }
      "message" =>
        handle_message.push(case_of(parts, 1, read_one(g, prev), at_))
      "intent" => handle_intent.push(case_of(parts, 1, read_one(g, prev), at_))
      "express" => {
        guard parts.length() >= 2 && parts[1].it is Id(kind) else {
          raise Syntax(
            msg="`express` says which channel it initiates on — write `express message <name>` or `express intent <name>`",
            span=at_,
          )
        }
        let c = case_of(parts, 2, read_one(g, prev), at_)
        if kind == "intent" {
          express_intent.push(c)
        } else {
          express_message.push(c)
        }
      }
      // A wire section carries its value verbatim into a compiled card's
      // manifest, where a host parses it — a format with another side to it,
      // and not this reader's to change.
      "provide" | "lookup" =>
        raise Syntax(
          msg="`\{word}` is not read from a `.tutu` file yet: a compiled card carries its value as SOURCE in the manifest, and the host parses that with the block grammar",
          span=at_,
        )
      _ =>
        raise Syntax(
          msg="`\{word}` is not a spec member — a component declares `field`, `property`, `pred`, `invariant`, `where`, `message`, `intent`, `express` and `implements`",
          span=at_,
        )
    }
  }
  {
    kind: RState,
    name: d.name,
    name_span: at_of(d.span),
    doc,
    fields,
    cases: [],
    handle_message,
    handle_intent,
    express_message,
    express_intent,
    properties,
    views: [],
    implements,
    bindings,
    provide: [],
    lookup: [],
    rules,
    wheres,
  }
}

///|
fn read_one(g : @ast.Node, prev : @ast.Node?) -> @sh.Member raise DefError {
  @sh.read_member(g, prev~) catch {
    e => {
      let @sh.ExError(message~, help~, span~) = e
      raise Syntax(msg=message + " — " + help, span=at_of(span))
    }
  }
}

///|
/// `field n :: T`.
fn field_of(m : @sh.Member, at : Span) -> RawField raise DefError {
  guard m.ty is Some(ty) else {
    raise Syntax(
      msg="`\{m.name}` has no type — write `field \{m.name} :: <Type>`",
      span=at,
    )
  }
  { name: m.name, span: at, doc: m.doc, attrs: [], ty: ty_of(ty, at), }
}

///|
/// `property n :: T ~public`, with a compact `get:` / `set:` under it.
fn property_of(m : @sh.Member, at : Span) -> RawProperty raise DefError {
  guard m.ty is Some(ty) else {
    raise Syntax(
      msg="property `\{m.name}` has no type — write `property \{m.name} :: <Type>`",
      span=at,
    )
  }
  let mut getter = None
  let mut setter = None
  for g in m.block() {
    let acc = read_one(g, None)
    let field = compact_field(acc, at)
    if acc.word == "get" {
      getter = Some(field)
    } else if acc.word == "set" {
      setter = Some(field)
    }
  }
  {
    // A component's OWN property. The section names which list it belongs to,
    // and a protocol's members go in one of the others.
    section: "local",
    name: m.name,
    span: at,
    doc: m.doc,
    ty: ty_of(ty, at),
    public_: m.has_option("public"),
    // A property with a `set` accessor is writable, and so is one the logic
    // section implements a `set` for — which is why `writable` is not read
    // from an option: the two sections would then have to agree twice.
    writable: setter is Some(_) || m.has_option("writable"),
    getter,
    setter,
  }
}

///|
/// `get: it.field` — the one field a compact accessor reads.
fn compact_field(acc : @sh.Member, at : Span) -> String raise DefError {
  let gs = acc.block()
  guard gs.length() == 1 else {
    raise Syntax(
      msg="a `\{acc.word}` in the spec section reads one field and nothing else",
      span=at,
    )
  }
  let ex = @sh.read_group(gs[0]) catch {
    e => {
      let @sh.ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  guard ex is EIt(f) else {
    raise Syntax(
      msg="a `\{acc.word}` in the spec section reads one field — move the body to the `logic:` section, or write `\{acc.word}: it.<field>`",
      span=at,
    )
  }
  "." + f
}

///|
/// `property Holder::filled = filled` — a protocol member bound to a local one.
fn binding_of(
  parts : Array[@ast.Node],
  section : String,
  at : Span,
) -> RawBinding? {
  guard @sh.qualified(parts, 1) is Some((name, next)) else { return None }
  guard next < parts.length() && parts[next].it is Op("=") else { return None }
  guard next + 1 < parts.length() && parts[next + 1].it is Id(here) else {
    return None
  }
  let halves = name.split("::").map(x => x.to_owned()).collect()
  guard halves.length() == 2 else { return None }
  Some({
    section,
    protocol_name: halves[0],
    member_name: halves[1],
    source: here,
    span: at,
  })
}

///|
/// `pred name: <expr>` / `invariant name:` with a `~format:`.
fn rule_of(m : @sh.Member, word : String, at : Span) -> RuleDecl raise DefError {
  let gs = m.block()
  guard gs.length() == 1 else {
    raise Syntax(
      msg="a `\{word}` is one expression — `and` two of them together if it is really two",
      span=at,
    )
  }
  {
    kind: if word == "invariant" {
      RInvariant
    } else {
      RPred
    },
    name: m.name,
    body: expr_of_group(gs[0], at),
    format: match m.option("format") {
      Some(f) => Some(expr_of_ex(f, at))
      None => None
    },
    doc: m.doc,
    span: at,
    name_span: at,
  }
}

///|
/// `message hold(Any)` — a channel case, qualified or not.
fn case_of(
  parts : Array[@ast.Node],
  from : Int,
  m : @sh.Member,
  at : Span,
) -> RawCase raise DefError {
  guard @sh.member_name(parts, from) is Some((name, next)) else {
    raise Syntax(msg="a channel case is a name", span=at)
  }
  let payload : Array[RawTy] = []
  if next < parts.length() && parts[next].it is Parens(gs) {
    for g in gs {
      let ex = @sh.read_group(g) catch {
        e => {
          let @sh.ExError(message~, help~, ..) = e
          raise Syntax(msg=message + " — " + help, span=at)
        }
      }
      payload.push(ty_of(ex, at))
    }
  }
  { name, span: at, doc: m.doc, payload, }
}

///|
fn expr_of_group(g : @ast.Node, at : Span) -> @tutuca.Expr raise DefError {
  let ex = @sh.read_group(g) catch {
    e => {
      let @sh.ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  expr_of_ex(ex, at)
}

///|
fn expr_of_ex(ex : @sh.Ex, at : Span) -> @tutuca.Expr raise DefError {
  @sh.to_expr(ex, @sh.ExCtx::in_body(Map([])), @report.Span::at(at.start)) catch {
    e => {
      let @sh.ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
}

///|
/// The doc above a declaration. Shrubbery hangs a `///` written between two of
/// them off the FIRST one's suffix, so reading one needs its predecessor.
fn decl_doc(d : @tutufile.Decl, prev : @tutufile.Decl?) -> String? {
  match prev {
    Some(p) => @sh.member_doc(d.node, Some(p.node))
    None => @sh.member_doc(d.node, None)
  }
}

///|
fn at_of(s : @report.Span) -> Span {
  { start: s.start, end_: s.end(), }
}
