// The spellings that still answer but are no longer the spelling.
//
// ONE table for the whole system, split by the KIND of name a spelling belongs
// to. It started as the builtins' own (`value_builtin.mbt`), for the reason
// stated there — a retirement worded differently at each of the four sites that
// report an unknown name is a retirement an author has to learn four times —
// and the reason generalises the moment a second family retires anything: a
// keyword, a derived answer name. Those live above `core`, and none of them may
// import each other, so the table they share has to be here.
//
// A kind rather than one flat namespace because the families do not share a
// namespace: `set` is a retired nothing as a builtin and could be a retired
// keyword, and a lookup that could not say which it meant would answer the
// wrong advice.

///|
/// Which family a retired spelling belongs to.
pub(all) enum RetiredKind {
  /// A name in a value position — a builtin the vocabulary no longer spells
  /// that way.
  BuiltinName
  /// A word of the block language: a declaration kind, an effect, a leg.
  KeywordName
  /// A derived name — the answer messages a `walk` raises for an intent.
  AnswerName
} derive(Debug, Eq)

///|
/// The retired builtins, each with the spelling that replaced it.
let retired_builtins : Map[String, String] = {
  "equals?": "`is` says this — write `a is b`",
  "falsy?": "`not` says this — write `not (truthy? x)`",
}

///|
/// The retired keywords. Empty until a keyword family is renamed.
let retired_keywords : Map[String, String] = Map([])

///|
/// The retired derived answer names. Empty until one is renamed.
let retired_answers : Map[String, String] = Map([])

///|
/// For a name that still answers but is no longer the spelling, what to write
/// instead. `None` for every name in current use.
pub fn retired(kind : RetiredKind, name : String) -> String? {
  match kind {
    BuiltinName => retired_builtins.get(name)
    KeywordName => retired_keywords.get(name)
    AnswerName => retired_answers.get(name)
  }
}
