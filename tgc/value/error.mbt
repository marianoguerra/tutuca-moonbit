///|
/// One sentence, and a position. Both codecs are read by machines that WROTE
/// the input, so the message is written to be actionable by whatever produced
/// the bytes rather than only by a person reading a log.
pub fn CodecError::message(self : CodecError) -> String {
  match self {
    NotEncodable(kind~, why~, at~) =>
      "cannot encode a \{kind}\{where_(at)}: \{why}"
    Truncated(want~, at~) => "input ended at byte \{at}, inside \{want}"
    BadCbor(why~, at~) => "not this CBOR profile at byte \{at}: \{why}"
    Trailing(at~) =>
      "a complete value ended at byte \{at} and the input did not; " +
      "a decoder that stops early has read a different message from the one that was sent"
    DuplicateKey(key~, at~) =>
      "the key \{key} appears twice\{where_(at)}; " +
      "which one was meant is a guess, so neither is taken"
  }
}

///|
/// The empty position is the document root, and " at " nothing reads worse than
/// no position at all.
fn where_(at : String) -> String {
  if at == "" {
    ""
  } else {
    " at \{at}"
  }
}

///|
pub impl Show for CodecError with fn output(self, logger) {
  logger.write_string(self.message())
}
