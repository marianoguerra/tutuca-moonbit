///|
/// Rejected, and why.
///
/// REJECTED is the card being turned away whole; a REFUSAL is one declaration
/// this backend did not lower, and is not an error at all — the module still
/// exists. Keeping the two words apart is the whole of what a host does next.
pub fn GenError::message(self : GenError) -> String {
  match self {
    BadCard(why) => "this is not a card: \{why}"
    BadScript(lines) => "this card does not check:\n  " + lines.join("\n  ")
    BadModule(lines) =>
      "the generated module did not compile — this is a tgc/emit bug rather " +
      "than a problem with the card, because a card that checks cannot " +
      "produce a module that does not:\n  " +
      lines.join("\n  ")
  }
}

///|
pub impl Show for GenError with fn output(self, logger) {
  logger.write_string(self.message())
}
