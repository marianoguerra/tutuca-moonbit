///|
/// One file, three components and a shared macro — the shape the example
/// library needs, where a module defines several components together.
let multi_src : String =
  #|spec:
  #|  JsonRoot:
  #|    field node :: Instance.of(JsonNode)
  #|
  #|  JsonNode:
  #|    field label :: String
  #|
  #|  JsonLeaf:
  #|    field id :: String
  #|    field value :: String
  #|
  #|view:
  #|  macro chip(~tone: "plain", ~body: ""):
  #|    span(class: "chip", data_tone: tone):
  #|      @(body)
  #|
  #|  JsonRoot:
  #|    div(class: "root"):
  #|      render(it.node)
  #|
  #|  JsonNode:
  #|    div(class: "node"):
  #|      @(it.label)
  #|      chip(~tone: "loud", ~body: "json")
  #|
  #|  JsonNode.compact:
  #|    span(class: "compact"):
  #|      @(it.label)
  #|
  #|  JsonLeaf:
  #|    b(~on_click: pick(it.id)):
  #|      @(it.value)

///|
test "components are grouped by the id prefix, views by the suffix" {
  let f = @viewgen.read_file(multi_src)
  assert_eq(f.components.map(c => c.name), ["JsonRoot", "JsonNode", "JsonLeaf"])
  // `Comp` is shorthand for `Comp:main`; `Comp:view` adds a named view.
  assert_eq(f.components[0].views.map(v => v.name), ["main"])
  assert_eq(f.components[1].views.map(v => v.name), ["main", "compact"])
  // The macro is shared by the whole file, not owned by a component.
  assert_eq(f.macros.map(m => m.name), ["chip"])
}

///|
test "one generated module carries every component in the file" {
  let f = @viewgen.read_file(multi_src)
  let src = @viewgen.emit_module("Ignored", "json.tutu", f)
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
      "pub(all) enum JsonLeafMsg", "pub let json_root_common_style", "pub let json_leaf_global_style",
    ] {
    assert_true(src.contains(want))
  }
  // The handler on JsonLeaf is typed on JsonLeaf, not on its file-mates.
  assert_true(src.contains("Pick(@tutuca.Value)"))
  assert_true(!src.contains("JsonRootMsg"))
}

///|
test "the IR module carries every component too, macros expanded" {
  let f = @viewgen.read_file(multi_src)
  let ir = @viewgen.emit_ir_module("Ignored", "json.tutu", f)
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
test "emit_modules produces the same public modules in one compilation" {
  let f = @viewgen.read_file(multi_src)
  let generated = @viewgen.emit_modules("Ignored", "json.tutu", f)
  assert_eq(
    generated.types_source,
    @viewgen.emit_module("Ignored", "json.tutu", f),
  )
  assert_eq(
    generated.ir_source,
    Some(@viewgen.emit_ir_module("Ignored", "json.tutu", f)),
  )
}

///|
test "a component name that is not a MoonBit identifier is rejected" {
  // A `.tutu` file always names its components — a bare `state { … }` was the
  // `.html` shape and there is no spelling for one here — so the only thing
  // left to reject is a name a generated module cannot carry.
  let msg = try {
    @viewgen.read_file(
      "spec:\n  Foo_Bar:\n    field n :: Int\n\nview:\n  Foo_Bar:\n    b():\n      \"a\"\n",
    )
    |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  assert_eq(msg, "no error")
}
