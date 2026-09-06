// The `spec:` section: a `StateDef` printed as the component declaration it
// came from.

///|
/// One type, in the new spelling.
///
/// The inverse of `tutufile/lower`'s `print_ty`, taken from the TYPE rather
/// than from the text it was written as — so a spelling the old parser accepted
/// loosely comes out canonical.
pub fn print_ty(t : @tutuca.Ty) -> String raise NoSpelling {
  match t {
    TyBool => "Bool"
    TyInt(width~, signed~) =>
      match (width, signed) {
        (32, true) => "Int"
        (8, true) => "Int8"
        (16, true) => "Int16"
        (32, false) => "UInt"
        (8, false) => "UInt8"
        _ => "UInt16"
      }
    TyFloat => "Double"
    TyText => "String"
    TyList(e) => "List.of(" + print_ty(e) + ")"
    TyTuple(ts) => {
      let parts = []
      for x in ts {
        parts.push(print_ty(x))
      }
      "Tuple.of(" + parts.join(", ") + ")"
    }
    TyOption(e) => "maybe(" + print_ty(e) + ")"
    TyRecord(n) | TyEnum(n) | TyVariant(n) => n
    TyFlags(n, _) => "Set.of(" + n + ")"
    TySet => "Set.of(String)"
    TyOMap(v) => "Map.of(String, " + print_ty(v) + ")"
    TyComp(Some(c)) => "Instance.of(" + c + ")"
    TyComp(None) => "Instance"
    TyCompProtocols(ids) => "Instance.of(" + ids.join(" && ") + ")"
    TyTable => "Table"
    TyAny => "Any"
  }
}

///|
/// One component's `spec:` body.
pub fn print_spec(
  def : @statedef.StateDef,
  root~ : Bool,
  names~ : Map[String, String],
  out : StringBuilder,
) -> Unit raise NoSpelling {
  write_doc(out, def.doc, "  ")
  let head = if root { " ~root" } else { "" }
  // A component that declares no members is written as a bare name: its whole
  // content is its view, and `:` with nothing under it is not a file.
  if is_empty(def) {
    out.write_string("  \{def.component}\{head}\n")
    return
  }
  out.write_string("  \{def.component}\{head}:\n")
  let mut first = true
  fn gap() {
    if !first {
      out.write_string("\n")
    }
    first = false
  }

  for f in def.fields {
    if f.doc is Some(_) {
      gap()
    }
    first = false
    write_doc(out, f.doc, "    ")
    out.write_string(
      "    field \{@names.snake_of(f.name)} :: \{print_ty(f.ty)}\n",
    )
  }
  for p in def.properties {
    gap()
    write_doc(out, p.doc, "    ")
    let vis = if p.public_ { " ~public" } else { "" }
    let name = @names.snake_of(p.name)
    // A property whose accessors are field reads is declared and implemented on
    // one line; anything with a body is declared here and implemented in
    // `logic:`, which is where behaviour lives.
    match (p.getter, p.setter) {
      (Some(g), Some(s)) => {
        out.write_string("    property \{name} :: \{print_ty(p.ty)}\{vis}:\n")
        out.write_string("      get: it.\{@names.snake_of(field_of(g))}\n")
        out.write_string("      set: it.\{@names.snake_of(field_of(s))}\n")
      }
      (Some(g), None) => {
        out.write_string("    property \{name} :: \{print_ty(p.ty)}\{vis}:\n")
        out.write_string("      get: it.\{@names.snake_of(field_of(g))}\n")
      }
      _ => out.write_string("    property \{name} :: \{print_ty(p.ty)}\{vis}\n")
    }
  }
  for r in def.rules {
    gap()
    write_doc(out, r.doc, "    ")
    let word = match r.kind {
      RPred => "pred"
      RInvariant => "invariant"
    }
    let body = expr_text(r.source)
    if r.format == "" {
      out.write_string("    \{word} \{@names.snake_of(r.name)}: \{body}\n")
    } else {
      out.write_string("    \{word} \{@names.snake_of(r.name)}:\n")
      out.write_string("      ~format: \{expr_text(r.format)}\n")
      out.write_string("      \{body}\n")
    }
  }
  for m in def.receive {
    gap()
    write_doc(out, m.doc, "    ")
    out.write_string("    message \{msg_sig(m)}\n")
  }
  for m in def.intent {
    gap()
    write_doc(out, m.doc, "    ")
    out.write_string("    intent \{msg_sig(m)}\n")
  }
  for m in def.express_message {
    gap()
    write_doc(out, m.doc, "    ")
    out.write_string("    express message \{msg_sig(m)}\n")
  }
  for m in def.express_intent {
    gap()
    write_doc(out, m.doc, "    ")
    out.write_string("    express intent \{msg_sig(m)}\n")
  }
  for w in def.wheres {
    gap()
    write_doc(out, w.doc, "    ")
    out.write_string("    where \{print_where(w)}\n")
  }
  for p in def.provide {
    gap()
    // `provide theme = it.theme` — one line each, where the old block was a
    // section. The value is the value language, read and printed like any other.
    out.write_string(
      "    provide \{@names.snake_of(p.name)} = \{expr_text(p.source)}\n",
    )
  }
  for l in def.lookup {
    gap()
    match l.default {
      Some(d) =>
        out.write_string(
          "    lookup \{@names.snake_of(l.name)} = \{expr_text(d)}\n",
        )
      None => out.write_string("    lookup \{@names.snake_of(l.name)}\n")
    }
  }
  if !def.implements.is_empty() {
    gap()
    print_implements(def, names, out)
  }
  if !def.property_bindings.is_empty() || !def.view_bindings.is_empty() {
    gap()
  }
  print_bindings(def, names, out)
  refuse_unconverted(def)
}

