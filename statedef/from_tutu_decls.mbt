// The declarations beside a component: helper types and protocols.

///|
/// `struct Line(what :: String, qty :: Int)` — a named record.
fn struct_of_tutu(d : @tutufile.Decl, doc : String?) -> RawDecl raise DefError {
  let at = at_of(d.span)
  guard d.node.it is Group(parts) &&
    parts.length() >= 3 &&
    parts[2].it is Parens(gs) else {
    raise Syntax(
      msg="`\{d.name}` declares no fields — write `struct \{d.name}(what :: String, qty :: Int)`",
      span=at,
    )
  }
  let fields : Array[RawField] = []
  for g in gs {
    let p = @sh.read_param(g) catch {
      e => {
        let @sh.ExError(message~, help~, ..) = e
        raise Syntax(msg=message + " — " + help, span=at)
      }
    }
    guard p.ty is Some(ty) else {
      raise Syntax(
        msg="field `\{p.name}` of `\{d.name}` has no type — write `\{p.name} :: <Type>`",
        span=at,
      )
    }
    fields.push({
      name: p.name,
      span: at,
      doc: None,
      attrs: [],
      ty: ty_of(ty, at),
    })
  }
  { ..empty_decl(RStruct, d.name, at, doc), fields, }
}

///|
/// `enum Tone:` with one case per line. A case that carries a payload makes
/// the whole declaration a VARIANT, which is a different type at the runtime.
fn enum_of_tutu(d : @tutufile.Decl, doc : String?) -> RawDecl raise DefError {
  let at = at_of(d.span)
  let cases : Array[RawCase] = []
  let members = @sh.body_groups(d)
  for i, g in members {
    let prev = if i > 0 { Some(members[i - 1]) } else { None }
    guard g.it is Group(parts) && parts.length() >= 1 && parts[0].it is Id(c) else {
      raise Syntax(
        msg="an enum case is a name — write one per line under `enum \{d.name}:`, with its payload in parentheses if it has one",
        span=at,
      )
    }
    let payload : Array[RawTy] = []
    if parts.length() > 1 && parts[1].it is Parens(gs) {
      for a in gs {
        let ex = @sh.read_group(a) catch {
          e => {
            let @sh.ExError(message~, help~, ..) = e
            raise Syntax(msg=message + " — " + help, span=at)
          }
        }
        payload.push(ty_of(ex, at))
      }
    }
    cases.push({ name: c, span: at, doc: @sh.member_doc(g, prev), payload, })
  }
  { ..empty_decl(REnum, d.name, at, doc), cases, }
}

///|
/// `protocol Container = "id":` — a wire vocabulary, and nothing here touches
/// the spelling of a member.
fn protocol_of_tutu(
  d : @tutufile.Decl,
  doc : String?,
) -> RawDecl raise DefError {
  let at = at_of(d.span)
  guard d.node.it is Group(parts) else {
    raise Syntax(msg="protocol `\{d.name}` has no id", span=at)
  }
  let mut id = ""
  for i in 0..<parts.length() {
    if parts[i].it is Op("=") &&
      i + 1 < parts.length() &&
      parts[i + 1].it is Lit(Str(s)) {
      id = s
    }
  }
  guard id != "" else {
    raise Syntax(
      msg="protocol `\{d.name}` has no id — write `protocol \{d.name} = \"your.domain/\{d.name}@1\":`, the string a second host dispatches by",
      span=at,
    )
  }
  let handle_message : Array[RawCase] = []
  let handle_intent : Array[RawCase] = []
  let express_message : Array[RawCase] = []
  let express_intent : Array[RawCase] = []
  let properties : Array[RawProperty] = []
  let views : Array[RawCase] = []
  let members = @sh.body_groups(d)
  for i, g in members {
    let prev = if i > 0 { Some(members[i - 1]) } else { None }
    guard g.it is Group(gp) && gp.length() > 0 && gp[0].it is Id(word) else {
      continue
    }
    let m = read_one(g, prev)
    match word {
      "message" => handle_message.push(case_of(gp, 1, m, at))
      "intent" => handle_intent.push(case_of(gp, 1, m, at))
      "express" => {
        guard gp.length() >= 2 && gp[1].it is Id(kind) else {
          raise Syntax(
            msg="`express` says which channel it initiates on",
            span=at,
          )
        }
        let c = case_of(gp, 2, m, at)
        if kind == "intent" {
          express_intent.push(c)
        } else {
          express_message.push(c)
        }
      }
      // A protocol's `provide` and `lookup` name a DYNAMIC channel and its
      // type — the same shape as a property, and without `~writable`, which
      // says nothing about a value that travels the tree. They share the
      // `properties` list and are told apart by `section`, the way a
      // component's own bindings are.
      "property" | "provide" | "lookup" => {
        guard m.ty is Some(ty) else {
          raise Syntax(
            msg="a protocol \{word} names a type — write `\{word} <name> :: <Type>`\{if word == "property" { ", and add `~writable` if it can be set" } else { "" }}",
            span=at,
          )
        }
        properties.push({
          section: word,
          name: m.name,
          span: at,
          doc: m.doc,
          ty: ty_of(ty, at),
          // A protocol member is public by definition: it is what a stranger
          // asks by.
          public_: true,
          writable: m.has_option("writable"),
          getter: None,
          setter: None,
        })
      }
      "view" => {
        guard gp.length() >= 2 && gp[1].it is Id(role) else {
          raise Syntax(
            msg="a protocol view names one role — write `view <role>`",
            span=at,
          )
        }
        views.push({ name: role, span: at, doc: m.doc, payload: [], })
      }
      other =>
        raise Syntax(
          msg="`\{other}` is not a protocol member — a protocol declares `message`, `intent`, `express`, `property`, `view`, `provide` and `lookup`",
          span=at,
        )
    }
  }
  {
    ..empty_decl(RProtocol(id), d.name, at, doc),
    handle_message,
    handle_intent,
    express_message,
    express_intent,
    properties,
    views,
  }
}

///|
/// A declaration with nothing in it, for the four kinds to fill in.
fn empty_decl(
  kind : RawKind,
  name : String,
  at : Span,
  doc : String?,
) -> RawDecl {
  {
    kind,
    name,
    name_span: at,
    doc,
    fields: [],
    cases: [],
    handle_message: [],
    handle_intent: [],
    express_message: [],
    express_intent: [],
    properties: [],
    views: [],
    implements: [],
    bindings: [],
    provide: [],
    lookup: [],
    rules: [],
    wheres: [],
    category: "",
    keywords: [],
  }
}
