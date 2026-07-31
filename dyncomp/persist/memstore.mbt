///| A store in memory.
///
/// Not only for tests: a host with no browser storage — a server render, a
/// page in private mode where localStorage throws — needs somewhere for the
/// same code path to write, and "nowhere" is a worse answer than "here until
/// you leave". It is also what makes the persistence tests independent of a
/// backend.

///|
pub struct MemStore {
  entries : Map[String, String]
}

///|
pub fn MemStore::new() -> MemStore {
  { entries: Map([]) }
}

///|
/// How many entries it holds — the one thing a caller asks a memory store that
/// it would not ask a real one.
pub fn MemStore::size(self : MemStore) -> Int {
  self.entries.length()
}

///|
pub impl Store for MemStore with fn get(self, key) {
  self.entries.get(key)
}

///|
pub impl Store for MemStore with fn set(self, key, value) {
  self.entries[key] = value
}

///|
pub impl Store for MemStore with fn remove(self, key) {
  self.entries.remove(key) |> ignore
}

///|
pub impl Store for MemStore with fn keys(self, prefix~) {
  let out : Array[String] = []
  for k in self.entries.keys() {
    if k.has_prefix(prefix) {
      out.push(k)
    }
  }
  out
}
