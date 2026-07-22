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
  @viewgen.view_surface(@viewgen.split_views(html).views)
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
test "$name in event position is a method, not an input" {
  let s = surface_of("<button @on.click=\"$inc\" :title=\"$label\">x</button>")
  assert_eq(s.methods, ["inc", "label"])
  assert_eq(s.inputs.map(i => i.name), [])
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
