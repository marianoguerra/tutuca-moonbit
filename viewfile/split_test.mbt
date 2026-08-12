///|
test "no templates: the whole file is the main view" {
  let vs = @viewfile.split_file(
    (
      #|<div class="counter">
      #|  <button @on.click="add 1">+1</button>
      #|</div>
    ),
  )
  assert_eq(only(vs).views.length(), 1)
  assert_eq(only(vs).views[0].name, "main")
  inspect(
    only(vs).views[0].source,
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
  let vs = @viewfile.split_file(src)
  inspect(only(vs).views[0].source, content=src)
}

///|
test "templates: id names the view, the id-less one is main" {
  let vs = @viewfile.split_file(
    (
      #|<template><div id="root"></div></template>
      #|<template id="row"><li><x text="@value"></x></li></template>
    ),
  )
  assert_eq(only(vs).views.map(v => v.name), ["main", "row"])
  inspect(
    only(vs).views[0].source,
    content=(
      #|<div id="root"></div>
    ),
  )
  inspect(
    only(vs).views[1].source,
    content=(
      #|<li><x text="@value"></x></li>
    ),
  )
}

///|
test "styles: in a template it is the view's, at file level the component's" {
  let vs = @viewfile.split_file(
    (
      #|<style>.counter { color: red }</style>
      #|<style data-global>body { margin: 0 }</style>
      #|<template><style>h1 { font-weight: 700 }</style><h1>hi</h1></template>
    ),
  )
  assert_eq(only(vs).common_style, ".counter { color: red }")
  assert_eq(only(vs).global_style, "body { margin: 0 }")
  assert_eq(only(vs).views[0].style, "h1 { font-weight: 700 }")
  inspect(
    only(vs).views[0].source,
    content=(
      #|<h1>hi</h1>
    ),
  )
}

///|
test "a < inside CSS does not confuse the scan" {
  let vs = @viewfile.split_file(
    (
      #|<template><style>.a { width: calc(1px) } /* a < b */</style><p>x</p></template>
    ),
  )
  assert_eq(only(vs).views[0].style, ".a { width: calc(1px) } /* a < b */")
  inspect(
    only(vs).views[0].source,
    content=(
      #|<p>x</p>
    ),
  )
}

///|
test "nested templates stay inside their view" {
  let vs = @viewfile.split_file(
    (
      #|<template><div><template id="inner">x</template></div></template>
      #|<template id="row">y</template>
    ),
  )
  assert_eq(only(vs).views.map(v => v.name), ["main", "row"])
  inspect(
    only(vs).views[0].source,
    content=(
      #|<div><template id="inner">x</template></div>
    ),
  )
}

///|
/// The message the CLI would print for a file that cannot be split.
fn split_error(source : String) -> String {
  try {
    @viewfile.split_file(source) |> ignore
    "no error"
  } catch {
    e => @viewfile.FileError::message(e)
  }
}

///|
test "errors" {
  inspect(
    split_error("<template id=\"a\">x</template>"),
    content=(
      #|this file declares no main view: add a `main` view (id="Comp" or id="Comp:main")
    ),
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

///|
/// The single component a one-component file declares.
fn only(f : @viewfile.ViewFile) -> @viewfile.ViewSet {
  f.components[0]
}

// -- the script block -------------------------------------------------------

///|
test "the script block is lifted out unparsed, with where it came from" {
  let vs = @viewfile.split_file(
    (
      #|<script type="tutuca/state">
      #|  interface counter { record state { count: s32 } }
      #|</script>
      #|
      #|<script type="tutuca/script">
      #|  on add(d) { .count += d }
      #|</script>
      #|
      #|<template><button @on.click="add 1">+1</button></template>
    ),
  )
  guard! vs.script is Some(block)
  // Raw text, exactly as written. Nothing here knows what a declaration is —
  // checking one needs the schema and the views' call sites, and neither is
  // in hand at split time.
  inspect(
    block.text,
    content=(
      #|
      #|  on add(d) { .count += d }
      #|
    ),
  )
  // The block starts on line 5 (1-based): the state block is lines 1-3, then
  // a blank, then the opening tag. The offset is the character just past that
  // tag's `>` — line 5 begins at 92 and `<script type="tutuca/script">` is 29
  // characters — so a span inside the block rebases onto the file exactly,
  // column included.
  assert_eq(block.line, 5)
  assert_eq(block.offset, 121)
  // …and it is NOT part of any view, the same way the schema is not.
  assert_eq(only(vs).views[0].source, "<button @on.click=\"add 1\">+1</button>")
}

///|
test "a file with no script block says so, rather than carrying an empty one" {
  // Which is every view file that predates the language, and is why the field
  // is an option rather than a String that happens to be blank.
  let vs = @viewfile.split_file("<template><b>hi</b></template>")
  assert_true(vs.script is None)
}

///|
test "two script blocks are refused" {
  inspect(
    split_error(
      "<script type=\"tutuca/script\">on a {}</script>" +
      "<script type=\"tutuca/script\">on b {}</script>" +
      "<template><b>hi</b></template>",
    ),
    content="two <script type=\"tutuca/script\"> blocks — one file declares one script, with one set of handlers per component",
  )
}

///|
test "a script block does not make a schema-only file into a view" {
  // A file that is only blocks declares no views at all. Before the script
  // block that was decided by the schema alone, so the new block has to join
  // the same lifted-region list or its text would become a `main` view.
  let vs = @viewfile.split_file(
    (
      #|<script type="tutuca/state">
      #|  interface counter { record state { count: s32 } }
      #|</script>
      #|<script type="tutuca/script">
      #|  on add(d) { .count += d }
      #|</script>
    ),
  )
  assert_eq(vs.components.length(), 0)
  assert_eq(vs.state.length(), 1)
  assert_true(vs.script is Some(_))
}
