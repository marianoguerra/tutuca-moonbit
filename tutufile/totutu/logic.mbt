// The `logic:` section: parsed handlers printed as the declarations they came
// from.

///|
/// One component's `logic:` body.
pub fn print_logic(
  comp : String,
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef?,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  out.write_string("  \{comp}:\n")
  let mut first = true
  let done : Array[String] = []
  for d in decls {
    // A `get` and a `set` with one name are ONE property in the new notation,
    // with its accessors under it — not two declarations that happen to agree
    // about a name. They are printed together at the first of the two.
    if d.kind is (DGet | DSet) {
      if done.contains(d.name) {
        continue
      }
      done.push(d.name)
      if !first {
        out.write_string("\n")
      }
      first = false
      print_property(d.name, decls, def, out)
      continue
    }
    if !first {
      out.write_string("\n")
    }
    first = false
    print_decl(d, out)
  }
}

///|
/// One property, with the accessors that implement it.
///
/// The TYPE comes from the schema: a `get`/`set` in the block language carries
/// none, because the property it implements was declared in the spec block and
/// a second annotation would be a second answer.
fn print_property(
  name : String,
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef?,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let ty = property_ty(name, def)
  let mut doc : String? = None
  for d in decls {
    if d.name == name && d.kind is DGet && d.doc != "" {
      doc = Some(d.doc)
    }
  }
  write_doc(out, doc, "    ")
  out.write_string("    property \{@names.snake_of(name)} :: \{ty}:\n")
  for d in decls {
    guard d.name == name && d.kind is (DGet | DSet) else { continue }
    let word = if d.kind is DGet { "get" } else { "set" }
    match d.body {
      Value(e) => out.write_string("      \{word}: \{print_expr(e)}\n")
      Stmts(stmts) => {
        // One statement that fits on a line sits on the accessor's own line.
        // One that does not — an `if`, which is three lines and carries its own
        // indentation — goes in the block under it, or its arms would be
        // written at a column that closes the block they belong to.
        let body = StringBuilder()
        print_stmts(stmts, "        ", body)
        let text = body.to_string()
        if stmts.length() == 1 && is_one_line(text) {
          out.write_string(
            "      \{word}: \{text.trim(chars=" \n").to_owned()}\n",
          )
        } else {
          out.write_string("      \{word}:\n")
          out.write_string(text)
        }
      }
    }
  }
}

///|
/// The declared type of a property, from the schema that declared it.
fn property_ty(
  name : String,
  def : @statedef.StateDef?,
) -> String raise NoSpelling {
  guard def is Some(def) else {
    raise NoSpelling(
      what="a `get` / `set` for `\{name}` with no schema to take its type from",
      help="the property has to be declared in the spec block",
    )
  }
  for p in def.properties {
    if p.name == name {
      return print_ty(p.ty)
    }
  }
  raise NoSpelling(
    what="a `get` / `set` for `\{name}`, which the spec block does not declare as a property",
    help="declare it in the spec block, or convert this file by hand",
  )
}

///|
/// One declaration.
fn print_decl(d : @tscript.Decl, out : StringBuilder) -> Unit raise NoSpelling {
  if d.doc != "" {
    write_doc(out, Some(d.doc), "    ")
  }
  let name = @names.rename_member(d.name)
  let params = param_list(d.params)
  match d.kind {
    // A property accessor is one declaration with its accessors under it, not
    // two declarations that happen to share a name — so `get` and `set` are
    // printed by `print_accessors`, and reaching one here is a caller's error.
    DGet | DSet => return
    DCompute => print_body_decl(d, "compute \{name}\{params}", out)
    DPred => print_body_decl(d, "pred \{name}\{row_params(d, params)}", out)
    DInvariant => print_body_decl(d, "invariant \{name}\{params}", out)
    // An enricher BINDS: its body is `name = value`, not a write to a place.
    // `:=` is a write and `=` is a binding, and the two are different
    // statements in the new notation exactly as they were two different things
    // in the old one.
    DEnrich =>
      print_body_decl(
        d,
        "enrich \{name}\{row_params(d, params)}",
        out,
        binds=true,
      )
    DBindWith => print_body_decl(d, "bind_with \{name}", out, binds=true)
    DReceive => print_body_decl(d, "receive \{name}\{params}", out)
    // A routed name is answered with `answer`, which is the word the logic
    // section takes: `intent` DECLARES one in `spec:`, and answering it is a
    // different thing in a different section.
    DAnswer => print_body_decl(d, "answer \{name}\{params}", out)
  }
}

