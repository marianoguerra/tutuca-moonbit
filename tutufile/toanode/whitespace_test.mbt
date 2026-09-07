// Whitespace, which is the one thing going direct deliberately changes.
//
// The rule: a text node exists where the file writes one, with the text the
// file wrote. Nothing is trimmed, nothing is condensed, and nothing is
// inferred from what kind of element it sits in.
//
// The rule it replaces was two passes deep. An HTML tokenizer turns source
// LAYOUT into text nodes — the newline and indent between two tags are
// characters in the document — and `anode/whitespace.mbt` then removes the ones
// it decides were layout, using a table of which tags are block-level. That
// table is not a fact about the view; it is a repair for something the
// tokenizer did. At-notation never does it, so there is nothing to repair.
//
// The printer path made this worse than a wash, because the printer INDENTS.
// `@button{+}` printed as `<button>\n      +\n    </button>` and the text node
// that came back was `"\n      +\n    "` — not whitespace-only, so the
// condensing pass left it alone. The printer's own formatting became content.

///|
/// The text nodes of a tree, in order, with their exact contents.
fn texts(node : @anode.ANode) -> Array[String] {
  let out = []
  fn walk(n : @anode.ANode) -> Unit {
    match n {
      Text(d) => out.push(d.val)
      Dom(d) =>
        for c in d.childs {
          walk(c)
        }
      Fragment(d) =>
        for c in d.childs {
          walk(c)
        }
      Show(d) | Hide(d) | PushView(d) | Scope(d) => walk(d.node)
      Each(d) => walk(d.node)
      Slot(d) => walk(d.node)
      _ => ()
    }
  }

  walk(node)
  out
}

///|
fn view_texts(view : String) -> Array[String] {
  match direct_view(card(view)) {
    Some(n) => texts(n)
    None => ["<no view>"]
  }
}

///|
test "text is what the file wrote, with nothing trimmed" {
  @debug.assert_eq(view_texts("  Card:\n    @button{+}"), ["+"])
  @debug.assert_eq(view_texts("  Card:\n    @p{ padded }"), [" padded "])
}

///|
/// The case the block/inline table existed to get right, and the case it could
/// still get wrong: spacing BETWEEN inline elements is content, and here it is
/// simply the text that was written.
test "spacing between inline elements is kept exactly" {
  @debug.assert_eq(view_texts("  Card:\n    @p{a @b{c} d}"), ["a ", "c", " d"])
  @debug.assert_eq(view_texts("  Card:\n    @p{@b{a} @b{b}}"), ["a", " ", "b"])
}

///|
/// A body written across lines gets the newline it was written with, and NOT
/// the indentation — shrubbery strips a multi-line at-body's indent before this
/// package sees it, so "explicit" does not mean "the file's leading spaces".
test "a multi-line body keeps its newlines and loses its indentation" {
  @debug.assert_eq(
    view_texts("  Card:\n    @div{\n      @span{a}\n      @span{b}\n    }"),
    ["a", "\n", "b"],
  )
}

///|
/// Nothing infers a text node that was not written. An element written with no
/// content has no children at all, rather than an empty text node the
/// condensing pass would have had to remove.
test "an empty element has no text node" {
  @debug.assert_eq(view_texts("  Card:\n    @div{}"), [])
  @debug.assert_eq(view_texts("  Card:\n    @input(~class: \"x\")"), [])
}

///|
/// The property that was broken, and the one worth watching: the text a
/// consumer reads is the text the file holds, and nothing on the way adds a
/// character nobody wrote.
///
/// The printer path used to fail this by INDENTING. `@button{+}` printed as
/// `<button>\n      +\n    </button>` and the text node that came back was
/// `"\n      +\n    "` — its own formatting, become content. There is nothing
/// between the file and the tree now, so there is nowhere for that to happen.
test "nothing makes its own formatting into text" {
  let src = card("  Card:\n    @button{+}")
  @debug.assert_eq(direct_view(src).map(texts), Some(["+"]))
}

///|
/// A body that arrives as SEVERAL content pieces still reads as one text node,
/// with the whitespace at the seams intact.
///
/// An escape splits a body — `@p{x @"@" y}` is the three pieces `"x "`, `"@"`,
/// `" y"` — but so does anything else that interrupts a text run, so this is not
/// a fact about escapes. The spaces live at the EDGES of the neighbouring
/// pieces, which is exactly what a per-piece trim or a joining separator would
/// destroy, and neither is here.
///
/// Asserted on the STRING. `strip_ws` collapses whitespace by design, so a
/// comparison that went through it would agree whether the spaces were there or
/// not — which is how the same bug reached the writer unnoticed.
test "a body split into pieces keeps the whitespace at the seams" {
  @debug.assert_eq(view_texts("  Card:\n    @p{write to me @\"@\" home}"), [
    "write to me @ home",
  ])
  @debug.assert_eq(view_texts("  Card:\n    @p{x @\"@\" y}"), ["x @ y"])
  @debug.assert_eq(view_texts("  Card:\n    @p{a@\"@\"b}"), ["a@b"])
}

///|
/// Wrapped prose, which arrives as more pieces than it looks like.
///
/// A continuation line indented deeper than the shared indent contributes the
/// EXCESS as a piece of its own: `@p{one two\n     three four}` is the four
/// pieces `"one two"`, `"\n"`, `"  "`, `"three four"`, where a plain two-line
/// body is three. So the piece count varies with how the prose is laid out, and
/// anything switching on it — or assuming text-newline-text — sees a different
/// shape on wrapped prose than on the same content unwrapped.
///
/// The rule, as `marianoguerra/shrubbery`'s README states it in doctests: one
/// piece per run of text on a line, a newline piece per break, a piece for
/// whatever indentation a line has beyond the shared indent, a piece per escape
/// result — concatenate them.
///
/// Joining with nothing inserted is what makes them come out right, and it is
/// also what preserves the relative indentation the author wrote. The
/// de-indentation itself is the notation's specification rather than a loss:
/// the columns shared with the first line's start are not part of the text.
test "wrapped prose joins to the text that was written" {
  @debug.assert_eq(view_texts("  Card:\n    @p{write to me\n       home}"), [
    "write to me\nhome",
  ])
  @debug.assert_eq(
    view_texts("  Card:\n    @p{one two\n         three four}"),
    ["one two\n  three four"],
  )
}
