// The `logic:` section, printed as the block the script parser reads.

///|
/// Print one component's handlers, and answer what its properties implement
/// so the spec block can be printed to match.
pub fn print_logic(
  decl : @tutufile.Decl,
  out : StringBuilder,
  rows? : Array[String] = [],
) -> Map[String, PropImpl] raise @sh.ExError {
  let impls = Map([])
  // See `member_doc`: a doc comment sits on the suffix of the member BEFORE the
  // one it documents, so reading a handler's doc needs its predecessor.
  let members = @sh.body_groups(decl)
  for at, group in members {
    let prev = if at > 0 { Some(members[at - 1]) } else { None }
    guard group.it is Group(parts) && parts.length() > 0 else { continue }
    guard parts[0].it is Id(word) else { continue }
    let m = @sh.read_member(group, prev~)
    // Everything below prints an expression, which has no span of its own —
    // so a failure is re-raised against the member it was printing, which is
    // the narrowest place that does have one.
    let m = { ..m, span: @sh.span_of(group), }
    try {
      match word {
        "receive" | "answer" => print_transition(m, out)
        "compute" => print_compute(m, out)
        "pred" => print_row_pred(m, out, rows)
        // An `invariant` here is the one the OLD notation writes in the script
        // block: checked after every dispatch, and — unlike one in `spec:` —
        // not projected into `spec_source`, so the schema does not carry it.
        // Two homes, two meanings, and a file has to be able to say either.
        "invariant" => print_row_pred(m, out, rows, word="invariant")
        "enrich" => print_enrich(m, out, rows)
        "bind_with" => print_bind_with(m, out)
        "property" => impls[m.name] = print_accessors(m, out)
        _ =>
          raise @sh.ExError(
            message="`\{word}` is not a logic member",
            help="a component's behaviour is `receive`, `answer`, `compute`, `pred`, `invariant`, `enrich`, `bind_with` and `property`",
            span=@sh.span_of(parts[0]),
          )
      }
    } catch {
      e => raise at_span(e, m.span)
    }
  }
  impls
}

///|
/// Re-raise a failure against a place, when it has none of its own.
///
/// A printer works over an expression and an expression carries no span, so
/// the enclosing declaration is the narrowest thing that can point anywhere.
/// Better the right line than the first one.
pub fn at_span(e : @sh.ExError, at : @report.Span) -> @sh.ExError {
  let @sh.ExError(message~, help~, span~) = e
  if span.start == 0 && span.len == 0 {
    @sh.ExError(message~, help~, span=at)
  } else {
    e
  }
}

