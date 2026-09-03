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
/// The retired keywords, each with the spelling that replaced it.
let retired_keywords : Map[String, String] = {
  "stop": "`drop` says this — the walk ends and the answer is dropped, which is what `stop` never said out loud",
  "sendReply": "`reply` says this — one word answers whoever asked, and the bucket decides who that is",
}

///|
/// The retired answer SUFFIXES, each with the suffix that replaced it.
///
/// A suffix and not a whole name, because a derived answer name is the
/// intent's own name plus one of three words — there is no fixed set of them
/// to enumerate. `saveDraftError` and `reloadError` are the same retirement.
let retired_answer_suffixes : Map[String, String] = {
  "Error": "the outcome is `Failed` — write `<name>Failed`",
}

///|
/// For a name that still answers but is no longer the spelling, what to write
/// instead. `None` for every name in current use.
///
/// `AnswerName` matches on the SUFFIX: the name is an intent's own plus one of
/// three words, so there is nothing to enumerate but the words.
pub fn retired(kind : RetiredKind, name : String) -> String? {
  match kind {
    BuiltinName => retired_builtins.get(name)
    KeywordName => retired_keywords.get(name)
    AnswerName => {
      // The longest matching suffix, so a longer retirement can never be
      // shadowed by a shorter one that happens to end it.
      let mut best : (String, String)? = None
      for suffix, advice in retired_answer_suffixes {
        if name.length() <= suffix.length() || !name.has_suffix(suffix) {
          continue
        }
        if best is Some((s, _)) && s.length() >= suffix.length() {
          continue
        }
        best = Some((suffix, advice))
      }
      best.map(p => p.1)
    }
  }
}