///|
/// A declaration with its options and its body under it.
fn print_body_decl(
  d : @tscript.Decl,
  head : String,
  out : StringBuilder,
  binds? : Bool = false,
) -> Unit raise NoSpelling {
  let opts = []
  match d.requires_ {
    Some(a) => opts.push("      ~requires: \{@names.snake_of(a.name)}\n")
    None => ()
  }
  match d.ensures_ {
    Some(a) => opts.push("      ~ensures: \{@names.snake_of(a.name)}\n")
    None => ()
  }
  if d.format is Some(f) {
    opts.push("      ~format: \{print_expr(f)}\n")
  }
  // One expression with no options fits on the declaration's own line, which is
  // what a `pred` or a `compute` usually is.
  match d.body {
    Value(e) =>
      if opts.is_empty() {
        out.write_string("    \{head}: \{print_expr(e)}\n")
        return
      } else {
        out.write_string("    \{head}:\n")
        for o in opts {
          out.write_string(o)
        }
        out.write_string("      \{print_expr(e)}\n")
        return
      }
    Stmts(stmts) => {
      out.write_string("    \{head}:\n")
      for o in opts {
        out.write_string(o)
      }
      print_stmts(stmts, "      ", out, binds~)
    }
  }
}

///|
/// A row member's parameter list.
///
/// The old notation gave a `@when` filter and an in-loop enricher NO
/// parameters: they read `@value` and `@key` out of the air. The new notation
/// names the row, so a member whose body reads those bindings declares them —
/// and the reader maps the names back, which is the only way the body's reads
/// resolve to the row again.
///
/// Only when the body actually reads one: a predicate that takes no arguments
/// and reads no row is a predicate about the component, and giving it two
/// parameters would change what it is.
fn row_params(d : @tscript.Decl, declared : String) -> String {
  if declared != "" {
    return declared
  }
  if reads_row(d.body) {
    "(value, key)"
  } else {
    ""
  }
}

///|
/// Whether a body reads the row bindings.
fn reads_row(b : @tscript.Body) -> Bool {
  let found = []
  fn look(e : @tutuca.Expr) -> Unit {
    if e.as_bind() is Some(n) && n is ("value" | "key" | "iter") {
      found.push(n)
    }
    if e.as_bind_member() is Some((n, _)) && n is ("value" | "key" | "iter") {
      found.push(n)
    }
  }

  fn walk_expr(e : @tutuca.Expr) -> Unit {
    look(e)
    match e {
      EApp(args~, ..) => args.each(walk_expr)
      EChain(operands~, ..) => operands.each(walk_expr)
      EUnary(operand~, ..) => walk_expr(operand)
      EIf(cond~, then_~, else_~, ..) => {
        walk_expr(cond)
        walk_expr(then_)
        walk_expr(else_)
      }
      ETpl(parts~, ..) =>
        for p in parts {
          if p is TExpr(v) {
            walk_expr(v)
          }
        }
      _ => ()
    }
  }

  fn walk_stmt(s : @tscript.Stmt) -> Unit {
    match s {
      SAssign(value~, ..) => walk_expr(value)
      SMethod(args~, ..) => args.each(walk_expr)
      SEffect(args~, ..) => args.each(walk_expr)
      SIf(cond~, then_~, else_~, ..) => {
        walk_expr(cond)
        then_.each(walk_stmt)
        else_.each(walk_stmt)
      }
      _ => ()
    }
  }

  match b {
    Value(e) => walk_expr(e)
    Stmts(ss) => ss.each(walk_stmt)
  }
  !found.is_empty()
}

