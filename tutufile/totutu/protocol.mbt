// A protocol, and the lines a component writes to claim one.
//
// A protocol id is a WIRE NAME — `"tutuca.dev/universal/Container@1"`, with the
// `@1` promising it does not move — so nothing here renames anything. The
// LOCAL name is what the notation writes (`implements Container`,
// `Holder::filled`), and the id is what a second host dispatches by; the two
// are related only through the declaration that pairs them.

///|
/// Every protocol the file declares, printed once each.
///
/// A `ProtocolDef` is attached to every component in the file rather than to
/// the one whose block held it, because a protocol is a declaration OF THE
/// FILE — so printing them per component would print each one as many times as
/// the file has components.
pub fn print_protocols(
  defs : Array[@statedef.StateDef],
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let seen = []
  for def in defs {
    for p in def.protocols {
      if seen.contains(p.id) {
        continue
      }
      seen.push(p.id)
      print_protocol(p, out)
      out.write_string("\n")
    }
    for r in def.protocol_imports {
      if seen.contains(r.id) {
        continue
      }
      seen.push(r.id)
      out.write_string("  import protocol \{r.local_name} = \{quote(r.id)}\n\n")
    }
  }
}

///|
/// One `protocol Name = "id":` block.
fn print_protocol(
  p : @statedef.ProtocolDef,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  write_doc(out, p.doc, "  ")
  out.write_string("  protocol \{p.local_name} = \{quote(p.id)}:\n")
  // A protocol's member names are WIRE names — the `@1` in the id promises
  // they do not move — so they are printed exactly as written, the way a
  // component's own qualified `Holder::hold` is.
  for m in p.handle_message {
    write_doc(out, m.doc, "    ")
    out.write_string("    message \{case_sig(m)}\n")
  }
  for m in p.handle_intent {
    write_doc(out, m.doc, "    ")
    out.write_string("    intent \{case_sig(m)}\n")
  }
  for m in p.express_message {
    write_doc(out, m.doc, "    ")
    out.write_string("    express message \{case_sig(m)}\n")
  }
  for m in p.express_intent {
    write_doc(out, m.doc, "    ")
    out.write_string("    express intent \{case_sig(m)}\n")
  }
  for d in p.properties {
    write_doc(out, d.doc, "    ")
    // A protocol property promises an OPERATION, not storage, so `~writable`
    // is the whole of what it says beyond its type.
    let writable = if d.writable { " ~writable" } else { "" }
    out.write_string("    property \{d.name} :: \{print_ty(d.ty)}\{writable}\n")
  }
  for v in p.views {
    out.write_string("    view \{v}\n")
  }
  // A protocol's dynamic channels. Like its properties, these are wire names
  // and a type, and unlike them there is nothing to be writable about.
  for d in p.provides {
    write_doc(out, d.doc, "    ")
    out.write_string("    provide \{d.name} :: \{print_ty(d.ty)}\n")
  }
  for d in p.lookups {
    write_doc(out, d.doc, "    ")
    out.write_string("    lookup \{d.name} :: \{print_ty(d.ty)}\n")
  }
}

///|
/// The local name a component knows a protocol id by.
///
/// `StateDef` stores the ID everywhere — in `implements` and in every binding —
/// because that is what dispatch uses. The notation writes the local name, so
/// the declarations that pair the two are read back into a map.
pub fn local_names(defs : Array[@statedef.StateDef]) -> Map[String, String] {
  let out = Map([])
  for def in defs {
    for p in def.protocols {
      out[p.id] = p.local_name
    }
    for r in def.protocol_imports {
      out[r.id] = r.local_name
    }
  }
  out
}

///|
/// `implements Container` — one line per protocol claimed.
pub fn print_implements(
  def : @statedef.StateDef,
  names : Map[String, String],
  out : StringBuilder,
) -> Unit raise NoSpelling {
  for id in def.implements {
    out.write_string("    implements \{local_of(id, names)}\n")
  }
}

///|
/// `property Holder::filled = filled` and `view Editable::editor = chrome` —
/// the lines that bind a protocol's member to something this component has.
pub fn print_bindings(
  def : @statedef.StateDef,
  names : Map[String, String],
  out : StringBuilder,
) -> Unit raise NoSpelling {
  // Left of the `=` is the protocol's member, a wire name that does not move.
  // Right of it is something THIS component has, and a local name is renamed
  // like every other — the binding has to name what the component now calls it.
  for b in def.property_bindings {
    out.write_string(
      "    property \{local_of(b.protocol_id, names)}::\{b.member_name} = \{@names.snake_of(b.source)}\n",
    )
  }
  for b in def.view_bindings {
    out.write_string(
      "    view \{local_of(b.protocol_id, names)}::\{b.member_name} = \{@names.snake_of(b.source)}\n",
    )
  }
  for b in def.provide_bindings {
    out.write_string(
      "    provide \{local_of(b.protocol_id, names)}::\{b.member_name} = \{expr_text(b.source)}\n",
    )
  }
  for b in def.lookup_bindings {
    out.write_string(
      "    lookup \{local_of(b.protocol_id, names)}::\{b.member_name} = \{expr_text(b.source)}\n",
    )
  }
}

///|
fn local_of(
  id : String,
  names : Map[String, String],
) -> String raise NoSpelling {
  match names.get(id) {
    Some(n) => n
    // Unreachable through the parser, which refuses an unknown protocol before
    // it builds the def — but a name invented here would be a component
    // claiming a protocol nothing declares.
    None =>
      raise NoSpelling(
        what="a protocol id (`\{id}`) with no declaration in this file",
        help="a component names a protocol it declares or imports; nothing here pairs that id with a name",
      )
  }
}
