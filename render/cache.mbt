// The component render-site cache (the port of src/cache.js's DomCache,
// adapted to the vdom architecture). JS caches real DOM nodes in a WeakMap
// keyed by the identity of [node, value, ...dynBindValues]; this caches the
// rendered `@vdom.Vdom` of a render site (JS _rValComp) and reuses it when
// nothing the site renders from has changed. `@vdom`'s morph then
// short-circuits the reused subtree through its physical_equal fast path.
//
// This is the second version of this file. The first keyed a Map on a string
// built per site per pass by a `site_cache_key` that concatenated the resolved
// view, the @push-view trail, the node id and the innermost loop key.
// benchmarks/OPTIMIZATIONS.md #8 measured that string as the reason the cache
// LOST time wherever it missed, and deleted the whole thing with the
// instruction that a reintroduced cache should be able to decline. So:
//
//   - The key is an instance's `@tutuca.ObjId` origin — a UInt64 the instance
//     already carries. Nothing is built at lookup time.
//   - A value with no id (a plain Map render site, a component-less ViewMap
//     embedding) is DECLINED before anything is spent on it.
//
// What a bucket does NOT have to be is unique. An `ObjId` is a fingerprint, so
// two instances made from the same arguments land in one bucket, as do two
// bundles loaded at runtime declaring the same component. That is fine, and it
// is what the entry below is for: a hit is decided by comparing the stored
// value by PHYSICAL identity (plus the site and the dynamic binds), so a
// bucket collision is a miss that overwrites. A stale subtree is never
// returned, and the cache can only ever affect performance.
//
// Two generations bound growth (entries not reused in a pass fall out after
// the next), standing in for the JS WeakMap's GC + periodic evict().

///|
/// One cached render site. Everything above `vdom` is what has to still hold
/// for it to be handed back.
///
/// The list is exactly what a render site reads, and no more. `render_site`
/// enters the component with `is_frame=true` and empty binds, and
/// `lookup_bind_chain` stops at a frame — so the enclosing `@each` binds and
/// every `@name` scope around it cannot reach inside, and are not here.
/// Position is not here either: handlers are reconstructed at dispatch time
/// from `data-eid` stamps and the meta comments (see events.mbt), never baked
/// into the subtree. What IS baked in is the `§Comp§` meta, which carries
/// `nid`/`cid`/`vid` — hence those three.
/// `pub` only because `RenderCache` is, and a public definition cannot name a
/// private type. Nothing outside this file reads a field of one.
pub struct CacheEntry {
  rev : Int
  node_id : Int?
  cid : Int
  vid : String
  /// The validator. Physical identity, because the transactor swaps the root
  /// with structural sharing: a subtree the last transaction did not touch
  /// keeps the exact same Value object, and that is the signal.
  value : @tutuca.Value
  dyn_binds : @component.DynBinds?
  vdom : @vdom.Vdom
}

///|
pub struct RenderCache {
  mut cur : Map[UInt64, CacheEntry]
  mut prev : Map[UInt64, CacheEntry]
  mut hit : Int
  mut miss : Int
}

///|
pub fn RenderCache::new() -> RenderCache {
  { cur: Map([]), prev: Map([]), hit: 0, miss: 0 }
}

///|
/// Drop both generations. For teardown (App::destroy), not for eviction —
/// next_generation is what bounds the cache while an app is live.
pub fn RenderCache::clear(self : RenderCache) -> Unit {
  self.cur = Map([])
  self.prev = Map([])
}

///|
fn dyn_binds_eq(a : @component.DynBinds?, b : @component.DynBinds?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
/// Cheapest test first: the revision is one Int compare and rules out the
/// common invalidation (this instance was updated) before anything else is
/// looked at.
fn CacheEntry::valid(
  self : CacheEntry,
  id : @tutuca.ObjId,
  node_id : Int?,
  rv : ResolvedView,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
) -> Bool {
  self.rev == id.rev &&
  self.node_id == node_id &&
  self.cid == rv.cid &&
  self.vid == rv.vid &&
  physical_equal(self.value, value) &&
  dyn_binds_eq(self.dyn_binds, dyn_binds)
}

///|
/// The cached vdom for this site, when everything it was built from still
/// holds. A previous-generation hit is promoted into the current generation so
/// it survives another pass.
pub fn RenderCache::get(
  self : RenderCache,
  id : @tutuca.ObjId,
  node_id : Int?,
  rv : ResolvedView,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
) -> @vdom.Vdom? {
  match self.cur.get(id.origin) {
    Some(e) if e.valid(id, node_id, rv, value, dyn_binds) => {
      self.hit += 1
      Some(e.vdom)
    }
    _ =>
      match self.prev.get(id.origin) {
        Some(e) if e.valid(id, node_id, rv, value, dyn_binds) => {
          self.hit += 1
          self.cur[id.origin] = e
          Some(e.vdom)
        }
        _ => {
          self.miss += 1
          None
        }
      }
  }
}

///|
pub fn RenderCache::set(
  self : RenderCache,
  id : @tutuca.ObjId,
  node_id : Int?,
  rv : ResolvedView,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
  vdom : @vdom.Vdom,
) -> Unit {
  self.cur[id.origin] = {
    rev: id.rev,
    node_id,
    cid: rv.cid,
    vid: rv.vid,
    value,
    dyn_binds,
    vdom,
  }
}

///|
/// Roll the generation at the start of a render pass: this pass's entries
/// become `prev`; anything not re-hit this pass is dropped after it.
pub fn RenderCache::next_generation(self : RenderCache) -> Unit {
  self.prev = self.cur
  self.cur = Map([])
}

///|
/// (hit, miss) since the last evict, WITHOUT clearing — the instrumentation
/// read. `evict` answers the same question but empties the cache doing it,
/// which makes it useless for watching a running app (or for a test that wants
/// to assert what the next pass did).
pub fn RenderCache::stats(self : RenderCache) -> (Int, Int) {
  (self.hit, self.miss)
}

///|
/// The number of entries held, current generation plus the one behind it.
/// Bounded growth is the whole reason there are two generations, so it is
/// worth being able to look.
pub fn RenderCache::size(self : RenderCache) -> (Int, Int) {
  (self.cur.length(), self.prev.length())
}

///|
/// Clear everything and return (hit, miss) since the last evict
/// (JS WeakMapDomCache.evict).
pub fn RenderCache::evict(self : RenderCache) -> (Int, Int) {
  let stats = (self.hit, self.miss)
  self.hit = 0
  self.miss = 0
  self.cur = Map([])
  self.prev = Map([])
  stats
}
