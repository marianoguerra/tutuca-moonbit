// Turning state-language names into tutuca and MoonBit identifiers.
//
// A field is written the way a view reads it, so `camel_name` is identity for
// one already in that form and these exist for the two shapes that genuinely
// differ: a MoonBit type or enum-variant name is UpperCamel, and a MoonBit
// binding has to dodge the keywords. The collision check stays, because
// `SetLabel` and `set_label` still both land on `setLabel` and one would
// silently shadow the other.

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
/// A state field name is free to collide with a MoonBit keyword. The escape
/// lands on the BINDING only: the runtime name keeps what the view and JSON
/// use, because renaming it would break both.
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
///
/// Named rather than inlined at the call sites because the NAME is what
/// carries that reasoning; `lexical_compare` alone looks like a style choice.
pub fn str_cmp(a : String, b : String) -> Int {
  a.lexical_compare(b)
}

///|
/// Map source names onto identifiers, refusing any pair that collides.
///
/// `kind` names what is being mapped, so the error can say "two fields" or
/// "two variants" rather than making the reader guess.
fn mapped(
  names : Array[String],
  kind : String,
  f : (String) -> String,
  span : Span,
) -> Array[(String, String)] raise DefError {
  let seen : Map[String, String] = Map([])
  let out : Array[(String, String)] = []
  for n in names {
    let ident = f(n)
    match seen.get(ident) {
      Some(first) => raise Collision(kind~, ident~, first~, second=n, span~)
      None => {
        seen[ident] = n
        out.push((n, ident))
      }
    }
  }
  out
}

///|
/// A component name, validated as a MoonBit type prefix: it heads every
/// generated type, so a name that is not an identifier would emit code that
/// does not compile.
fn component_of(written : String, span : Span) -> String raise DefError {
  let name = upper_name(written)
  let chars = name.to_array()
  if chars.length() == 0 || !is_alpha(chars[0]) {
    raise BadComponentName(name=written, span~)
  }
  name
}

///|
/// "Counter" -> "counter", "TodoList" -> "todo_list".
///
/// The value-namespace spelling of a type name, which is what every generated
/// FUNCTION over a named type is called (`counter_label_to_value`). It lives
/// here rather than in one emitter because two emitters now write calls to
/// those functions, and a name they disagreed about would be a link error
/// nobody could read.
pub fn value_prefix(name : String) -> String {
  let sb = StringBuilder::new()
  let mut prev_alnum = false
  for i, c in name.to_array() {
    if !is_alnum(c) {
      if prev_alnum {
        sb.write_char('_')
      }
      prev_alnum = false
      continue
    }
    let is_upper = c >= 'A' && c <= 'Z'
    if is_upper && i > 0 && prev_alnum {
      sb.write_char('_')
    }
    sb.write_char(lower_char(c))
    prev_alnum = true
  }
  sb.to_string()
}

///|
fn lower_char(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// A MoonBit expression of type `@tutuca.Value` for `e`, which has type `ty`.
///
/// The one projection from the typed world back into the dynamic one, and the
/// reason it is HERE: the codec emitter writes it for every state field, and
/// the script backend writes it wherever a typed expression meets a builtin or
/// a channel payload. Two implementations would disagree about a set or a
/// nested record long before anyone noticed.
///
/// `Any` and a component slot pass through, because they already ARE a Value —
/// which is the case the JSON path could never do at all.
pub fn StateDef::to_value_src(
  self : StateDef,
  ty : StateTy,
  e : String,
) -> String {
  match ty {
    TBool => "Bool(\{e})"
    TInt(..) => "Num(\{e}.to_double())"
    TFloat => "Num(\{e})"
    TText => "Str(\{e})"
    TAny | TComp(_) => e
    TList(inner) =>
      "(List(\{e}.map(x => \{self.to_value_src(inner, "x")})) : @tutuca.Value)"
    TSet | TFlags(_) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, b in \{e} { m[k] = Bool(b) }; (Map(m) : @tutuca.Value) }"
    TOMap(inner) =>
      "{ let m : Map[String, @tutuca.Value] = Map([]); for k, x in \{e} { m[k] = \{self.to_value_src(inner, "x")} }; (Map(m) : @tutuca.Value) }"
    // Nested (inside a list, a map, a record): there is no key to omit here,
    // so None becomes Null. The key-omitting form is at the state level.
    TOption(inner) =>
      "(match \{e} { Some(x) => \{self.to_value_src(inner, "x")}; None => Null })"
    TTuple(ts) => {
      let parts = ts
        .mapi((i, t) => self.to_value_src(t, "\{e}.\{i}"))
        .join(", ")
      "(List([\{parts}]) : @tutuca.Value)"
    }
    TRecord(n) | TEnum(n) | TVariant(n) =>
      match self.user_ty(n) {
        Some({ kind: URecord(fs), .. }) if fs.is_empty() => e
        Some(ut) => "\{value_prefix(ut.name)}_to_value(\{e})"
        // Unresolved: `moonbit_ty` made it a @tutuca.Value, so it already is
        // one.
        None => e
      }
  }
}
