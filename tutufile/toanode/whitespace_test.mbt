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
/// The printer path's own indentation, as content. This is what the direct path
/// stops doing, stated as the thing it is: the same source, through the two
/// paths, and only one of them adds characters nobody wrote.
test "the printer path made its own formatting into text" {
  let src = card("  Card:\n    @button{+}")
  @debug.assert_eq(direct_view(src).map(texts), Some(["+"]))
  @debug.assert_eq(printed_view(src).map(texts), Some(["\n  +\n"]))
}
