// Printing the AST back as canonical source.
//
// This exists to be tested through. A grammar with no printer is pinned only
// by whatever assertions somebody thought to write; a grammar with one is
// pinned by round-tripping — parse, print, parse again, and the two ASTs agree
// or the difference is a bug in one of the three. That property is what the
// suite beside this file asserts for every form in the design's §2.3.
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
/// How an assignment operator is written. `pub` so `tscript/check` can spell a
/// finding the same way the printer spells the source, rather than keeping its
/// own copy of the mapping.
pub fn AssignOp::word(self : AssignOp) -> String {
  match self {
    ASet => "="
    AAdd => "+="
    ASub => "-="
  }
}

///|
fn assign_word(op : AssignOp) -> String {
  op.word()
}

///|
/// Escape a string back into a `'…'` literal.
fn quote_str(s : String) -> String {
  let b = StringBuilder::new()
  b.write_char('\'')
  for c in s {
    // A newline in a literal is printed as `\n` rather than as itself: the
    // source round-trips either way, but a declaration that grew three lines
    // because a seed carries a paragraph is a declaration nobody can read.
    match escape_of(c) {
      Some(e) => {
        b.write_char('\\')
        b.write_char(e)
      }
      None => b.write_char(c)
    }
  }
  b.write_char('\'')
  b.to_string()
}

///|
/// A number as source. `Double::to_string` prints a whole number with no
/// fraction, which is what the language wants — `1`, not `1.0`.
fn num_src(n : Double) -> String {
  let i = n.to_int()
  if i.to_double() == n {
    i.to_string()
  } else {
    n.to_string()
  }
}

///|
fn lit_src(l : @tutuca.Lit) -> String {
  match l {
    LNull => "null"
    LBool(b) => if b { "true" } else { "false" }
    LNum(n) => num_src(n)
    LStr(s) => quote_str(s)
  }
}

