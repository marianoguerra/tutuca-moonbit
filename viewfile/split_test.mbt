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
      #|<script type="tutuca/spec">
      #|  state Counter { count: Int }
      #|</script>
      #|
      #|<script type="tutuca/script">
      #|  on add(d) { .count += d }
      #|</script>
      #|
      #|<template><button @on.click="add 1">+1</button></template>
    ),
  )
  guard! vs.script_for("") is Some(block)
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
  // The block starts on line 5 (1-based): the spec block is lines 1-3, then
  // a blank, then the opening tag. The offset is the character just past that
  // tag's `>` — line 5 begins at 70 and `<script type="tutuca/script">` is 29
  // characters — so a span inside the block rebases onto the file exactly,
  // column included.
  assert_eq(block.line, 5)
  assert_eq(block.offset, 99)
  // …and it is NOT part of any view, the same way the schema is not.
  assert_eq(only(vs).views[0].source, "<button @on.click=\"add 1\">+1</button>")
}

///|
test "the spec block splits and its fields are read" {
  let vs = @viewfile.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Counter { count: Int }
      #|</script>
      #|<template><b @text=".count"></b></template>
    ),
  )
  assert_eq(vs.state.length(), 1)
  assert_eq(vs.state[0].fields[0].name, "count")
}

///|
test "two spec blocks are two specs, and there is no order to merge them in" {
  try
    @viewfile.split_file(
      (
        #|<script type="tutuca/spec">
        #|  state A { n: Int }
        #|</script>
        #|<script type="tutuca/spec">
        #|  state B { n: Int }
        #|</script>
        #|<template><p>hi</p></template>
      ),
    )
    |> ignore
  catch {
    e => assert_true(e.message().contains("one file declares one spec"))
  } noraise {
    _ => fail("expected the second block to be refused")
  }
}

///|
test "a file with no script block says so, rather than carrying an empty one" {
  // Which is every view file that predates the language, and is why the field
  // is an option rather than a String that happens to be blank.
  let vs = @viewfile.split_file("<template><b>hi</b></template>")
  assert_true(vs.script_for("") is None)
}

///|
test "one script block per component, named the way a template id is" {
  // A block is written about ONE component — `.title` means that component's
  // state and nothing else — so a file declaring four of them needs four
  // blocks. `for=` is the same device `<template id="Counter:row">` already
  // uses one element over.
  inspect(
    split_error(
      "<script type=\"tutuca/script\">on a {}</script>" +
      "<script type=\"tutuca/script\">on b {}</script>" +
      "<template><b>hi</b></template>",
    ),
    content="two unqualified <script type=\"tutuca/script\"> blocks — a block is written about ONE component, so name each one with `for=\"Comp\"`",
  )
  inspect(
    split_error(
      "<script type=\"tutuca/script\" for=\"Row\">on a {}</script>" +
      "<script type=\"tutuca/script\" for=\"Row\">on b {}</script>" +
      "<template id=\"Row\"><b>hi</b></template>",
    ),
    content="two <script type=\"tutuca/script\" for=\"Row\"> blocks — one component answers one set of handlers",
  )
  // Named blocks, one each: both are kept, and each answers for its own.
  let vs = @viewfile.split_file(
    "<script type=\"tutuca/script\" for=\"Row\">on a {}</script>" +
    "<script type=\"tutuca/script\" for=\"Cell\">on b {}</script>" +
    "<template id=\"Row\"><b>hi</b></template>" +
    "<template id=\"Cell\"><i>c</i></template>",
  )
  assert_eq(vs.scripts.length(), 2)
  guard! vs.script_for("Row") is Some(row)
  assert_eq(row.text, "on a {}")
  guard! vs.script_for("Cell") is Some(cell)
  assert_eq(cell.text, "on b {}")
  // …and a component with no block of its own has none, rather than the
  // other component's.
  assert_true(vs.script_for("Nobody") is None)
}

