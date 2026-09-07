///|
/// The counter demo's view, as it lives in demo/counterlib/counter.tutu.
let counter_view : String =
  #|    @div(~class: "counter"){
  #|      @h1{@(it.label): @span(~id: "count"){@(it.count)}}
  #|      @button(~id: "inc", ~on_click: add(1)){+1}
  #|      @button(~id: "dec", ~on_click: add(-1)){-1}
  #|      @button(~id: "reset", ~on_click: resetCount){reset}
  #|      @input(~id: "label", ~value: it.label, ~on_input: setLabel(e.value), ~on_keydown: setLabel("sent!") ~send)
  #|      @ul(~id: "history"){@each(value, key in it.history){@li{@(value)}}}
  #|    }

///|
/// One view, read the way `tutuca gen` reads one.
///
/// The body arrives already indented for the `view:` section it goes in — a
/// helper that re-indented it would be a helper that reads shrubbery to write
/// it. The `spec:` section is a formality: `view_surface` collects the fields
/// a view READS, so what the component declares is not this layer's question.
fn surface_of(view : String) -> @viewgen.Surface raise @viewgen.GenError {
  let f = @viewgen.read_file(
    "spec:\n  T:\n    field x :: Int\n\nview:\n  T:\n" + view + "\n",
  )
  @viewgen.view_surface(f.components[0].views, macros=f.macros)
}

///|
test "the counter view's surface" {
  let s = surface_of(counter_view)
  assert_eq(s.inputs.map(i => i.name), ["add", "resetCount", "setLabel"])
  // `add(1)` / `add(-1)` agree on one numeric argument.
  assert_eq(s.inputs[0].args, Some([VDouble]))
  assert_eq(s.inputs[0].sites, ["~on_click"])
  // `resetCount` takes none.
  assert_eq(s.inputs[1].args, Some([]))
  // `setLabel(e.value)` (a DOM value read) and `setLabel("sent!")` are both text.
  assert_eq(s.inputs[2].args, Some([VString]))
  assert_eq(s.inputs[2].sites, ["~on_input", "~on_keydown"])
  assert_eq(s.fields, ["count", "history", "label"])
  assert_eq(s.ids, ["count", "dec", "history", "inc", "label", "reset"])
  assert_eq(s.methods, [])
}

///|
test "value's type follows the host element: checkbox Bool, file Value" {
  // The glue delivers a checkbox's `value` as the checked state and a file
  // input's as a metadata Map / Null — the inferred payload must match, or
  // every runtime dispatch would fall into Unknown.
  let s = surface_of(
    (
      #|    @div{
      #|      @input(~type: "checkbox", ~on_input: setDone(e.value))
      #|      @input(~type: "file", ~on_change: onPick(e.value))
      #|      @input(~type: "text", ~on_input: setName(e.value))
      #|    }
    ),
  )
  assert_eq(s.inputs.map(i => i.name), ["onPick", "setDone", "setName"])
  assert_eq(s.inputs[0].args, Some([VValue]))
  assert_eq(s.inputs[1].args, Some([VBool]))
  assert_eq(s.inputs[2].args, Some([VString]))
}

///|
test "a dynamic type keeps the default String inference for value" {
  // Only a static type option is visible at generation time.
  let s = surface_of("    @input(~type: it.kind, ~on_input: setIt(e.value))")
  assert_eq(s.inputs[0].args, Some([VString]))
}

///|
test "checkbox and text call sites of one handler join to Value" {
  let s = surface_of(
    (
      #|    @div{
      #|      @input(~type: "checkbox", ~on_input: setIt(e.value))
      #|      @input(~on_input: setIt(e.value))
      #|    }
    ),
  )
  assert_eq(s.inputs[0].args, Some([VValue]))
}

///|
test "call sites that disagree on arity carry the raw args" {
  let s = surface_of(
    (
      #|    @div{
      #|      @button(~on_click: go(1)){a}
      #|      @button(~on_dblclick: go(1, "two")){b}
      #|    }
    ),
  )
  assert_eq(s.inputs[0].name, "go")
  assert_eq(s.inputs[0].args, None)
}

///|
test "call sites that disagree on a position fall back to Value" {
  let s = surface_of(
    (
      #|    @div{
      #|      @button(~on_click: go(1)){a}
      #|      @button(~on_dblclick: go("two")){b}
      #|    }
    ),
  )
  assert_eq(s.inputs[0].args, Some([VValue]))
}

