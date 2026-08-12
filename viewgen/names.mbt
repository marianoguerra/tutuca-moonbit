// Turning view vocabulary into MoonBit identifiers.
//
// Two shapes are derived from the component name: a TYPE prefix (`Counter`,
// used as `CounterInput` / `CounterMsg` / …) and a VALUE prefix (`counter`,
// used as `counter_views` / `counter_fields` / …). View, handler and id
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
/// "setLabel" / "set-label" / "set_label" -> "SetLabel". Separators and any
/// other non-alphanumeric characters are dropped, capitalizing what follows.
///
/// The same rule statedef applies to a WIT name, and deliberately the same
/// function: a handler the views raise and a message case the schema declares
/// both end up as variants of a generated enum, so if the two spellings could
/// drift, a name declared in the block and used in a view would produce two
/// different variants and neither would be wrong on its own.
pub fn variant_name(name : String) -> String {
  @statedef.upper_name(name)
}

///|
/// "Counter" -> "counter", "TodoList" -> "todo_list".
fn value_prefix(name : String) -> String {
  @statedef.value_prefix(name)
}

///|
/// The component name as a MoonBit type prefix, validated: it heads every
/// generated type, so a name that is not an identifier would emit code that
/// does not compile.
fn type_prefix(name : String) -> String raise GenError {
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
fn variants_for(
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