///|
/// A parameter list, or nothing.
fn param_list(params : Array[@tscript.Param]) -> String {
  if params.is_empty() {
    return ""
  }
  // A parameter carries a name and nothing else: the block language does not
  // annotate one, and the type a `.tutu` file may write is optional.
  let parts = []
  for p in params {
    parts.push(@names.snake_of(p.name))
  }
  "(" + parts.join(", ") + ")"
}

///|
/// A statement list, with each `new` folded into the call that consumes it.
///
/// `new Todo` opens an argument map at `cur`, the assignments under it fill the
/// map in, and the value is MADE at the moment `cur` is read. The new notation
/// has no `new` and no `cur`: every `struct` and component has a parenthesised
/// parameter list, so the aggregate is spelled directly at the point it is used.
///
/// So the three-statement run becomes one call, and the fold is over a RUN
/// rather than a statement — which is why this exists beside `print_stmt`
/// rather than inside it.
fn print_stmts(
  stmts : Array[@tscript.Stmt],
  indent : String,
  out : StringBuilder,
  binds? : Bool = false,
) -> Unit raise NoSpelling {
  let mut i = 0
  while i < stmts.length() {
    guard stmts[i] is SNew(ty~, ..) else {
      print_stmt(stmts[i], indent, out, binds~)
      i = i + 1
      continue
    }
    let fields = []
    let mut j = i + 1
    while j < stmts.length() &&
          stmts[j] is SAssign(place~, ..) &&
          place.root is PTarget {
      guard stmts[j] is SAssign(place~, op~, value~, ..) else { break }
      guard op is ASet && place.steps is [PField(f)] else {
        raise NoSpelling(
          what="a `new` block that writes `cur` with `\{if op is ASet { "a path" } else { "+=" }}`",
          help="an aggregate is spelled directly in the new notation, so each field is written once — this one has to be rewritten by hand",
        )
      }
      fields.push((f, value))
      j = j + 1
    }
    guard j < stmts.length() else {
      raise NoSpelling(
        what="a `new \{ty.name}` that nothing reads",
        help="the value is made where `cur` is read, and nothing here reads it",
      )
    }
    print_consumer(stmts[j], ctor_text(ty, fields), indent, out)
    i = j + 1
  }
}

///|
/// The constructor call a `new` run builds.
fn ctor_text(
  ty : @tscript.TyRef,
  fields : Array[(String, @tutuca.Expr)],
) -> String raise NoSpelling {
  let parts = []
  for f in fields {
    parts.push("\{@names.snake_of(f.0)}: \{print_expr(f.1)}")
  }
  "\{ty.name}(\{parts.join(", ")})"
}

