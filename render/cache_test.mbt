// The render-site cache, from outside: what it reuses, what it declines, and
// what it does when two instances land in one bucket.
//
// `parse_node` and `to_html` come from render_test.mbt — same blackbox test
// module.

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
  Some(CardState::{ title: t })
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
    init=CardState::{ title: "" },
    update=(_s : CardState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Some(CardState::{ title: t })
        _ => None
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
  cache : @render.RenderCache,
) -> @vdom.Vdom {
  cache.next_generation()
  let stack = @render.RenderStack::new(root, comps=scope.comps)
  let ctx = @render.RenderCtx::new(
    view_resolver=scope.comps,
    render_cache=cache,
  )
  @render.render(node, stack, ctx).unwrap()
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
test "an unchanged instance is reused, as the very same Vdom" {
  // The reuse IS the physical identity: that is what @vdom's differ
  // short-circuits on, so a hit that returned an equal-but-fresh tree would
  // save the render and none of the patch.
  let (scope, card) = card_scope()
  let node = one_slot()
  let cache = @render.RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("one") }) })
  let first = pass(node, root, scope, cache)
  let second = pass(node, root, scope, cache)
  assert_eq(cache.stats(), (1, 1)) // one miss to fill it, one hit to reuse it
  assert_eq(texts(second), ["one"])
  // the rendered site inside the wrapper is the reused object
  guard first is Node(f)
  guard second is Node(s)
  assert_true(physical_equal(f.childs[0], s.childs[0]))
}

///|
test "an updated instance misses, because its revision moved" {
  let (scope, card) = card_scope()
  let node = one_slot()
  let cache = @render.RenderCache::new()
  let inst = card.make({ "title": Str("one") })
  let _ = pass(node, Map({ "a": inst }), scope, cache)
  let renamed = send(inst, "rename", [Str("two")])
  let after = pass(node, Map({ "a": renamed }), scope, cache)
  assert_eq(cache.stats(), (0, 2))
  assert_eq(texts(after), ["two"])
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
  let cache = @render.RenderCache::new()
  let a = card.make({ "title": Str("same") })
  let b = card.make({ "title": Str("same") })
  guard a.identity() is Some(id_a)
  guard b.identity() is Some(id_b)
  assert_eq(id_a.to_hex(), id_b.to_hex())
  assert_eq(texts(pass(node, Map({ "a": a }), scope, cache)), ["same"])
  assert_eq(texts(pass(node, Map({ "a": b }), scope, cache)), ["same"])
  assert_eq(texts(pass(node, Map({ "a": a }), scope, cache)), ["same"])
  // never a hit: each pass evicts the other's entry
  assert_eq(cache.stats(), (0, 3))
}

///|
test "one instance at two sites in one pass: a miss that overwrites" {
  // Both sites key on the same origin, and they differ in node_id, so the
  // second one cannot take the first's entry. It overwrites instead — which
  // is why the §Comp§ metas below carry their own nids and not one nid twice.
  let (scope, card) = card_scope()
  let node = parse_node("<div><x render=\".a\"></x><x render=\".a\"></x></div>")
  let cache = @render.RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("twice") }) })
  assert_eq(texts(pass(node, root, scope, cache)), ["twice", "twice"])
  assert_eq(cache.stats(), (0, 2))
  // one bucket, so the two sites cannot both be held
  assert_eq(cache.size(), (1, 0))
}

///|
test "a value with no bucket is declined, not missed" {
  // A plain Map render site (and every component-less ViewMap embedding) has
  // nothing whose generations can be told apart. The cache is not consulted at
  // all — building a key and missing with it is what OPTIMIZATIONS #8 measured
  // as the reason the previous cache lost time where it did not hit.
  let cache = @render.RenderCache::new()
  let card = parse_node("<div class=\"plain\">static</div>")
  let resolver : &@render.ViewResolver = @render.ViewMap::{
    views: { "main": card },
  }
  let v : @tutuca.Value = Map({ "a": Num(1) })
  let ctx = @render.RenderCtx::new(view_resolver=resolver, render_cache=cache)
  let stack = @render.RenderStack::new(v)
  guard @render.render_root(v, stack, ctx) is Some(first)
  guard @render.render_root(v, stack, ctx) is Some(second)
  assert_eq(cache.stats(), (0, 0))
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
  let cache = @render.RenderCache::new()
  let root : @tutuca.Value = Map({ "a": card.make({ "title": Str("one") }) })
  let _ = pass(node, root, scope, cache)
  assert_eq(cache.stats(), (0, 1)) // filled
  let _ = pass(node, root, scope, cache)
  assert_eq(cache.stats(), (1, 1)) // found in the previous generation
  let _ = pass(empty, root, scope, cache) // a pass that renders no site
  let _ = pass(node, root, scope, cache)
  assert_eq(cache.stats(), (1, 2)) // and it is gone
}
