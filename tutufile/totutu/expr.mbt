// `@tutuca.Expr` printed as the shrubbery it is written as in a `.tutu` file.
//
// The inverse of `tutufile/toanode`'s `to_expr`, and the two are checked
// against each other by every file the converter round-trips: what this prints
// is read back by that, and `tutufile/equiv` compares the trees.
//
// **Parentheses are added freely.** Shrubbery refuses an unparenthesised chain
// that mixes operator families, and the fold that could decide which ones are
// needed would be a precedence table — the one thing the notation exists not to
// have. Redundant parentheses change nothing about what is read.

///|
/// Something the new notation cannot spell.
pub(all) suberror NoSpelling {
  NoSpelling(what~ : String, help~ : String)
}

///|
/// One expression.
pub fn print_expr(e : @tutuca.Expr) -> String raise NoSpelling {
  match e {
    ELit(lit~, ..) => print_lit(lit)
    ERead(place~, ..) => print_place(place)
    ERef(place~, ..) => print_place(place)
    EMethod(name~, ..) => "\{@names.snake_of(name)}()"
    EDyn(name~, ..) => "dyn.\{@names.snake_of(name)}"
    EName(name~, ..) => @names.rename_member(name)
    ETypeName(name~, ..) => name
    // `^name` in a macro body: the parameter, under its own name.
    EMacroVar(name~, ..) => @names.snake_of(name)
    EConfigVar(name~, ..) => "host.\{name}"
    EEventPath(segments~, ..) => "e." + segments.join(".")
    EApp(name~, args~, ..) => print_app(name, args)
    EChain(ops~, operands~, ..) => print_chain(ops, operands)
    EUnary(op~, operand~, ..) =>
      match op {
        UNot => "!" + print_atom(operand)
        UNeg => "-" + print_atom(operand)
      }
    // The arms are parenthesised because alternatives do not nest by writing
    // more of them: `if a | b | if c | d | e` is FOUR arms at one level, and an
    // `if` takes two.
    EIf(cond~, then_~, else_~, ..) =>
      "if \{print_expr(cond)} | \{print_arm_expr(then_)} | \{print_arm_expr(else_)}"
    ETpl(parts~, ..) => print_tpl(parts)
  }
}

///|
/// One arm of a conditional. A nested conditional is parenthesised so its own
/// alternatives stay its own.
fn print_arm_expr(e : @tutuca.Expr) -> String raise NoSpelling {
  match e {
    EIf(..) => "(" + print_expr(e) + ")"
    _ => print_expr(e)
  }
}

///|
/// An expression in a position where a bare operator chain would be read as
/// part of something larger.
fn print_atom(e : @tutuca.Expr) -> String raise NoSpelling {
  match e {
    EChain(..) | EIf(..) | EApp(..) => "(" + print_expr(e) + ")"
    _ => print_expr(e)
  }
}

///|
pub fn print_lit(lit : @tutuca.Lit) -> String {
  match lit {
    LNull => "none"
    LBool(b) => if b { "true" } else { "false" }
    LNum(n) => print_num(n)
    LStr(s) => quote(s)
  }
}

///|
/// A number, whole where it is whole: `1.0` and `1` read differently.
pub fn print_num(n : Double) -> String {
  if n == n.trunc() && n.abs() < 1.0e15 {
    "\{n.to_int()}"
  } else {
    "\{n}"
  }
}

