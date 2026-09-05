// The `spec:` section, printed as the block the state parser reads.

///|
/// What a component's properties are implemented with, gathered from the
/// `logic:` section before the spec block is printed.
///
/// The two sections disagree about nothing here — the spec declares the
/// member and the logic gives it a body — but the OLD spelling puts both in
/// one place, so the printer has to have read both before it can write either.
pub(all) struct PropImpl {
  get_ : Bool
  set_ : Bool
}

///|
/// Print one component's `state` declaration.
pub fn print_state(
  decl : @tutufile.Decl,
  impls : Map[String, PropImpl],
  out : StringBuilder,
) -> Unit raise ExError {
  write_doc(out, decl_doc(decl), "")
  out.write_string("state \{decl.name} {\n")
  let props = []
  let rules = []
  let wheres = []
  let provides = []
  let lookups = []
  for group in body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    match word {
      "field" => print_field(read_member(group), out)
      "property" => props.push(read_member(group))
      "pred" | "invariant" => rules.push(read_member(group))
      "where" => wheres.push(group)
      "provide" => provides.push(group)
      "lookup" => lookups.push(group)
      // channels and helper types are declarations of the file, not of the
      // state body, and are printed after it
      "message" | "intent" | "express" | "implements" => ()
      _ =>
        raise ExError(
          message="`\{word}` is not a spec member",
          help="a component declares `field`, `property`, `pred`, `invariant`, `where`, `provide`, `lookup`, `message`, `intent` and `express`",
          span=span_of(parts[0]),
        )
    }
  }
  if !props.is_empty() {
    out.write_string("\n  property {\n")
    for p in props {
      print_property(p, impls, out)
    }
    out.write_string("  }\n")
  }
  for g in provides {
    print_binding_decl(g, "provide", out)
  }
  for g in lookups {
    print_binding_decl(g, "lookup", out)
  }
  for r in rules {
    print_rule(r, out)
  }
  for g in wheres {
    print_where(g, out)
  }
  out.write_string("}\n")
}

///|
/// `field n :: Int = 0` → `n: Int`, with the initialiser dropped into the
/// fixture the old notation would have needed for it.
fn print_field(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "  ")
  guard m.ty is Some(ty) else {
    raise ExError(
      message="`\{m.name}` has no type",
      help="write `field \{m.name} :: <Type>`",
      span=m.span,
    )
  }
  out.write_string("  \{m.name}: \{print_ty(ty)}\n")
}

///|
/// A property, in whichever of the two old spellings its body calls for.
fn print_property(
  m : Member,
  impls : Map[String, PropImpl],
  out : StringBuilder,
) -> Unit raise ExError {
  write_doc(out, m.doc, "    ")
  guard m.ty is Some(ty) else {
    raise ExError(
      message="property `\{m.name}` has no type",
      help="write `property \{m.name} :: <Type>`",
      span=m.span,
    )
  }
  let vis = if m.has_option("public") { "pub " } else { "" }
  // a body written in the spec section is the compact, field-backed form
  let mut accessors = ""
  for g in m.block() {
    let acc = read_member(g)
    let backing = compact_backing(acc)
    match backing {
      Some(field) => accessors = accessors + " \{acc.word} .\{field}"
      None =>
        raise ExError(
          message="a `\{acc.word}` in the spec section reads one field and nothing else",
          help="move the body to the `logic:` section, or write `\{acc.word}: it.<field>`",
          span=acc.span,
        )
    }
  }
  if accessors == "" {
    let impl_ = impls.get(m.name).unwrap_or({ get_: true, set_: false, })
    accessors = " get"
    if impl_.set_ {
      accessors = accessors + " set"
    }
  }
  out.write_string("    \{vis}\{m.name}: \{print_ty(ty)} {\{accessors} }\n")
}

///|
/// The field a one-line accessor reads, if that is all it does.
fn compact_backing(acc : Member) -> String? {
  let groups = acc.block()
  guard groups.length() == 1 else { return None }
  // `set(v): it.f := v` is a write, which is a statement rather than a value,
  // so the field is read off the place instead of out of an expression.
  guard groups[0].it is Group(parts) else { return None }
  let terms = match find_op(parts, [":="]) {
    Some(at) => parts[:at]
    None => parts[:]
  }
  guard terms.length() == 3 && terms[0].it is Id("it") && terms[1].it is Op(".") else {
    return None
  }
  match terms[2].it {
    Id(f) => Some(f)
    _ => None
  }
}

