// Which notation a source is written in.
//
// This lives here rather than at the seam that asks, because the question is
// about the notation and the notation is this package's subject. It also has
// to be asked of TEXT rather than of a filename: a page compiles a card a
// model has just written, and there is no path to look at.

///|
/// Whether a source is a `.tutu` file.
///
/// Decided by the first line that says anything: a `.tutu` file opens with one
/// of the five section words at column zero, and an `.html` card opens with
/// markup. Reading the whole body for markup instead would misread a `.tutu`
/// card that MENTIONS `<script>` — in a doc comment, in a `@str{}`, in a view
/// teaching HTML, in a scene's expected text — as the thing it is describing.
pub fn is_tutu_source(source : String) -> Bool {
  for line in source.split("\n") {
    let text = line.to_owned()
    let trimmed = text.trim(chars=" \t\r").to_owned()
    if trimmed == "" || trimmed.has_prefix("//") {
      continue
    }
    // a section opens at column zero; anything indented is inside something,
    // and a `.tutu` file cannot open inside something
    if text != trimmed {
      return false
    }
    for word in ["spec", "logic", "view", "fixtures", "tests"] {
      if trimmed == word + ":" || trimmed.has_prefix(word + ": ") {
        return true
      }
    }
    return false
  }
  false
}
