///|
test "no templates: the whole file is the main view" {
  let vs = @viewgen.split_views(
    (
      #|<div class="counter">
      #|  <button @on.click="add 1">+1</button>
      #|</div>
    ),
  )
  assert_eq(vs.views.length(), 1)
  assert_eq(vs.views[0].name, "main")
  inspect(
    vs.views[0].source,
    content=(
      #|<div class="counter">
      #|  <button @on.click="add 1">+1</button>
      #|</div>
    ),
  )
}

///|
test "raw source survives quotes, sigils and character references" {
  // The point of slicing rather than re-serializing: none of this may be
  // normalized away.
  let src =
    #|<x text="'a > b'" :title=".t" @on.click="go 'x'" @each=".xs">&amp;&lt;</x>
  let vs = @viewgen.split_views(src)
  inspect(vs.views[0].source, content=src)
}

///|
test "templates: id names the view, the id-less one is main" {
  let vs = @viewgen.split_views(
    (
      #|<template><div id="root"></div></template>
      #|<template id="row"><li><x text="@value"></x></li></template>
    ),
  )
  assert_eq(vs.views.map(v => v.name), ["main", "row"])
  inspect(
    vs.views[0].source,
    content=(
      #|<div id="root"></div>
    ),
  )
  inspect(
    vs.views[1].source,
    content=(
      #|<li><x text="@value"></x></li>
    ),
  )
}

///|
test "styles: in a template it is the view's, at file level the component's" {
  let vs = @viewgen.split_views(
    (
      #|<style>.counter { color: red }</style>
      #|<style data-global>body { margin: 0 }</style>
      #|<template><style>h1 { font-weight: 700 }</style><h1>hi</h1></template>
    ),
  )
  assert_eq(vs.common_style, ".counter { color: red }")
  assert_eq(vs.global_style, "body { margin: 0 }")
  assert_eq(vs.views[0].style, "h1 { font-weight: 700 }")
  inspect(
    vs.views[0].source,
    content=(
      #|<h1>hi</h1>
    ),
  )
}

///|
test "a < inside CSS does not confuse the scan" {
  let vs = @viewgen.split_views(
    (
      #|<template><style>.a { width: calc(1px) } /* a < b */</style><p>x</p></template>
    ),
  )
  assert_eq(vs.views[0].style, ".a { width: calc(1px) } /* a < b */")
  inspect(
    vs.views[0].source,
    content=(
      #|<p>x</p>
    ),
  )
}

///|
test "nested templates stay inside their view" {
  let vs = @viewgen.split_views(
    (
      #|<template><div><template id="inner">x</template></div></template>
      #|<template id="row">y</template>
    ),
  )
  assert_eq(vs.views.map(v => v.name), ["main", "row"])
  inspect(
    vs.views[0].source,
    content=(
      #|<div><template id="inner">x</template></div>
    ),
  )
}

///|
/// The message the CLI would print for a file that cannot be split.
fn split_error(source : String) -> String {
  try {
    @viewgen.split_views(source) |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
}

///|
test "errors" {
  inspect(
    split_error("<template id=\"a\">x</template>"),
    content="no main view: give one <template> no id attribute, or id=\"main\"",
  )
  inspect(
    split_error("<template>x</template><template>y</template>"),
    content=(
      #|two views are both named "main"
    ),
  )
  inspect(
    split_error("junk<template>x</template>"),
    content="unexpected 'j' outside a <template>; with templates present, every view must live inside one",
  )
  inspect(
    split_error("<template id=\"row\">x"),
    content=(
      #|unclosed <template id="row">
    ),
  )
}
