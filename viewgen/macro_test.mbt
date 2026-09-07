///|
/// A macro declared in the view file, with defaults and parameters read in its
/// body — the shape `svg_more.mbt` registers from MoonBit today.
let macro_src : String =
  #|spec:
  #|  Icons:
  #|    field size :: Int
  #|    field heart :: String
  #|    field star :: String
  #|
  #|view:
  #|  macro icon(~size: "24", ~color: "currentColor", ~path: ""):
  #|    svg(width: size, height: size, viewBox: "0 0 24 24", stroke: color):
  #|      path(d: path)
  #|
  #|  Icons:
  #|    div(class: "icons"):
  #|      icon(~size: it.size, ~color: "#e11d48", ~path: it.heart)
  #|      icon(~size: "20", ~path: it.star)

///|
test "a macro declared in the view file is split out, not treated as a view" {
  let vs = @viewgen.read_file(macro_src)
  assert_eq(only(vs).views.map(v => v.name), ["main"])
  assert_eq(vs.macros.map(m => m.name), ["icon"])
  // The macro's BODY is not here: a view arrives expanded, so what a consumer
  // needs of a macro is its name. See `viewgen/read.mbt`.
  assert_eq(vs.macros[0].source, "")
}

///|
test "the macro is expanded before the surface is taken" {
  let vs = @viewgen.read_file(macro_src)
  // A view arrives EXPANDED — `ViewBuilder` grafts a macro call where it
  // stands — so the expansion's own field reads are in the surface whether or
  // not the macro table is passed. Passing it used to be the difference
  // between a surface and a `no macro named 'icon'` error; the reader answers
  // that question now, and it answers it once.
  let with_ = @viewgen.view_surface(only(vs).views, macros=vs.macros)
  let without = @viewgen.view_surface(only(vs).views)
  assert_eq(with_.fields, ["heart", "size", "star"])
  assert_eq(without.fields, with_.fields)
}

///|
test "a macro view compiles to a tree, with no macro node left in it" {
  let vs = @viewgen.read_file(macro_src)
  let ir = @viewgen.emit_ir_module("Icons", "icons.tutu", vs)
  // The expansion is inlined: <svg> from the macro body appears in the tree,
  // and no MacroCall constructor survives (it is not expressible).
  assert_true(ir.contains("@anode.h(\"svg\""))
  assert_true(ir.contains("@anode.h(\"path\""))
  assert_true(!ir.contains("MacroCall"))
  // The default won where the call did not pass one, and the call won where
  // it did: `size="20"` overrides `'24'`.
  assert_true(ir.contains("\"20\"") || ir.contains("const_num(20"))
}

///|
test "the compiled macro view renders" {
  let vs = @viewgen.read_file(macro_src)
  let views = @viewgen.build_views(only(vs), macros=vs.macros)
  guard! views.get("main") is Some(v) && v.anode is Some(_)
  guard! v.ctx is Some(_)
  // The macro body's own event registrations land in the view's context, so
  // the renderer can still resolve them by data-eid.
  assert_eq(v.name, "main")
}

///|
/// The single component a one-component file declares. A local copy: the
/// original lived beside the splitter, which is one package down now.
fn only(f : @viewfile.ViewFile) -> @viewfile.ViewSet {
  f.components[0]
}
