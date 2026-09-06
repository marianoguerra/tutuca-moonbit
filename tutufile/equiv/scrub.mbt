// What a comparison of two files must NOT look at.
//
// Four things differ between an `.html` file and the `.tutu` file that replaces
// it without either of them meaning something different, and each is here with
// the reason it is here. Everything else is compared.

///|
/// Blank the positions and the registration ids in a `Debug` rendering.
///
/// **Spans** are offsets into the text that was parsed, and the two files are
/// different texts. `core/expr_spec.mbt` already makes this argument for
/// `Expr`'s own `Eq`, which ignores spans for the same reason: a span is where
/// something was read, not what it is.
///
/// **Node ids** — `Some(n)` on the wrappers, a bare `Int` on `Each`, `Render`
/// and `RenderIt`, so both spellings are blanked — are handed out by whoever
/// built the tree, and recovered from
/// the tree by `ParseContext::from_ir` rather than trusted from outside. Two
/// trees that address their own nodes consistently are the same tree; which
/// integers they chose is not a fact about the view. `data-eid` is NOT blanked
/// — that one indexes the handler table an element points into, so it is
/// behaviour — and `data-nid` is not: it names the scope FRAME a node is in,
/// recovered from the tree the same way a node id is, so which integer it got
/// is not a fact about the view either.
///
/// **Layout**: `Debug` wraps a value across lines once it is long enough, so
/// the same tree renders differently depending on how deep it sits. Collapsing
/// runs of whitespace is what makes the comparison about the value.
pub fn scrub(s : String) -> String {
  rename_names(
    tighten(
      @toanode.collapse_ws(
        blank_ints(
          blank_ints(
            blank_ints(
              blank_ints(
                blank_after(s, "node_id: Some(", ")"),
                "\"data-nid\": LNum(",
              ),
              "node_id: ",
            ),
            "start: ",
          ),
          "end_: ",
        ),
      ),
    ),
  )
}

///|
/// Put every name the component OWNS into the spelling a `.tutu` file uses.
///
/// **Renaming is part of the conversion** (`docs/tutu-migration.md`, "Names"),
/// so `pokeAll` in the `.html` file and `poke_all` in the `.tutu` file are the
/// same handler and must compare equal. The rule is total — `@names.snake_of`
/// — so the checker applies it itself rather than being handed a table by the
/// converter it is checking. A converter and a checker sharing a table would
/// agree by construction and prove nothing.
///
/// It runs on BOTH sides, so it cannot hide a difference: two names only
/// collide here if renaming really does map them together, which is what
/// renaming means. What it leaves alone is what the rule leaves alone —
/// anything that is not a bare lowercase identifier, which is every type name,
/// every `Proto::member`, every selector with punctuation in it and every line
/// of prose.
fn rename_names(s : String) -> String {
  let out = StringBuilder()
  let cs : Array[Char] = s.iter().collect()
  let mut i = 0
  while i < cs.length() {
    if cs[i] != '"' {
      out.write_char(cs[i])
      i = i + 1
      continue
    }
    // one quoted run, taking `\"` as an interior quote
    let word = StringBuilder()
    let mut j = i + 1
    while j < cs.length() && cs[j] != '"' {
      if cs[j] == '\\' && j + 1 < cs.length() {
        word.write_char(cs[j])
        j = j + 1
      }
      word.write_char(cs[j])
      j = j + 1
    }
    let text = word.to_string()
    out.write_char('"')
    // A COLLECTION MUTATOR is normalized further than a name: `removeAt` and
    // `deleteAt` are one operation the old language spelled twice, and the new
    // notation keeps one of them. It applies only after `operation=`, so a
    // handler that happens to be called `removeAt` is still just a name.
    out.write_string(
      if after_operation(cs, i) {
        @names.mutator_of(text)
      } else if is_owned_name(text) {
        @names.snake_of(text)
      } else {
        text
      },
    )
    if j < cs.length() {
      out.write_char('"')
    }
    i = j + 1
  }
  out.to_string()
}

