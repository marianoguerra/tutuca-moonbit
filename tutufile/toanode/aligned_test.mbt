// What a `style()` body is, and how its two spellings are told apart.
//
// This file was the two-spellings differential while the corpus was converted
// -- each construct written both ways, read to a tree, compared
// whitespace-exact -- and that half went with the spelling it compared
// against. `to_anode_test.mbt` is the corpus of constructs now, and
// `whitespace_test.mbt` states the rule that replaced the old one.
//
// What is left is about tutuca's own extension rather than about the notation
// it moved from: a style body is raw CSS or it is notation, and THE BODY'S OWN
// SHAPE decides -- `@{…}` is an at-notation literal block, an ordinary block is
// `marianoguerra/shrubbery-css`. Neither can be read as the other, so there is
// no flag and no second element name.

///|
/// The style a view carries.
fn view_style(src : String) -> String {
  let decls = view_decls(src)
  for d in decls {
    if d.kind is View {
      let macros = macros_of(decls) catch { _ => return "!macros" }
      let b = ViewBuilder::new(macros~)
      let v = b.view(d) catch { _ => return "!refused" }
      return v.style
    }
  }
  "!no view"
}

///|
test "an `@` inside a raw-text block is refused, not silently dropped" {
  // A LATENT BUG this alignment surfaced, and it predates it: `@media` inside
  // an at-notation body is a FORM whose command is `media`, so the reader saw
  // no string there and wrote nothing. The stylesheet came out as
  // ` (min-width: 40em) { .a { color: red } }` — CSS a browser accepts and
  // ignores. `styles.md` says a conditional group rule belongs in a scoped
  // style, so following the documentation reached it.
  //
  // It is refused now, and the message names both repairs -- escape the `@`,
  // or write the block as notation, where `media(…)` is a call and no `@`
  // appears at all.
  inspect(
    view_style(
      card(
        "  Card:\n    style(): @{@media (min-width: 40em) { .a { color: red } }}\n    p(): \"x\"",
      ),
    ),
    content="!refused",
  )
}

///|
test "balanced braces need no escaping at all" {
  // The half that DOES work, and the reason raw text is spelled `@{…}` rather
  // than counted: at-notation ends its body at the matching brace.
  inspect(
    view_style(
      card(
        "  Card:\n    style(): @{.a { color: red } .b { color: blue }}\n    p(): \"x\"",
      ),
    ),
    content=".a { color: red } .b { color: blue }",
  )
}

///|
test "a bare declaration list is a style too" {
  // What `styles.md` documents: with no selector these land in the component's
  // scope wrapper and style its root element.
  let s = view_style(
    card(
      "  Card:\n    style(): @{padding: 0.75rem; color: red;}\n    p(): \"x\"",
    ),
  )
  inspect(s, content="padding: 0.75rem; color: red;")
}

///|
/// The style a FILE-level declaration carries -- `style()` at the top of
/// `view:`, which is the component's `common_style`, or `style(~global)`,
/// which is the page's.
fn file_style(src : String) -> String {
  for d in view_decls(src) {
    if d.kind is Style {
      return @toanode.style_of(d) catch { _ => "!refused" }
    }
  }
  "!no style"
}

///|
test "a style block written as notation lowers to CSS" {
  inspect(
    view_style(
      card(
        "  Card:\n    style():\n      class(mine):\n        color: red\n    p(): \"x\"",
      ),
    ),
    content=".mine{color:red}",
  )
}

///|
test "a bare declaration is legal in a scoped block, and styles the root" {
  // Legal because the block is lowered as a rule BODY, through
  // `shrubbery-css`'s `lower_block`. At top level the same input is
  // `shrubcss::declaration_at_top_level` -- the right answer to a question
  // this is not asking.
  inspect(
    view_style(
      card(
        "  Card:\n    style():\n      padding: rem(0.75)\n      class(mine):\n        color: red\n    p(): \"x\"",
      ),
    ),
    content="padding:0.75rem;.mine{color:red}",
  )
}

///|
test "the two spellings of one stylesheet agree" {
  let raw = view_style(
    card("  Card:\n    style(): @{.mine{color:red}}\n    p(): \"x\""),
  )
  let notation = view_style(
    card(
      "  Card:\n    style():\n      class(mine):\n        color: red\n    p(): \"x\"",
    ),
  )
  assert_eq(notation, raw)
}

///|
test "a conditional group rule nests inside a scoped block" {
  // `@media` and its family DO nest, so they are legal in a view's own style.
  // Written as notation the `@` never appears -- which is the repair the
  // raw-text refusal names.
  inspect(
    view_style(
      card(
        "  Card:\n    style():\n      media(min_width: em(40)):\n        class(a):\n          color: red\n    p(): \"x\"",
      ),
    ),
    content="@media (min-width:40em){.a{color:red}}",
  )
}

///|
test "a global block is a stylesheet in its own right" {
  // The scope decides the CONTEXT, and that is the whole gain: `@font-face` is
  // top-level-only, so it is legal here.
  inspect(
    file_style(
      "spec:\n  Card:\n    field n :: Int\n\nview:\n  style(~global):\n    font_face():\n      font_family: \"X\"\n\n  Card:\n    p(): \"x\"\n",
    ),
    content="@font-face{font-family:\"X\"}",
  )
}

///|
test "a top-level-only at-rule is refused in a SCOPED block" {
  // `styles.md` says a browser silently drops `@font-face` from a scoped block
  // and that NOTHING CHECKS THIS. Something does now: `shrubbery-css@0.2.0`
  // added `at_rule_not_nestable`, checked against the enclosing context, so
  // the same declaration is legal one scope out and refused here.
  //
  // This test recorded the opposite until that landed -- the claim was made
  // before it was measured, the measurement refuted it, and the fix restored
  // it. The claim is only worth anything with this test under it.
  inspect(
    view_style(
      card(
        "  Card:\n    style():\n      font_face():\n        font_family: \"X\"\n    p(): \"x\"",
      ),
    ),
    content="!refused",
  )
}