///|
/// The statement that reads `cur`, with the constructor written where it was.
///
/// Three shapes, which is what the corpus writes: a collection method
/// (`.items.push cur`), an assignment, and an effect. Anything else is refused
/// rather than guessed at — a `cur` this does not find is a value silently
/// dropped.
fn print_consumer(
  stmt : @tscript.Stmt,
  ctor : String,
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  // Whether the constructor found the `cur` it replaces. A consumer that
  // mentions `cur` in no argument would print without it, and the aggregate
  // would be gone from a file that still compiles — so it is counted, not
  // assumed.
  let placed = FixedArray::make(1, false)
  fn one(e : @tutuca.Expr) -> String raise NoSpelling {
    if e is ERead(place~, ..) && place.root is PTarget && place.steps.is_empty() {
      placed[0] = true
      ctor
    } else {
      print_expr(e)
    }
  }

  match stmt {
    SMethod(place~, call~, args~, ..) => {
      let parts = []
      for a in args {
        parts.push(one(a))
      }
      out.write_string(
        "\{indent}\{print_stmt_place(place)}.\{checked_mutator(call)}(\{parts.join(", ")})\n",
      )
    }
    SAssign(place~, op~, value~, ..) => {
      let word = match op {
        ASet => ":="
        AAdd => "+="
        ASub => "-="
      }
      out.write_string(
        "\{indent}\{print_stmt_place(place)} \{word} \{one(value)}\n",
      )
    }
    SEffect(name~, args~, route~, ..) => {
      let msg_at = if name == "sendAt" { 1 } else { 0 }
      let parts = []
      for i, a in args {
        if i == msg_at && a.as_lit() is Some(LStr(who)) {
          parts.push(quote(@names.rename_member(who)))
        } else {
          parts.push(one(a))
        }
      }
      print_effect_text(name, parts, route, indent, out)
    }
    _ =>
      raise NoSpelling(
        what="a `new` whose value is read by a statement this does not know",
        help="the value is made where `cur` is read — a collection method, an assignment or an effect",
      )
  }
  guard placed[0] else {
    raise NoSpelling(
      what="a `new` run whose `cur` is filled by something other than `cur.<field> = …`",
      help="an aggregate is spelled directly in the new notation, so everything it holds is written inside its parentheses — rewrite this run by hand",
    )
  }
}

///|
/// One statement.
fn print_stmt(
  s : @tscript.Stmt,
  indent : String,
  out : StringBuilder,
  binds? : Bool = false,
) -> Unit raise NoSpelling {
  match s {
    SAssign(place~, op~, value~, ..) => {
      // In an enricher a name is BOUND, not written to: `tag = …` introduces
      // the binding a view then reads, where `:=` is a write to a place that
      // already exists. The old notation spelled the first `@tag = …`.
      let word = match op {
        ASet => if binds && place.root is PBind(_) { "=" } else { ":=" }
        AAdd => "+="
        ASub => "-="
      }
      out.write_string(
        "\{indent}\{print_stmt_place(place)} \{word} \{print_expr(value)}\n",
      )
    }
    SMethod(place~, call~, args~, ..) => {
      let parts = []
      for a in args {
        parts.push(print_expr(a))
      }
      out.write_string(
        "\{indent}\{print_stmt_place(place)}.\{checked_mutator(call)}(\{parts.join(", ")})\n",
      )
    }
    SEffect(name~, args~, route~, ..) =>
      print_effect(name, args, route, indent, out)
    SIf(cond~, then_~, else_~, ..) => {
      out.write_string("\{indent}if \{print_expr(cond)}\n")
      out.write_string("\{indent}| ")
      print_arm(then_, indent, out)
      // A branch with nothing to do otherwise writes one arm. An empty second
      // arm would be a bar with nothing after it, which is not a statement.
      if !else_.is_empty() {
        out.write_string("\{indent}| ")
        print_arm(else_, indent, out)
      }
    }
    SNew(..) =>
      raise NoSpelling(
        what="a `new` statement",
        help="every `struct` and component has a parenthesised parameter list in the new notation, so an aggregate is spelled directly — this one has to be rewritten as a constructor call by hand",
      )
  }
}

///|
/// One arm of an `if`. A single statement sits on the bar; several go in a
/// block under it.
fn print_arm(
  stmts : Array[@tscript.Stmt],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let body = StringBuilder()
  print_stmts(stmts, indent + "    ", body)
  let text = body.to_string()
  if stmts.length() == 1 && is_one_line(text) {
    out.write_string(text.trim(chars=" \n").to_owned() + "\n")
    return
  }
  out.write_string("\n")
  out.write_string(text)
}

///|
/// A place on the left of a statement. A binding an enricher introduces is
/// written bare — they are the names it is producing.
fn print_stmt_place(place : @tutuca.Place) -> String raise NoSpelling {
  match (place.root, place.steps) {
    (PBind(b), []) => @names.snake_of(b)
    _ => print_expr(@tutuca.Expr::ERead(place~, span=place.span))
  }
}

