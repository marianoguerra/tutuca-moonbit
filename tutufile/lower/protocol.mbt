// Protocols, and the members a component binds to them.
//
// A protocol id is a WIRE NAME: `"tutuca.dev/universal/Container@1"` and the
// members under it are what a second host dispatches by, so nothing here
// touches their spelling. `Container::appendCell` stays `appendCell` however
// the rest of the file is written — the `@1` in the id is a promise that the
// names do not move, and a printer that applied a naming convention to them
// would break it silently.

///|
/// A qualified name — `Holder::hold` — if the terms start with one.
pub fn qualified(parts : Array[@ast.Node], from : Int) -> (String, Int)? {
  guard from + 2 < parts.length() else { return None }
  guard parts[from].it is Id(a) else { return None }
  // A protocol name is UpperCamel, which is what tells `Holder::hold` from
  // the `count :: Int` beside it: `::` is one operator in both places, and
  // the terms cannot say which is meant.
  guard is_upper(a) else { return None }
  guard parts[from + 1].it is Op("::") else { return None }
  guard parts[from + 2].it is Id(b) else { return None }
  Some((a + "::" + b, from + 3))
}

///|
/// A member name, qualified or not, and where it ends.
pub fn member_name(parts : Array[@ast.Node], from : Int) -> (String, Int)? {
  match qualified(parts, from) {
    Some(pair) => Some(pair)
    None => {
      guard from < parts.length() && parts[from].it is Id(n) else {
        return None
      }
      Some((n, from + 1))
    }
  }
}

///|
/// One declared case: its name — qualified or not — and its payload types.
pub fn case_text(parts : Array[@ast.Node], from : Int) -> String raise ExError {
  guard member_name(parts, from) is Some((name, next)) else {
    raise ExError(
      message="a channel case is a name",
      help="write `message <name>` or `message <Protocol>::<name>`",
      span=span_of(parts[0]),
    )
  }
  guard next < parts.length() && parts[next].it is Parens(gs) else {
    return name
  }
  let tys = []
  for g in gs {
    tys.push(print_ty(read_group(g)))
  }
  name + "(" + tys.join(", ") + ")"
}

///|
/// `protocol Name = "id":` with its members.
pub fn print_protocol(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  write_doc(out, decl_doc(decl), "")
  guard decl.node.it is Group(parts) else { return }
  guard parts.length() >= 4 && parts[2].it is Op("=") else {
    raise ExError(
      message="protocol `\{decl.name}` has no id",
      help="write `protocol \{decl.name} = \"your.domain/\{decl.name}@1\":` — the id is what a second host dispatches by",
      span=decl.span,
    )
  }
  guard parts[3].it is Lit(Str(id)) else {
    raise ExError(
      message="a protocol id is a quoted string",
      help="write `protocol \{decl.name} = \"your.domain/\{decl.name}@1\":`",
      span=span_of(parts[3]),
    )
  }
  out.write_string("protocol \{decl.name} = \"\{id}\" {\n")
  let messages = []
  let intents = []
  let ex_messages = []
  let ex_intents = []
  let props = []
  let views = []
  for group in body_groups(decl) {
    guard group.it is Group(gp) && gp.length() > 0 && gp[0].it is Id(word) else {
      continue
    }
    write_doc(out, doc_of(group), "  ")
    match word {
      "message" => messages.push(case_text(gp, 1))
      "intent" => intents.push(case_text(gp, 1))
      "express" => {
        guard gp.length() >= 2 && gp[1].it is Id(kind) else {
          raise ExError(
            message="`express` says which channel it initiates on",
            help="write `express message <name>` or `express intent <name>`",
            span=span_of(gp[0]),
          )
        }
        if kind == "intent" {
          ex_intents.push(case_text(gp, 2))
        } else {
          ex_messages.push(case_text(gp, 2))
        }
      }
      "property" => props.push(protocol_property(gp))
      "view" => {
        guard gp.length() >= 2 && gp[1].it is Id(role) else {
          raise ExError(
            message="a protocol view names one role",
            help="write `view <role>` — a role is a view an implementer supplies",
            span=span_of(gp[0]),
          )
        }
        views.push(role)
      }
      other =>
        raise ExError(
          message="`\{other}` is not a protocol member",
          help="a protocol declares `message`, `intent`, `express`, `property` and `view`",
          span=span_of(gp[0]),
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
  out.write_string("}\n")
}

///|
/// A protocol's abstract property: a name, a type, and `set` if it is writable.
fn protocol_property(parts : Array[@ast.Node]) -> String raise ExError {
  guard parts.length() >= 4 &&
    parts[1].it is Id(name) &&
    parts[2].it is Op("::") else {
    raise ExError(
      message="a protocol property names a type",
      help="write `property <name> :: <Type>`, and add `~writable` if it can be set",
      span=span_of(parts[0]),
    )
  }
  let ty = print_ty(read_ex(parts[3:]))
  let writable = has_kw(parts[:], "writable")
  if writable {
    "\{name}: \{ty} set"
  } else {
    "\{name}: \{ty}"
  }
}