///|
/// Whether the quote at `at` opens the value of an `operation=` field.
fn after_operation(cs : Array[Char], at : Int) -> Bool {
  let key : Array[Char] = "operation=".iter().collect()
  at >= key.length() && matches_at(cs, key, at - key.length())
}

///|
/// Whether a quoted string is a name the rename applies to: a bare identifier
/// starting with a lowercase letter.
///
/// Everything else is left alone, and each exclusion is one of the rule's own:
/// an uppercase start is a TYPE, a `::` is a protocol member the wire froze,
/// and anything with a space or a dot in it is prose, a selector or a path
/// rather than a name.
fn is_owned_name(s : String) -> Bool {
  guard s.length() > 0 && s[0] is ('a'..='z') else { return false }
  for c in s {
    guard c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_') else { return false }
  }
  true
}

///|
/// Drop the punctuation `Debug` adds only because it wrapped: the spaces around
/// brackets and the trailing comma before a closer.
///
/// Without this the same tree compares unequal for sitting one level deeper in
/// one file than in the other, which is a fact about the printer's line width
/// and about nothing else.
fn tighten(s : String) -> String {
  let out = StringBuilder()
  let cs : Array[Char] = s.iter().collect()
  for i, c in cs {
    if c == ' ' {
      let prev = if i > 0 { cs[i - 1] } else { ',' }
      let next = if i + 1 < cs.length() { cs[i + 1] } else { ',' }
      if prev is ('(' | '[' | '{') || next is (')' | ']' | '}') {
        continue
      }
    }
    out.write_char(c)
  }
  let once = out.to_string()
  let tidy = StringBuilder()
  let ds : Array[Char] = once.iter().collect()
  for i, c in ds {
    if c == ',' {
      let next = if i + 1 < ds.length() { ds[i + 1] } else { ' ' }
      if next is (')' | ']' | '}') {
        continue
      }
    }
    tidy.write_char(c)
  }
  tidy.to_string()
}

///|
/// Replace the digits following each occurrence of `key` with `_`.
fn blank_ints(s : String, key : String) -> String {
  let out = StringBuilder()
  let cs : Array[Char] = s.iter().collect()
  let k : Array[Char] = key.iter().collect()
  let mut i = 0
  while i < cs.length() {
    if matches_at(cs, k, i) {
      out.write_string(key)
      i = i + k.length()
      let mut saw = false
      while i < cs.length() && cs[i] is ('0'..='9' | '-') {
        i = i + 1
        saw = true
      }
      // Only a run of digits is a value to blank. `node_id: Some(_)` has
      // already been handled and must come through untouched.
      if saw {
        out.write_char('_')
      }
    } else {
      out.write_char(cs[i])
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// Replace `open` … `close` with `open_close`, for `node_id: Some(3)`.
fn blank_after(s : String, open : String, close : String) -> String {
  let out = StringBuilder()
  let cs : Array[Char] = s.iter().collect()
  let k : Array[Char] = open.iter().collect()
  let c : Array[Char] = close.iter().collect()
  let mut i = 0
  while i < cs.length() {
    if matches_at(cs, k, i) {
      out.write_string(open)
      i = i + k.length()
      while i < cs.length() && !matches_at(cs, c, i) {
        i = i + 1
      }
      out.write_char('_')
      out.write_string(close)
      i = i + c.length()
    } else {
      out.write_char(cs[i])
      i = i + 1
    }
  }
  // `node_id: None` and `node_id: Some(_)` say the same thing about a tree that
  // addresses its own nodes: one registered the node and the other did not, and
  // nothing outside the tree reads the difference.
  out.to_string().replace_all(old="node_id: None", new="node_id: Some(_)")
}

///|
fn matches_at(cs : Array[Char], key : Array[Char], at : Int) -> Bool {
  if at + key.length() > cs.length() {
    return false
  }
  for j, c in key {
    if cs[at + j] != c {
      return false
    }
  }
  true
}