///|
/// A double-quoted string. The `.tutu` notation has one string quote, where the
/// old one had two.
pub fn quote(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\t' => out.write_string("\\t")
      _ => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// A place: `it.field`, a binding, or one step into either.
fn print_place(place : @tutuca.Place) -> String raise NoSpelling {
  let root = match place.root {
    PState(f) => "it." + @names.snake_of(f)
    PBind(b) => @names.snake_of(b)
    PParam(p) => @names.snake_of(p)
    PTarget => "cur"
  }
  let out = StringBuilder()
  out.write_string(root)
  for step in place.steps {
    match step {
      PField(f) => out.write_string("." + @names.snake_of(f))
      PIndex(k) => out.write_string("[" + print_expr(k) + "]")
    }
  }
  out.to_string()
}

///|
/// An application. Most of them are the READING vocabulary, which the new
/// notation spells as methods on the value being read.
fn print_app(
  name : String,
  args : Array[@tutuca.Expr],
) -> String raise NoSpelling {
  // the operators, which parse as applications in a slot
  if binary_op(name) is Some(op) && args.length() == 2 {
    return "(\{print_expr(args[0])} \{op} \{print_expr(args[1])})"
  }
  if name == "not" && args.length() == 1 {
    return "!" + print_atom(args[0])
  }
  // `null? x` is the shape predicate, which is `x == none`
  if name == "null?" && args.length() == 1 {
    return "(\{print_expr(args[0])} == none)"
  }
  // the numeric builtins, which have no receiver
  if ["max", "min", "clamp"].contains(name) {
    return "math.\{name}(" + joined(args) + ")"
  }
  // a receiver method: the first argument is what it is read from
  if receiver_method(name) is Some(word) && args.length() >= 1 {
    let rest = args[1:].to_owned()
    return "\{print_atom(args[0])}.\{word}(\{joined(rest)})"
  }
  // what is left is a `compute` of the component's own, called with arguments
  "\{@names.snake_of(name)}(" + joined(args) + ")"
}

///|
/// The operator an application is the prefix spelling of.
fn binary_op(name : String) -> String? {
  match name {
    "is" => Some("==")
    "is not" => Some("!=")
    "and" => Some("&&")
    "or" => Some("||")
    "<" | "<=" | ">" | ">=" | "+" | "-" | "*" | "/" | "mod" | "implies" =>
      Some(name)
    _ => None
  }
}

///|
/// The method a reading builtin is spelled as. The inverse of the table in
/// `tutufile/toanode`.
fn receiver_method(name : String) -> String? {
  match name {
    "empty?" => Some("is_empty")
    "truthy?" => Some("is_truthy")
    "null?" => Some("is_null")
    "len" => Some("length")
    "has" => Some("has")
    "contains" => Some("contains")
    "str" => Some("to_string")
    "int" => Some("to_int")
    "num" => Some("to_number")
    "lower" => Some("lower")
    "upper" => Some("upper")
    "trim" => Some("trim")
    _ => None
  }
}

///|
/// A chain of one operator family.
fn print_chain(
  ops : Array[String],
  operands : Array[@tutuca.Expr],
) -> String raise NoSpelling {
  let out = StringBuilder()
  out.write_char('(')
  out.write_string(print_expr(operands[0]))
  for i, op in ops {
    let word = binary_op(op).unwrap_or(op)
    out.write_string(" \{word} ")
    out.write_string(print_expr(operands[i + 1]))
  }
  out.write_char(')')
  out.to_string()
}

///|
/// `$'text {expr}'` becomes `@str{text @(expr)}`.
///
/// The `@` and the braces are the notation's own, so text that contains one has
/// to escape it — `@@` and `@{`/`@}` — or the body would read as a hole.
fn print_tpl(parts : Array[@tutuca.TplPart]) -> String raise NoSpelling {
  let out = StringBuilder()
  out.write_string("@str{")
  for p in parts {
    match p {
      TText(text~, ..) => out.write_string(escape_text(text))
      TExpr(e) =>
        // A hole is already a call site, so a `compute` in one is named rather
        // than called — the same rule the reader applies coming the other way.
        match e {
          EMethod(name~, ..) => out.write_string("@(\{@names.snake_of(name)})")
          _ => out.write_string("@(" + print_expr(e) + ")")
        }
    }
  }
  out.write_char('}')
  out.to_string()
}

///|
/// Text inside an at-notation body.
///
/// Text that holds none of the three characters the notation owns is written as
/// itself. Text that holds one is written WHOLE, as `@"…"` — an at-form whose
/// body is a string literal — rather than character by character.
///
/// Whole, because the per-character form does not survive the round trip.
/// `write to me @"@" home` parses, but it produces THREE text nodes and eats
/// the spaces around the at-form, so the tree that comes back is `"write to
/// me"`, `"@"`, `"home"` where the file said one node with two spaces in it.
/// `@"write to me @ home"` is one node with exactly those characters.
///
/// And NOT `@@` / `@{` / `@}`. Those look like escapes and are not: `a@@b`,
/// `a@{b` and `a@}b` are read errors in the reference implementation as well as
/// in this port. Measured against `marianoguerra/shrubbery@0.1.1`.
pub fn escape_text(s : String) -> String {
  let mut owned = false
  for c in s {
    if c is ('@' | '{' | '}') {
      owned = true
      break
    }
  }
  if !owned {
    return s
  }
  let out = StringBuilder()
  out.write_string("@\"")
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      _ => out.write_char(c)
    }
  }
  out.write_string("\"")
  out.to_string()
}

///|
fn joined(args : Array[@tutuca.Expr]) -> String raise NoSpelling {
  let parts = []
  for a in args {
    parts.push(print_expr(a))
  }
  parts.join(", ")
}