///|
/// An effect, which is a call in the new notation with its decorations as
/// options.
fn print_effect(
  name : String,
  args : Array[@tutuca.Expr],
  route : Array[@tutuca.Leg],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  // The message an effect carries is a name the component OWNS — `ask
  // 'loadData'` is answered as `load_data_ok`, and the two have to be spelled
  // the same way or the answer arm never fires. A qualified one is a wire name
  // and `rename_member` leaves it alone.
  let msg_at = if name == "sendAt" { 1 } else { 0 }
  let printed = []
  for i, a in args {
    if i == msg_at && a.as_lit() is Some(LStr(who)) {
      printed.push(quote(@names.rename_member(who)))
    } else {
      printed.push(print_expr(a))
    }
  }
  print_effect_text(name, printed, route, indent, out)
}

///|
/// An effect whose arguments are already printed.
///
/// Split from `print_effect` so that a `new` folded into an effect can hand the
/// constructor text in as one of them — the shape of the call is the same
/// whichever way its arguments were arrived at.
fn print_effect_text(
  name : String,
  args : Array[String],
  route : Array[@tutuca.Leg],
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  let parts = []
  let opts = []
  // `sendAt &.status 'flash' 'Ready'` puts the ADDRESS first; the new spelling
  // makes it an option, so the message reads first as it does everywhere else.
  let verb = if name == "sendAt" {
    guard args.length() >= 1 else {
      raise NoSpelling(
        what="a `sendAt` with no address",
        help="`sendAt` takes the place to send to first",
      )
    }
    opts.push("~to: " + args[0])
    for a in args[1:] {
      parts.push(a)
    }
    "send"
  } else {
    for a in args {
      parts.push(a)
    }
    @names.snake_of(name)
  }
  if !route.is_empty() {
    let legs = []
    for leg in route {
      legs.push(leg_word(leg))
    }
    if legs.length() == 1 {
      opts.push("~route: " + legs[0])
    } else {
      opts.push("~route: [" + legs.join(", ") + "]")
    }
  }
  for o in opts {
    parts.push(o)
  }
  out.write_string("\{indent}\{verb}(\{parts.join(", ")})\n")
}

///|
/// One leg of a route, under the word `Leg::word` already names it by — one
/// spelling, in the package that owns the type.
fn leg_word(leg : @tutuca.Leg) -> String {
  leg.word()
}

///|
/// A collection mutator the new notation has a method for.
///
/// The old block language had two spellings of one operation — `removeAt` and
/// `deleteAt` — and the new notation keeps `delete_at`. `delete` and `set`
/// parsed there and named no operation at all, so a call to one is refused
/// rather than printed as a method that does not exist.
///
/// `clear` is a method. It reads like the other two dropped names and is not
/// one of them: it is the ONLY spelling for emptying a list, because there is
/// no list literal to assign, so dropping it would take the operation with it.
pub fn checked_mutator(name : String) -> String raise NoSpelling {
  let m = @names.mutator_of(name)
  guard [
    "push", "insert_at", "set_at", "delete_at", "clear", "add", "remove", "toggle",
  ].contains(m) else {
    raise NoSpelling(
      what="`\{name}`, which is not a collection method",
      help="the methods are `push`, `insert_at`, `set_at`, `delete_at`, `clear`, `add`, `remove` and `toggle` — `delete` and `set` parsed in the old notation and named no operation",
    )
  }
  m
}

///|
/// Whether a printed body is one line, so it can sit after its `:`.
///
/// Lived in the view printer, which is deleted: it printed the old at-notation
/// spelling and nothing called it any more. The logic printer is the only
/// caller left.
fn is_one_line(s : String) -> Bool {
  let body = s.trim(chars=" \n")
  body != "" && !body.contains("\n")
}
