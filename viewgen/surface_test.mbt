///|
/// The counter demo's view, as it will live in demo/counterlib/counter.html.
let counter_html : String =
  #|<template>
  #|  <div class="counter">
  #|    <h1><x text=".label"></x>: <span id="count"><x text=".count"></x></span></h1>
  #|    <button id="inc" @on.click="add 1">+1</button>
  #|    <button id="dec" @on.click="add -1">-1</button>
  #|    <button id="reset" @on.click="resetCount">reset</button>
  #|    <input id="label" :value=".label" @on.input="setLabel value"
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
  // (app/app.mbt collapses both into push_input), so the sigil claims a
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
