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
  // A file with no `spec:` section declares no component, which is a legal
  // thing to write: a `view:` on its own is most of the skill's examples and a
  // fragment a page hands the generator. `defs_of` refuses an EMPTY block for a
  // different reason — a block of types with no state — and answering that
  // here made every view-only file a syntax error.
  guard decls.length() > 0 else { return [] }
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
    ImportProtocol => import_protocol_of_tutu(d, doc)
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
  let provide : Array[ProvideDecl] = []
  let lookup : Array[LookupDecl] = []
  let mut category = ""
  let keywords : Array[String] = []
  let members = @sh.body_groups(d)
  for at, g in members {
    let prev = if at > 0 { Some(members[at - 1]) } else { None }
    guard g.it is Group(parts) && parts.length() > 0 else { continue }
    // What the component says ABOUT itself rather than declares, and the only
    // members written as options. They lead the block, the way every option
    // that carries a value does.
    if parts[0].it is Kw(opt) {
      catalog_option(
        opt,
        parts,
        at_of(@sh.span_of(g)),
        v => category = v,
        keywords,
      )
      continue
    }
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
      "provide" | "lookup" =>
        match wiring_of(parts, word, at_) {
          Binding(b) => bindings.push(b)
          Provided(p) => provide.push(p)
          Wanted(l) => lookup.push(l)
        }
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
    provide,
    lookup,
    rules,
    wheres,
    category,
    keywords,
  }
}

