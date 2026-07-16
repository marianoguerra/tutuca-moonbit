// Value-identity render cache (the port of src/cache.js's DomCache, adapted to
// the vdom architecture). JS caches real DOM nodes in a WeakMap keyed by the
// identity of [node, value, ...dynBindValues]; this port caches the rendered
// `@vdom.Vdom` of a component render site (JS _rValComp) and reuses it across
// render passes when the site's value AND dynamic-binding context are
// PHYSICALLY unchanged. The transactor swaps the root with structural sharing,
// so a subtree the last transaction didn't touch keeps the exact same Value
// object — that identity is the cache's validity signal, and morph's
// physical_equal fast path then short-circuits the reused subtree in O(1).
//
// MoonBit has no WeakMap (nor identity-hash), so entries live in a plain
// Map keyed by a per-slot string; the stored (value, dyn_binds) identities
// VALIDATE a hit. A slot-key collision whose identities don't match is treated
// as a miss and overwrites — a stale subtree is never returned, so the cache
// only ever affects performance, never correctness. Two generations bound
// growth (entries not reused in a pass fall out after the next), standing in
// for the JS WeakMap's GC + periodic evict().

// An entry is (source value, dynamic-binding context, rendered vdom); the
// first two identities validate a hit. Kept as a tuple so no internal type
// leaks into RenderCache's public interface.

///|
type CacheEntry = (@tutuca.Value, @component.DynBinds?, @vdom.Vdom)

///|
pub struct RenderCache {
  mut cur : Map[String, CacheEntry]
  mut prev : Map[String, CacheEntry]
  mut hit : Int
  mut miss : Int
}

///|
pub fn RenderCache::new() -> RenderCache {
  { cur: {}, prev: {}, hit: 0, miss: 0 }
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
fn entry_valid(
  e : CacheEntry,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
) -> Bool {
  physical_equal(e.0, value) && dyn_binds_eq(e.1, dyn_binds)
}

///|
/// Return the cached vdom for `key` when its stored value/dyn_binds are still
/// physically identical; promote a previous-generation hit into the current
/// generation so it survives another pass.
pub fn RenderCache::get(
  self : RenderCache,
  key : String,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
) -> @vdom.Vdom? {
  match self.cur.get(key) {
    Some(e) if entry_valid(e, value, dyn_binds) => {
      self.hit += 1
      Some(e.2)
    }
    _ =>
      match self.prev.get(key) {
        Some(e) if entry_valid(e, value, dyn_binds) => {
          self.hit += 1
          self.cur[key] = e
          Some(e.2)
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
  key : String,
  value : @tutuca.Value,
  dyn_binds : @component.DynBinds?,
  vdom : @vdom.Vdom,
) -> Unit {
  self.cur[key] = (value, dyn_binds, vdom)
}

///|
/// Roll the generation at the start of a render pass: this pass's entries
/// become `prev`; anything not re-hit this pass is dropped after it.
pub fn RenderCache::next_generation(self : RenderCache) -> Unit {
  self.prev = self.cur
  self.cur = {}
}

///|
/// Clear everything and return (hit, miss) counters since the last evict
/// (JS WeakMapDomCache.evict).
pub fn RenderCache::evict(self : RenderCache) -> (Int, Int) {
  let stats = (self.hit, self.miss)
  self.hit = 0
  self.miss = 0
  self.cur = {}
  self.prev = {}
  stats
}
