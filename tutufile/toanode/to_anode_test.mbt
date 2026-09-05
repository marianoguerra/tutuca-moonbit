// The markup translation, against the path it replaces.
//
// Same oracle as `to_expr_test.mbt` and the same reason: `tutufile/lower`
// prints the file as the blocks the old front end reads, `@viewfile.split_file`
// splits them, and `@anode.View::compile` parses the template. Where the two
// trees agree, going direct changed nothing.
//
// They are compared MODULO WHITESPACE, which is the one deliberate difference
// rather than a gap in the test — `whitespace_test.mbt` pins what it is, in
// both directions.

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
/// The same view through the printer, the file splitter and the HTML parser —
/// every step the pipeline takes today.
pub fn printed_view(src : String, name? : String = "") -> @anode.ANode? {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  let out = @lower.lower(src, id)
  let file = @viewfile.split_file(out.text, name="Card") catch {
    _ => return None
  }
  let scope = FileMacros::of(file.macros)
  for comp in file.components {
    for v in comp.views {
      if name == "" || v.name == name {
        let view = @anode.View::new(v.name, raw_view=v.source)
        let px = @anode.ParseContext::new()
        view.compile(px, scope) catch {
          _ => return None
        }
        return view.anode
      }
    }
  }
  None
}

///|
/// A macro scope over the file's own printed macro templates.
priv struct FileMacros {
  by_name : Map[String, @anode.Macro]
}

///|
fn FileMacros::of(defs : Array[@viewfile.MacroDef]) -> FileMacros {
  let by_name : Map[String, @anode.Macro] = Map([])
  for d in defs {
    by_name[d.name] = { defaults: d.defaults, raw_view: d.source, }
  }
  { by_name, }
}

///|
impl @anode.MacroScope for FileMacros with fn lookup_macro(self, name) {
  self.by_name.get(name)
}

///|
/// Both trees, whitespace normalized, as one assertion.
///
/// Normalizing is what makes the comparison about STRUCTURE. The two paths
/// disagree about whitespace by design, and a comparison that would not look
/// past that would say nothing about everything else they agree on.
fn same_tree(src : String, name? : String = "") -> Unit raise {
  let a = direct_view(src, name~)
  let b = printed_view(src, name~)
  assert_true(a is Some(_))
  assert_true(b is Some(_))
  assert_eq(
    @debug.to_string(a.map(strip_ws)),
    @debug.to_string(b.map(strip_ws)),
  )
}

///|
/// A `view:` section wrapped in the smallest file that carries one.
fn card(view : String) -> String {
  "spec:\n  Card:\n    field n :: Int\n\nview:\n" + view + "\n"
}

///|
test "an element, its attributes and its text" {
  same_tree(card("  Card:\n    @div(~class: \"box\"){hello}"))
}

///|
test "a dynamic attribute, a constant one, and a flag" {
  same_tree(
    card(
      "  Card:\n    @input(~class: \"draft\", ~value: it.n, ~disabled, ~aria_label: \"draft\")",
    ),
  )
}

///|
test "a hole is a render-text node" {
  same_tree(card("  Card:\n    @output{@(it.n)}"))
}

///|
test "an event handler registers, and the element carries its eid" {
  same_tree(card("  Card:\n    @button(~on_click: add){+}"))
}

///|
test "a handler with arguments reads the event" {
  same_tree(card("  Card:\n    @input(~on_input: search(e.value))"))
}

///|
test "a property write is an action rather than a handler" {
  same_tree(card("  Card:\n    @input(~on_input: it.n := e.value)"))
}

///|
test "an increment write carries the read it is built from" {
  same_tree(card("  Card:\n    @button(~on_click: it.n += 1){+}"))
}

///|
test "a collection action names the operation" {
  same_tree(card("  Card:\n    @button(~on_click: it.rows.push(it.n)){add}"))
}

///|
test "show and hide wrap what they govern" {
  same_tree(card("  Card:\n    @show(it.open){@div{body}}"))
  same_tree(card("  Card:\n    @hide(it.open){@div{body}}"))
}

///|
test "an each carries its sequence and its binder" {
  same_tree(card("  Card:\n    @ul{@each(row in it.rows){@li{@(row)}}}"))
}

///|
test "an each with a filter and an index" {
  same_tree(
    card(
      "  Card:\n    @ul{@each(row, i in it.rows, ~when: unfinished){@li{@(row)}}}",
    ),
  )
}

