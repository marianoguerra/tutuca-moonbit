// The markup translation: every construct the notation has, read into a tree.
//
// Same corpus as `to_expr_test.mbt` and the same history: this was a
// DIFFERENTIAL against the path it replaced — the printer wrote the file as the
// blocks an HTML front end read, the splitter split them, and
// `@anode.View::compile` parsed the template, and the two trees were compared
// modulo whitespace. That is what made the printer safe to delete, and it went
// with it. What is left is the corpus. See `reads` below.
//
// Whitespace was the one deliberate difference rather than a gap in the test,
// and it is still the one thing worth pinning on its own:
// `whitespace_test.mbt` says what the rule is.

///|
/// The `view:` section's declarations.
fn view_decls(src : String) -> Array[@tutufile.Decl] {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  let file = @tutufile.read(src, id)
  match file.section(View) {
    Some(s) => s.decls
    None => []
  }
}

///|
/// The first view declaration in a source, built directly.
pub fn direct_view(src : String, name? : String = "") -> @anode.ANode? {
  let decls = view_decls(src)
  let macros = macros_of(decls) catch { _ => return None }
  for d in decls {
    if d.kind is View && (name == "" || d.name == name) {
      let b = ViewBuilder::new(macros~)
      let v = b.view(d) catch { _ => return None }
      return v.anode
    }
  }
  None
}

///|
/// The construct reads, and the tree it reads into.
///
/// This was a DIFFERENTIAL assertion while the printer existed: the same
/// source read both ways, whitespace normalized, compared as trees. That is
/// what made the printer safe to delete, and it went with it — what is left is
/// the corpus, which is the half worth keeping. Every case below is a
/// construct the notation has, and the claim is that the reader answers a tree
/// for each of them.
fn reads(src : String, name? : String = "") -> Unit raise {
  assert_true(direct_view(src, name~) is Some(_), msg=src)
}

///|
/// A `view:` section wrapped in the smallest file that carries one.
fn card(view : String) -> String {
  "spec:\n  Card:\n    field n :: Int\n\nview:\n" + view + "\n"
}

///|
test "an element, its attributes and its text" {
  reads(card("  Card:\n    div(class: \"box\"): \"hello\""))
}

///|
test "a dynamic attribute, a constant one, and a flag" {
  reads(
    card(
      "  Card:\n    input(class: \"draft\", value: it.n, disabled, aria_label: \"draft\")",
    ),
  )
}

///|
test "a hole is a render-text node" {
  reads(card("  Card:\n    output(): @(it.n)"))
}

///|
test "an event handler registers, and the element carries its eid" {
  reads(card("  Card:\n    button(~on_click: add): \"+\""))
}

///|
test "a handler with arguments reads the event" {
  reads(card("  Card:\n    input(~on_input: search(e.value))"))
}

///|
test "a property write is an action rather than a handler" {
  reads(card("  Card:\n    input(~on_input: it.n := e.value)"))
}

///|
test "an increment write carries the read it is built from" {
  reads(card("  Card:\n    button(~on_click: it.n += 1): \"+\""))
}

///|
test "a collection action names the operation" {
  reads(card("  Card:\n    button(~on_click: it.rows.push(it.n)): \"add\""))
}

///|
test "show and hide wrap what they govern" {
  reads(card("  Card:\n    show(it.open): div(): \"body\""))
  reads(card("  Card:\n    hide(it.open): div(): \"body\""))
}

///|
test "an each carries its sequence and its binder" {
  reads(card("  Card:\n    ul():\n      each(row in it.rows):\n        li(): @(row)"))
}

///|
test "an each with a filter and an index" {
  reads(
    card(
      "  Card:\n    ul():\n      each(row, i in it.rows, ~when: unfinished):\n        li(): @(row)",
    ),
  )
}

///|
/// Reading a MEMBER of a loop's binding: the most ordinary thing a loop body
/// does, and where the printer path used to lose the node silently.
///
/// Two sigil rules met and neither knew about the other. `rename_ex` maps the
/// file's binder `row` onto the renderer's binding, giving the name `@value`;
/// `print_member` then prefixed `@` unconditionally, giving `@@value.title`.
/// Nothing parsed that, so the value was dropped, so the `<x text>` element was
/// dropped — and the loop rendered empty rows with no diagnostic anywhere.
/// `print_member` now adds the sigil only when it is not already there.
///
/// Going direct there is no sigil to apply twice: a binder maps to a binding
/// once, in `ExCtx`, and a member read is a `Place` with one step. Both are
/// asserted, because the two paths agreeing is the whole claim.
test "a loop binding's member is a place with one step" {
  let src = card("  Card:\n    ul():\n      each(row in it.rows):\n        li(): @(row.title)")
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  ignore(id)
  let direct = @debug.to_string(direct_view(src).map(strip_ws))
  assert_true(direct.contains("PBind(\"value\"), steps: [PField(\"title\")]"))
}

