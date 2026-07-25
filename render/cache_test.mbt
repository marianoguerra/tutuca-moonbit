// RenderCache instrumentation: the hit/miss counters are what tell you whether
// the cache is doing anything at all, so they are worth pinning. Most of these
// drive the cache directly — one entry, one question — and the end-to-end
// behaviour through `render_root` is covered in render_test.mbt.
//
// The invariant behind every assertion: a hit requires the stored value AND
// the stored dynamic-binding context to be PHYSICALLY unchanged. A key
// collision whose identities disagree is a miss and overwrites, so the cache
// can only ever cost time, never correctness.

///|
fn vdom_of(tag : String) -> @vdom.Vdom {
  @vdom.h(tag, attrs=Map([]))
}

///|
test "hit and miss counters track lookups" {
  let cache = @render.RenderCache::new()
  let v : @tutuca.Value = Map({ "a": Num(1) })
  let node = vdom_of("div")
  @debug.assert_eq(cache.stats(), (0, 0))

  // cold: a miss
  assert_true(cache.get("k", v, None) is None)
  @debug.assert_eq(cache.stats(), (0, 1))
  cache.set("k", v, None, node)

  // warm: two hits on the same identity
  assert_true(cache.get("k", v, None) is Some(_))
  assert_true(cache.get("k", v, None) is Some(_))
  @debug.assert_eq(cache.stats(), (2, 1))

  // a structurally equal but distinct value is a MISS: identity is the signal
  let twin : @tutuca.Value = Map({ "a": Num(1) })
  assert_eq(twin, v) // structurally equal…
  assert_true(cache.get("k", twin, None) is None) // …and still a miss
  @debug.assert_eq(cache.stats(), (2, 2))
}

///|
test "a hit returns the stored vdom, by identity" {
  let cache = @render.RenderCache::new()
  let v : @tutuca.Value = Str("x")
  let node = vdom_of("p")
  cache.set("k", v, None, node)
  guard cache.get("k", v, None) is Some(got)
  assert_true(physical_equal(got, node))
}

///|
test "generation rollover promotes a reused entry and drops the rest" {
  let cache = @render.RenderCache::new()
  let kept : @tutuca.Value = Str("kept")
  let dropped : @tutuca.Value = Str("dropped")
  cache.set("kept", kept, None, vdom_of("a"))
  cache.set("dropped", dropped, None, vdom_of("b"))
  @debug.assert_eq(cache.size(), (2, 0))

  // one roll: both entries move to `prev` and are still reachable
  cache.next_generation()
  @debug.assert_eq(cache.size(), (0, 2))
  assert_true(cache.get("kept", kept, None) is Some(_)) // promoted into `cur`
  @debug.assert_eq(cache.size(), (1, 2))

  // second roll: `prev` is replaced by what this pass reused, so the entry
  // nothing asked for is gone and the promoted one survives.
  cache.next_generation()
  assert_true(cache.get("kept", kept, None) is Some(_))
  assert_true(cache.get("dropped", dropped, None) is None)
}

///|
test "an entry unused for two generations falls out" {
  let cache = @render.RenderCache::new()
  let v : @tutuca.Value = Str("v")
  cache.set("k", v, None, vdom_of("i"))
  cache.next_generation()
  cache.next_generation()
  assert_true(cache.get("k", v, None) is None)
}

///|
test "the same component value under two slots caches separately" {
  // A child component rendered at two sites is ONE value with two entries;
  // each site keeps its own vdom, and neither invalidates the other.
  let cache = @render.RenderCache::new()
  let shared : @tutuca.Value = Map({ "n": Num(7) })
  let left = vdom_of("left")
  let right = vdom_of("right")
  cache.set("slot-a", shared, None, left)
  cache.set("slot-b", shared, None, right)
  guard cache.get("slot-a", shared, None) is Some(a)
  guard cache.get("slot-b", shared, None) is Some(b)
  assert_true(physical_equal(a, left))
  assert_true(physical_equal(b, right))
  @debug.assert_eq(cache.size(), (2, 0))
}

///|
test "numeric and string loop keys do not share an entry" {
  // The slot key ends with the innermost @each key rendered as text, so a
  // list index 1 and a map key "1" can produce the SAME string. They must not
  // be able to serve each other's vdom — the stored identity is what settles
  // it, and a disagreement is a miss.
  let cache = @render.RenderCache::new()
  let by_index : @tutuca.Value = Str("item at 1")
  let by_name : @tutuca.Value = Str("item named 1")
  let indexed = vdom_of("indexed")
  cache.set("c\u{1f}main\u{1f}\u{1f}3\u{1f}1", by_index, None, indexed)
  // same key text, different value identity -> miss, and it overwrites
  assert_true(
    cache.get("c\u{1f}main\u{1f}\u{1f}3\u{1f}1", by_name, None) is None,
  )
  cache.set("c\u{1f}main\u{1f}\u{1f}3\u{1f}1", by_name, None, vdom_of("named"))
  // the overwritten entry is gone rather than stale
  assert_true(
    cache.get("c\u{1f}main\u{1f}\u{1f}3\u{1f}1", by_index, None) is None,
  )
  guard cache.get("c\u{1f}main\u{1f}\u{1f}3\u{1f}1", by_name, None) is Some(got)
  assert_false(physical_equal(got, indexed))
}

///|
test "a changed dynamic binding invalidates an otherwise unchanged value" {
  // Same value, different provide/lookup context: the view can read the
  // dynamic binding, so the cached fragment is not reusable.
  let cache = @render.RenderCache::new()
  let v : @tutuca.Value = Str("same")
  let binds_a : @component.DynBinds = { binds: Map([]), parent: None }
  let binds_b : @component.DynBinds = { binds: Map([]), parent: None }
  cache.set("k", v, Some(binds_a), vdom_of("div"))
  assert_true(cache.get("k", v, Some(binds_a)) is Some(_)) // same frame: hit
  assert_true(cache.get("k", v, Some(binds_b)) is None) // different frame: miss
  assert_true(cache.get("k", v, None) is None) // no frame at all: miss
  // …and the reverse: an entry stored without a frame is not served to one
  let cache2 = @render.RenderCache::new()
  cache2.set("k", v, None, vdom_of("div"))
  assert_true(cache2.get("k", v, Some(binds_a)) is None)
  assert_true(cache2.get("k", v, None) is Some(_))
}

///|
test "evict clears both generations and reports the counters" {
  let cache = @render.RenderCache::new()
  let v : @tutuca.Value = Str("v")
  assert_true(cache.get("k", v, None) is None) // miss
  cache.set("k", v, None, vdom_of("div"))
  assert_true(cache.get("k", v, None) is Some(_)) // hit
  @debug.assert_eq(cache.stats(), (1, 1))
  @debug.assert_eq(cache.evict(), (1, 1))
  @debug.assert_eq(cache.stats(), (0, 0))
  @debug.assert_eq(cache.size(), (0, 0))
  assert_true(cache.get("k", v, None) is None)
}
