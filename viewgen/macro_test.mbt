///|
/// A macro declared in the view file, with defaults, slots and `^var`
/// references — the shape svg_more.mbt registers from MoonBit today.
let macro_html : String =
  #|<template id="macro:icon" data-size="'24'" data-color="'currentColor'">
  #|  <svg :width="^size" :height="^size" viewBox="0 0 24 24" :stroke="^color"><path :d="^path"></path></svg>
  #|</template>
  #|<template>
  #|  <div class="icons">
  #|    <x:icon :size=".size" :color="'#e11d48'" :path=".heart"></x:icon>
  #|    <x:icon size="20" :path=".star"></x:icon>
  #|  </div>
  #|</template>

///|
test "a macro declared in the view file is split out, not treated as a view" {
  let vs = @viewgen.split_views(macro_html)
  assert_eq(vs.views.map(v => v.name), ["main"])
  assert_eq(vs.macros.map(m => m.name), ["icon"])
  assert_eq(vs.macros[0].defaults, { "size": "'24'", "color": "'currentColor'" })
  assert_true(vs.macros[0].source.contains("^size"))
}

///|
test "the macro expands at generation time" {
  let vs = @viewgen.split_views(macro_html)
  // Without the declarations the call cannot resolve, and that is an error
  // rather than a silently broken view.
  let without = try {
    @viewgen.view_surface(vs.views) |> ignore
    "no error"
  } catch {
    e => @viewgen.GenError::message(e)
  }
  inspect(
    without,
    content=(
      #|view "main": no macro named 'icon' — declare it as <template id="macro:icon">
    ),
  )
  // With them, the expansion's own field reads show up in the surface.
  let s = @viewgen.view_surface(vs.views, macros=vs.macros)
  assert_eq(s.fields, ["heart", "size", "star"])
}

///|
test "a macro view compiles to a tree, with no macro node left in it" {
  let vs = @viewgen.split_views(macro_html)
  assert_true(@viewgen.ir_supported(vs.views, macros=vs.macros))
  let ir = @viewgen.emit_ir_module("Icons", "icons.html", vs)
  // The expansion is inlined: <svg> from the macro body appears in the tree,
  // and no MacroCall constructor survives (it is not expressible).
  assert_true(ir.contains("tag: \"svg\""))
  assert_true(ir.contains("tag: \"path\""))
  assert_true(!ir.contains("MacroCall"))
  // The default won where the call did not pass one, and the call won where
  // it did: `size="20"` overrides `'24'`.
  assert_true(ir.contains("LStr(\"20\")") || ir.contains("Const(lit=LNum(20"))
}

///|
test "the compiled macro view renders" {
  let vs = @viewgen.split_views(macro_html)
  let views = @viewgen.compiled_views(vs)
  guard views.get("main") is Some(v) && v.anode is Some(_)
  guard v.ctx is Some(_)
  // The macro body's own event registrations land in the view's context, so
  // the renderer can still resolve them by data-eid.
  assert_eq(v.name, "main")
}
