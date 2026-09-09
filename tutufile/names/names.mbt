// `loadRowsOk` becomes `load_rows_ok`, and `Container::appendCell` does not.

///|
/// A name the component OWNS, in the spelling a `.tutu` file uses.
///
/// Fields, handlers, computes, rules, macros and a component's own message
/// names are `snake_case` in the new notation. The rule is total and
/// mechanical, which is what lets the checker apply it independently of the
/// converter rather than being handed a table to trust.
///
/// A name already in snake_case is its own answer, so running this twice
/// changes nothing.
pub fn snake_of(name : String) -> String {
  let cs : Array[Char] = name.iter().collect()
  let out = StringBuilder()
  for i, c in cs {
    if c is ('A'..='Z') {
      // A boundary is a capital after a lowercase or a digit (`loadRows`), or
      // the last capital of a run that is starting a new word (`HTMLDoc`).
      let after_lower = i > 0 && cs[i - 1] is ('a'..='z' | '0'..='9')
      let starts_word = i > 0 &&
        cs[i - 1] is ('A'..='Z') &&
        i + 1 < cs.length() &&
        cs[i + 1] is ('a'..='z')
      if after_lower || starts_word {
        out.write_char('_')
      }
      out.write_char(lower_ascii(c))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// One ASCII capital, lowered.
fn lower_ascii(c : Char) -> Char {
  Int::unsafe_to_char(c.to_int() + 32)
}

///|
/// A name written as `Proto::member`, renamed on the half that is ours.
///
/// **A protocol member is not ours to rename.** A protocol id and its members
/// are a wire vocabulary — `"tutuca.dev/universal/Container@1"` and
/// `Container::appendCell`, dispatched by a second host as those exact strings,
/// with `@1` promising they do not move. A card that answered `::append_cell`
/// where another answers `::appendCell` would carry the same protocol id, the
/// same version, different members, and compose with nothing, silently.
///
/// So a qualified name comes back untouched, and the wart of a camelCase member
/// in a snake_case file is correct.
pub fn rename_member(name : String) -> String {
  if name.contains("::") {
    name
  } else {
    snake_of(name)
  }
}

///|
/// A component TYPE keeps its PascalCase: it names a type, not a member.
pub fn is_type_name(name : String) -> Bool {
  name.length() > 0 && name[0] is ('A'..='Z')
}

///|
/// Normalize an internal collection operation to its `.tutu` method spelling.
/// Deletion operations print as `delete_at`.
///
/// Total and idempotent like `snake_of`, and for the same reason: the converter
/// applies it when printing, and the checker applies it when comparing, without
/// either being handed a table by the other.
pub fn mutator_of(name : String) -> String {
  match name {
    "deleteAt" | "delete_at" | "removeAt" | "remove_at" => "delete_at"
    "insertAt" | "insert_at" => "insert_at"
    "setAt" | "set_at" => "set_at"
    other => snake_of(other)
  }
}
