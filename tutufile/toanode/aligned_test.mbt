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
  // Both spellings are refused now, and the message names both repairs.
  for
    src in [
      "  Card:\n    @style{@media (min-width: 40em) { .a { color: red } }}\n    @p{x}",
      "  Card:\n    style(): @{@media (min-width: 40em) { .a { color: red } }}\n    p(): \"x\"",
    ] {
    inspect(view_style(card(src)), content="!refused")
  }
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