///|
/// A `compute` called in a VALUE slot is a method; a bare name in an event
/// slot is a handler. One notation, and the position is the whole difference.
///
/// The old notation spelled the first `$label` and the second `label`, and a
/// `$name` written in an event slot was refused — `METHOD_IN_EVENT` — because
/// the sigil claimed a distinction that does not exist. There is no sigil now,
/// so the two spellings are `label()` and `label` and there is nothing left to
/// refuse: `~on_click: label()` and `~on_click: label` are read as one
/// dispatch. That rule still runs over views built as markup through
/// `@anode.View::new`, where the distinction can still be written.
test "a compute in a value position is a method" {
  let s = surface_of("    @button(~on_click: inc, ~title: label()){x}")
  assert_eq(s.methods, ["label"])
  assert_eq(s.inputs.map(i => i.name), ["inc"])
  let same = surface_of("    @button(~on_click: inc()){x}")
  assert_eq(same.inputs.map(i => i.name), ["inc"])
  assert_eq(same.methods, [])
}

///|
test "fields under a scope-changing node are not this component's" {
  // `it.label` is read at the root; the loop item and the child component are
  // read through their own binder, so neither is a field of this state.
  let s = surface_of(
    (
      #|    @div{
      #|      @(it.label)
      #|      @ul{@each(row in it.rows){@li{@(row.name)}}}
      #|      @render(it.child, ~as: it.title)
      #|    }
    ),
  )
  assert_eq(s.fields, ["child", "label", "rows", "title"])
}

