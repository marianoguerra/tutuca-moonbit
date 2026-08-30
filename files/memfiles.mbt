///| A `FileService` with no browser under it.
///
/// What `moon test` drives the whole round trip on: a test saves a trace, reads
/// the text back out of `saved`, feeds it to `provide`, and asks the panel to
/// import it — which is the same sequence a person performs with a download and
/// a file picker, minus the browser.
///
/// It is deliberately not a filesystem. Saving appends to a list and reading
/// answers from a table the test filled, because the questions a test has are
/// "was this saved, under what name" and "what happens when the read fails" —
/// neither of which a real file would answer more truthfully.

///|
/// One file handed to the viewer.
pub(all) struct SavedFile {
  name : String
  mime : String
  text : String
} derive(Eq, Debug)

///|
pub struct MemFiles {
  priv saved : Array[SavedFile]
  /// What a read of each id answers. An id with no entry is an error, which is
  /// the same answer a browser gives for a file the viewer never picked.
  priv provided : Map[Int, Result[String, String]]
}

///|
pub fn MemFiles::new() -> MemFiles {
  { saved: [], provided: Map([]), }
}

///|
/// Everything saved so far, in the order it was saved.
pub fn MemFiles::saved(self : MemFiles) -> Array[SavedFile] {
  self.saved
}

///|
/// The most recent save, which is what a test that made exactly one wants.
pub fn MemFiles::last_saved(self : MemFiles) -> SavedFile? {
  match self.saved {
    [.., last] => Some(last)
    _ => None
  }
}

///|
/// Make `id` answer with `text`.
pub fn MemFiles::provide(self : MemFiles, id~ : Int, text : String) -> Unit {
  self.provided[id] = Ok(text)
}

///|
/// Make `id` fail with `why` — the other half of the round trip, and the one a
/// panel's error path is never otherwise exercised by.
pub fn MemFiles::provide_error(
  self : MemFiles,
  id~ : Int,
  why : String,
) -> Unit {
  self.provided[id] = Err(why)
}

///|
/// Feed the last save straight back as a readable file.
///
/// The round trip in one call, because that is the shape a test actually wants:
/// save a trace, read the same trace. Answers the id it filed it under, or
/// `None` when nothing has been saved.
pub fn MemFiles::round_trip(self : MemFiles) -> Int? {
  match self.last_saved() {
    Some(f) => {
      let id = self.provided.length() + 1
      self.provide(id~, f.text)
      Some(id)
    }
    None => None
  }
}

///|
pub impl FileService for MemFiles with fn save_text(self, name~, mime~, text) {
  self.saved.push({ name, mime, text, })
}

///|
/// Synchronous, which a browser's read is not — and that is the one way this
/// lies. A test that wants to prove a caller survives a read landing LATER
/// holds the continuation itself rather than asking this for it.
pub impl FileService for MemFiles with fn read_text(self, id~, then~) {
  match self.provided.get(id) {
    Some(r) => then(r)
    None => then(Err("no file #\{id}"))
  }
}
