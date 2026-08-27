///| What a stored component IS, and where it goes.
///
/// Two things, deliberately separate. A `Snapshot` is the value — enough to
/// build the instance again, from either end — and a `Store` is somewhere to
/// put it. The browser's localStorage is one store, a Map is another, and the
/// code that decides WHEN to save should be able to say so without knowing
/// which one it is talking to.

///|
/// One stored instance.
///
/// Both halves are here on purpose. `state` is the guest's own bytes, which
/// only the guest reads and which may hold what the declared fields do not
/// name; `fields` is the host's projection of those declared fields, which the
/// host can produce and consume with no guest code at all. A snapshot that
/// carries both restores through the guest when it can and through the
/// framework when it cannot — a guest that changed its format, a bundle that
/// is not loaded yet, a component that never persisted anything.
pub(all) struct Snapshot {
  /// The bundle's module name, so a restore knows whom to ask.
  module_ : String
  /// The component within it.
  component : String
  /// The name this instance answers to across sessions, and the key it is
  /// stored under by `save`.
  id : String
  /// The guest's opaque bytes. Empty means the guest does not persist, which
  /// is a decision rather than a failure: `fields` is then the whole story.
  state : Bytes
  /// The declared-field projection (`Value::to_json` over the schema).
  fields : Json
} derive(Eq, Debug)

///|
/// A key-value store of TEXT.
///
/// Text rather than bytes because every store worth having on a page is
/// string-shaped — localStorage, sessionStorage, a cookie, a JSON column —
/// and pretending otherwise would mean every implementation inventing the
/// same encoding. `Snapshot::to_json` does it once, with base64, so an
/// implementation of this trait is four one-line methods.
pub(open) trait Store {
  fn get(Self, key : String) -> String?
  fn set(Self, key : String, value : String) -> Unit
  fn remove(Self, key : String) -> Unit
  /// Every key that starts with `prefix`, so a host can find what it saved
  /// without keeping a second index of its own. Order is the store's.
  fn keys(Self, prefix~ : String) -> Array[String]
}

///|
/// The key a snapshot is stored under: the store's namespace, then what the
/// instance is called. One shape in one place, because `save` and `keys` have
/// to agree about it and a mismatch would look exactly like "nothing saved".
pub fn key_of(prefix : String, id : String) -> String {
  prefix + id
}

///|
/// Store a snapshot under `prefix + snapshot.id`.
///
/// A snapshot with no id is NOT stored, and that is the point of the `id`
/// field: something the host can find again. Answering false rather than
/// inventing a key keeps "saved" honest.
pub fn save(
  store : &Store,
  snap : Snapshot,
  prefix? : String = "tutuca:",
) -> Bool {
  guard snap.id != "" else { return false }
  store.set(key_of(prefix, snap.id), snap.to_json().stringify())
  true
}

///|
/// Read one back. None for a key that holds nothing, or text that is not a
/// snapshot — a store is shared with whoever else writes to it, so anything
/// in it is untrusted input.
pub fn load(
  store : &Store,
  id : String,
  prefix? : String = "tutuca:",
) -> Snapshot? {
  guard store.get(key_of(prefix, id)) is Some(text) else { return None }
  let parsed = @json.parse(text) catch { _ => return None }
  Snapshot::from_json(parsed)
}

///|
/// Forget one. Idempotent, like every store's remove.
pub fn forget(
  store : &Store,
  id : String,
  prefix? : String = "tutuca:",
) -> Unit {
  store.remove(key_of(prefix, id))
}

///|
/// The ids this store holds under `prefix`, with the prefix stripped — what a
/// host restoring a page asks for before it knows what it will find.
pub fn saved_ids(store : &Store, prefix? : String = "tutuca:") -> Array[String] {
  store
  .keys(prefix~)
  .map(k => {
    if k.has_prefix(prefix) {
      k[prefix.length():].to_owned()
    } else {
      k
    }
  })
}

///|
/// A snapshot as JSON: the guest's bytes base64 inside it, everything else as
/// itself. This is the one place bytes and text meet, which is why `Store` can
/// be a text store and a guest can still persist a compressed buffer.
pub fn Snapshot::to_json(self : Snapshot) -> Json {
  {
    "module": Json::string(self.module_),
    "component": Json::string(self.component),
    "id": Json::string(self.id),
    "state": Json::string(@base64.encode(self.state[:])),
    "fields": self.fields,
  }
}

///|
/// The inverse, over input nobody vouched for. None for anything that is not
/// a snapshot; base64 that will not decode reads as "no guest bytes" rather
/// than as a failure, because the declared fields are still worth having.
pub fn Snapshot::from_json(j : Json) -> Snapshot? {
  guard j is Object(m) else { return None }
  guard m.get("module") is Some(String(module_)) else { return None }
  guard m.get("component") is Some(String(component)) else { return None }
  let id = match m.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let state = match m.get("state") {
    Some(String(b64)) =>
      if b64 == "" {
        b""
      } else {
        @base64.decode(b64[:]) catch {
          _ => b""
        }
      }
    _ => b""
  }
  let fields = m.get("fields").unwrap_or(Json::object({}))
  Some({ module_, component, id, state, fields, })
}

///|
/// The declared fields as a Map a constructor takes — the restore path that
/// needs no guest code, and the one a host falls back to when the guest
/// refuses its own bytes.
pub fn Snapshot::field_args(self : Snapshot) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  if self.fields is Object(m) {
    for name, v in m {
      out[name] = @tutuca.Value::from_json(v)
    }
  }
  out
}

///|
/// Whether the guest wrote anything of its own.
pub fn Snapshot::has_state(self : Snapshot) -> Bool {
  self.state.length() > 0
}
