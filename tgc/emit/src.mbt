// The source buffer, and the two naming rules.

///|
/// A Wax source buffer.
///
/// It is a `StringBuilder` with an indent, and it stays that thin on purpose:
/// the generated module's readability is a feature — a card author reads it to
/// find out what a handler became — so the emitters below write Wax the way a
/// person would, rather than assembling a tree that prints as something close.
priv struct Src {
  buf : StringBuilder
  mut depth : Int
}

///|
fn Src::new() -> Src {
  { buf: StringBuilder(), depth: 0, }
}

///|
fn Src::line(self : Src, text : String) -> Unit {
  for _ in 0..<self.depth {
    self.buf.write_string("    ")
  }
  self.buf.write_string(text)
  self.buf.write_string("\n")
}

///|
fn Src::blank(self : Src) -> Unit {
  self.buf.write_string("\n")
}

///|
fn Src::open(self : Src, text : String) -> Unit {
  self.line(text)
  self.depth = self.depth + 1
}

///|
fn Src::close(self : Src, text : String) -> Unit {
  self.depth = self.depth - 1
  self.line(text)
}

///|
fn Src::text(self : Src) -> String {
  self.buf.to_string()
}

///|
/// A Wax string literal.
///
/// Wax literals are `[mut i8]`, which IS `tg_bytes`, so a card's text needs no
/// interning table and no constant pool — the language already hands you the
/// format's text type. What it does need is escaping, and the set is small
/// because a card's names and literals are text rather than binary.
fn wax_str(s : String) -> String {
  let out = StringBuilder()
  out.write_string("\"")
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(c)
    }
  }
  out.write_string("\"")
  out.to_string()
}

///|
/// A double, spelled so Wax reads it back as the same double.
///
/// The trailing `.0` is not decoration: Wax types `1` as an integer and `1.0`
/// as a float, and an `f64` argument spelled `1` is a type error rather than a
/// coercion.
fn wax_num(n : Double) -> String {
  if n.is_nan() {
    // A card cannot write one; a `Ty::zero` cannot be one. Belt and braces.
    return "(0.0 / 0.0)"
  }
  if n.is_inf() {
    return if n > 0.0 { "(1.0 / 0.0)" } else { "(-1.0 / 0.0)" }
  }
  let s = n.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") {
    s
  } else {
    s + ".0"
  }
}

///|
/// A card's name, as a Wax identifier.
///
/// Wax has no source namespaces, so every generated name is prefixed with its
/// component. A card declaring one component gets `C_receive_inc`; a card
/// declaring several gets one per component and they cannot collide, which is
/// the whole of what the prefix is for.
///
/// Non-identifier characters become `_`, and a name that would start with a
/// digit gets a leading `_`. Two card names that mangle the same are a
/// collision the caller has to catch — `compile_decls` does, because a silent
/// one would be a handler answering another handler's messages.
fn mangle(s : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      (!first && c >= '0' && c <= '9')
    if ok {
      out.write_char(c)
    } else {
      out.write_char('_')
    }
    first = false
  }
  let text = out.to_string()
  if text.length() == 0 {
    "_"
  } else {
    text
  }
}
