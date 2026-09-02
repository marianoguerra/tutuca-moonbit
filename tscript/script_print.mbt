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
/// An operand as source: parenthesized where the grammar requires it.
///
/// The rule and the parentheses are `core`'s (`value_show.mbt`) — one printer
/// for one AST — and this is the one line of it a statement printer needs.
fn operand_source(e : @tutuca.Expr) -> String {
  @tutuca.operand_source(e)
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
      indent +
      place.to_source() +
      " " +
      assign_word(op) +
      " " +
      value.to_source()
    SMethod(place~, call~, args~, ..) => {
      let head = indent + place.to_source() + "." + call
      if args.is_empty() {
        head
      } else {
        head + " " + args.map(a => operand_source(a)).join(" ")
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
        head + " " + args.map(a => operand_source(a)).join(" ")
      }
    }
    SNew(ty~, ..) => indent + "new " + ty.to_source()
    SIf(cond~, then_~, else_~, ..) => {
      let b = StringBuilder()
      let inner = indent + "  "
      b.write_string(indent + "if " + cond.to_source() + " {\n")
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
  let b = StringBuilder()
  if self.doc != "" {
    for line in self.doc.split("\n") {
      b.write_string("/// " + line.to_owned() + "\n")
    }
  }
  b.write_string(kind_word(self.kind))
  b.write_char(' ')
  b.write_string(self.name)
  if !self.params.is_empty() && !(self.kind is DSet) {
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
    b.write_string("\n  format " + e.to_source())
  }
  match self.body {
    Value(e) => {
      b.write_string(" { ")
      b.write_string(e.to_source())
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