///|
/// Whether a component declares no members at all — a view and nothing else,
/// which several of the smallest examples are.
fn is_empty(def : @statedef.StateDef) -> Bool {
  def.fields.is_empty() &&
  def.properties.is_empty() &&
  def.rules.is_empty() &&
  def.wheres.is_empty() &&
  def.receive.is_empty() &&
  def.intent.is_empty() &&
  def.express_message.is_empty() &&
  def.express_intent.is_empty() &&
  def.implements.is_empty() &&
  def.property_bindings.is_empty() &&
  def.view_bindings.is_empty() &&
  def.provide.is_empty() &&
  def.lookup.is_empty()
}

///|
/// An enum CASE: its name exactly as written, and the payload it carries.
///
/// A case name is not renamed. It is a name at the type level — it encodes as
/// itself, a value round-trips through it, and the codec compares it as a
/// string — so it belongs with the component and struct names the rename leaves
/// alone rather than with the members it does not.
fn case_sig(m : @statedef.MsgDef) -> String raise NoSpelling {
  if m.payload.is_empty() {
    return m.source_name
  }
  let parts = []
  for t in m.payload {
    parts.push(print_ty(t))
  }
  "\{m.source_name}(\{parts.join(", ")})"
}

///|
/// A message case: its name, and the payload it carries.
fn msg_sig(m : @statedef.MsgDef) -> String raise NoSpelling {
  let name = @names.rename_member(m.source_name)
  if m.payload.is_empty() {
    return name
  }
  let parts = []
  for t in m.payload {
    parts.push(print_ty(t))
  }
  "\{name}(\{parts.join(", ")})"
}

///|
/// `.field` as written by a compact accessor, without its dot.
fn field_of(source : String) -> String {
  let t = source.trim(chars=" ").to_owned()
  if t.has_prefix(".") {
    t[1:].to_owned()
  } else {
    t
  }
}

///|
/// One expression, read from the old notation and printed in the new.
fn expr_text(source : String) -> String raise NoSpelling {
  let e = @tscript.parse_expr_source(source) catch {
    _ =>
      raise NoSpelling(
        what="an expression that does not parse (`\{source.trim(chars=" ")}`)",
        help="fix it in the `.html` file before converting",
      )
  }
  print_expr(e)
}

///|
/// The parts of a schema this converter does not print yet.
///
/// Each is refused BY NAME rather than dropped: a component whose protocol
/// declarations vanished would compile, register, and compose with nothing.
fn refuse_unconverted(def : @statedef.StateDef) -> Unit raise NoSpelling {
  let missing = []
  if !def.provide_bindings.is_empty() || !def.lookup_bindings.is_empty() {
    missing.push("a `provide` or `lookup` protocol binding")
  }
  guard missing.is_empty() else {
    raise NoSpelling(
      what="\{missing.join(", ")} in `\{def.component}`",
      help="convert this file by hand: the converter prints fields, properties, rules and message declarations, and refuses the rest rather than dropping it",
    )
  }
}