///|
fn place_src(p : Place) -> String {
  let b = StringBuilder::new()
  match p.root {
    PState(n) => {
      b.write_char('.')
      b.write_string(n)
    }
    PBind(n) => {
      b.write_char('@')
      b.write_string(n)
    }
    // No sigil: a parameter is written the way it was declared, and the steps
    // below it print attached, which is the only spelling that reads back.
    PParam(n) => b.write_string(n)
  }
  for st in p.steps {
    match st {
      PField(n) => {
        b.write_char('.')
        b.write_string(n)
      }
      PIndex(e) => {
        b.write_char('[')
        b.write_string(expr_src(e))
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
    ELit(..) | ETpl(..) | ERead(..) | EMethod(..) | EDyn(..) | EName(..) =>
      false
    ERef(..) => false
    EApp(..) | EChain(..) | EUnary(..) | EIf(..) => true
  }
}

///|
fn operand_src(e : Expr) -> String {
  if needs_parens(e) {
    "(" + expr_src(e) + ")"
  } else {
    expr_src(e)
  }
}

///|
fn expr_src(e : Expr) -> String {
  match e {
    ELit(lit~, ..) => lit_src(lit)
    ETpl(parts~, ..) => {
      let b = StringBuilder::new()
      b.write_string("$'")
      for part in parts {
        match part {
          TText(t) =>
            for c in t {
              if c is ('\'' | '\\') {
                b.write_char('\\')
              }
              b.write_char(c)
            }
          TExpr(inner) => {
            b.write_char('{')
            b.write_string(expr_src(inner))
            b.write_char('}')
          }
        }
      }
      b.write_char('\'')
      b.to_string()
    }
    ERead(place~, ..) => place_src(place)
    EMethod(name~, ..) => "$" + name
    EDyn(name~, ..) => "*" + name
    EName(name~, ..) => name
    ERef(place~, ..) => "&" + place_src(place)
    EApp(name~, args~, ..) =>
      name + " " + args.map(a => operand_src(a)).join(" ")
    EUnary(op~, operand~, ..) => op_word(op) + operand_src(operand)
    EChain(ops~, operands~, ..) => {
      let b = StringBuilder::new()
      b.write_string(operand_src(operands[0]))
      for i, op in ops {
        b.write_char(' ')
        b.write_string(op)
        b.write_char(' ')
        b.write_string(operand_src(operands[i + 1]))
      }
      b.to_string()
    }
    EIf(cond~, then_~, else_~, ..) =>
      "if " +
      expr_src(cond) +
      " { " +
      expr_src(then_) +
      " } else { " +
      expr_src(else_) +
      " }"
  }
}

///|
pub fn Expr::to_source(self : Expr) -> String {
  expr_src(self)
}

///|
pub fn TyRef::to_source(self : TyRef) -> String {
  if self.args.is_empty() {
    self.name
  } else {
    self.name + "[" + self.args.map(a => a.to_source()).join(", ") + "]"
  }
}

///|
fn stmt_src(s : Stmt, indent : String) -> String {
  match s {
    SAssign(place~, op~, value~, ..) =>
      indent + place_src(place) + " " + assign_word(op) + " " + expr_src(value)
    SMethod(place~, call~, args~, ..) => {
      let head = indent + place_src(place) + "." + call
      if args.is_empty() {
        head
      } else {
        head + " " + args.map(a => operand_src(a)).join(" ")
      }
    }
    SEffect(name~, args~, route~, ..) => {
      // Leg words go between the verb and the arguments, which is where they
      // are written and the only place they can be read back from.
      let head = if route.is_empty() {
        indent + name
      } else {
        indent + name + " " + @tutuca.route_label(route)
      }
      if args.is_empty() {
        head
      } else {
        head + " " + args.map(a => operand_src(a)).join(" ")
      }
    }
    SNew(ty~, ..) => indent + "new " + ty.to_source()
    SIf(cond~, then_~, else_~, ..) => {
      let b = StringBuilder::new()
      let inner = indent + "  "
      b.write_string(indent + "if " + expr_src(cond) + " {\n")
      for st in then_ {
        b.write_string(stmt_src(st, inner) + "\n")
      }
      if else_.is_empty() {
        b.write_string(indent + "}")
      } else {
        b.write_string(indent + "} else {\n")
        for st in else_ {
          b.write_string(stmt_src(st, inner) + "\n")
        }
        b.write_string(indent + "}")
      }
      b.to_string()
    }
  }
}

///|
pub fn Decl::to_source(self : Decl) -> String {
  let b = StringBuilder::new()
  if self.doc != "" {
    for line in self.doc.split("\n") {
      b.write_string("/// " + line.to_owned() + "\n")
    }
  }
  b.write_string(kind_word(self.kind))
  b.write_char(' ')
  b.write_string(self.name)
  if !self.params.is_empty() {
    b.write_char('(')
    b.write_string(self.params.map(p => p.name).join(", "))
    b.write_char(')')
  }
  // In the order the two moments happen, whichever order they were written in.
  if self.requires_ is Some(c) {
    b.write_string(" requires " + c.name)
  }
  if self.ensures_ is Some(c) {
    b.write_string(" ensures " + c.name)
  }
  // On its own line, because a sentence is long and the body under it is the
  // thing being read. The parser accepts either, and canonical is the one that
  // stays readable at the width a real message has.
  if self.format is Some(e) {
    b.write_string("\n  format " + expr_src(e))
  }
  match self.body {
    Value(e) => {
      b.write_string(" { ")
      b.write_string(expr_src(e))
      b.write_string(" }")
    }
    Stmts(ss) =>
      if ss.is_empty() {
        b.write_string(" {}")
      } else {
        b.write_string(" {\n")
        for s in ss {
          b.write_string(stmt_src(s, "  ") + "\n")
        }
        b.write_char('}')
      }
  }
  b.to_string()
}
