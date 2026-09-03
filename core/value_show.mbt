// Source round-trip: every expression prints back as its original syntax.
//
// ONE printer, for the reason there is one AST. It used to be two — this one
// over the slot vocabulary, and `tscript/script_print.mbt`'s over the block
// grammar — and they disagreed about small things (whether a newline in a
// literal is escaped, whether a zero-argument application keeps its trailing
// space) that nobody chose and nobody could see.
//
// Canonical, not faithful. Parentheses are emitted wherever the grammar
// REQUIRES them rather than wherever the author wrote them, so printing is a
// normal form: two spellings of the same expression print identically, which
// is exactly what makes a round-trip comparison meaningful.

///|
fn op_word(op : UnOp) -> String {
  match op {
    UNot => "not "
    UNeg => "-"
  }
}

///|
fn lit_source(l : Lit) -> String {
  match l {
    LNull => "null"
    LBool(b) => if b { "true" } else { "false" }
    LNum(n) => num_source(n)
    LStr(s) => escape_str_literal(s)
  }
}

///|
/// A place as source: the root's sigil, then every step attached.
pub fn Place::to_source(self : Place) -> String {
  let b = StringBuilder()
  match self.root {
    PState(n) => {
      b.write_char('.')
      b.write_string(n)
    }
    PBind(n) => {
      b.write_char('@')
      b.write_string(n)
    }
    // No sigil either: `cur` is not a binding, and writing it as one was the
    // whole of what `@cur` got wrong.
    PTarget => b.write_string(target_bind)
    // No sigil: a parameter is written the way it was declared, and the steps
    // below it print attached, which is the only spelling that reads back.
    PParam(n) => b.write_string(n)
  }
  for st in self.steps {
    match st {
      PField(n) => {
        b.write_char('.')
        b.write_string(n)
      }
      PIndex(e) => {
        b.write_char('[')
        b.write_string(val_source(e))
        b.write_char(']')
      }
    }
  }
  b.to_string()
}

///|
/// True when an expression needs parentheses to sit where an OPERAND is
/// expected — as an argument of an application, or beside an operator.
///
/// An atom never does. Everything with an operator or a juxtaposition in it
/// always does, and that is the grammar's own rule rather than a precedence
/// judgement: the language has no precedence, so anything compound in an
/// operand position is written parenthesized or is not written at all.
fn needs_parens(e : Expr) -> Bool {
  match e {
    EApp(args~, ..) => !args.is_empty()
    EChain(..) | EUnary(..) | EIf(..) => true
    _ => false
  }
}

///|
pub fn operand_source(e : Expr) -> String {
  if needs_parens(e) {
    "(" + val_source(e) + ")"
  } else {
    val_source(e)
  }
}

///|
fn val_source(val : Expr) -> String {
  match val {
    // `e` is the root and never a segment, so it is written back rather than
    // stored — there is no expression that means "the event".
    EEventPath(segments~, ..) => "e." + segments.join(".")
    ELit(lit~, ..) => lit_source(lit)
    ETpl(parts~, ..) => {
      let b = StringBuilder()
      b.write_string("$'")
      for part in parts {
        match part {
          // Re-escape the raw text (the parse unescaped it once).
          TText(text~, ..) => escape_str_into(b, text)
          TExpr(inner) => {
            b.write_char('{')
            b.write_string(val_source(inner))
            b.write_char('}')
          }
        }
      }
      b.write_char('\'')
      b.to_string()
    }
    EApp(name~, args~, ..) =>
      // A zero-argument application prints as the bare name, so the round trip
      // holds once the vocabulary admits one.
      if args.is_empty() {
        name
      } else if is_infix_op(name) && args.length() == 2 {
        // A comparison is written INFIX and has to print that way. The view
        // slot parser builds one as an application — the same node a named
        // builtin makes — so the shape says nothing about the spelling, and a
        // printer that ignored the difference would answer a form nothing
        // parses.
        operand_source(args[0]) + " " + name + " " + operand_source(args[1])
      } else {
        name + " " + args.map(a => operand_source(a)).join(" ")
      }
    EName(name~, ..) => name
    ETypeName(name~, ..) => name
    EDyn(name~, ..) => "*" + name
    EMethod(name~, ..) => "$" + name
    EMacroVar(name~, ..) => "^" + name
    EConfigVar(name~, ..) => "host." + name
    ERead(place~, ..) => place.to_source()
    ERef(place~, ..) => "&" + place.to_source()
    EUnary(op~, operand~, ..) => op_word(op) + operand_source(operand)
    EChain(ops~, operands~, ..) => {
      let b = StringBuilder()
      b.write_string(operand_source(operands[0]))
      for i, op in ops {
        b.write_char(' ')
        b.write_string(op)
        b.write_char(' ')
        b.write_string(operand_source(operands[i + 1]))
      }
      b.to_string()
    }
    EIf(cond~, then_~, else_~, ..) =>
      "if " +
      val_source(cond) +
      " { " +
      val_source(then_) +
      " } else { " +
      val_source(else_) +
      " }"
  }
}

///|
/// Print an expression back as canonical source. Round-tripping through this
/// is how the grammar is pinned: parse, print, parse again, and the two ASTs
/// agree.
pub fn Expr::to_source(self : Expr) -> String {
  val_source(self)
}

///|
pub impl Show for Val with fn output(self, logger) {
  logger.write_string(val_source(self))
}

///|
/// Written between its operands rather than in front of them. The compare
/// family and nothing else: `and` / `or` / `implies` are named applications in
/// a view slot and read as such.
fn is_infix_op(name : String) -> Bool {
  name is ("is" | "is not" | "<" | "<=" | ">" | ">=")
}