///|
/// A `where` clause: the subject, the relation, and what it relates to.
///
/// The vocabulary is closed and invertible — that is what makes it a `where`
/// rather than a `pred` — so printing it is one arm per relation and no
/// fallthrough.
fn print_where(w : @statedef.WhereDecl) -> String raise NoSpelling {
  let subject = "it." + @names.snake_of(w.subject)
  let field = (f : String) => "it." + @names.snake_of(f)
  match w.relation {
    DIndexOf(field=f, allow_none~) =>
      "\{subject} is_index_of \{field(f)}" +
      (if allow_none { " ~or_none" } else { "" })
    DKeyOf(field=f) => "\{subject} is_key_of \{field(f)}"
    DMemberOf(field=f) => "\{subject} is_member_of \{field(f)}"
    DElementOf(field=f) => "\{subject} is_element_of \{field(f)}"
    DSubsetOf(field=f) => "\{subject} is_subset_of \{field(f)}"
    DCompare(op~, rhs~) => "\{subject} \{op_word(op)} \{operand(rhs)}"
    // A call, because `in_range` is the one relation that takes two arguments
    // and a bare pair would read as two terms of one expression.
    DBetween(lo~, hi~) => "\{subject} in_range(\{operand(lo)}, \{operand(hi)})"
    DOneOf(vs) => {
      let parts = []
      for v in vs {
        parts.push(print_value(v))
      }
      "\{subject} is_one_of [\{parts.join(", ")}]"
    }
    DNonEmpty => "\{subject} non_empty"
    DPattern(p) => "\{subject} pattern \{quote(p)}"
    DFormat(f) => "\{subject} format \{quote(f)}"
    // `where … len <= 100` states the inner relation about the LENGTH rather
    // than about the value. One prefix, because a length is the only projection
    // this vocabulary admits — anything else about a collection is a fact about
    // its elements, and a domain is about the field.
    DLen(inner) => "\{subject} len \{relation_tail(inner)}"
  }
}

///|
/// A relation without its subject, for the one form that nests.
fn relation_tail(d : @tutuca.Domain) -> String raise NoSpelling {
  match d {
    DCompare(op~, rhs~) => "\{op_word(op)} \{operand(rhs)}"
    DBetween(lo~, hi~) => "in_range(\{operand(lo)}, \{operand(hi)})"
    _ =>
      raise NoSpelling(
        what="a `where … len` whose relation is not an ordering",
        help="a length is compared or bounded — `len <= 100`, `len in_range(1, 10)`",
      )
  }
}

///|
fn op_word(op : @tutuca.DomainOp) -> String {
  match op {
    DGe => ">="
    DGt => ">"
    DLe => "<="
    DLt => "<"
  }
}

///|
fn operand(o : @tutuca.DomainOperand) -> String {
  match o {
    DLit(n) => print_num(n)
    DField(f) => "it." + @names.snake_of(f)
  }
}

///|
/// A doc comment, one `///` line per line of it.
pub fn write_doc(out : StringBuilder, doc : String?, indent : String) -> Unit {
  match doc {
    Some(text) =>
      for line in text.split("\n") {
        let t = line.to_owned()
        if t == "" {
          out.write_string("\{indent}///\n")
        } else {
          out.write_string("\{indent}/// \{t}\n")
        }
      }
    None => ()
  }
}

///|
/// A `struct` or an `enum` declared beside a component.
///
/// A struct's fields are its HEADER — `struct Line(what :: String, qty :: Int)`
/// — because a declaration with an empty body is not a declaration. An enum
/// writes one case per line.
pub fn print_user_ty(
  t : @statedef.UserTy,
  out : StringBuilder,
) -> Unit raise NoSpelling {
  write_doc(out, t.doc, "  ")
  match t.kind {
    URecord(fields) => {
      let parts = []
      for f in fields {
        parts.push("\{@names.snake_of(f.name)} :: \{print_ty(f.ty)}")
      }
      out.write_string("  struct \{t.source_name}(\{parts.join(", ")})\n")
    }
    UEnum(cases) => {
      out.write_string("  enum \{t.source_name}:\n")
      for c in cases {
        // The case name as written: it encodes as itself.
        out.write_string("    \{c.0}\n")
      }
    }
    // A case that carries a payload writes it in parentheses, which is what
    // makes the enum a VARIANT rather than a set of names.
    UVariant(cases) => {
      out.write_string("  enum \{t.source_name}:\n")
      for c in cases {
        out.write_string("    \{case_sig(c)}\n")
      }
    }
  }
}