///|
/// `receive` / `answer`, with the contract options where the clauses used to
/// sit on the header.
fn print_transition(
  m : @sh.Member,
  out : StringBuilder,
) -> Unit raise @sh.ExError {
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
    Some(@sh.EName(r)) => out.write_string(" requires " + r)
    Some(_) =>
      raise @sh.ExError(
        message="`~requires` names a rule",
        help="declare the rule with `pred` in the spec section and name it here",
        span=m.span,
      )
    None => ()
  }
  match m.option("ensures") {
    Some(@sh.EName(r)) => out.write_string(" ensures " + r)
    Some(_) =>
      raise @sh.ExError(
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
fn print_compute(m : @sh.Member, out : StringBuilder) -> Unit raise @sh.ExError {
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
fn print_row_pred(
  m : @sh.Member,
  out : StringBuilder,
  rows : Array[String],
  word? : String = "pred",
) -> Unit raise @sh.ExError {
  write_doc(out, m.doc, "")
  // A row filter takes no parameters in the old notation — it reads the row out
  // of the air — so the names that ARE the row are not written back out.
  out.write_string(word + " " + m.name + param_text(m, rows))
  // `~format:` is what the rule SAYS when it declines, and a rule declared
  // here carries one exactly as one in `spec:` does. Dropping it left a
  // refusal with nothing to report.
  match m.option("format") {
    Some(f) => out.write_string("\n  format " + print_ex(f))
    None => ()
  }
  out.write_string(" {\n")
  print_value_body(m, out, row_renames(m, rows))
  out.write_string("}\n\n")
}

///|
/// A member's parameter list, or nothing when its parameters are the row.
fn param_text(m : @sh.Member, rows : Array[String]) -> String {
  if rows.contains(m.name) || m.params.is_empty() {
    return ""
  }
  let names = []
  for p in m.params {
    names.push(p.name)
  }
  "(" + names.join(", ") + ")"
}

///|
/// An in-loop enricher: its statements are bindings rather than writes.
fn print_enrich(
  m : @sh.Member,
  out : StringBuilder,
  rows : Array[String],
) -> Unit raise @sh.ExError {
  write_doc(out, m.doc, "")
  out.write_string("enrich " + m.name + " {\n")
  print_binds(m, out, row_renames(m, rows))
  out.write_string("}\n\n")
}

///|
/// The scope form, which is handed no row.
fn print_bind_with(
  m : @sh.Member,
  out : StringBuilder,
) -> Unit raise @sh.ExError {
  write_doc(out, m.doc, "")
  out.write_string("bindWith " + m.name + " {\n")
  print_binds(m, out, {})
  out.write_string("}\n\n")
}

///|
/// `item, i` are the renderer's row and key, whatever the loop called them.
fn row_renames(m : @sh.Member, rows : Array[String]) -> Map[String, String] {
  let out = Map([])
  guard rows.contains(m.name) else { return out }
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
fn print_accessors(
  m : @sh.Member,
  out : StringBuilder,
) -> PropImpl raise @sh.ExError {
  let mut has_get = false
  let mut has_set = false
  for g in m.block() {
    let acc = @sh.read_member(g)
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
        let renames = Map([])
        if acc.params.length() > 0 {
          renames[acc.params[0].name] = "value"
        }
        out.write_string("set " + m.name + " {\n")
        print_body(acc, out, renames)
        out.write_string("}\n\n")
      }
      other =>
        raise @sh.ExError(
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
  m : @sh.Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  let groups = m.block()
  guard groups.length() == 1 else {
    raise @sh.ExError(
      message="a `\{m.word}` answers one value",
      help="write one expression — a body with steps in it is a `receive`",
      span=m.span,
    )
  }
  let ex = rename_ex(@sh.read_group(groups[0]), renames)
  out.write_string("  " + print_ex(ex) + "\n")
}

///|
/// Every statement of a member's block.
fn print_body(
  m : @sh.Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  for g in m.block() {
    print_stmt(g, out, "  ", renames)
  }
}

///|
/// An enricher's block: `name = value` becomes `@name = value`.
fn print_binds(
  m : @sh.Member,
  out : StringBuilder,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  for g in m.block() {
    guard g.it is Group(parts) else { continue }
    let split = @sh.find_op(parts, ["="])
    guard split is Some(at) && parts[0].it is Id(name) else {
      raise @sh.ExError(
        message="an enricher binds names to values",
        help="write `<name> = <value>`",
        span=@sh.span_of(g),
      )
    }
    let value = rename_ex(@sh.read_ex(parts[at + 1:]), renames)
    out.write_string("  @\{name} = \{print_ex(value)}\n")
    // A name this body bound is a BINDING from here on: a later line reading
    // it reads the bind, not a free name. The old notation wrote the sigil on
    // both sides, so the read has to carry it back too.
    renames[name] = "@" + name
  }
}

///|
/// One statement.
pub fn print_stmt(
  group : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  guard group.it is Group(parts) && parts.length() > 0 else { return }
  // an `if` statement keeps its two arms
  // An `if` STATEMENT takes one arm or two. Two is the shape a value `if` has,
  // and one is the shape a statement often has and a value never can: a
  // conditional write with nothing to do otherwise. Refusing the one-armed form
  // would leave the commonest branch in the block language with no spelling.
  if parts[0].it is Id("if") && parts[parts.length() - 1].it is Alts(arms) {
    guard arms.length() is (1 | 2) else {
      raise @sh.ExError(
        message="an `if` takes one arm or two, and this has \{arms.length()}",
        help="write `if <cond> | <then>`, or `if <cond> | <then> | <else>`",
        span=@sh.span_of(group),
      )
    }
    let cond = rename_ex(@sh.read_ex(parts[1:parts.length() - 1]), renames)
    out.write_string("\{indent}if (\{print_ex(cond)}) {\n")
    print_arm(arms[0], out, indent + "  ", renames)
    if arms.length() == 2 {
      out.write_string("\{indent}} else {\n")
      print_arm(arms[1], out, indent + "  ", renames)
    }
    out.write_string("\{indent}}\n")
    return
  }
  match @sh.find_op(parts, [":=", "+=", "-=", "*=", "/="]) {
    Some(at) => {
      let op = match parts[at].it {
        Op(o) => o
        _ => ":="
      }
      let place = rename_ex(@sh.read_ex(parts[:at]), renames)
      let value = rename_ex(@sh.read_ex(parts[at + 1:]), renames)
      let word = if op == ":=" { "=" } else { op }
      let hoisted = hoist(value, out, indent)
      out.write_string(
        "\{indent}\{print_place(place)} \{word} \{print_ex(hoisted)}\n",
      )
    }
    None => print_call_stmt(@sh.read_ex(parts[:]), out, indent, renames)
  }
}

///|
fn print_arm(
  node : @ast.Node,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  guard node.it is Block(gs) else { return }
  for g in gs {
    print_stmt(g, out, indent, renames)
  }
}

///|
/// A statement that is a call: a collection operation, or an effect.
fn print_call_stmt(
  ex : @sh.Ex,
  out : StringBuilder,
  indent : String,
  renames : Map[String, String],
) -> Unit raise @sh.ExError {
  let ex = rename_ex(ex, renames)
  guard ex is @sh.ECall(callee, args) else {
    raise @sh.ExError(
      message="a statement is a write, a collection operation or an effect",
      help="a bare value does nothing — write `it.x := <value>` to keep it",
      span=@report.Span::at(0),
    )
  }
  match callee {
    @sh.EName(verb) => print_effect(verb, args, out, indent)
    @sh.EMember(recv, op) => {
      guard @sh.collection_op(op) is Some(word) else {
        raise @sh.ExError(
          message="`\{op}` is not a collection operation",
          help="the operations are `push`, `insert_at`, `set_at`, `delete_at`, `clear`, `add`, `remove` and `toggle`",
          span=@report.Span::at(0),
        )
      }
      let pos = @sh.positional(args)
      let printed = []
      for a in pos {
        printed.push(print_ex(hoist(a, out, indent)))
      }
      let tail = if printed.is_empty() { "" } else { " " + printed.join(" ") }
      out.write_string("\{indent}\{print_place(recv)}.\{word}\{tail}\n")
    }
    _ =>
      raise @sh.ExError(
        message="only a name or a place can be called as a statement",
        help="write `send(…)`, `ask(…)`, or `it.<field>.<operation>(…)`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The effect verbs, with the route and the target that decorated them.
fn print_effect(
  verb : String,
  args : Array[@sh.Arg],
  out : StringBuilder,
  indent : String,
) -> Unit raise @sh.ExError {
  let pos = @sh.positional(args)
  let printed = []
  for a in pos {
    printed.push(print_ex(hoist(a, out, indent)))
  }
  let rest = if printed.length() > 1 {
    " " + printed[1:].to_owned().join(" ")
  } else {
    ""
  }
  let name = if printed.is_empty() { "" } else { printed[0] }
  match verb {
    "send" =>
      match @sh.kw_arg(args, "to") {
        Some(place) =>
          out.write_string(
            "\{indent}sendAt &\{print_place(place)} \{name}\{rest}\n",
          )
        None => out.write_string("\{indent}send \{name}\{rest}\n")
      }
    "ask" | "notify" => {
      let route = match @sh.kw_arg(args, "route") {
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
      raise @sh.ExError(
        message="`\{other}` is not an effect",
        help="the effects are `send`, `ask`, `notify`, `reply`, `fail`, `forward` and `drop`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// `~route: dyn` or `~route: [lex, dyn]` — legs in the order written.
fn route_words(ex : @sh.Ex) -> String raise @sh.ExError {
  match ex {
    @sh.EName(leg) => leg
    @sh.EList(legs) => {
      let out = []
      for l in legs {
        match l {
          @sh.EName(n) => out.push(n)
          _ =>
            raise @sh.ExError(
              message="a route is a list of legs",
              help="the legs are `dyn` and `lex`",
              span=@report.Span::at(0),
            )
        }
      }
      out.join(" ")
    }
    _ =>
      raise @sh.ExError(
        message="a route is a leg or a list of legs",
        help="write `~route: dyn`, `~route: lex`, or `~route: [lex, dyn]`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// A PLACE, which is what a write and a receiver address.
fn print_place(ex : @sh.Ex) -> String raise @sh.ExError {
  match ex {
    @sh.EIt(f) => "." + f
    @sh.EState(f) => "state." + f
    @sh.EIndex(base, k) => print_place(base) + "[" + print_ex(k) + "]"
    @sh.EMember(@sh.EIt(f), m) => "." + f + "." + m
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
fn hoist(
  ex : @sh.Ex,
  out : StringBuilder,
  indent : String,
) -> @sh.Ex raise @sh.ExError {
  guard ex is @sh.ECall(@sh.EName(name), args) else { return ex }
  guard @sh.is_upper(name) else { return ex }
  out.write_string("\{indent}new \{name}\n")
  for a in args {
    match a {
      @sh.AField(field, value) => {
        guard !(value is @sh.ECall(@sh.EName(_), _)) else {
          raise @sh.ExError(
            message="a constructor inside a constructor cannot be built here",
            help="build the inner one first and write it into a field, then build the outer",
            span=@report.Span::at(0),
          )
        }
        out.write_string("\{indent}cur.\{field} = \{print_ex(value)}\n")
      }
      @sh.AKw(k, _) =>
        raise @sh.ExError(
          message="`~\{k}` is not a field of `\{name}`",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
      @sh.APos(_) =>
        raise @sh.ExError(
          message="`\{name}` is built by naming its fields",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
      @sh.AFlag(f) =>
        raise @sh.ExError(
          message="`~\{f}` is not a field of `\{name}`",
          help="write `\{name}(field: <value>, …)`",
          span=@report.Span::at(0),
        )
    }
  }
  @sh.EName("cur")
}

///|
/// Rewrite the names a body was written with into the ones the renderer
/// hands it.
pub fn rename_ex(ex : @sh.Ex, renames : Map[String, String]) -> @sh.Ex {
  if renames.is_empty() {
    return ex
  }
  match ex {
    @sh.EName(n) =>
      match renames.get(n) {
        Some(to) =>
          if to.has_prefix("@") {
            @sh.EName(to)
          } else {
            @sh.EName(to)
          }
        None => ex
      }
    @sh.EMember(base, m) =>
      match base {
        @sh.EName(n) =>
          match renames.get(n) {
            Some(to) => @sh.EMember(@sh.EName(to), m)
            None => @sh.EMember(rename_ex(base, renames), m)
          }
        _ => @sh.EMember(rename_ex(base, renames), m)
      }
    @sh.EIndex(a, b) => @sh.EIndex(rename_ex(a, renames), rename_ex(b, renames))
    @sh.ECall(c, args) => {
      let out = []
      for a in args {
        out.push(
          match a {
            @sh.APos(e) => @sh.APos(rename_ex(e, renames))
            @sh.AKw(k, e) => @sh.AKw(k, rename_ex(e, renames))
            @sh.AField(k, e) => @sh.AField(k, rename_ex(e, renames))
            @sh.AFlag(_) => a
          },
        )
      }
      @sh.ECall(rename_ex(c, renames), out)
    }
    @sh.EBin(op, a, b) =>
      @sh.EBin(op, rename_ex(a, renames), rename_ex(b, renames))
    @sh.EUn(op, a) => @sh.EUn(op, rename_ex(a, renames))
    @sh.EIf(c, a, b) =>
      @sh.EIf(
        rename_ex(c, renames),
        rename_ex(a, renames),
        rename_ex(b, renames),
      )
    @sh.ETemplate(parts) => {
      let out = []
      for p in parts {
        out.push(
          match p {
            @sh.TText(t) => @sh.TText(t)
            @sh.THole(e) => @sh.THole(rename_ex(e, renames))
          },
        )
      }
      @sh.ETemplate(out)
    }
    @sh.EList(xs) => {
      let out = []
      for x in xs {
        out.push(rename_ex(x, renames))
      }
      @sh.EList(out)
    }
    _ => ex
  }
}
