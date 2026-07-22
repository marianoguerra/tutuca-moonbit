// Turning view vocabulary into MoonBit identifiers.
//
// Two shapes are derived from the component name: a TYPE prefix (`Counter`,
// used as `CounterInput` / `CounterMsg` / …) and a VALUE prefix (`counter`,
// used as `counter_main_view` / `counter_fields` / …). View, handler and id
// names become enum variants.

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
/// "setLabel" / "set-label" / "set_label" -> "SetLabel". Separators and any
/// other non-alphanumeric characters are dropped, capitalizing what follows.
pub fn variant_name(name : String) -> String {
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
/// "Counter" -> "counter", "TodoList" -> "todo_list".
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
    sb.write_char(lower(c))
    prev_alnum = true
  }
  sb.to_string()
}

///|
/// The component name as a MoonBit type prefix, validated: it heads every
/// generated type, so a name that is not an identifier would emit code that
/// does not compile.
pub fn type_prefix(name : String) -> String raise GenError {
  let chars = name.to_array()
  if chars.length() == 0 || !is_alpha(chars[0]) {
    raise BadComponentName(name)
  }
  let sb = StringBuilder::new()
  for i, c in chars {
    if !is_alnum(c) && c != '_' {
      raise BadComponentName(name)
    }
    sb.write_char(if i == 0 { upper(c) } else { c })
  }
  sb.to_string()
}

///|
/// Map source names to variant names, refusing any pair that collides — two
/// handlers named `set-label` and `setLabel` would otherwise silently emit
/// one variant and drop a case.
pub fn variants_for(
  names : Array[String],
) -> Array[(String, String)] raise GenError {
  let seen : Map[String, String] = Map([])
  let out : Array[(String, String)] = []
  for n in names {
    let v = variant_name(n)
    match seen.get(v) {
      Some(first) => raise NameCollision(variant=v, first~, second=n)
      None => {
        seen[v] = n
        out.push((n, v))
      }
    }
  }
  out
}
