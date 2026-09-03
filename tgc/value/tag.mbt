///|
pub fn TVal::tag(self : TVal) -> @abi.Tag {
  match self {
    TNull => TagNull
    TBool(_) => TagBool
    TNum(_) => TagNum
    TInt(_) => TagInt
    TStr(_) => TagStr
    TBin(_) => TagBin
    TInstant(..) => TagInstant
    TList(_) => TagList
    TMap(_) => TagMap
    TFunc => TagFunc
    TComp(_) => TagComp
    TExt(..) => TagExt
  }
}

///|
/// `Show` for a value is its JSON, which is the spelling a person reading a
/// test failure or a log already knows how to read. A value with no JSON — a
/// function — says so rather than aborting a diagnostic.
pub impl Show for TVal with fn output(self, logger) {
  let text = to_json(self).stringify() catch { _ => "<\{kind_word(self)}>" }
  logger.write_string(text)
}

///|
pub impl Show for CompRef with fn output(self, logger) {
  logger.write_string(
    "\{self.module_}#\{self.component}(\{self.state.length()} bytes)",
  )
}
