// The render-site cache: what it reuses, what it declines, and
// what it does when two instances land in one bucket.
//
// `parse_node` and `to_html` come from render_wbtest.mbt — the same white-box
// test module.

///|
fn RenderCache::size(self : RenderCache) -> (Int, Int) {
  (self.cur.length(), self.prev.length())
}

///|
priv struct CardState {
  title : String
}

///|
impl @component.Fields for CardState with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for CardState with fn decode(f) {
  guard f.get("title") is Some(Str(t)) else { return None }
  Some({ title: t, })
}

///|
impl @component.Fields for CardState with fn schema() {
  @component.SchemaInfo::new(fingerprint="card_state", fields=[
    @component.FieldInfo::new("title", TyText),
  ])
}

///|
/// A registry holding one `Card` component, plus the component itself.
fn card_scope() -> (@component.ComponentStack, @component.Component) raise {
  let card = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<p class=\"card\" @text=\".title\"></p>",
      ),
    },
    name="Card",
    init=CardState::{ title: "", },
    update=(_s : CardState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Next({ title: t, })
        _ => Unhandled
      }
    },
  )
  let scope = @component.ComponentStack::new()
  scope.register_components([card])
  scope.compile_all()
  (scope, card)
}

///|
fn send(
  v : @tutuca.Value,
  name : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  @tutuca.Path::new().update(v, Receive, name, args)
}

///|
/// One render pass over `node` against `root`, the way App::render_now runs
/// one: roll the generation, then render with the cache in the ctx.
fn pass(
  node : @anode.ANode,
  root : @tutuca.Value,
  scope : @component.ComponentStack,
  cache : RenderCache,
) -> @vdom.Vdom {
  cache.next_generation()
  let stack = RenderStack::new(root, comps=scope.comps)
  let ctx = RenderCtx::new(view_resolver=scope.comps, render_cache=cache)
  render(node, stack, ctx).unwrap()
}

///|
/// The one render site every single-slot test uses.
fn one_slot() -> @anode.ANode {
  parse_node("<div><x render=\".a\"></x></div>")
}

///|
/// The text a tree renders, in order.
///
/// The full HTML is not assertable here: a rendered site carries a `§Comp§`
/// meta and `data-cid` stamps holding the component's registry id, which comes
/// from a process-global counter and so depends on what else the suite built.
/// The text is what the cache could get WRONG, and it is stable.
fn texts(v : @vdom.Vdom) -> Array[String] {
  let out : Array[String] = []
  fn go(n : @vdom.Vdom) -> Unit {
    match n {
      Text(s) => out.push(s)
      Comment(_) => ()
      Fragment(cs) =>
        for c in cs {
          go(c)
        }
      Node(e) =>
        for c in e.childs {
          go(c)
        }
    }
  }

  go(v)
  out
}

///|
fn first_child(v : @vdom.Vdom) -> @vdom.Vdom {
  guard v is Node(node) && node.childs is [child, ..] else {
    abort("expected a node with a child")
  }
  child
}

///|
test "an unchanged instance is reused, as the very same Vdom" {
  // The reuse IS the physical identity: that is what @vdom's differ
  // short-circuits on, so a hit that returned an equal-but-fresh tree would
  // save the render and none of the patch.
  let (scope, card) = card_scope()
  let node = one_slot()
  let cache = RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("one") }) })
  let first = pass(node, root, scope, cache)
  let second = pass(node, root, scope, cache)
  assert_eq(texts(second), ["one"])
  // the rendered site inside the wrapper is the reused object
  guard! first is Node(f)
  guard! second is Node(s)
  assert_true(physical_equal(f.childs[0], s.childs[0]))
}

///|
test "an updated instance misses, because its revision moved" {
  let (scope, card) = card_scope()
  let node = one_slot()
  let cache = RenderCache::new()
  let inst = card.make({ "title": Str("one") })
  let before = pass(node, Map({ "a": inst }), scope, cache)
  let renamed = send(inst, "rename", [Str("two")])
  let after = pass(node, Map({ "a": renamed }), scope, cache)
  assert_eq(texts(after), ["two"])
  assert_false(physical_equal(first_child(before), first_child(after)))
}

///|
test "two instances sharing a bucket are correct, and thrash" {
  // Two instances made from the same arguments have the same origin — that is
  // what dropping uniqueness means. The stored value's physical identity is
  // what turns the collision into a miss, so each pass rebuilds the site the
  // other one filled and BOTH render the right thing. A wrong subtree here
  // would be the only way this design could fail; a thrash is a cost.
  let (scope, card) = card_scope()
  let node = one_slot()
  let cache = RenderCache::new()
  let a = card.make({ "title": Str("same") })
  let b = card.make({ "title": Str("same") })
  guard! a.identity() is Some(id_a)
  guard! b.identity() is Some(id_b)
  assert_eq(id_a.to_hex(), id_b.to_hex())
  let first_a = pass(node, Map({ "a": a }), scope, cache)
  assert_eq(texts(first_a), ["same"])
  assert_eq(texts(pass(node, Map({ "a": b }), scope, cache)), ["same"])
  let second_a = pass(node, Map({ "a": a }), scope, cache)
  assert_eq(texts(second_a), ["same"])
  // The intervening instance overwrote the shared bucket, so A rebuilt.
  assert_false(physical_equal(first_child(first_a), first_child(second_a)))
}

