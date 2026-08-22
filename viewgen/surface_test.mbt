///|
/// The counter demo's view, as it will live in demo/counterlib/counter.html.
let counter_html : String =
  #|<template>
  #|  <div class="counter">
  #|    <h1><x text=".label"></x>: <span id="count"><x text=".count"></x></span></h1>
  #|    <button id="inc" @on.click="add 1">+1</button>
  #|    <button id="dec" @on.click="add -1">-1</button>
  #|    <button id="reset" @on.click="resetCount">reset</button>
  #|    <input id="label" :value=".label" @on.input="setLabel e.value"
  #|           @on.keydown+send="setLabel 'sent!'">
  #|    <ul id="history"><li @each=".history"><x text="@value"></x></li></ul>
  #|  </div>
  #|</template>

///|
fn surface_of(html : String) -> @viewgen.Surface raise @viewgen.GenError {
  let f = @viewgen.split_file(html)
  @viewgen.view_surface(f.components[0].views, macros=f.macros)
}

///|
test "the counter view's surface" {
  let s = surface_of(counter_html)
  assert_eq(s.inputs.map(i => i.name), ["add", "resetCount", "setLabel"])
  // `add 1` / `add -1` agree on one numeric argument.
  assert_eq(s.inputs[0].args, Some([VDouble]))
  assert_eq(s.inputs[0].sites, ["@on.click"])
  // `resetCount` takes none.
  assert_eq(s.inputs[1].args, Some([]))
  // `setLabel value` (a DOM value bind) and `setLabel 'sent!'` are both text.
  assert_eq(s.inputs[2].args, Some([VString]))
  assert_eq(s.inputs[2].sites, ["@on.input", "@on.keydown"])
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
      #|<div>
      #|  <input type="checkbox" @on.input="setDone e.value">
      #|  <input type="file" @on.change="onPick e.value">
      #|  <input type="text" @on.input="setName e.value">
      #|</div>
    ),
  )
  assert_eq(s.inputs.map(i => i.name), ["onPick", "setDone", "setName"])
  assert_eq(s.inputs[0].args, Some([VValue]))
  assert_eq(s.inputs[1].args, Some([VBool]))
  assert_eq(s.inputs[2].args, Some([VString]))
}

///|
test "a dynamic :type keeps the default String inference for value" {
  // Only a static type attribute is visible at generation time.
  let s = surface_of("<input :type=\".kind\" @on.input=\"setIt e.value\">")
  assert_eq(s.inputs[0].args, Some([VString]))
}

///|
test "checkbox and text call sites of one handler join to Value" {
  let s = surface_of(
    (
      #|<div>
      #|  <input type="checkbox" @on.input="setIt e.value">
      #|  <input @on.input="setIt e.value">
      #|</div>
    ),
  )
  assert_eq(s.inputs[0].args, Some([VValue]))
}

///|
test "call sites that disagree on arity carry the raw args" {
  let s = surface_of(
    (
      #|<div>
      #|  <button @on.click="go 1">a</button>
      #|  <button @on.dblclick="go 1 'two'">b</button>
      #|</div>
    ),
  )
  assert_eq(s.inputs[0].name, "go")
  assert_eq(s.inputs[0].args, None)
}

///|
test "call sites that disagree on a position fall back to Value" {
  let s = surface_of(
    (
      #|<div>
      #|  <button @on.click="go 1">a</button>
      #|  <button @on.dblclick="go 'two'">b</button>
      #|</div>
    ),
  )
  assert_eq(s.inputs[0].args, Some([VValue]))
}

///|
test "$name is a method in a value position and refused in an event one" {
  // A value position is where `$` earns its keep: there is no event and no
  // ctx, so an input handler cannot go there.
  let s = surface_of("<button @on.click=\"inc\" :title=\"$label\">x</button>")
  assert_eq(s.methods, ["label"])
  assert_eq(s.inputs.map(i => i.name), ["inc"])
  // In an event position it is the SAME dispatch as the bare name
  // (app/app.mbt pushes both as one `Receive`), so the sigil claims a
  // distinction that does not exist and is refused.
  try surface_of("<button @on.click=\"$inc\">x</button>") |> ignore catch {
    MethodInEventPosition(name~, site~, ..) => {
      assert_eq(name, "inc")
      assert_eq(site, "@on.click")
    }
    e => fail("expected the sigil to be refused, got \{e.message()}")
  } noraise {
    _ => fail("expected the sigil to be refused")
  }
}

///|
test "fields under a scope-changing node are not this component's" {
  // `.label` is read at the root; `.name` addresses the loop item and
  // `.title` the child component, so neither is a field of this state.
  let s = surface_of(
    (
      #|<div>
      #|  <x text=".label"></x>
      #|  <ul><li @each=".rows"><x text=".name"></x></li></ul>
      #|  <x render=".child" as=".title"></x>
      #|</div>
    ),
  )
  assert_eq(s.fields, ["child", "label", "rows", "title"])
}

