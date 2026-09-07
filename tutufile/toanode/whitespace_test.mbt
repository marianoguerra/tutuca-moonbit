// Whitespace, which is the deepest thing the aligned notation changes.
//
// THE RULE: whitespace only ever exists inside a string. It is
// `marianoguerra/shrubbery-html`'s third law, taken verbatim, and it is what
// makes the indentation free -- a space cannot mean anything unless a string
// says so, and a string says so by containing it.
//
// It replaces two rules, one on top of the other. An HTML tokenizer turns
// source LAYOUT into text nodes -- the newline and indent between two tags are
// characters in the document -- and `anode/whitespace.mbt` then removed the
// ones it decided were layout, using a table of which tags are block-level.
// That table was never a fact about the view; it was a repair for something
// the tokenizer did. At-notation manufactured less but still manufactured: a
// body written across lines carried a `"\n"` text node per break, and an escape
// split one text run into three pieces whose seams had to be joined back.
//
// Under law 3 there is nothing to repair and nothing to join. A text node
// exists where a string literal is written, holding exactly what the literal
// holds, and nowhere else.

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
test "text is what the string holds" {
  @debug.assert_eq(view_texts("  Card:\n    button(): \"+\""), ["+"])
  @debug.assert_eq(view_texts("  Card:\n    p(): \" padded \""), [" padded "])
}

///|
/// Spacing between inline elements is CONTENT, and it is written as content.
///
/// The old spelling put it in the layout -- `@p{a @b{c} d}` -- where it was a
/// space that happened to survive, and layout that happens to survive is layout
/// a formatter can lose. Here it is a string, so nothing can lose it.
test "spacing between inline elements is a string" {
  @debug.assert_eq(
    view_texts(
      "  Card:\n    p():\n      \"a \"\n      b(): \"c\"\n      \" d\"",
    ),
    ["a ", "c", " d"],
  )
  @debug.assert_eq(
    view_texts(
      "  Card:\n    p():\n      b(): \"a\"\n      \" \"\n      b(): \"b\"",
    ),
    ["a", " ", "b"],
  )
}

///|
/// The property that earns the design: the layout is free.
///
/// The same view at two indentations, and on one line versus several, is the
/// same tree. Under every previous spelling this was false -- the at-notation
/// body gained a `"\n"` per line break, and the printer path before it wrote
/// its own indentation into the text -- which is why reformatting a view file
/// was a thing nobody could do safely.
test "reindenting a view cannot change the page" {
  let one = view_texts("  Card:\n    p(): b(): \"a\"")
  let many = view_texts("  Card:\n    p():\n      b():\n        \"a\"")
  @debug.assert_eq(many, one)
  @debug.assert_eq(one, ["a"])
}

///|
/// A body written across lines manufactures NOTHING.
///
/// This is the case that changed. The at-notation body answered
/// `["a", "\n", "b"]` here -- a text node per line break, which rendered as a
/// space between two inline elements and as nothing between two block ones, so
/// the same file meant different things depending on what it wrapped.
test "a multi-line body has no text but its strings" {
  @debug.assert_eq(
    view_texts("  Card:\n    div():\n      span(): \"a\"\n      span(): \"b\""),
    ["a", "b"],
  )
}

///|
/// Nothing infers a text node that was not written.
test "an empty element has no text node" {
  @debug.assert_eq(view_texts("  Card:\n    div()"), [])
  @debug.assert_eq(view_texts("  Card:\n    input(class: \"x\")"), [])
}

///|
/// There is no escape, and there are no pieces.
///
/// The at-notation body needed `@"…"` for a literal `@`, `{` or `}`, and using
/// it split one text run into three whose seams had to be joined back with
/// nothing inserted -- a rule that had to be got right in the reader, in the
/// printer and in the converter, and was got wrong in the converter. A string
/// literal holds the characters it holds.
test "a string literal needs no escape and splits into nothing" {
  @debug.assert_eq(view_texts("  Card:\n    p(): \"write to me @ home\""), [
    "write to me @ home",
  ])
  @debug.assert_eq(view_texts("  Card:\n    p(): \"a@b\""), ["a@b"])
  @debug.assert_eq(view_texts("  Card:\n    p(): \"{ and }\""), ["{ and }"])
}

///|
/// A newline in the text is a newline IN THE STRING.
///
/// Wrapped prose used to be the subtlest case in this file: a continuation line
/// indented past the shared indent contributed its excess as a piece of its
/// own, so the piece count varied with how the prose was laid out. There is one
/// piece now, and it says what it contains.
test "a newline in text is written in the string" {
  @debug.assert_eq(view_texts("  Card:\n    p(): \"write to me\\nhome\""), [
    "write to me\nhome",
  ])
}
