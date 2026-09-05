// The `logic:` section, printed as the block the script parser reads.

///|
/// Print one component's handlers, and answer what its properties implement
/// so the spec block can be printed to match.
pub fn print_logic(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Map[String, PropImpl] raise ExError {
  let impls = {}
  for group in body_groups(decl) {
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    let m = read_member(group)
    match word {
      "receive" | "answer" => print_transition(m, out)
      "compute" => print_compute(m, out)
      "pred" => print_row_pred(m, out)
      "enrich" => print_enrich(m, out)
      "bind_with" => print_bind_with(m, out)
      "property" => impls[m.name] = print_accessors(m, out)
      _ =>
        raise ExError(
          message="`\{word}` is not a logic member",
          help="a component's behaviour is `receive`, `answer`, `compute`, `pred`, `enrich`, `bind_with` and `property`",
          span=span_of(parts[0]),
        )
    }
  }
  impls
}

///|
/// `receive` / `answer`, with the contract options where the clauses used to
/// sit on the header.
fn print_transition(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "")
  out.write_string(m.word + " " + m.name)
  if !m.params.is_empty() {
    let names = []
    for p in m.params {
      names.push(p.name)
    }
    out.write_string("(" + names.join(", ") + ")")
  }
  match m.option("requires") {
    Some(EName(r)) => out.write_string(" requires " + r)
    Some(_) =>
      raise ExError(
        message="`~requires` names a rule",
        help="declare the rule with `pred` in the spec section and name it here",
        span=m.span,
      )
    None => ()
  }
  match m.option("ensures") {
    Some(EName(r)) => out.write_string(" ensures " + r)
    Some(_) =>
      raise ExError(
        message="`~ensures` names a rule",
        help="declare the rule with `pred` in the spec section and name it here",
        span=m.span,
      )
    None => ()
  }
  out.write_string(" {\n")
  print_body(m, out, {})
  out.write_string("}\n\n")
}

///|
/// A parameterised derivation.
fn print_compute(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "")
  out.write_string("compute " + m.name)
  if !m.params.is_empty() {
    let names = []
    for p in m.params {
      names.push(p.name)
    }
    out.write_string("(" + names.join(", ") + ")")
  }
  out.write_string(" {\n")
  print_value_body(m, out, {})
  out.write_string("}\n\n")
}

///|
/// A row filter. Its parameters are what the renderer hands it, so they are
/// renamed to the bindings the old notation reads them out of.
fn print_row_pred(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "")
  out.write_string("pred " + m.name + " {\n")
  print_value_body(m, out, row_renames(m))
  out.write_string("}\n\n")
}

///|
/// An in-loop enricher: its statements are bindings rather than writes.
fn print_enrich(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "")
  out.write_string("enrich " + m.name + " {\n")
  print_binds(m, out, row_renames(m))
  out.write_string("}\n\n")
}

///|
/// The scope form, which is handed no row.
fn print_bind_with(m : Member, out : StringBuilder) -> Unit raise ExError {
  write_doc(out, m.doc, "")
  out.write_string("bindWith " + m.name + " {\n")
  print_binds(m, out, {})
  out.write_string("}\n\n")
}

///|
/// `item, i` are the renderer's row and key, whatever the loop called them.
fn row_renames(m : Member) -> Map[String, String] {
  let out = {}
  if m.params.length() > 0 {
    out[m.params[0].name] = "@value"
  }
  if m.params.length() > 1 {
    out[m.params[1].name] = "@key"
  }
  if m.params.length() > 2 {
    out[m.params[2].name] = "@iter"
  }
  out
}