///|
test "one instance at two sites in one pass: a miss that overwrites" {
  // Both sites key on the same origin, and they differ in node_id, so the
  // second one cannot take the first's entry. It overwrites instead — which
  // is why the §Comp§ metas below carry their own nids and not one nid twice.
  let (scope, card) = card_scope()
  let node = parse_node("<div><x render=\".a\"></x><x render=\".a\"></x></div>")
  let cache = RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("twice") }) })
  assert_eq(texts(pass(node, root, scope, cache)), ["twice", "twice"])
  // one bucket, so the two sites cannot both be held
  assert_eq(cache.size(), (1, 0))
}

///|
test "a value with no bucket is declined, not missed" {
  // A plain Map render site (and every component-less ViewMap embedding) has
  // nothing whose generations can be told apart. The cache is not consulted at
  // all — building a key and missing with it is what OPTIMIZATIONS #8 measured
  // as the reason the previous cache lost time where it did not hit.
  let cache = RenderCache::new()
  let card = parse_node("<div class=\"plain\">static</div>")
  let resolver : &ViewResolver = ViewMap::{ views: { "main": card }, }
  let v : @tutuca.Value = Map({ "a": Num(1) })
  let ctx = RenderCtx::new(view_resolver=resolver, render_cache=cache)
  let stack = RenderStack::new(v)
  guard! render_root(v, stack, ctx) is Some(first)
  guard! render_root(v, stack, ctx) is Some(second)
  assert_eq(cache.size(), (0, 0))
  assert_false(physical_equal(first, second))
  assert_true(first.is_equal_to(second))
}

///|
test "an entry is reusable for one pass, then falls out" {
  // Two generations is the whole growth bound, and this is exactly how far it
  // reaches: an entry filled in one pass is still found in the next (out of
  // `prev`, and promoted by the hit), and a pass that goes by without
  // rendering the site drops it. Nothing needs evicting on a timer.
  let (scope, card) = card_scope()
  let node = one_slot()
  let empty = parse_node("<div></div>")
  let cache = RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("one") }) })
  let first = pass(node, root, scope, cache)
  let second = pass(node, root, scope, cache)
  assert_true(physical_equal(first_child(first), first_child(second)))
  let _ = pass(empty, root, scope, cache) // a pass that renders no site
  let after_gap = pass(node, root, scope, cache)
  assert_false(physical_equal(first_child(second), first_child(after_gap)))
}

///|
/// A child whose `compute` answers a name an ancestor published, the way a
/// generated one does: by asking the stack it was handed.
priv struct ThemedState {
  label : String
  child : @tutuca.Value
}

///|
impl @component.Fields for ThemedState with fn schema() {
  @component.SchemaInfo::new(fingerprint="themed_state", fields=[
    @component.FieldInfo::new("label", TyText),
    @component.FieldInfo::new("child", TyAny),
  ])
}

///|
impl @component.Fields for ThemedState with fn encode(s) {
  { "label": Str(s.label), "child": s.child }
}

///|
impl @component.Fields for ThemedState with fn decode(f) {
  guard f.get("label") is Some(Str(l)) else { return None }
  Some({ label: l, child: f.get("child").unwrap_or(Null), })
}

///|
test "a compute reading `*name` is answered by the render chain it is under" {
  // The parity claim the whole change rests on. `stack.lookup_dynamic` is the
  // call `core/value_eval.mbt` makes for a `Val::Dyn` in a SLOT, so a `pred`
  // or a `compute` that reads `*theme` now answers what `@text="*theme"`
  // beside it would answer — one question, one answer, both backends.
  //
  // Before this, the same body compiled to `ctx.lookup(...)` in a function
  // that had no `ctx`, so the generated module did not build at all.
  let themed = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<p><x text=\"$themeLabel\"></x>|<x text=\"*theme\"></x></p>",
      ),
    },
    name="Themed",
    init=ThemedState::{ label: "", child: Null, },
    compute={
      "themeLabel": (_s : ThemedState, _args, stack) => {
        stack.lookup_dynamic("theme")
      },
    },
    lookup=[@component.lookup_name("theme")],
  )
  let shell = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".child\"></x></div>",
      ),
    },
    name="Shell",
    init=ThemedState::{ label: "dark", child: Null, },
    provide={ "theme": ".label" },
  )
  let scope = @component.ComponentStack::new()
  scope.register_components([themed, shell])
  scope.compile_all()
  let child_fields : Map[String, @tutuca.Value] = { "label": Str("x") }
  let child = themed.make(child_fields)
  let shell_fields : Map[String, @tutuca.Value] = {
    "label": Str("dark"),
    "child": child,
  }
  let root : @tutuca.Value = Map({ "a": shell.make(shell_fields) })
  let html = to_html(pass(one_slot(), root, scope, RenderCache::new()))
  // Both halves read "dark": the slot's `*theme` and the compute's
  // `stack.lookup_dynamic("theme")` are the same question.
  assert_true(html.contains("dark|dark"))
}