///|
/// `~category: "layout"` and `~keywords: ["layout", "box"]`.
///
/// Both are SEARCH TEXT and neither is an identifier — a person types them
/// into a palette and they are matched against what is written here — so they
/// are read as strings and nothing normalizes them.
fn catalog_option(
  opt : String,
  parts : Array[@ast.Node],
  at : Span,
  set_category : (String) -> Unit,
  keywords : Array[String],
) -> Unit raise DefError {
  guard parts.length() >= 2 && parts[1].it is Block(bgs) && bgs.length() == 1 else {
    raise Syntax(
      msg="`~\{opt}` needs a value — write `~\{opt}: <value>` on its own line inside the component",
      span=at,
    )
  }
  let value = @sh.read_group(bgs[0]) catch {
    e => {
      let ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  match opt {
    "category" =>
      match value {
        EStr(text) => set_category(text)
        _ =>
          raise Syntax(
            msg="a category is a string — write `~category: \"layout\"`, since it is matched against what a person types",
            span=at,
          )
      }
    "keywords" =>
      match value {
        EList(items) =>
          for item in items {
            match item {
              EStr(text) => keywords.push(text)
              _ =>
                raise Syntax(
                  msg="a keyword is a string — write `~keywords: [\"layout\", \"box\"]`",
                  span=at,
                )
            }
          }
        _ =>
          raise Syntax(
            msg="`~keywords` takes a list — write `~keywords: [\"layout\", \"box\"]`, since a comma only separates inside brackets",
            span=at,
          )
      }
    _ =>
      raise Syntax(
        msg="`~\{opt}` is not something a component declares about itself — a component's options are `~category` and `~keywords`",
        span=at,
      )
  }
}

///|
/// Which of the three tables a `provide` / `lookup` line lands in.
///
/// A qualified name fills a PROTOCOL's channel and shares one table with
/// `property Clock::now = …` and `view Sheet::row = …`; a bare one is this
/// component's own wiring. One reader answers both because one line spells
/// both, and the qualification is the only thing that tells them apart.
priv enum Wiring {
  Binding(RawBinding)
  Provided(ProvideDecl)
  Wanted(LookupDecl)
}

///|
/// `provide theme = it.theme`, `lookup theme = "plain"`, `lookup theme`,
/// `provide Clock::now = it.now`.
fn wiring_of(
  parts : Array[@ast.Node],
  word : String,
  at : Span,
) -> Wiring raise DefError {
  guard @sh.member_name(parts, 1) is Some((name, next)) else {
    raise Syntax(
      msg="a `\{word}` names one binding — write `\{word} <name>` or `\{word} <Protocol>::<member> = <value>`",
      span=at,
    )
  }
  let value = if next >= parts.length() {
    None
  } else {
    guard parts[next].it is Op("=") else {
      raise Syntax(
        msg="a `\{word}` is a name, or a name and a value — write `\{word} \{name} = <value>`",
        span=at,
      )
    }
    guard next + 1 < parts.length() else {
      raise Syntax(
        msg="`\{word} \{name} =` says nothing is on the right — write the value it \{if word == "provide" { "publishes" } else { "falls back to" }}",
        span=at,
      )
    }
    Some(wire_value(parts[next + 1:], word, name, at))
  }
  let halves = name.split("::").map(x => x.to_owned()).collect()
  if halves.length() == 2 {
    guard value is Some(v) else {
      raise Syntax(
        msg="a protocol's `\{word}` states what fills it — write `\{word} \{name} = <value>`",
        span=at,
      )
    }
    return Binding({
      section: word,
      protocol_name: halves[0],
      member_name: halves[1],
      source: v,
      span: at,
    })
  }
  if word == "provide" {
    guard value is Some(v) else {
      raise Syntax(
        msg="every `provide` states what produces it — write `provide \{name} = it.<field>`",
        span=at,
      )
    }
    Provided({ name, source: v, span: at, })
  } else {
    Wanted({ name, default: value, span: at, })
  }
}

///|
/// A wiring value, as the text a manifest carries and `component/` reads.
///
/// The one place this file writes source rather than reading it, and it is
/// deliberate: `provide` and `lookup` are the seam between a card and whatever
/// host loads it, so their value is a WIRE FORMAT with another side to it
/// (`@tscript.parse_provide`, `@component.lookup_or`) and a MoonBit caller
/// spells the same thing by hand as `provide={ "items": ".items" }`.
///
/// The grammar is closed on purpose. A provide must be ADDRESSABLE — it is
/// read as a value and used as a render target and a resume path — and a
/// lookup default is a fallback value, so between them a path, `self` and a
/// literal is the whole vocabulary. Anything else is refused here with the
/// shape to write, rather than printed into text whose other side would judge
/// it later.
fn wire_value(
  terms : ArrayView[@ast.Node],
  word : String,
  name : String,
  at : Span,
) -> String raise DefError {
  // `self` is a WORD in this position and not a name: it publishes the
  // declaring component's own type, which no expression can spell.
  if terms.length() == 1 && terms[0].it is Id("self") {
    return "self"
  }
  let ex = @sh.read_ex(terms) catch {
    e => {
      let ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  wire_ex(ex, word, name, at)
}

///|
/// The closed grammar itself: a path, or a literal.
fn wire_ex(
  ex : @sh.Ex,
  word : String,
  name : String,
  at : Span,
) -> String raise DefError {
  match ex {
    EIt(f) => "." + f
    EIndex(base, k) =>
      wire_ex(base, word, name, at) + "[" + wire_ex(k, word, name, at) + "]"
    EStr(s) => "'" + s.replace_all(old="'", new="\\'") + "'"
    ENum(n) =>
      if n == n.trunc() && n.abs() < 1.0e15 {
        n.to_int64().to_string()
      } else {
        n.to_string()
      }
    EBool(b) => if b { "true" } else { "false" }
    // `null` and `none` are WORDS to the reader and literals to everything
    // downstream — `to_expr` folds them the same way, and this is the same
    // fold at the one place that writes text instead of a tree.
    ENone | EName("null") | EName("none") => "null"
    EList(items) =>
      if items.is_empty() {
        "[]"
      } else {
        raise Syntax(
          msg="a `\{word}`'s value is a path or a constant, and `\{name}` is given a list with entries in it",
          span=at,
        )
      }
    _ =>
      raise Syntax(
        msg="a `\{word}`'s value is addressable or constant — write `\{word} \{name} = it.<field>`, `it.<seq>[<key>]`\{if word == "provide" { " or `self`" } else { ", or a literal" }}",
        span=at,
      )
  }
}

///|
fn read_one(g : @ast.Node, prev : @ast.Node?) -> @sh.Member raise DefError {
  @sh.read_member(g, prev~) catch {
    e => {
      let ExError(message~, help~, span~) = e
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
      let ExError(message~, help~, ..) = e
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
          let ExError(message~, help~, ..) = e
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
      let ExError(message~, help~, ..) = e
      raise Syntax(msg=message + " — " + help, span=at)
    }
  }
  expr_of_ex(ex, at)
}

///|
fn expr_of_ex(ex : @sh.Ex, at : Span) -> @tutuca.Expr raise DefError {
  @sh.to_expr(ex, @sh.ExCtx::in_body(Map([])), @report.Span::at(at.start)) catch {
    e => {
      let ExError(message~, help~, ..) = e
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