///|
test "a view the reader will not read fails generation" {
  // `@nope` is not an element and there is no way to write one that is not: the
  // old notation had a fixed directive list on an open set of attributes, so an
  // `@nope=".x"` looked like both and was caught by a list. Here an element
  // name IS the vocabulary, and `~nope:` is simply an attribute called `nope`.
  let msg = try {
    surface_of("    @div{@each(value in it.rows, ~when: visible()){@p{x}}}")
    |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  // The repair, not just the verdict.
  assert_true(msg.contains("declare it in the logic section"), msg~)
}

///|
/// The alter directives, each into its own bucket.
///
/// Split by bucket rather than pooled: `~when` answers Bool, `~loop_with`
/// returns a slice plan, and `~enrich_with` means two different signatures
/// depending on whether an `@each` is around it — so the bucket is what makes
/// a name typeable at all.
test "the alter handler names, by bucket" {
  let s = surface_of(
    (
      #|    @div{
      #|      @ul{
      #|        @each(value, key in it.items, ~when: keepItem, ~loop_with: firstPage, ~enrich_with: enrichItem){
      #|          @li{@(value)}
      #|        }
      #|      }
      #|      @div(~enrich_with: pagerInfo){@(total)}
      #|    }
    ),
  )
  assert_eq(s.whens, ["keepItem"])
  assert_eq(s.loop_withs, ["firstPage"])
  // inside an @each: mutates the binds map
  assert_eq(s.enriches, ["enrichItem"])
  // no @each around it: returns the binds
  assert_eq(s.bind_withs, ["pagerInfo"])
  // none of them is a call, so none lands in `methods`
  assert_eq(s.methods, [])
}

// -- the `e.` boundary -------------------------------------------------------

///|
/// The generation error a view fails with, or "" when it generates.
fn view_err(view : String) -> String {
  try {
    surface_of(view) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
/// The advisory findings a view turns up.
fn view_hints(view : String) -> Array[String] raise {
  surface_of(view).hints
}

///|
test "an e. path in an argument slot parses and types" {
  let s = surface_of("    @input(~on_input: setIt(e.value))")
  assert_eq(s.inputs.length(), 1)
  assert_eq(s.inputs[0].name, "setIt")
  // The accessor's own type, from layer 1's table — an `e.` path does not
  // make the argument opaque.
  assert_eq(s.inputs[0].args, Some([VString]))
}

///|
test "a path off the allowlist is a hint naming the step, not an error" {
  // These views are the author's own code: any path resolves under the open
  // profile they run under, so the generator advises rather than gates. What
  // the hint says is who WILL refuse the step — a host compiling
  // guest-supplied views holds its policy's safe profile to this same list
  // and turns it away at registration.
  let hints = view_hints(
    "    @button(~on_click: go(e.target.ownerDocument.defaultView.localStorage.length)){x}",
  )
  assert_eq(hints.length(), 1)
  assert_eq(
    hints[0],
    "view main: `~on_click=\"… e.target.ownerDocument.defaultView.localStorage.length\"` — `ownerDocument` (at 1) is off the event-path allowlist. It resolves here, but a host compiling guest-supplied views refuses it: every step through a host object must be one of currentTarget, dataTransfer, dataset, detail, relatedTarget, target",
  )
  // ...and nothing generates as an error for either escape path.
  assert_eq(view_err("    @button(~on_click: go(e.target.form.action)){x}"), "")
  // A permitted one draws no hint at all.
  assert_eq(view_hints("    @button(~on_click: go(e.target.value)){x}"), [])
  assert_eq(
    view_hints("    @button(~on_click: go(e.target.dataset.rowId)){x}"),
    [],
  )
  assert_eq(view_hints("    @button(~on_click: go(e.detail.a.b.c)){x}"), [])
}

///|
test "a rooted path naming no known property is a hint, with the nearest" {
  let hints = view_hints("    @button(~on_click: go(e.valeu)){x}")
  assert_eq(hints.length(), 1)
  assert_eq(
    hints[0],
    "view main: `~on_click=\"… e.valeu\"` — no event interface has a `valeu` property — did you mean `e.value`?",
  )
  // A computed accessor is known even though no specification has it: `value`
  // is the glue's, and a check against the specs alone would warn about the
  // most common read in the language.
  assert_eq(view_hints("    @button(~on_click: go(e.value)){x}"), [])
  assert_eq(view_hints("    @button(~on_click: go(e.isCtrl)){x}"), [])
  // ...and a real one from the generated table.
  assert_eq(view_hints("    @button(~on_click: go(e.deltaY)){x}"), [])
  assert_eq(view_hints("    @button(~on_click: go(e.pointerId)){x}"), [])
}

///|
test "an argument says where it reads from" {
  // The three prefixed spellings are accepted, and say nothing.
  assert_eq(view_hints("    @input(~on_input: setIt(e.value))"), [])
  assert_eq(view_hints("    @input(~on_input: setIt(it.draft))"), [])
  assert_eq(view_err("    @input(~on_input: setIt(it.draft))"), "")
  assert_eq(
    view_hints(
      "    @ul{@each(row in it.rows){@button(~on_click: setIt(row)){x}}}",
    ),
    [],
  )
}

///|
test "an operator is transparent to the surface walk" {
  // The reason operators lower to `App` rather than to new `Expr` cases. Every
  // walker in the tree already recurses through `App(args~, ..)` and ignores
  // the name — the statedef collector here, the `UnknownStateField` checker,
  // the method collector — so nesting an operator changes nothing for any of
  // them. A `it.kind` buried under `!(…)` is still a field the state must
  // declare, and a call under one is still a method.
  let s = surface_of(
    (
      #|    @div{
      #|      @show(!(it.kind.is_empty())){@p{a}}
      #|      @hide(it.items.length() == 1){@p{b}}
      #|      @show(it.open && (it.n > 0)){@p{c}}
      #|      @p(~class: if !canSubmit() | "on" | "off"){d}
      #|      @show(it.view == "detail"){@p{e}}
      #|    }
    ),
  )
  assert_eq(s.fields, ["items", "kind", "n", "open", "view"])
  assert_eq(s.methods, ["canSubmit"])
}

///|
test "a macro argument is an operand in a conditional slot" {
  // The regression this covers, and the exact shape it broke: a `row` macro
  // that hides itself when the value it was handed is empty. A macro parameter
  // is a slot value on its own AND a part of an expression, because it expands
  // to exactly one operand — so an operator over it cannot regroup anything,
  // and the `from_macro` mark stays on the constant where the origin rule
  // reads it.
  let src =
    #|spec:
    #|  T:
    #|    field title :: String
    #|    field blurb :: String
    #|
    #|view:
    #|  macro row(~value: "", ~label: ""):
    #|    @div(~class: "row"){
    #|      @hide(value.is_empty()){
    #|        @span{@(label)}
    #|        @show(!(value.is_empty())){@b{@(value)}}
    #|      }
    #|    }
    #|
    #|  T:
    #|    @div{
    #|      @row(~value: it.title, ~label: "Title")
    #|      @row(~value: it.blurb, ~label: "Blurb")
    #|    }
  let f = @viewgen.read_file(src)
  let s = @viewgen.view_surface(f.components[0].views, macros=f.macros)
  assert_eq(s.fields, ["blurb", "title"])
}
