// The reader against the printer, over every `logic:` body in the repo's own
// corpus of examples.
//
// The two paths must answer the same declarations: reading the section
// directly, and printing it as the block language for `@tscript.parse` to read
// back. That is the property that lets the printer go — and it is checked by
// COMPARING, because a reader that merely parses is a reader that could be
// producing anything.

///|
fn both(src : String) -> (String, String)? {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Logic) is Some(section) else { return None }
  guard section.decls is [decl, ..] else { return None }
  let direct = read_logic(decl) catch { _ => return None }
  let out = StringBuilder()
  let _ = @lower.print_logic(decl, out) catch { _ => return None }
  let printed = @tscript.parse_script(out.to_string()) catch {
    _ => return None
  }
  Some((flat(scrub(direct)), flat(scrub(printed))))
}

///|
/// The Debug rendering wraps at a width, so the same tree prints differently
/// inside a longer parent. Whitespace out.
fn flat(s : String) -> String {
  let out = StringBuilder()
  let mut space = false
  for c in s {
    if c is (' ' | '\n' | '\t') {
      space = true
    } else {
      // A trailing comma before a closing bracket is layout too: the Debug
      // renderer writes one only when it broke the line.
      if space && !(c is (')' | ']' | '}')) {
        out.write_char(' ')
      }
      space = false
      out.write_char(c)
    }
  }
  let mut text = out.to_string()
  // Whatever the renderer put next to a bracket is layout: the space it used
  // to indent, and the trailing comma it writes only when it broke the line.
  for _ in 0..<3 {
    for
      pair in [
        (",)", ")"),
        (",]", "]"),
        (",}", "}"),
        ("( ", "("),
        ("[ ", "["),
        ("{ ", "{"),
        (" )", ")"),
        (" ]", "]"),
        (" }", "}"),
        (", )", ")"),
      ] {
      text = text.replace_all(old=pair.0, new=pair.1)
    }
  }
  text
}

///|
/// Spans are file positions and the two paths measure from different files —
/// one from the `.tutu`, one from the text it was printed to. Blanked, because
/// what is compared is the declarations and not where they sat.
fn scrub(ds : Array[@tscript.Decl]) -> String {
  let out = @debug.to_string(ds)
  let sb = StringBuilder()
  let cs = out.to_array()
  let mut i = 0
  while i < cs.length() {
    if i + 6 < cs.length() &&
      cs[i] == 's' &&
      cs[i + 1] == 'p' &&
      cs[i + 2] == 'a' &&
      cs[i + 3] == 'n' {
      // `span: {start: 12, end_: 30}` — skip to the closing brace.
      sb.write_string("span: _")
      while i < cs.length() && cs[i] != '}' {
        i = i + 1
      }
      i = i + 1
    } else {
      sb.write_char(cs[i])
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// One `logic:` body, compared both ways.
fn agree(body : String) -> (String, String)? {
  both(
    "spec:\n  T:\n    field n :: Int\n    field xs :: List.of(String)\n    field s :: String\n\nlogic:\n  T:\n" +
    body,
  )
}

///|
test "every statement shape reads the same both ways" {
  let bodies = [
    "    receive inc:\n      it.n += 1\n", "    receive dec:\n      it.n -= 1\n",
    "    receive set_it(v):\n      it.n := v\n", "    receive push(v):\n      it.xs.push(v)\n",
    "    receive flash:\n      send(\"flash\", it.s)\n", "    receive save:\n      ask(\"save_draft\", it.s, ~route: lex)\n",
    "    receive tell:\n      notify(\"changed\", it.n)\n", "    receive stop_it:\n      drop()\n",
    "    receive guard_it:\n      if it.n > 0 | it.n := 0\n", "    receive two_ways:\n      if it.n > 0 | it.n := 0 | it.n := 1\n",
    "    compute caption(): it.s.length()\n", "    pred room: it.n < 10\n", "    receive bump:\n      ~requires: room\n      it.n += 1\n",
    "    bind_with info:\n      heading = it.s\n", "    receive drop_at(i):\n      it.xs.delete_at(i)\n",
    // A constructor inside an expression. There is no aggregate literal in the
    // value language, so both paths lift it into the `new` / `cur` pair that
    // builds one — and the reader had to grow that, because a `.tutu` writes a
    // CALL where the old notation asked for the pair by hand.
     "    receive add_row:\n      it.rows.push(Row())\n", "    receive add_named(t):\n      it.rows.push(Row(label: t))\n",
    // A property with a body, both accessors. `set:` is the one declaration
    // whose parameter nothing writes down — the notation has no place for it
    // and the reader supplies it — so it is the one most worth comparing.
     "    property shown :: Int:\n      get: it.n\n      set: it.n := value\n", "    property signed :: Int:\n      get: if it.n < 0 | -it.n | it.n\n      set:\n        if it.n < 0\n        | it.n := -value\n        | it.n := value\n",
  ]
  let broken = []
  for b in bodies {
    match agree(b) {
      Some((a, p)) =>
        if a != p {
          broken.push(b + "\n  direct: " + a + "\n  printed: " + p)
        }
      None => broken.push("neither path read: " + b)
    }
  }
  @debug.assert_eq(broken, [])
}

///|
test "a transition reads the same both ways" {
  let src =
    #|spec:
    #|  T:
    #|    field n :: Int
    #|logic:
    #|  T:
    #|    /// One up.
    #|    receive inc:
    #|      it.n += 1
    #|
  guard both(src) is Some((a, b)) else { fail("neither path read it") }
  @debug.assert_eq(a, b)
}

///|
/// The one thing the two paths do NOT agree on, and what it is.
///
/// Named rather than left out: a differential test that quietly skips what it
/// cannot reconcile is a test that passes for the wrong reason, and each of
/// these is a fact about the printer that the reader is not obliged to repeat.
///
/// There were three, and two of them were bugs rather than differences of
/// opinion — both found by switching the card compiler onto this reader:
///
///   - The collection method. This reader kept the spelling the NOTATION uses
///     and the printer mapped it back to `deleteAt`; the backends match on the
///     mapped name, so a `logic:` section reaching them with `delete_at` had
///     its handler refused and dropped. Both readers share one table now
///     (`@sh.collection_op`).
///   - A ROW member's parameters. The old notation gave a `~when` filter and an
///     in-loop enricher none — they read the row out of the air — and this
///     reader kept the names the file writes, so the body read a parameter
///     nothing bound. The renderer's names for a row are fixed, so the
///     author's are two spellings of one thing and the body reads a BINDING.
///
/// Both moved up into the agreements.
test "what the two paths disagree about, and why" {
  // 1. `forward(~route: [dyn, lex])` — the printer drops the route. A bug in
  //    a printer that is going, and the reader is the one that is right.
  guard agree("    receive pass:\n      forward(~route: [dyn, lex])\n")
    is Some((direct, printed)) else {
    fail("neither path read the forward")
  }
  assert_true(direct.contains("route=[Dyn, Lex]"))
  assert_true(printed.contains("route=[]"))

}
