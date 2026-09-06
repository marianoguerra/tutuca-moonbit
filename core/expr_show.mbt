// An expression, written back as the notation reads it.
//
// For a READER — a diagnostic that quotes the rule that failed, a panel that
// shows what a component declares. Not a serialiser: nothing parses this back,
// and a shape it cannot spell is written as a description rather than refused,
// because a sentence with a gap in it is still a better answer than none.

///|
/// An expression as `.tutu` source.
pub fn Expr::show_source(self : Expr) -> String {
  match self {
    ELit(lit~, ..) => show_lit(lit)
    ETpl(parts~, ..) => {
      let out = StringBuilder()
      out.write_string("@str{")
      for p in parts {
        match p {
          TText(text~, ..) => out.write_string(text)
          TExpr(e) => out.write_string("@(" + e.show_source() + ")")
        }
      }
      out.write_string("}")
      out.to_string()
    }
    ERead(place~, ..) => show_place(place)
    ERef(place~, ..) => "&" + show_place(place)
    EMethod(name~, ..) => name + "()"
    EDyn(name~, ..) => "dyn." + name
    EMacroVar(name~, ..) => "^" + name
    EConfigVar(name~, ..) => "host." + name
    EName(name~, ..) => name
    ETypeName(name~, ..) => name
    EEventPath(segments~, ..) => "e." + segments.join(".")
    EApp(name~, args~, ..) => {
      let parts = []
      for a in args {
        parts.push(a.show_source())
      }
      name + "(" + parts.join(", ") + ")"
    }
    // The operands and the operators alternate: `a + b + c` is three operands
    // and two `+`, which is how one chain of one precedence is carried.
    EChain(ops~, operands~, ..) => {
      let out = StringBuilder()
      for i, e in operands {
        if i > 0 && i - 1 < ops.length() {
          out.write_string(" " + ops[i - 1] + " ")
        }
        out.write_string(e.show_source())
      }
      out.to_string()
    }
    EUnary(op~, operand~, ..) =>
      (if op is UNot { "!" } else { "-" }) + operand.show_source()
    EIf(cond~, then_~, else_~, ..) =>
      "if " +
      cond.show_source() +
      " | " +
      then_.show_source() +
      " | " +
      else_.show_source()
  }
}

///|
fn show_lit(l : Lit) -> String {
  match l {
    LNull => "none"
    LBool(b) => if b { "true" } else { "false" }
    LNum(n) =>
      if n == n.to_int().to_double() {
        n.to_int().to_string()
      } else {
        n.to_string()
      }
    LStr(s) => "\"" + s.replace_all(old="\"", new="\\\"") + "\""
  }
}

///|
fn show_place(p : Place) -> String {
  let out = StringBuilder()
  match p.root {
    PState(f) => out.write_string("it." + f)
    PBind(n) => out.write_string(n)
    PTarget => out.write_string(target_bind)
    PParam(n) => out.write_string(n)
  }
  for s in p.steps {
    match s {
      PField(f) => out.write_string("." + f)
      PIndex(e) => out.write_string("[" + e.show_source() + "]")
    }
  }
  out.to_string()
}