///|
test "a script block does not make a schema-only file into a view" {
  // A file that is only blocks declares no views at all. Before the script
  // block that was decided by the schema alone, so the new block has to join
  // the same lifted-region list or its text would become a `main` view.
  let vs = @viewfile.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Counter { count: Int }
      #|</script>
      #|<script type="tutuca/script">
      #|  on add(d) { .count += d }
      #|</script>
    ),
  )
  assert_eq(vs.components.length(), 0)
  assert_eq(vs.state.length(), 1)
  assert_true(vs.script_for("") is Some(_))
}

///|
/// The fifth block. Lifted out like the other four — its text never counts as
/// stray and never reaches a view — and PARSED, so a scene that is wrong is
/// wrong on the line of the `.html`.
test "a test block is lifted out and parsed" {
  let f = @viewfile.split_file(
    (
      #|<script type="tutuca/spec">
      #|  state Counter { count: Int }
      #|</script>
      #|<script type="tutuca/test">
      #|{ "it counts": { "steps": [
      #|  { "click": "button.inc" },
      #|  { "expect": "text", "at": "output", "is": "1" }
      #|] } }
      #|</script>
      #|<template id="Counter"><button class="inc"></button><output></output></template>
    ),
    name="Counter",
  )
  assert_eq(f.tests.length(), 1)
  inspect(f.tests[0].name, content="it counts")
  assert_eq(f.tests[0].steps.length(), 2)
  // ...and it left no trace in the view it sits beside.
  inspect(
    f.components[0].views[0].source,
    content="<button class=\"inc\"></button><output></output>",
  )
}

///|
/// A malformed scene reports the line of the FILE, not of the block — which is
/// the whole reason this is parsed here rather than handed back raw.
test "a bad scene is reported on the line of the html file" {
  let src =
    #|<script type="tutuca/spec">
    #|  state Counter { count: Int }
    #|</script>
    #|
    #|<script type="tutuca/test">
    #|{ "it counts": { "steps": [ { "clik": "button" } ] } }
    #|</script>
    #|<template id="Counter"><b></b></template>
  inspect(
    file_err(src),
    content="line 5: test block: scene `it counts`, step 0: names no verb — a step is one of `click`, `type`, `key`, `check`, `fire`, `drag`, `send` or `expect`, so did you mean `click`?",
  )
}

///|
test "two test blocks are one too many" {
  let src =
    #|<script type="tutuca/test">{}</script>
    #|<script type="tutuca/test">{}</script>
    #|<template id="C"><b></b></template>
  inspect(
    file_err(src),
    content="two <script type=\"tutuca/test\"> blocks — one file declares one object of scenes, and two would have to be merged in an order the file does not state",
  )
}

///|
fn file_err(src : String) -> String {
  try {
    @viewfile.split_file(src, name="C") |> ignore
    "no error"
  } catch {
    e => e.message()
  }
}

///|
/// `data-root` names the component a host mounts. Absent, the first in the
/// file is the root — which is the only answer a card with one has.
test "data-root names the root, and its absence means the first" {
  let two =
    #|<template id="Row:main"><li></li></template>
    #|<template id="Board:main"><section></section></template>
  inspect(@viewfile.split_file(two, name="C").root, content="")
  let marked =
    #|<template id="Row:main"><li></li></template>
    #|<template id="Board:main" data-root><section></section></template>
  inspect(@viewfile.split_file(marked, name="C").root, content="Board")
  // …and the marker does NOT reorder the components: a file-level <style>
  // belongs to the one at index 0, so moving the root would move a stylesheet
  // as a side effect of saying which component is the interesting one.
  let f = @viewfile.split_file(marked, name="C")
  @debug.assert_eq(f.components.map(c => c.name), ["Row", "Board"])
}

///|
test "two roots do not say which" {
  inspect(
    file_err(
      (
        #|<template id="A:main" data-root><b></b></template>
        #|<template id="B:main" data-root><b></b></template>
      ),
    ),
    content="two <template>s carry `data-root` (`A` and `B`) — a file has one root, and two markers do not say which",
  )
}