///|
/// Reading a MEMBER of a loop's binding is where the printer path silently
/// loses the node, and it is the most ordinary thing a loop body does.
///
/// Two sigil rules meet and neither knows about the other. `rename_ex` maps the
/// file's binder `row` onto the renderer's binding, giving the name `@value`;
/// then `print_member` prefixes `@` unconditionally, giving `@@value.title`.
/// Nothing parses that, so the value is dropped, so the `<x text>` element is
/// dropped — and the loop renders empty rows with no diagnostic anywhere.
///
/// Going direct there is no sigil to apply twice. A binder maps to a binding
/// once, in `ExCtx`, and a member read is a `Place` with one step.
test "a loop binding's member, which the printer path drops" {
  let src = card("  Card:\n    @ul{@each(row in it.rows){@li{@(row.title)}}}")
  // the printed text carries the doubled sigil...
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  assert_true(@lower.lower(src, id).text.contains("@@value.title"))
  // ...so the parsed tree has an empty `li`, while the direct one reads it
  let printed = @debug.to_string(printed_view(src).map(strip_ws))
  let direct = @debug.to_string(direct_view(src).map(strip_ws))
  assert_true(
    printed.contains("tag: \"li\"") && !printed.contains("RenderText"),
  )
  assert_true(direct.contains("PBind(\"value\"), steps: [PField(\"title\")]"))
}

///|
test "a render node, with and without a named view" {
  same_tree(card("  Card:\n    @render(it.child)"))
  same_tree(card("  Card:\n    @render(it.child, ~as: \"edit\")"))
}

///|
test "a conditional attribute value" {
  same_tree(card("  Card:\n    @div(~class: if it.on | \"a\" | \"b\"){x}"))
}

///|
test "the markup directives, each in its own variant" {
  same_tree(card("  Card:\n    @div(~inner_html: it.body)"))
  same_tree(card("  Card:\n    @div(~inner_md: it.body)"))
  same_tree(card("  Card:\n    @div(~inner_svg: it.body)"))
  same_tree(card("  Card:\n    @div(~dangerously_inner_html: it.body)"))
}

///|
test "a nested tree keeps its shape" {
  same_tree(
    card(
      "  Card:\n    @div(~class: \"box\"){\n      @button(~class: \"add\", ~on_click: add){+}\n      @output{@(it.n)}\n    }",
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
test "a macro parameter reaches the body on both paths" {
  let src = card(
    "  macro badge(~label: \"New\"):\n    @span(~class: \"badge\"){@(label)}\n  Card:\n    @div{@badge(~label: \"Sale\")}",
  )
  let printed = @debug.to_string(printed_view(src).map(strip_ws))
  let direct = @debug.to_string(direct_view(src).map(strip_ws))
  // the argument is in the tree on both sides, and neither leaves an unbound
  // binding where it goes
  assert_true(printed.contains("ELit(lit=LStr(\"Sale\")"))
  assert_true(direct.contains("ELit(lit=LStr(\"Sale\")"))
  assert_false(printed.contains("PBind(\"label\")"))
  assert_false(direct.contains("PBind(\"label\")"))
  // and the one difference left is the wrapper
  assert_true(printed.contains("MacroCall"))
  assert_false(direct.contains("MacroCall"))
}

///|
/// A parameter left at its default takes the default the same way.
test "a macro used at its default" {
  let src = card(
    "  macro badge(~label: \"New\"):\n    @span(~class: \"badge\"){@(label)}\n  Card:\n    @div{@badge()}",
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
    "  macro pair(~a: \"x\", ~b: \"y\"):\n    @span{@(a)}\n    @span{@(b)}\n  Card:\n    @div{@pair(~a: \"1\", ~b: \"2\")}",
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
    "  macro shout(~what: \"hi\"):\n    @strong{@(what)}\n  Card:\n    @div{@shout(~what: it.n)}",
  )
  let out = @debug.to_string(direct_view(src).map(strip_ws))
  assert_true(out.contains("PState(\"n\")"))
}

///|
/// A macro that reaches itself is refused rather than followed.
test "a macro cannot expand into itself" {
  let src = card(
    "  macro loopy():\n    @div{@loopy()}\n  Card:\n    @div{@loopy()}",
  )
  assert_true(direct_view(src) is None)
}
