// ANode::collect_classes — the margaui scanner's view of a template
// (spec.mbt; JS ParseCtxClassSetCollector semantics).

///|
priv struct NoMacros {}

///|
impl @anode.MacroScope for NoMacros with fn lookup_macro(_self, _name) {
  None
}

///|
fn classes_of(raw_view : String) -> Array[String] raise {
  let v = @anode.View::new("main", raw_view~)
  v.compile(@anode.ParseContext::new(), NoMacros::{  }, cid=LNum(0))
  let set : Set[String] = Set([])
  guard v.anode is Some(node)
  node.collect_classes(set)
  let out = set.to_array()
  out.sort()
  out
}

///|
test "const class attrs split on whitespace" {
  let cs = classes_of(
    "<div class=\"btn  btn-primary\n join-item\"><span class=\"badge\"></span></div>",
  )
  debug_inspect(
    cs,
    content=(
      #|["btn", "badge", "join-item", "btn-primary"]
    ),
  )
}

///|
test "dynamic :class collects only literal template fragments" {
  // `badge badge-` is literal, `{.kind}` is not; the bare `.other` field
  // contributes nothing.
  let cs = classes_of(
    "<div :class=\"$'badge badge-{.kind}'\"><i :class=\".other\"></i></div>",
  )
  debug_inspect(
    cs,
    content=(
      #|["badge", "badge-"]
    ),
  )
}

///|
test "@if.class collects both branches" {
  let cs = classes_of(
    "<button @if.class=\".on\" @then=\"'tab tab-active'\" @else=\"'tab'\"></button>",
  )
  debug_inspect(
    cs,
    content=(
      #|["tab", "tab-active"]
    ),
  )
}

///|
test "classes inside wrappers, loops and fragments are found" {
  let cs = classes_of(
    "<section class=\"flex\"><div @each=\".items\" class=\"row\"><b @show=\".x\" class=\"k\"></b></div></section>",
  )
  debug_inspect(
    cs,
    content=(
      #|["k", "row", "flex"]
    ),
  )
}

///|
test "macro-expanded classes are collected from compiled views" {
  let v = @anode.View::new("main", raw_view="<div><x:chip></x:chip></div>")
  let macros : Map[String, @anode.Macro] = {
    "chip": {
      defaults: {},
      raw_view: "<span class=\"badge badge-info\"></span>",
    },
  }
  let scope = MacroMap::{ macros, }
  v.compile(@anode.ParseContext::new(), scope, cid=LNum(0))
  let set : Set[String] = Set([])
  guard v.anode is Some(node)
  node.collect_classes(set)
  let out = set.to_array()
  out.sort()
  debug_inspect(
    out,
    content=(
      #|["badge", "badge-info"]
    ),
  )
}

///|
priv struct MacroMap {
  macros : Map[String, @anode.Macro]
}

///|
impl @anode.MacroScope for MacroMap with fn lookup_macro(self, name) {
  self.macros.get(name)
}