///|
/// `pred` / `invariant`, with `~format` printed where `format` used to sit.
fn print_rule(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "  ")
  out.write_string("  \{m.word} \{m.name}")
  match m.option("format") {
    Some(f) => out.write_string("\n    format \{print_ex(f)}")
    None => ()
  }
  let groups = m.block()
  guard groups.length() == 1 else {
    raise ExError(
      message="a `\{m.word}` is one expression",
      help="write the rule as one boolean — `and` two of them together if it is really two",
      span=m.span,
    )
  }
  out.write_string(" { \{print_ex(read_group(groups[0]))} }\n")
}

///|
/// `provide theme = it.theme` / `lookup color = "gray"`, one per line in the
/// new notation and one section in the old.
fn print_binding_decl(
  group : @ast.Node,
  word : String,
  out : StringBuilder,
) -> Unit raise ExError {
  guard group.it is Group(parts) && parts.length() >= 2 else {
    raise ExError(
      message="a `\{word}` names what it \{if word == "provide" { "publishes" } else { "wants" }}",
      help="write `\{word} <name>`",
      span=span_of(group),
    )
  }
  guard parts[1].it is Id(name) else {
    raise ExError(
      message="a `\{word}` names one binding",
      help="write `\{word} <name>`",
      span=span_of(parts[1]),
    )
  }
  if parts.length() == 2 {
    out.write_string("  \{word} { \{name} }\n")
    return
  }
  guard parts[2].it is Op("=") else {
    raise ExError(
      message="a `\{word}` is a name, or a name and a value",
      help="write `\{word} \{name} = <value>`",
      span=span_of(parts[2]),
    )
  }
  let value = if parts.length() >= 4 && parts[3].it is Id("self") {
    "self"
  } else {
    print_ex(read_ex(parts[3:]))
  }
  out.write_string("  \{word} { \{name} = \{value} }\n")
}

///|
/// A field domain, whose vocabulary is words in both notations.
fn print_where(group : @ast.Node, out : StringBuilder) -> Unit raise ExError {
  guard group.it is Group(parts) && parts.length() >= 2 else {
    raise ExError(
      message="a `where` states a relation",
      help="write `where it.<field> <relation> <target>`",
      span=span_of(group),
    )
  }
  let terms = parts[1:]
  let or_none = has_kw(terms, "or_none")
  let words = []
  let mut i = 0
  while i < terms.length() {
    let t = terms[i]
    match t.it {
      Kw(_) => i = i + 1
      Id("it") =>
        if i + 2 < terms.length() && terms[i + 1].it is Op(".") {
          let field = node_text(terms[i + 2])
          // the SUBJECT is bare and every other field read carries its dot
          words.push(if words.is_empty() { field } else { "." + field })
          i = i + 3
        } else {
          i = i + 1
        }
      Id(w) => {
        words.push(where_word(w))
        i = i + 1
      }
      Op(o) => {
        words.push(o)
        i = i + 1
      }
      Lit(Str(s)) => {
        words.push(quote_str(s))
        i = i + 1
      }
      Lit(_) => {
        words.push(print_ex(read_group(t)))
        i = i + 1
      }
      Brackets(gs) => {
        let items = []
        for g in gs {
          items.push(print_ex(read_group(g)))
        }
        words.push("[" + items.join(", ") + "]")
        i = i + 1
      }
      Parens(gs) => {
        // `in_range(0, 100)` is the one relation written as a call
        let items = []
        for g in gs {
          items.push(print_ex(read_group(g)))
        }
        guard items.length() == 2 && words.length() >= 1 else {
          raise ExError(
            message="`in_range` takes a low and a high bound",
            help="write `where it.n in_range(0, 100)`",
            span=span_of(t),
          )
        }
        let _ = words.pop()
        words.push("between \{items[0]} and \{items[1]}")
        i = i + 1
      }
      _ => i = i + 1
    }
  }
  let tail = if or_none { " or none" } else { "" }
  out.write_string("  where \{words.join(" ")}\{tail}\n")
}

///|
/// The relation a domain word spells in the old notation.
fn where_word(w : String) -> String {
  match w {
    "is_index_of" => "is index of"
    "is_key_of" => "is key of"
    "is_member_of" => "is member of"
    "is_subset_of" => "is subset of"
    "is_one_of" => "is one of"
    "in_range" => "between"
    other => other
  }
}

///|
fn has_kw(terms : ArrayView[@ast.Node], name : String) -> Bool {
  for t in terms {
    if t.it is Kw(n) && n == name {
      return true
    }
  }
  false
}

