// Port of the optimize (RenderOnce) suite from tutuca test/anode.test.js.

///|
priv struct OptScope {
  macros : Map[String, @anode.Macro]
}

///|
impl @anode.MacroScope for OptScope with fn lookup_macro(self, name) {
  self.macros.get(name)
}

///|
fn optimize_view(
  raw_view : String,
  macros? : Map[String, @anode.Macro] = Map([]),
) -> @anode.View raise @anode.MacroError {
  let v = @anode.View::new("myView", raw_view~)
  let px = @anode.ParseContext::new()
  v.compile(px, OptScope::{ macros, }, cid=LNum(0))
  v
}

///|
test "whole root fragment cached when all childs constant" {
  let v = optimize_view(
    "<x><p>a</p>\nb\n<ul>\n  <li>c</li>\n  <li>d</li>\n</ul></x>",
  )
  assert_true(v.anode is Some(RenderOnce(_)))
}

///|
test "fragment caches only constant childs" {
  let v = optimize_view(
    "<x><p>a</p>\nb\n<div @show=\".isVisible\">show</div>\n<div @hide=\".isHidden\">hide</div>\n<p :id=\".key\">dyn attrs</p>\n<ul>\n  <li>c</li>\n  <li>d</li>\n</ul></x>",
  )
  guard v.anode is Some(Fragment(f))
  // Layout mirrors the JS test: whitespace text nodes interleave the elements.
  assert_true(f.childs[0] is RenderOnce(_)) // <p>a</p>
  assert_true(f.childs[1] is RenderOnce(_)) // "b" text (with surrounding space)
  guard f.childs[2] is Show(show)
  assert_true(show.node is RenderOnce(_))
  guard f.childs[4] is Hide(hide)
  assert_true(hide.node is RenderOnce(_))
  assert_true(f.childs[6] is Dom(_)) // dyn attrs stay unoptimized
  assert_true(f.childs[8] is RenderOnce(_)) // <ul>
}

///|
test "show/hide are not cached themselves but optimize their child" {
  let v = optimize_view("<div @show=\".a\">hi</div>")
  guard v.anode is Some(Show(w))
  assert_true(w.node is RenderOnce(_))
  let v2 = optimize_view("<div @hide=\".a\">hi</div>")
  guard v2.anode is Some(Hide(w2))
  assert_true(w2.node is RenderOnce(_))
}

///|
test "each optimizes constant child" {
  let v = optimize_view("<div @each=\".a\">hi</div>")
  guard v.anode is Some(Each(e))
  assert_true(e.node is RenderOnce(_))
}

///|
test "scope optimizes constant child" {
  let v = optimize_view("<div @enrich-with=\"$a\">hi</div>")
  guard v.anode is Some(Scope(s))
  assert_true(s.node is RenderOnce(_))
}

///|
test "render-it is never optimized" {
  let v = optimize_view("<div><x render-it></x></div>")
  guard v.anode is Some(Dom(d))
  assert_true(d.childs[0] is RenderIt(_))
}

///|
test "render-each is never optimized" {
  let v = optimize_view("<div><x render-each=\".a\"></x></div>")
  guard v.anode is Some(Dom(d))
  guard d.childs[0] is Each(e)
  assert_true(e.node is RenderIt(_))
}

///|
test "x text is never optimized" {
  let v = optimize_view("<div><x text=\".a\"></x></div>")
  guard v.anode is Some(Dom(d))
  assert_true(d.childs[0] is RenderText(_))
}

///|
test "push-view optimizes constant child" {
  let v = optimize_view("<div @push-view=\"'myview'\"><p>static</p></div>")
  guard v.anode is Some(PushView(w))
  assert_true(w.node is RenderOnce(_))
}

///|
test "constant macro child gets wrapped by parent" {
  let card = @anode.Macro::{
    defaults: Map([]),
    raw_view: "<div class=\"card\"><p>static</p></div>",
  }
  let v = optimize_view(
    "<div><x:card></x:card><span :class=\".cls\">dyn</span></div>",
    macros={ "card": card },
  )
  guard v.anode is Some(Dom(d))
  assert_true(d.childs[0] is RenderOnce(_))
}

///|
test "dynamic macro subtree gets optimized" {
  let card = @anode.Macro::{
    defaults: Map([]),
    raw_view: "<div>\n  <p>static</p>\n  <span :class=\".cls\">dyn</span>\n</div>",
  }
  let v = optimize_view("<div><x:card></x:card></div>", macros={ "card": card })
  guard v.anode is Some(Dom(d))
  guard d.childs[0] is MacroCall(m)
  guard m.node is Some(Dom(inner))
  assert_true(inner.childs[0] is RenderOnce(_))
}
