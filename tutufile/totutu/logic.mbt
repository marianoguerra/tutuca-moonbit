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
        for st in stmts {
          print_stmt(st, "        ", body)
        }
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
    DPred => print_body_decl(d, "pred \{name}\{params}", out)
    DInvariant => print_body_decl(d, "invariant \{name}\{params}", out)
    DEnrich => print_body_decl(d, "enrich \{name}\{params}", out)
    DBindWith => print_body_decl(d, "bind_with \{name}", out)
    DReceive => print_body_decl(d, "receive \{name}\{params}", out)
    DAnswer => print_body_decl(d, "intent \{name}\{params}", out)
  }
}

///|
/// A declaration with its options and its body under it.
fn print_body_decl(
  d : @tscript.Decl,
  head : String,
  out : StringBuilder,
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
      for s in stmts {
        print_stmt(s, "      ", out)
      }
    }
  }
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
/// One statement.
fn print_stmt(
  s : @tscript.Stmt,
  indent : String,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  match s {
    SAssign(place~, op~, value~, ..) => {
      let word = match op {
        ASet => ":="
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
        "\{indent}\{print_stmt_place(place)}.\{@names.mutator_of(call)}(\{parts.join(", ")})\n",
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
  for s in stmts {
    print_stmt(s, indent + "    ", body)
  }
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
    opts.push("~to: " + print_expr(args[0]))
    for a in args[1:] {
      parts.push(print_expr(a))
    }
    "send"
  } else {
    for a in args {
      parts.push(print_expr(a))
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