///|
test "a view that would warn at runtime fails generation" {
  let msg = try {
    surface_of("<div @nope=\".x\"></div>") |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  inspect(
    msg,
    content=(
      #|view "main": unknown directive '@nope=".x"' on <div>
    ),
  )
}

///|
/// The alter directives, each into its own bucket.
///
/// Split by bucket rather than pooled: `@when` answers Bool, `@loop-with`
/// returns a slice plan, and `@enrich-with` means two different signatures
/// depending on whether an `@each` is around it — so the bucket is what makes
/// a name typeable at all.
test "the alter handler names, by bucket" {
  let s = surface_of(
    (
      #|<template>
      #|  <ul>
      #|    <li @each=".items" @when="keepItem" @loop-with="firstPage"
      #|        @enrich-with="enrichItem"><x text="@value"></x></li>
      #|  </ul>
      #|  <div @enrich-with="pagerInfo"><x text="@total"></x></div>
      #|</template>
    ),
  )
  assert_eq(s.whens, ["keepItem"])
  assert_eq(s.loop_withs, ["firstPage"])
  // inside an @each: mutates the binds map
  assert_eq(s.enriches, ["enrichItem"])
  // no @each around it: returns the binds
  assert_eq(s.enrich_scopes, ["pagerInfo"])
  // none of them is a `$name`, so none lands in `methods`
  assert_eq(s.methods, [])
}

///|
/// A `$name` in an alter position is a method like any other — it resolves
/// through the compute bucket at render time — so it belongs in `methods` and
/// NOT in the alter bucket, which would otherwise declare a handler the
/// author never has to write.
test "a $name in an alter position is a method, not a bucket entry" {
  let s = surface_of(
    (
      #|<template>
      #|  <ul><li @each=".items" @when="$visible"><x text="@value"></x></li></ul>
      #|</template>
    ),
  )
  assert_eq(s.methods, ["visible"])
  assert_eq(s.whens, [])
}

// -- v2: the `e.` boundary ---------------------------------------------------

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
  let s = surface_of("<input @on.input=\"setIt e.value\">")
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
    "<button @on.click=\"go e.target.ownerDocument.defaultView.localStorage.length\">x</button>",
  )
  assert_eq(hints.length(), 1)
  assert_eq(
    hints[0],
    "view main: `@on.click=\"… e.target.ownerDocument.defaultView.localStorage.length\"` — `ownerDocument` (at 1) is off the event-path allowlist. It resolves here, but a host compiling guest-supplied views refuses it: every step through a host object must be one of currentTarget, dataTransfer, dataset, detail, relatedTarget, target",
  )
  // ...and nothing generates as an error for either escape path.
  assert_eq(
    view_err("<button @on.click=\"go e.target.form.action\">x</button>"),
    "",
  )
  // A permitted one draws no hint at all.
  assert_eq(view_hints("<button @on.click=\"go e.target.value\">x</button>"), [])
  assert_eq(
    view_hints("<button @on.click=\"go e.target.dataset.rowId\">x</button>"),
    [],
  )
  assert_eq(view_hints("<button @on.click=\"go e.detail.a.b.c\">x</button>"), [])
}

///|
test "a rooted path naming no known property is a hint, with the nearest" {
  let hints = view_hints("<button @on.click=\"go e.valeu\">x</button>")
  assert_eq(hints.length(), 1)
  assert_eq(
    hints[0],
    "view main: `@on.click=\"… e.valeu\"` — no event interface has a `valeu` property — did you mean `e.value`?",
  )
  // A computed accessor is known even though no specification has it: `value`
  // is the glue's, and a check against the specs alone would warn about the
  // most common read in the language.
  assert_eq(view_hints("<button @on.click=\"go e.value\">x</button>"), [])
  assert_eq(view_hints("<button @on.click=\"go e.isCtrl\">x</button>"), [])
  // ...and a real one from the generated table.
  assert_eq(view_hints("<button @on.click=\"go e.deltaY\">x</button>"), [])
  assert_eq(view_hints("<button @on.click=\"go e.pointerId\">x</button>"), [])
}

///|
test "a bare name in an argument slot is a build error" {
  // It names nothing: there is no scope to look it up in, so it would resolve
  // to `Null` and the handler would be handed a hole with nothing reporting
  // it. The message names all three sigils rather than assuming the event.
  assert_eq(
    view_err("<input @on.input=\"setIt value\">"),
    "view \"main\": `@on.input=\"… value\"` — an argument needs a sigil saying where it reads from. Write `e.value` for the event, `.value` for state, or `@value` for a binding",
  )
  // The three prefixed spellings are accepted, and say nothing.
  assert_eq(view_hints("<input @on.input=\"setIt e.value\">"), [])
  assert_eq(view_hints("<input @on.input=\"setIt .draft\">"), [])
  assert_eq(view_err("<input @on.input=\"setIt .draft\">"), "")
}

///|
test "an e. path is refused outside an argument slot" {
  // The group table is where this is decided: a `@text=\"e.value\"` would be a
  // render-time read of an event that is not happening.
  assert_true(view_err("<p @text=\"e.value\"></p>") != "")
}