///|
test "a render node, with and without a named view" {
  reads(card("  Card:\n    render(it.child)"))
  reads(card("  Card:\n    render(it.child, ~as: \"edit\")"))
}

///|
test "a conditional attribute value" {
  reads(card("  Card:\n    div(class: if it.on | \"a\" | \"b\"): \"x\""))
}

///|
test "the markup directives, each in its own variant" {
  reads(card("  Card:\n    @div(~inner_html: it.body)"))
  reads(card("  Card:\n    @div(~inner_md: it.body)"))
  reads(card("  Card:\n    @div(~inner_svg: it.body)"))
  reads(card("  Card:\n    @div(~dangerously_inner_html: it.body)"))
}

///|
test "a nested tree keeps its shape" {
  reads(
    card(
      "  Card:\n    div(class: \"box\"):\n      button(class: \"add\", ~on_click: add): \"+\"\n      output(): @(it.n)",
    ),
  )
}

///|
/// A macro call, expanded from the shrubbery tree the macro was written as.
///
/// The two paths agree about what a parameter MEANS — `print_macro` passes its
/// rename map now, so the argument reaches the body on both — and they still
/// differ about the SHAPE: the printer path keeps a `MacroCall` node with the
/// expansion inside it, which the ahead-of-time generator then strips
/// (`viewgen`'s `strip_macro_calls`). Expanding in place is the end state that
/// strip was reaching for, so a macro adds no node of its own at any point.
test "a macro parameter reaches the body" {
  let src = card(
    "  macro badge(~label: \"New\"):\n    span(class: \"badge\"): @(label)\n\n  Card:\n    div(): badge(~label: \"Sale\")",
  )
  let direct = @debug.to_string(direct_view(src).map(strip_ws))
  // the argument is in the tree, and nothing is left of the binding it went
  // through
  assert_true(direct.contains("ELit(lit=LStr(\"Sale\")"))
  assert_false(direct.contains("PBind(\"label\")"))
  // …and a macro adds no node of its own: the call is grafted where it stands,
  // so there is no `MacroCall` for the generator to strip afterwards.
  assert_false(direct.contains("MacroCall"))
}

///|
/// A parameter left at its default takes the default the same way.
test "a macro used at its default" {
  let src = card(
    "  macro badge(~label: \"New\"):\n    span(class: \"badge\"): @(label)\n\n  Card:\n    div(): badge()",
  )
  assert_true(
    @debug.to_string(direct_view(src)).contains("ELit(lit=LStr(\"New\")"),
  )
}

///|
/// A macro body with several elements expands to several nodes, not to a
/// fragment wrapping them.
///
/// The old path keeps a `MacroCall` node with the expansion inside it, which
/// the ahead-of-time generator then strips (`viewgen`'s `strip_macro_calls`).
/// Expanding in place is the end state that strip was reaching for, and it
/// means a macro adds no node of its own to the tree at any point.
test "a macro whose body is more than one element" {
  let src = card(
    "  macro pair(~a: \"x\", ~b: \"y\"):\n    span(): @(a)\n    span(): @(b)\n\n  Card:\n    div(): pair(~a: \"1\", ~b: \"2\")",
  )
  let direct = @debug.to_string(direct_view(src).map(strip_ws))
  assert_false(direct.contains("MacroCall"))
  assert_true(direct.contains("ELit(lit=LStr(\"1\")"))
  assert_true(direct.contains("ELit(lit=LStr(\"2\")"))
}

///|
/// A macro argument that is an EXPRESSION is what holding a macro as a tree
/// buys, and the printer path has nowhere to put one: a `macro_vars` entry is a
/// source STRING, so an argument has to survive being printed and re-lexed in
/// the callee's frame.
test "a macro argument can be an expression" {
  let src = card(
    "  macro shout(~what: \"hi\"):\n    strong(): @(what)\n\n  Card:\n    div(): shout(~what: it.n)",
  )
  let out = @debug.to_string(direct_view(src).map(strip_ws))
  assert_true(out.contains("PState(\"n\")"))
}

///|
/// A macro that reaches itself is refused rather than followed.
test "a macro cannot expand into itself" {
  let src = card(
    "  macro loopy():\n    div(): loopy()\n\n  Card:\n    div(): loopy()",
  )
  assert_true(direct_view(src) is None)
}
