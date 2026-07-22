///|
/// One file, three components and a shared macro — the shape the example
/// library needs, where a module defines several components together.
let multi_html : String =
  #|<template id="macro:chip" data-tone="'plain'">
  #|  <span class="chip" :data-tone="^tone"><x:slot></x:slot></span>
  #|</template>
  #|<template id="JsonRoot">
  #|  <div class="root"><x render=".node"></x></div>
  #|</template>
  #|<template id="JsonNode:main">
  #|  <div class="node"><x text=".label"></x><x:chip tone="loud">json</x:chip></div>
  #|</template>
  #|<template id="JsonNode:compact">
  #|  <span class="compact"><x text=".label"></x></span>
  #|</template>
  #|<template id="JsonLeaf">
  #|  <b @on.click="pick .id"><x text=".value"></x></b>
  #|</template>

///|
test "components are grouped by the id prefix, views by the suffix" {
  let f = @viewgen.split_file(multi_html)
  assert_eq(f.components.map(c => c.name), ["JsonRoot", "JsonNode", "JsonLeaf"])
  // `Comp` is shorthand for `Comp:main`; `Comp:view` adds a named view.
  assert_eq(f.components[0].views.map(v => v.name), ["main"])
  assert_eq(f.components[1].views.map(v => v.name), ["main", "compact"])
  // The macro is shared by the whole file, not owned by a component.
  assert_eq(f.macros.map(m => m.name), ["chip"])
}

///|
test "one generated module carries every component in the file" {
  let f = @viewgen.split_file(multi_html)
  let src = @viewgen.emit_module("Ignored", "json.html", f)
  // Each component gets its own prefix; `--name` is not consulted because
  // the file names them.
  for
    want in [
      "pub fn json_root_views", "pub fn json_node_views", "pub fn json_leaf_views",
    ] {
    assert_true(!src.contains(want)) // those live in the IR module
  }
  for
    want in [
      "pub(all) enum JsonRootView", "pub(all) enum JsonNodeView", "pub(all) enum JsonLeafMsg",
      "pub let json_root_common_style", "pub let json_leaf_global_style",
    ] {
    assert_true(src.contains(want))
  }
  // The handler on JsonLeaf is typed on JsonLeaf, not on its file-mates.
  assert_true(src.contains("Pick(@tutuca.Value)"))
  assert_true(!src.contains("JsonRootMsg"))
}

///|
test "the IR module carries every component too, macros expanded" {
  let f = @viewgen.split_file(multi_html)
  assert_true(@viewgen.ir_supported(f))
  let ir = @viewgen.emit_ir_module("Ignored", "json.html", f)
  for
    want in [
      "pub fn json_root_views", "pub fn json_node_views", "pub fn json_leaf_views",
    ] {
    assert_true(ir.contains(want))
  }
  // The shared macro expanded into JsonNode's tree.
  assert_true(ir.contains("\"chip\""))
  assert_true(!ir.contains("MacroCall"))
}

///|
test "a file either names its components or does not" {
  let msg = try {
    @viewgen.split_file(
      "<template id=\"Counter\">a</template><template id=\"row\">b</template>",
    )
    |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  inspect(
    msg,
    content="this file mixes `Component:view` ids with bare ones — name every component, or none of them",
  )
}

///|
test "a component id that is not a MoonBit identifier is rejected" {
  let msg = try {
    @viewgen.emit_module(
      "X",
      "x.html",
      @viewgen.split_file("<template id=\"Foo-Bar\">a</template>"),
    )
    |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  inspect(
    msg,
    content=(
      #|"Foo-Bar" is not usable as a component name: expected a name starting with a letter and made of letters, digits and underscores
    ),
  )
}
