// The second front end against the first: the same `spec:` section read
// directly, and lowered into the block language for the other one to read.
//
// That is what makes the lowering safe to delete. A reader that merely parses
// could be producing anything; a reader that agrees with the thing it replaces,
// declaration by declaration, is one you can take the other side away from.

///|
/// Both readings of one `spec:` section, as text to compare.
fn both_ways(src : String) -> (String, String)? {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Spec) is Some(section) else { return None }
  let direct = @statedef.state_of_tutu(section.decls, name="T") catch {
    _ => return None
  }
  let lowered = @lower.lower(src, id)
  if lowered.reports.length() > 0 {
    return None
  }
  let block = spec_block(lowered.text)
  let printed = @statedef.parse_state(block, name="T") catch {
    _ => return None
  }
  Some((flat(@debug.to_string(direct)), flat(@debug.to_string(printed))))
}

///|
/// The `<script type="tutuca/spec">` block out of the lowered file.
fn spec_block(text : String) -> String {
  let open = "<script type=\"tutuca/spec\">"
  guard text.find(open) is Some(at) else { return "" }
  let from = at + open.length()
  guard text.find("</script>") is Some(_) else { return "" }
  let rest = text[from:].to_owned()
  match rest.find("</script>") {
    Some(end_) => rest[:end_].to_owned()
    None => rest
  }
}

///|
/// Spans measure from two different files, and the Debug renderer wraps at a
/// width. Both out, so what is compared is the declarations.
fn flat(s : String) -> String {
  let out = StringBuilder()
  let cs = s.to_array()
  let mut i = 0
  let mut space = false
  while i < cs.length() {
    // `span: {start: 1, end_: 9}` and `{ start: … }` alike.
    if i + 4 < cs.length() &&
      cs[i] == 's' &&
      cs[i + 1] == 'p' &&
      cs[i + 2] == 'a' &&
      cs[i + 3] == 'n' {
      out.write_string("span:_")
      while i < cs.length() && cs[i] != '}' {
        i = i + 1
      }
      i = i + 1
      continue
    }
    if cs[i] is (' ' | '\n' | '\t') {
      space = true
    } else {
      if space && !(cs[i] is (')' | ']' | '}' | ',')) {
        out.write_char(' ')
      }
      space = false
      out.write_char(cs[i])
    }
    i = i + 1
  }
  let mut text = out.to_string()
  for _ in 0..<3 {
    for
      pair in [
        (",)", ")"),
        (",]", "]"),
        (",}", "}"),
        ("( ", "("),
        ("[ ", "["),
        ("{ ", "{"),
      ] {
      text = text.replace_all(old=pair.0, new=pair.1)
    }
  }
  text
}

///|
/// One component, both ways.
fn agree(body : String) -> (String, String)? {
  both_ways("spec:\n  T:\n" + body)
}

///|
test "a field, a property and a rule read the same both ways" {
  let bodies = [
    "    field n :: Int\n", "    field s :: String\n    field xs :: List.of(String)\n",
    "    field m :: Map.of(String, Int)\n", "    field o :: maybe(Int)\n", "    field c :: Instance\n",
    "    field n :: Int\n    property double :: Int ~public\n", "    field n :: Int\n    property shown :: Int ~public:\n      get: it.n\n",
    "    field n :: Int\n    pred ok: it.n > 0\n", "    field n :: Int\n    invariant sane: it.n >= 0\n",
    "    field n :: Int\n    where it.n >= 0\n", "    field n :: Int\n    where it.n in_range(0, 100)\n",
    "    field s :: String\n    where it.s is_one_of [\"a\", \"b\"]\n", "    field s :: String\n    where it.s non_empty\n",
    "    field n :: Int\n    message bump\n    message add(Int)\n", "    field n :: Int\n    intent picked(String)\n",
    "    field n :: Int\n    express intent asked(Bool)\n",
    // The wiring sections. `wire_value` is the one place the reader WRITES
    // source, so it is the one place worth holding to the printer line by
    // line — a path, a seq-access, `self`, and each shape a default takes.
     "    field theme :: String\n    provide theme = it.theme\n", "    field items :: List.of(Any)\n    field at :: String\n    provide sel = it.items[it.at]\n",
    "    field n :: Int\n    provide Cell = self\n", "    field n :: Int\n    lookup theme\n",
    "    field n :: Int\n    lookup theme = \"plain\"\n", "    field n :: Int\n    lookup n = 0\n",
    "    field n :: Int\n    lookup on = true\n", "    field n :: Int\n    lookup v = null\n",
  ]
  let broken = []
  for b in bodies {
    match agree(b) {
      Some((a, p)) =>
        if a != p {
          broken.push(b + "\n  direct:  " + a + "\n  printed: " + p)
        }
      None => broken.push("neither path read: " + b)
    }
  }
  @debug.assert_eq(broken, [])
}

///|
/// The declarations beside a component, and what a component says about one.
test "types, protocols and the bindings to them read the same both ways" {
  let files = [
    "spec:\n  struct Line(what :: String, qty :: Int)\n\n  T:\n    field n :: Int\n",
    "spec:\n  enum Tone:\n    calm\n    loud\n\n  T:\n    field n :: Int\n", "spec:\n  enum Pick:\n    none_\n    one(String)\n\n  T:\n    field n :: Int\n",
    "spec:\n  protocol Holder = \"x/Holder@1\":\n    message hold(Any)\n    property filled :: Bool\n\n  T:\n    field n :: Int\n",
    "spec:\n  protocol Editable = \"x/Editable@1\":\n    view editor\n\n  T:\n    field n :: Int\n    implements Editable\n    view Editable::editor = chrome\n",
    "spec:\n  protocol Holder = \"x/Holder@1\":\n    property filled :: Bool\n\n  T:\n    field n :: Int\n    implements Holder\n    property filled :: Bool ~public\n    property Holder::filled = filled\n",
    "spec:\n  T:\n    field rows :: List.of(Any)\n    field at :: Int\n    where it.at is_index_of it.rows\n",
    "spec:\n  T:\n    field rows :: Map.of(String, Any)\n    field k :: String\n    where it.k is_key_of it.rows\n",
    "spec:\n  T:\n    field s :: String\n    where it.s len <= 100\n",
  ]
  let broken = []
  for f in files {
    match both_ways(f) {
      Some((a, p)) =>
        if a != p {
          broken.push(f + "\n  direct:  " + a + "\n  printed: " + p)
        }
      None => broken.push("neither path read: " + f)
    }
  }
  @debug.assert_eq(broken, [])
}

///|
/// A default the printer could not carry.
///
/// `@component.lookup_or("entries", "[]")` is the documented MoonBit spelling
/// of an empty-collection fallback, and the lowering refused the `.tutu` line
/// that means it — "a list or map literal has no place in an expression",
/// which is true of an expression and not of this. So there is no other side
/// to agree with here, and the assertion is that the direct reader reads it.
test "an empty collection is a lookup default the lowering could not print" {
  let src = "spec:\n  T:\n    field n :: Int\n    lookup xs = []\n"
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Spec) is Some(section) else { fail("no spec section") }
  let defs = @statedef.state_of_tutu(section.decls, name="T")
  @debug.assert_eq(defs[0].lookup.map(l => (l.name, l.default)), [
    ("xs", Some("[]")),
  ])
}
