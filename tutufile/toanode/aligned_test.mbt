// The two notations, read to one tree.
//
// The `view:` section is being aligned with `marianoguerra/shrubbery-html`,
// whose three laws are that an element is a call and its children are its
// BLOCK, that an attribute is a plain declaration, and that text is a string
// literal — so whitespace only ever exists inside one. Tutuca adds three that
// widen rather than contradict: a `~keyword` is a directive and not an
// attribute, an attribute's value is an expression, and a parenthesised group
// in a child position is a hole.
//
// While the corpus is converted both spellings are read, and they are told
// apart STRUCTURALLY rather than by a flag: the old at-notation body arrives as
// a `Brackets` inside the element's parentheses, the new one as a `Block` after
// them. Neither can be read as the other.
//
// The claim here is the one that makes the conversion safe: for each construct,
// the two spellings answer the SAME tree. Compared through `@debug.to_string`,
// which renders a text node's contents exactly — a comparison that normalised
// whitespace could not see the one dimension law 3 changes, and this repo has
// already shipped four defects whose check sat one step from what broke.

///|
/// The same view, written both ways, read to the same tree.
fn same(old : String, new : String) -> Unit raise {
  let a = direct_view(card("  Card:\n    " + old))
  let b = direct_view(card("  Card:\n    " + new))
  assert_true(a is Some(_), msg="old spelling did not read: " + old)
  assert_true(b is Some(_), msg="new spelling did not read: " + new)
  assert_eq(
    @debug.to_string(b.unwrap()),
    @debug.to_string(a.unwrap()),
    msg=new + "\n  is not\n" + old,
  )
}

///|
test "an element, its attributes and its text" {
  same("@div(~class: \"box\"){hello}", "div(class: \"box\"): \"hello\"")
}

///|
test "an element with no children, and a void one" {
  same("@div(~class: \"x\")", "div(class: \"x\")")
  same("@br", "br()")
}

///|
test "a flag is a valueless attribute" {
  same("@input(~type: \"checkbox\", ~disabled)", "input(type: \"checkbox\", disabled)")
}

///|
test "an underscore is a hyphen, in both spellings" {
  same("@div(~data_id: \"3\", ~aria_label: \"Close\")", "div(data_id: \"3\", aria_label: \"Close\")")
}

///|
test "an attribute's value is an expression" {
  same("@input(~value: it.n)", "input(value: it.n)")
  same("@p(~class: @str{n @(it.n)}){x}", "p(class: @str{n @(it.n)}): \"x\"")
}

///|
test "a hole keeps its spelling" {
  same("@output{@(it.n)}", "output(): @(it.n)")
}

///|
test "nesting, and a text run that carries its own space" {
  same(
    "@p{@\"Hello, \"@strong{@(it.n)}!}",
    "p():\n      \"Hello, \"\n      strong(): @(it.n)\n      \"!\"",
  )
}

///|
test "whitespace between two inline elements is a string, not a layout" {
  same(
    "@div{@span{a} @span{b}}",
    "div():\n      span(): \"a\"\n      \" \"\n      span(): \"b\"",
  )
}

///|
test "an event handler, and its modifiers" {
  same("@button(~on_click: inc){+}", "button(~on_click: inc): \"+\"")
  same(
    "@input(~on_keydown: it.n := default ~cancel)",
    "input(~on_keydown: it.n := default ~cancel)",
  )
}

///|
test "an attribute and a directive on one element" {
  same(
    "@button(~class: \"btn\", ~on_click: inc){+}",
    "button(class: \"btn\", ~on_click: inc): \"+\"",
  )
}

///|
test "show and hide" {
  same("@show(it.n){@p{y}}", "show(it.n): p(): \"y\"")
  same("@hide(it.n){@p{n}}", "hide(it.n): p(): \"n\"")
}

///|
test "a comment node" {
  same("@comment{ x }", "comment(): \" x \"")
}

///|
test "a loop, and its render-time options" {
  same(
    "@ul{@each(value, key in it.xs){@li{@(value)}}}",
    "ul():\n      each(value, key in it.xs):\n        li(): @(value)",
  )
  same(
    "@each(value, key in it.xs, ~when: keep){@li{@(value)}}",
    "each(value, key in it.xs, ~when: keep):\n      li(): @(value)",
  )
}

///|
test "rendering a child, and a named view of one" {
  same("@render(it.kid)", "render(it.kid)")
  same("@render(it.kid, ~as: \"edit\")", "render(it.kid, ~as: \"edit\")")
  same("@each(v, k in it.xs){@render(v)}", "each(v, k in it.xs): render(v)")
}

///|
/// The same view, both ways, when the difference is the STYLE and not the tree.
fn same_style(old : String, new : String) -> Unit raise {
  let a = view_style(card("  Card:\n    " + old + "\n    @p{x}"))
  let b = view_style(card("  Card:\n    " + new + "\n    p(): \"x\""))
  assert_eq(b, a, msg=new + "\n  is not\n" + old)
}

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
test "a style block is raw text in either spelling" {
  same_style("@style{.mine { color: red; }}", "style(): @{.mine { color: red; }}")
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
  for src in [
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
      card("  Card:\n    style(): @{.a { color: red } .b { color: blue }}\n    p(): \"x\""),
    ),
    content=".a { color: red } .b { color: blue }",
  )
}

///|
test "a bare declaration list is a style too" {
  // What `styles.md` documents: with no selector these land in the component's
  // scope wrapper and style its root element.
  let s = view_style(
    card("  Card:\n    style(): @{padding: 0.75rem; color: red;}\n    p(): \"x\""),
  )
  inspect(s, content="padding: 0.75rem; color: red;")
}
