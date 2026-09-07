// The claim that makes the conversion safe: a converted view reads to the tree
// the original read to.
//
// Compared WHITESPACE-EXACT, through `@debug.to_string`. A comparison that
// normalised whitespace would be blind to the one dimension the aligned
// notation changes, and this repo has already shipped four defects whose check
// sat one step from what broke.

///|
/// A `view:` section wrapped in the smallest file that carries one.
fn card(view : String) -> String {
  "spec:\n  Card:\n    field n :: Int\n\nview:\n" + view + "\n"
}

///|
/// The `view:` declarations of a source.
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
/// The first view declaration of a source.
fn first_view(src : String) -> @tutufile.Decl? {
  for d in view_decls(src) {
    if d.kind is View {
      return Some(d)
    }
  }
  None
}

///|
/// The tree a source's first view reads to.
fn tree(src : String) -> String raise {
  let decls = view_decls(src)
  let macros = @toanode.macros_of(decls)
  let d = first_view(src).unwrap()
  let b = @toanode.ViewBuilder::new(macros~)
  @debug.to_string(b.view(d).anode)
}

///|
/// Convert one view's body, and answer the whole file rewritten.
fn convert(src : String) -> String raise {
  let d = first_view(src).unwrap()
  let body = @toshrub.print_view(d, "    ")
  "spec:\n  Card:\n    field n :: Int\n\nview:\n  " + d.name + ":\n" + body
}

///|
/// Convert, and assert the two read alike.
fn survives(view : String) -> Unit raise {
  let src = card(view)
  let out = convert(src)
  assert_eq(tree(out), tree(src), msg=out)
}

///|
test "an element, its attributes and its text" {
  survives("  Card:\n    @div(~class: \"box\"){hello}")
}

///|
test "a void element and an empty one" {
  survives("  Card:\n    @div{@br@p(~class: \"x\")}")
}

///|
test "a flag, a hyphenated name and an expression value" {
  survives(
    "  Card:\n    @input(~type: \"checkbox\", ~disabled, ~data_id: \"3\", ~value: it.n)",
  )
}

///|
test "a hole, and a string template" {
  survives("  Card:\n    @p(~class: @str{n @(it.n)}){@(it.n)}")
}

///|
test "text that carries its own whitespace" {
  survives("  Card:\n    @p{@\"Hello, \"@strong{@(it.n)}!}")
  survives("  Card:\n    @div{@span{a} @span{b}}")
}

///|
test "an event, its arguments and its modifiers" {
  survives("  Card:\n    @button(~class: \"b\", ~on_click: inc){+}")
  survives("  Card:\n    @input(~on_keydown: it.n := default ~cancel)")
}

///|
test "the forms: show, hide, each, render" {
  survives("  Card:\n    @show(it.n){@p{y}}")
  survives("  Card:\n    @hide(it.n){@p{n}}")
  survives("  Card:\n    @ul{@each(value, key in it.xs){@li{@(value)}}}")
  survives(
    "  Card:\n    @each(value, key in it.xs, ~when: keep){@li{@(value)}}",
  )
  survives("  Card:\n    @render(it.kid, ~as: \"edit\")")
  survives("  Card:\n    @each(v, k in it.xs){@render(v)}")
}

///|
test "a comment node keeps its edges" {
  survives("  Card:\n    @div{@comment{ x }}")
}

///|
test "a whole view, as the corpus writes one" {
  survives(
    "  Card:\n    @div{@button(~class: \"dec\", ~on_click: dec){-} @span(~class: \"count\"){@(it.n)} @button(~class: \"inc\", ~on_click: inc){+}}",
  )
}

///|
/// A whole file, converted, with everything outside `view:` byte-identical.
fn file_survives(src : String) -> String raise {
  let sources = @report.Sources::new()
  let id = sources.add("card.tutu", src)
  let f = @tutufile.read(src, id)
  let out = @toshrub.print_file(src, f).unwrap()
  // Every view in the file reads to the tree it read to before.
  let before = view_trees(src)
  let after = view_trees(out)
  assert_eq(after, before, msg=out)
  out
}

///|
/// Every view of a source, as trees, keyed in declaration order.
fn view_trees(src : String) -> Array[String] raise {
  let decls = view_decls(src)
  let macros = @toanode.macros_of(decls)
  let out = []
  for d in decls {
    if d.kind is View {
      let b = @toanode.ViewBuilder::new(macros~)
      out.push(d.name + " => " + @debug.to_string(b.view(d).anode))
    }
  }
  out
}

///|
test "a file with a macro, a style, and two views" {
  let src =
    #|spec:
    #|  Card:
    #|    field n :: Int
    #|
    #|view:
    #|  @style{.mine { color: red; }}
    #|
    #|  macro badge(~label: "New"):
    #|    @span(~class: "badge"){@(label)}
    #|
    #|  Card:
    #|    @div{@badge(~label: "Beta") @button(~on_click: inc){+}}
    #|
    #|  Card.edit:
    #|    @input(~value: it.n, ~on_input: it.n := e.value)
    #|
  let out = file_survives(src)
  inspect(
    out,
    content=(
      #|spec:
      #|  Card:
      #|    field n :: Int
      #|
      #|view:
      #|  style(): @{.mine { color: red; }}
      #|
      #|  macro badge(~label: "New"):
      #|    span(class: "badge"):
      #|      @(label)
      #|
      #|  Card:
      #|    div():
      #|      badge(~label: "Beta")
      #|      " "
      #|      button(~on_click: inc):
      #|        "+"
      #|
      #|  Card.edit:
      #|    input(value: it.n, ~on_input: it.n := e.value)
      #|
    ),
  )
}

///|
test "a view with no body keeps its bare name" {
  // A REGRESSION. `MinimumViableComponent` is a real view in the corpus -- a
  // component that renders nothing -- written as a bare name with no `:` at
  // all. Giving it a colon writes a block with nothing under it, which the
  // reader rejects two lines later with "nothing follows this `:`".
  //
  // The tree check did not catch it: both spellings read to the same empty
  // view, so they compared equal, and the FILE was what stopped parsing. That
  // is why `cmd/to-shrub` now re-reads its own output and asks whether it is a
  // file at all, separately from asking what it means.
  let src =
    #|spec:
    #|  Card:
    #|    field n :: Int
    #|
    #|view:
    #|  Empty
    #|
    #|  Card:
    #|    p(): "x"
    #|
  let out = file_survives(src)
  inspect(
    out,
    content=(
      #|spec:
      #|  Card:
      #|    field n :: Int
      #|
      #|view:
      #|  Empty
      #|
      #|  Card:
      #|    p():
      #|      "x"
      #|
    ),
  )
}

///|
test "converting an already-converted file changes nothing" {
  // Idempotency, which is not required of a throwaway but is what caught the
  // printer reading only the OLD spelling of a raw-text body: run twice and
  // every `style()` came back empty. The round-trip check refused on it, so
  // nothing was written -- but failing safe is not the same as being right.
  let src =
    #|spec:
    #|  Card:
    #|    field n :: Int
    #|
    #|view:
    #|  Card:
    #|    style(): @{.mine { color: red; }}
    #|    p(): "x"
    #|
  let once = file_survives(src)
  let twice = file_survives(once)
  assert_eq(twice, once)
  assert_true(once.contains(".mine { color: red; }"), msg=once)
}