///|
/// `struct Line(what :: String)` → `struct Line { what: String }`.
pub fn print_struct(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  write_doc(out, decl_doc(decl), "")
  guard decl.node.it is Group(parts) && parts.length() >= 3 else {
    raise ExError(
      message="`\{decl.name}` declares no fields",
      help="write `struct \{decl.name}(what :: String, qty :: Int)`",
      span=decl.span,
    )
  }
  guard parts[2].it is Parens(gs) else {
    raise ExError(
      message="`\{decl.name}` declares no fields",
      help="write `struct \{decl.name}(what :: String, qty :: Int)`",
      span=decl.span,
    )
  }
  let fields = []
  for g in gs {
    let p = read_param(g)
    guard p.ty is Some(ty) else {
      raise ExError(
        message="field `\{p.name}` of `\{decl.name}` has no type",
        help="write `\{p.name} :: <Type>`",
        span=span_of(g),
      )
    }
    fields.push("\{p.name}: \{print_ty(ty)}")
  }
  out.write_string("struct \{decl.name} { \{fields.join(", ")} }\n")
}

///|
/// `enum Priority:` with one case per line → `enum Priority { low, high }`.
pub fn print_enum(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  write_doc(out, decl_doc(decl), "")
  let cases = []
  for g in body_groups(decl) {
    guard g.it is Group(parts) && parts.length() >= 1 && parts[0].it is Id(c) else {
      raise ExError(
        message="an enum case is a name",
        help="write one case per line under `enum \{decl.name}:`",
        span=span_of(g),
      )
    }
    cases.push(c)
  }
  out.write_string("enum \{decl.name} { \{cases.join(", ")} }\n")
}

///|
/// The `handle` and `express` blocks, gathered from the component's own
/// `message` / `intent` / `express` lines.
pub fn print_channels(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  let messages = []
  let intents = []
  let ex_messages = []
  let ex_intents = []
  for group in body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    match word {
      "message" => messages.push(channel_case(read_member(group)))
      "intent" => intents.push(channel_case(read_member(group)))
      "express" => {
        guard parts.length() >= 2 && parts[1].it is Id(kind) else {
          raise ExError(
            message="`express` says which channel it initiates on",
            help="write `express message <name>` or `express intent <name>`",
            span=span_of(parts[0]),
          )
        }
        let inner = read_member(drop_head(group))
        if kind == "intent" {
          ex_intents.push(channel_case(inner))
        } else {
          ex_messages.push(channel_case(inner))
        }
      }
      _ => ()
    }
  }
  if !messages.is_empty() || !intents.is_empty() {
    out.write_string("handle \{decl.name} {\n")
    if !messages.is_empty() {
      out.write_string("  message { \{messages.join(", ")} }\n")
    }
    if !intents.is_empty() {
      out.write_string("  intent { \{intents.join(", ")} }\n")
    }
    out.write_string("}\n")
  }
  if !ex_messages.is_empty() || !ex_intents.is_empty() {
    out.write_string("express \{decl.name} {\n")
    if !ex_messages.is_empty() {
      out.write_string("  message { \{ex_messages.join(", ")} }\n")
    }
    if !ex_intents.is_empty() {
      out.write_string("  intent { \{ex_intents.join(", ")} }\n")
    }
    out.write_string("}\n")
  }
}

///|
/// One declared case: its name, and the payload types it carries.
fn channel_case(m : Member) -> String raise ExError {
  if m.params.is_empty() {
    return m.name
  }
  let tys = []
  for p in m.params {
    guard p.ty is Some(ty) else {
      raise ExError(
        message="a declared payload names its type",
        help="write `message \{m.name}(Int)` — a payload is decoded at the boundary",
        span=m.span,
      )
    }
    tys.push(print_ty(ty))
  }
  m.name + "(" + tys.join(", ") + ")"
}

///|
/// The same group with its first term removed, for `express intent x`.
fn drop_head(group : @ast.Node) -> @ast.Node {
  match group.it {
    Group(parts) => @ast.Node::new(Group(parts[1:].to_owned()), group.span)
    _ => group
  }
}

///|
/// The groups inside a declaration's block.
pub fn body_groups(decl : @tutufile.Decl) -> Array[@ast.Node] {
  match decl.body {
    Some(node) =>
      match node.it {
        Block(gs) => gs
        _ => []
      }
    None => []
  }
}

///|
/// The `///` above a declaration.
pub fn decl_doc(decl : @tutufile.Decl) -> String? {
  doc_of(decl.node)
}

///|
/// Print a doc comment, if there is one.
pub fn write_doc(out : StringBuilder, doc : String?, indent : String) -> Unit {
  match doc {
    Some(text) =>
      for line in text.split("\n") {
        out.write_string("\{indent}/// \{line}\n")
      }
    None => ()
  }
}
