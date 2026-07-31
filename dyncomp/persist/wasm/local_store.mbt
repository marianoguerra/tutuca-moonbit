///| `Store` over the browser's localStorage.
///
/// Four imports and no cleverness, which is the point: the decisions about
/// WHAT to store and WHEN live in `dyncomp/persist` and in the host, and this
/// is the part that knows the browser. A page in private mode, a storage quota
/// that is full, a user who turned it off — every one of those surfaces as a
/// throwing `setItem`, and the JS side swallows it, so a failed write reads
/// here as "nothing was stored" rather than as a crash mid-render.

///|
extern "wasm" fn tkv_get(key : String) -> String = "tkv" "get"

///|
extern "wasm" fn tkv_set(key : String, value : String) -> Unit = "tkv" "set"

///|
extern "wasm" fn tkv_remove(key : String) -> Unit = "tkv" "remove"

///|
/// Every key with this prefix, as a JSON array of strings. One call rather
/// than length + key(i) in a loop: each FFI hop copies a string, and the list
/// is read once when a page starts.
extern "wasm" fn tkv_keys(prefix : String) -> String = "tkv" "keys"

///|
/// The browser's localStorage, as a `Store`.
///
/// Stateless — every method goes straight to the browser — so holding two of
/// these is the same as holding one, and a value written by another tab is
/// visible to this one on the next read.
pub struct LocalStore {
  /// Prepended to every key, so one page's components cannot collide with
  /// another's in the single flat namespace a browser origin has. Distinct
  /// from the snapshot prefix `@persist.save` takes: this one separates APPS,
  /// that one separates kinds of thing within an app.
  prefix : String
}

///|
pub fn LocalStore::new(prefix? : String = "") -> LocalStore {
  { prefix, }
}

///|
fn LocalStore::full(self : LocalStore, key : String) -> String {
  self.prefix + key
}

///|
pub impl @persist.Store for LocalStore with fn get(self, key) {
  // "" is how the bridge spells a missing key: localStorage answers null and
  // wasm-gc strings are not nullable. A stored empty string is not a snapshot
  // either way, so the two collapse without losing anything.
  let v = tkv_get(self.full(key))
  if v == "" {
    None
  } else {
    Some(v)
  }
}

///|
pub impl @persist.Store for LocalStore with fn set(self, key, value) {
  tkv_set(self.full(key), value)
}

///|
pub impl @persist.Store for LocalStore with fn remove(self, key) {
  tkv_remove(self.full(key))
}

///|
pub impl @persist.Store for LocalStore with fn keys(self, prefix~) {
  let raw = tkv_keys(self.full(prefix))
  let parsed = @json.parse(raw) catch { _ => return [] }
  guard parsed is Array(items) else { return [] }
  let out : Array[String] = []
  let cut = self.prefix.length()
  for item in items {
    if item is String(k) && k.has_prefix(self.prefix) {
      out.push(k[cut:].to_owned())
    }
  }
  out
}