///|
/// A property's accessors, and what they add up to for the spec block.
fn print_accessors(m : Member, out : StringBuilder) -> PropImpl raise ExError {
  let mut has_get = false
  let mut has_set = false
  for g in m.block() {
    let acc = read_member(g)
    match acc.word {
      "get" => {
        has_get = true
        write_doc(out, m.doc, "")
        out.write_string("get " + m.name + " {\n")
        print_value_body(acc, out, {})
        out.write_string("}\n\n")
      }
      "set" => {
        has_set = true
        // the old notation's setter takes one implicit `value`
        let renames = {}
        if acc.params.length() > 0 {
          renames[acc.params[0].name] = "value"
        }
        out.write_string("set " + m.name + " {\n")
        print_body(acc, out, renames)
        out.write_string("}\n\n")
      }
      other =>
        raise ExError(
          message="`\{other}` is not a property accessor",
          help="a property has a `get` and, if it is writable, a `set`",
          span=acc.span,
        )
    }
  }
  { get_: has_get || !has_set, set_: has_set, }
}

///|
/// A body that is one VALUE rather than a sequence of steps: a `get`, a
/// `compute`, a `pred`. The old notation writes the same thing between the
/// same braces, so what changes is only that this one is an expression.
fn print_value_body(
  m : Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise ExError {
  let groups = m.block()
  guard groups.length() == 1 else {
    raise ExError(
      message="a `\{m.word}` answers one value",
      help="write one expression — a body with steps in it is a `receive`",
      span=m.span,
    )
  }
  let ex = rename_ex(read_group(groups[0]), renames)
  out.write_string("  " + print_ex(ex) + "\n")
}

///|
/// Every statement of a member's block.
fn print_body(
  m : Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise ExError {
  for g in m.block() {
    print_stmt(g, out, "  ", renames)
  }
}

///|
/// An enricher's block: `name = value` becomes `@name = value`.
fn print_binds(
  m : Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise ExError {
  for g in m.block() {
    guard g.it is Group(parts) else { continue }
    let split = find_op(parts, ["="])
    guard split is Some(at) && parts[0].it is Id(name) else {
      raise ExError(
        message="an enricher binds names to values",
        help="write `<name> = <value>`",
        span=span_of(g),
      )
    }
    let value = rename_ex(read_ex(parts[at + 1:]), renames)
    out.write_string("  @\{name} = \{print_ex(value)}\n")
  }
}

///|
/// One statement.
pub fn print_stmt(
  group : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 else { return }
  // an `if` statement keeps its two arms
  if parts[0].it is Id("if") && parts[parts.length() - 1].it is Alts(arms) {
    guard arms.length() == 2 else {
      raise ExError(
        message="an `if` takes exactly two arms",
        help="write `if <cond> | <then> | <else>`",
        span=span_of(group),
      )
    }
    let cond = rename_ex(read_ex(parts[1:parts.length() - 1]), renames)
    out.write_string("\{indent}if (\{print_ex(cond)}) {\n")
    print_arm(arms[0], out, indent + "  ", renames)
    out.write_string("\{indent}} else {\n")
    print_arm(arms[1], out, indent + "  ", renames)
    out.write_string("\{indent}}\n")
    return
  }
  match find_op(parts, [":=", "+=", "-=", "*=", "/="]) {
    Some(at) => {
      let op = match parts[at].it {
        Op(o) => o
        _ => ":="
      }
      let place = rename_ex(read_ex(parts[:at]), renames)
      let value = rename_ex(read_ex(parts[at + 1:]), renames)
      let word = if op == ":=" { "=" } else { op }
      let hoisted = hoist(value, out, indent)
      out.write_string(
        "\{indent}\{print_place(place)} \{word} \{print_ex(hoisted)}\n",
      )
    }
    None => print_call_stmt(read_ex(parts[:]), out, indent, renames)
  }
}

///|
fn print_arm(
  node : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise ExError {
  guard node.it is Block(gs) else { return }
  for g in gs {
    print_stmt(g, out, indent, renames)
  }
}

///|
/// A statement that is a call: a collection operation, or an effect.
fn print_call_stmt(
  ex : Ex,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise ExError {
  let ex = rename_ex(ex, renames)
  guard ex is ECall(callee, args) else {
    raise ExError(
      message="a statement is a write, a collection operation or an effect",
      help="a bare value does nothing — write `it.x := <value>` to keep it",
      span=@report.Span::at(0),
    )
  }
  match callee {
    EName(verb) => print_effect(verb, args, out, indent)
    EMember(recv, method) => {
      guard collection_op(method) is Some(word) else {
        raise ExError(
          message="`\{method}` is not a collection operation",
          help="the operations are `push`, `insert_at`, `set_at`, `delete_at`, `add`, `remove` and `toggle`",
          span=@report.Span::at(0),
        )
      }
      let pos = positional(args)
      let printed = []
      for a in pos {
        printed.push(print_ex(hoist(a, out, indent)))
      }
      let tail = if printed.is_empty() { "" } else { " " + printed.join(" ") }
      out.write_string("\{indent}\{print_place(recv)}.\{word}\{tail}\n")
    }
    _ =>
      raise ExError(
        message="only a name or a place can be called as a statement",
        help="write `send(…)`, `ask(…)`, or `it.<field>.<operation>(…)`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The old spelling of a collection operation.
fn collection_op(name : String) -> String? {
  match name {
    "push" => Some("push")
    "insert_at" => Some("insertAt")
    "set_at" => Some("setAt")
    "delete_at" => Some("deleteAt")
    "add" => Some("add")
    "remove" => Some("remove")
    "toggle" => Some("toggle")
    _ => None
  }
}

///|
/// The effect verbs, with the route and the target that decorated them.
fn print_effect(
  verb : String,
  args : Array[Arg],
  out : StringBuilder,
  indent : String,
) -> Unit raise ExError {
  let pos = positional(args)
  let printed = []
  for a in pos {
    printed.push(print_ex(hoist(a, out, indent)))
  }
  let rest = if printed.length() > 1 {
    " " + printed[1:].to_array().join(" ")
  } else {
    ""
  }
  let name = if printed.is_empty() { "" } else { printed[0] }
  match verb {
    "send" =>
      match kw_arg(args, "to") {
        Some(place) =>
          out.write_string(
            "\{indent}sendAt &\{print_place(place)} \{name}\{rest}\n",
          )
        None => out.write_string("\{indent}send \{name}\{rest}\n")
      }
    "ask" | "notify" => {
      let route = match kw_arg(args, "route") {
        Some(r) => " " + route_words(r)
        None => ""
      }
      out.write_string("\{indent}\{verb}\{route} \{name}\{rest}\n")
    }
    "reply" | "fail" =>
      out.write_string(
        "\{indent}\{verb}\{if printed.is_empty() { "" } else { " " + printed.join(" ") }}\n",
      )
    "forward" | "drop" => out.write_string("\{indent}\{verb}\n")
    other =>
      raise ExError(
        message="`\{other}` is not an effect",
        help="the effects are `send`, `ask`, `notify`, `reply`, `fail`, `forward` and `drop`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// `~route: dyn` or `~route: [lex, dyn]` — legs in the order written.
fn route_words(ex : Ex) -> String raise ExError {
  match ex {
    EName(leg) => leg
    EList(legs) => {
      let out = []
      for l in legs {
        match l {
          EName(n) => out.push(n)
          _ =>
            raise ExError(
              message="a route is a list of legs",
              help="the legs are `dyn` and `lex`",
              span=@report.Span::at(0),
            )
        }
      }
      out.join(" ")
    }
    _ =>
      raise ExError(
        message="a route is a leg or a list of legs",
        help="write `~route: dyn`, `~route: lex`, or `~route: [lex, dyn]`",
        span=@report.Span::at(0),
      )
  }
}

///|
fn kw_arg(args : Array[Arg], name : String) -> Ex? {
  for a in args {
    if a is AKw(n, v) && n == name {
      return Some(v)
    }
  }
  None
}

///|
/// A PLACE, which is what a write and a receiver address.
fn print_place(ex : Ex) -> String raise ExError {
  match ex {
    EIt(f) => "." + f
    EState(f) => "state." + f
    EIndex(base, k) => print_place(base) + "[" + print_ex(k) + "]"
    EMember(EIt(f), m) => "." + f + "." + m
    _ => print_ex(ex)
  }
}

///|
/// Lift a constructor call out of an expression into the `new` / `cur` block
/// the old notation builds an aggregate with.
///
/// The value language has no aggregate literal there — a value is built by
/// mutating a target — so a constructor call becomes the target and the writes
/// that fill it, and what is left in the expression is the target itself.
fn hoist(ex : Ex, out : StringBuilder, indent : String) -> Ex raise ExError {
  guard ex is ECall(EName(name), args) else { return ex }
  guard is_upper(name) else { return ex }
  out.write_string("\{indent}new \{name}\n")
  for a in args {
    match a {
      AField(field, value) => {
        guard !(value is ECall(EName(_), _)) else {
          raise ExError(
            message="a constructor inside a constructor cannot be built here",
            help="build the inner one first and write it into a field, then build the outer",
            span=@report.Span::at(0),
          )
        }
        out.write_string("\{indent}cur.\{field} = \{print_ex(value)}\n")
      }
      AKw(k, _) =>
        raise ExError(
          message="`~\{k}` is not a field of `\{name}`",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
      APos(_) =>
        raise ExError(
          message="`\{name}` is built by naming its fields",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
      AFlag(f) =>
        raise ExError(
          message="`~\{f}` is not a field of `\{name}`",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
    }
  }
  EName("cur")
}

///|
fn is_upper(name : String) -> Bool {
  guard name.length() > 0 else { return false }
  let c = name.get_char(0)
  c is Some(ch) && ch >= 'A' && ch <= 'Z'
}

///|
/// The index of the first top-level operator from a set.
fn find_op(parts : Array[@ast.Node], ops : Array[String]) -> Int? {
  let mut i = 0
  while i < parts.length() {
    if parts[i].it is Op(o) && ops.contains(o) {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Rewrite the names a body was written with into the ones the renderer
/// hands it.
pub fn rename_ex(ex : Ex, renames : Map[String, String]) -> Ex {
  if renames.is_empty() {
    return ex
  }
  match ex {
    EName(n) =>
      match renames.get(n) {
        Some(to) => if to.has_prefix("@") { EName(to) } else { EName(to) }
        None => ex
      }
    EMember(base, m) =>
      match base {
        EName(n) =>
          match renames.get(n) {
            Some(to) => EMember(EName(to), m)
            None => EMember(rename_ex(base, renames), m)
          }
        _ => EMember(rename_ex(base, renames), m)
      }
    EIndex(a, b) => EIndex(rename_ex(a, renames), rename_ex(b, renames))
    ECall(c, args) => {
      let out = []
      for a in args {
        out.push(
          match a {
            APos(e) => APos(rename_ex(e, renames))
            AKw(k, e) => AKw(k, rename_ex(e, renames))
            AField(k, e) => AField(k, rename_ex(e, renames))
            AFlag(_) => a
          },
        )
      }
      ECall(rename_ex(c, renames), out)
    }
    EBin(op, a, b) => EBin(op, rename_ex(a, renames), rename_ex(b, renames))
    EUn(op, a) => EUn(op, rename_ex(a, renames))
    EIf(c, a, b) =>
      EIf(rename_ex(c, renames), rename_ex(a, renames), rename_ex(b, renames))
    ETemplate(parts) => {
      let out = []
      for p in parts {
        out.push(
          match p {
            TText(t) => TText(t)
            THole(e) => THole(rename_ex(e, renames))
          },
        )
      }
      ETemplate(out)
    }
    EList(xs) => {
      let out = []
      for x in xs {
        out.push(rename_ex(x, renames))
      }
      EList(out)
    }
    _ => ex
  }
}
