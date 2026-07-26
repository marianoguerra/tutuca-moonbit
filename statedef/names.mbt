// Turning WIT vocabulary into tutuca and MoonBit identifiers.
//
// WIT names are canonically kebab-case; tutuca field and handler names are
// lowerCamel (they are the names views write and JSON carries); MoonBit type
// names are UpperCamel. Three shapes, so three functions — and a collision
// check after every mapping, because `set-label` and `set_label` both land
// on `setLabel` and one would silently shadow the other.

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_alnum(c : Char) -> Bool {
  is_alpha(c) || (c >= '0' && c <= '9')
}

///|
fn upper(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    Int::unsafe_to_char(c.to_int() - 32)
  } else {
    c
  }
}

///|
fn lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    Int::unsafe_to_char(c.to_int() + 32)
  } else {
    c
  }
}

///|
/// "set-label" -> "setLabel". The tutuca runtime name: what a view writes as
/// `.setLabel` and what the JSON encoding carries.
pub fn camel_name(name : String) -> String {
  let sb = StringBuilder::new()
  let mut cap = false
  let mut first = true
  for c in name.to_array() {
    if is_alnum(c) {
      sb.write_char(if first { lower(c) } else if cap { upper(c) } else { c })
      cap = false
      first = false
    } else {
      cap = true
    }
  }
  sb.to_string()
}

///|
/// "set-label" -> "SetLabel". A MoonBit type or enum-variant name.
pub fn upper_name(name : String) -> String {
  let sb = StringBuilder::new()
  let mut cap = true
  for c in name.to_array() {
    if is_alnum(c) {
      sb.write_char(if cap { upper(c) } else { c })
      cap = false
    } else {
      cap = true
    }
  }
  sb.to_string()
}

///|
/// The MoonBit binding for a runtime field name: itself, or itself plus `_`
/// when it is a keyword.
///
/// A WIT field name is free to collide with a MoonBit keyword — `type` and
/// `enum` are perfectly good field names in an IDL. The escape lands on the
/// BINDING only: the runtime name keeps what the view and the JSON use,
/// because renaming it would break both.
pub fn binding_name(name : String) -> String {
  match name {
    "as"
    | "async"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "defer"
    | "derive"
    | "else"
    | "enum"
    | "extern"
    | "false"
    | "fn"
    | "for"
    | "guard"
    | "if"
    | "impl"
    | "import"
    | "in"
    | "init"
    | "is"
    | "let"
    | "letrec"
    | "loop"
    | "main"
    | "match"
    | "mut"
    | "priv"
    | "pub"
    | "raise"
    | "readonly"
    | "return"
    | "self"
    | "struct"
    | "suberror"
    | "test"
    | "trait"
    | "traitalias"
    | "true"
    | "try"
    | "type"
    | "typealias"
    | "using"
    | "virtual"
    | "while"
    | "with"
    // Reserved for possible future use rather than in use today. MoonBit
    // warns on these, and a generated file must not be the thing that warns.
    | "abstract"
    | "alias"
    | "assert"
    | "do"
    | "final"
    | "include"
    | "inherit"
    | "lazy"
    | "method"
    | "module"
    | "package"
    | "static"
    | "super"
    | "typeof"
    | "unsafe"
    | "yield" => name + "_"
    _ => name
  }
}

///|
/// Byte order, for sorting generated declarations.
///
/// NOT `a < b`: MoonBit's `Compare for String` is length-first, so it would
/// put `sel` before `item`. That is still deterministic — which is all the
/// drift check needs — but a generated module reads as a list a person
/// scans, and a list ordered by length reads as unordered.
pub fn str_cmp(a : String, b : String) -> Int {
  let (x, y) = (a.to_array(), b.to_array())
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] != y[i] {
      return if x[i] < y[i] { -1 } else { 1 }
    }
  }
  x.length() - y.length()
}

///|
/// Map WIT names onto identifiers, refusing any pair that collides.
///
/// `kind` names what is being mapped, so the error can say "two fields" or
/// "two variants" rather than making the reader guess.
fn mapped(
  names : Array[String],
  kind : String,
  f : (String) -> String,
) -> Array[(String, String)] raise DefError {
  let seen : Map[String, String] = Map([])
  let out : Array[(String, String)] = []
  for n in names {
    let ident = f(n)
    match seen.get(ident) {
      Some(first) => raise Collision(kind~, ident~, first~, second=n)
      None => {
        seen[ident] = n
        out.push((n, ident))
      }
    }
  }
  out
}

///|
/// The component name a WIT interface names, validated as a MoonBit type
/// prefix: it heads every generated type, so a name that is not an
/// identifier would emit code that does not compile.
fn component_of(iface : String) -> String raise DefError {
  let name = upper_name(iface)
  let chars = name.to_array()
  if chars.length() == 0 || !is_alpha(chars[0]) {
    raise BadInterfaceName(iface)
  }
  name
}
