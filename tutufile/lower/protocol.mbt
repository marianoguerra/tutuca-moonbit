// Protocols, printed back into the block the old state language read.

///|
/// One declared case: its name — qualified or not — and its payload types.
pub fn case_text(
  parts : Array[@ast.Node],
  from : Int,
) -> String raise @sh.ExError {
  guard @sh.member_name(parts, from) is Some((name, next)) else {
    raise @sh.ExError(
      message="a channel case is a name",
      help="write `message <name>` or `message <Protocol>::<name>`",
      span=@sh.span_of(parts[0]),
    )
  }
  guard next < parts.length() && parts[next].it is Parens(gs) else {
    return name
  }
  let tys = []
  for g in gs {
    tys.push(print_ty(@sh.read_group(g)))
  }
  name + "(" + tys.join(", ") + ")"
}

///|
/// `protocol Name = "id":` with its members.
pub fn print_protocol(
  decl : @tutufile.Decl,
  out : StringBuilder,
  doc? : String?,
) -> Unit raise @sh.ExError {
  // A doc between two declarations attaches to the FIRST one's suffix, so the
  // caller — which has the predecessor in hand — is the only one that can read
  // it. `decl_doc` alone sees a protocol's own leading doc and nothing else,
  // which is right for the first declaration in a section and wrong for the
  // rest.
  write_doc(out, doc.unwrap_or(@sh.decl_doc(decl)), "")
  guard decl.node.it is Group(parts) else { return }
  guard parts.length() >= 4 && parts[2].it is Op("=") else {
    raise @sh.ExError(
      message="protocol `\{decl.name}` has no id",
      help="write `protocol \{decl.name} = \"your.domain/\{decl.name}@1\":` — the id is what a second host dispatches by",
      span=decl.span,
    )
  }
  guard parts[3].it is Lit(Str(id)) else {
    raise @sh.ExError(
      message="a protocol id is a quoted string",
      help="write `protocol \{decl.name} = \"your.domain/\{decl.name}@1\":`",
      span=@sh.span_of(parts[3]),
    )
  }
  out.write_string("protocol \{decl.name} = \"\{id}\" {\n")
  let messages = []
  let intents = []
  let ex_messages = []
  let ex_intents = []
  let props = []
  let views = []
  let provides = []
  let lookups = []
  for group in @sh.body_groups(decl) {
    guard group.it is Group(gp) && gp.length() > 0 && gp[0].it is Id(word) else {
      continue
    }
    write_doc(out, @sh.doc_of(group), "  ")
    match word {
      "message" => messages.push(case_text(gp, 1))
      "intent" => intents.push(case_text(gp, 1))
      "express" => {
        guard gp.length() >= 2 && gp[1].it is Id(kind) else {
          raise @sh.ExError(
            message="`express` says which channel it initiates on",
            help="write `express message <name>` or `express intent <name>`",
            span=@sh.span_of(gp[0]),
          )
        }
        if kind == "intent" {
          ex_intents.push(case_text(gp, 2))
        } else {
          ex_messages.push(case_text(gp, 2))
        }
      }
      "property" => props.push(protocol_property(gp))
      // A protocol's `provide` and `lookup` name a dynamic channel and its
      // type — the same shape as a property, and without `~writable`, which
      // says nothing about a value that travels the tree.
      "provide" => provides.push(protocol_channel(gp, "provide"))
      "lookup" => lookups.push(protocol_channel(gp, "lookup"))
      "view" => {
        guard gp.length() >= 2 && gp[1].it is Id(role) else {
          raise @sh.ExError(
            message="a protocol view names one role",
            help="write `view <role>` — a role is a view an implementer supplies",
            span=@sh.span_of(gp[0]),
          )
        }
        views.push(role)
      }
      other =>
        raise @sh.ExError(
          message="`\{other}` is not a protocol member",
          help="a protocol declares `message`, `intent`, `express`, `property`, `view`, `provide` and `lookup`",
          span=@sh.span_of(gp[0]),
        )
    }
  }
  if !messages.is_empty() || !intents.is_empty() {
    out.write_string("  handle {\n")
    if !messages.is_empty() {
      out.write_string("    message { \{messages.join(", ")} }\n")
    }
    if !intents.is_empty() {
      out.write_string("    intent { \{intents.join(", ")} }\n")
    }
    out.write_string("  }\n")
  }
  if !ex_messages.is_empty() || !ex_intents.is_empty() {
    out.write_string("  express {\n")
    if !ex_messages.is_empty() {
      out.write_string("    message { \{ex_messages.join(", ")} }\n")
    }
    if !ex_intents.is_empty() {
      out.write_string("    intent { \{ex_intents.join(", ")} }\n")
    }
    out.write_string("  }\n")
  }
  if !props.is_empty() {
    out.write_string("  property { \{props.join(", ")} }\n")
  }
  if !views.is_empty() {
    out.write_string("  view { \{views.join(", ")} }\n")
  }
  if !provides.is_empty() {
    out.write_string("  provide { \{provides.join(", ")} }\n")
  }
  if !lookups.is_empty() {
    out.write_string("  lookup { \{lookups.join(", ")} }\n")
  }
  out.write_string("}\n")
}

///|
/// A protocol's abstract property: a name, a type, and `set` if it is writable.
fn protocol_property(parts : Array[@ast.Node]) -> String raise @sh.ExError {
  guard parts.length() >= 4 &&
    parts[1].it is Id(name) &&
    parts[2].it is Op("::") else {
    raise @sh.ExError(
      message="a protocol property names a type",
      help="write `property <name> :: <Type>`, and add `~writable` if it can be set",
      span=@sh.span_of(parts[0]),
    )
  }
  let ty = print_ty(@sh.read_ex(parts[3:]))
  let writable = has_kw(parts[:], "writable")
  if writable {
    "\{name}: \{ty} set"
  } else {
    "\{name}: \{ty}"
  }
}

///|
/// A protocol's `provide` or `lookup`: a name and the type that travels.
fn protocol_channel(
  parts : Array[@ast.Node],
  word : String,
) -> String raise @sh.ExError {
  guard parts.length() >= 4 &&
    parts[1].it is Id(name) &&
    parts[2].it is Op("::") else {
    raise @sh.ExError(
      message="a protocol `\{word}` names a type",
      help="write `\{word} <name> :: <Type>`",
      span=@sh.span_of(parts[0]),
    )
  }
  "\{name}: \{print_ty(@sh.read_ex(parts[3:]))}"
}
