///| Saving a file to wherever the viewer keeps files, and reading one back.
///
/// Two directions, one trait, and they are not symmetric — which is the whole
/// reason this is a seam rather than two FFI calls at the call site.
///
/// Saving is synchronous and one-way: a page hands the browser some text and a
/// name, the browser does the rest, and there is nothing to wait for and
/// nothing to fail in a way the caller could act on.
///
/// Reading is neither. The viewer picks the file, the read is asynchronous, and
/// on wasm-gc a closure cannot cross into JS — so the answer comes back through
/// a continuation parked on THIS side and resumed by the host. That is why
/// `read_text` takes a `then` instead of returning: there is no value to return
/// yet, and pretending otherwise would push the same wait into every caller.

///|
/// Somewhere to put a file, and somewhere to get one from.
///
/// `pub(open)` because the interesting implementations are not in this package:
/// `files/wasm` talks to a browser, `MemFiles` answers from a table, and a host
/// with its own idea of where files live should be able to say so.
pub(open) trait FileService {
  /// Hand `text` to the viewer as a file called `name`.
  ///
  /// `mime` is what the file claims to be — `application/json`, `text/plain`.
  /// It is a hint to whatever opens the file afterwards and nothing here
  /// depends on it, but a browser download names its own default from it, so
  /// getting it wrong is visible to a person.
  fn save_text(Self, name~ : String, mime~ : String, text : String) -> Unit

  /// Read the file `id` names, and hand the text to `then`.
  ///
  /// `id` is the integer a picked or dropped file's descriptor carries — the
  /// `File` itself is a browser object and never becomes a `Value`, so the
  /// backend keeps the last pick and a caller names it again by number.
  ///
  /// `then` is called exactly once, with `Err` carrying a sentence fit to show
  /// a person: an id nothing answers to, a read the browser refused. A caller
  /// that cannot proceed without the text shows the sentence and stops.
  fn read_text(Self, id~ : Int, then~ : (Result[String, String]) -> Unit) -> Unit
}

///|
/// The name a saved file gets when the caller has nothing better.
///
/// Here rather than at the call site because two callers that disagree about
/// the extension produce two kinds of file for one kind of content, and the
/// CLI reads `.trace.jsonl` (`tutuca trace <file>`).
pub fn trace_filename(stem : String) -> String {
  let base = if stem == "" { "recording" } else { stem }
  base + ".trace.jsonl"
}

///|
/// What a trace file claims to be.
///
/// `application/jsonl` is not registered, and a browser handed an unknown type
/// may refuse to preview it; `application/json` is wrong about the format but
/// right about the bytes, and JSONL is not JSON. `text/plain` is the honest
/// answer for a line-oriented text file and the one every tool can open.
pub const TRACE_MIME : String = "text/plain"
