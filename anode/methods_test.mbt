// View::collect_method_names — what a template CALLS with `$name` (spec.mbt).
// The dyncomp host compares this against a bundle's declared `methods`, which
// is the only thing standing between a forgotten declaration and an attribute
// that silently renders as nothing.

///|
priv struct NoMacrosM {}

///|
impl @anode.MacroScope for NoMacrosM with fn lookup_macro(_self, _name) {
  None
}

///|
fn methods_of(raw_view : String) -> Array[String] raise {
  let v = @anode.View::new("main", raw_view~)
  v.compile(@anode.ParseContext::new(), NoMacrosM::{  }, cid=LNum(0))
  let set : Set[String] = Set([])
  v.collect_method_names(set)
  let out = set.to_array()
  out.sort()
  out
}

///|
test "methods in attribute, text and @if branch positions" {
  let ms = methods_of(
    "<div :class=\"$cls\" :style=\"$sty\" @if.title=\"$on\" @then=\"$yes\" @else=\"$no\"><x text=\"$label\"></x></div>",
  )
  debug_inspect(
    ms,
    content=(
      #|["no", "on", "cls", "sty", "yes", "label"]
    ),
  )
}

///|
test "a path is not a method" {
  // `.field`, `@bind`, `*dyn` and a bare handler name all read through other
  // machinery; only `$name` reaches call-method.
  let ms = methods_of(
    "<div :class=\"@value.headerClass\" :title=\".label\" :lang=\"*theme\" @on.click=\"save\"></div>",
  )
  debug_inspect(ms, content="[]")
}

///|
test "methods nested in a template string and a predicate" {
  let ms = methods_of(
    "<div :class=\"$'row {$kind} {.n}'\" @show=\"empty? $items\"></div>",
  )
  debug_inspect(
    ms,
    content=(
      #|["kind", "items"]
    ),
  )
}

///|
test "@on handlers are collected off the parse context, not the tree" {
  // Attribute parsing registers events on the ParseContext and leaves a
  // data-eid behind, so a tree walk alone sees neither the handler nor its args.
  let ms = methods_of(
    "<button @on.click=\"$bump $step\" @on.keydown+cancel=\"$reset\">go</button>",
  )
  debug_inspect(
    ms,
    content=(
      #|["bump", "step", "reset"]
    ),
  )
}

///|
test "loop directives and render sites are walked" {
  let ms = methods_of(
    "<ul><li @each=\".items\" @when=\"$isBig\" @loop-with=\"$plan\" @text=\"@value\"></li><x render=\".body\" as=\"$viewName\"></x></ul>",
  )
  debug_inspect(
    ms,
    content=(
      #|["plan", "isBig", "viewName"]
    ),
  )
}
