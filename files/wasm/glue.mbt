///| `FileService` over the browser.
///
/// Two imports and one export, and the asymmetry between them IS the browser:
/// handing somebody a file is a synchronous call that cannot meaningfully
/// fail, and reading one they picked is an asynchronous read that can fail
/// several ways.
///
/// The read is why there is an export at all. A closure cannot cross into JS
/// on wasm-gc, so the continuation cannot go with the request — it stays here,
/// in a table, under a number that does go, and the page hands the number back
/// with the text. That is the same shape `dyncomp`'s bundle loader uses for
/// the same reason, and it is the only shape available.

///|
/// Hand the viewer a file. Blob, object URL, a click on an anchor nobody sees,
/// and the URL revoked — the page has no other way to produce a download.
extern "wasm" fn tfiles_save_text(
  name : String,
  mime : String,
  text : String,
) -> Unit = "tfiles" "save_text"

///|
/// Ask for the text of file `file_id`, to be answered later at `req_id`.
///
/// Answers nothing here: the browser's read is a promise, and the reply
/// arrives through `on_file_text`.
extern "wasm" fn tfiles_read_text(file_id : Int, req_id : Int) -> Unit = "tfiles" "read_text"

///|
/// The reads that have been asked for and not yet answered.
///
/// Module-level because the answer comes back through a package-level EXPORT,
/// which is the only door a wasm-gc page has: an export is a function, not a
/// method, so there is nowhere else for it to look. One page, one table.
let pending : Map[Int, (Result[String, String]) -> Unit] = Map([])

///|
let next_req : Ref[Int] = { val: 1, }

///|
/// The page's answer to one `read_text`.
///
/// A page forwards its own export to this. Unknown ids are ignored rather than
/// treated as an error: a read whose continuation has already been taken is a
/// double answer, and running the continuation twice would import the same
/// file twice.
pub fn on_file_text(req_id : Int, ok : Bool, text : String) -> Unit {
  match pending.get(req_id) {
    Some(then) => {
      pending.remove(req_id)
      then(if ok { Ok(text) } else { Err(text) })
    }
    None => ()
  }
}

///|
/// The browser, as a `FileService`.
///
/// Stateless — every method goes straight to the page — so holding two of
/// these is the same as holding one.
pub struct BrowserFiles {}

///|
pub fn browser_files() -> BrowserFiles {
  BrowserFiles::{ }
}

///|
pub impl @files.FileService for BrowserFiles with fn save_text(
  _self,
  name~,
  mime~,
  text,
) {
  tfiles_save_text(name, mime, text)
}

///|
pub impl @files.FileService for BrowserFiles with fn read_text(
  _self,
  id~,
  then~,
) {
  let req = next_req.val
  next_req.val = req + 1
  pending[req] = then
  tfiles_read_text(id, req)
}
