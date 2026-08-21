// Runtime warning hook for non-fatal problems found during evaluation.

///|
/// Where runtime warnings go. Defaults to println; a host can redirect it —
/// e.g. into an error
/// pane or the browser console — without threading a context through eval.
pub let warn_hook : Ref[(String) -> Unit] = Ref(msg => println(msg))

///|
/// Report a runtime warning through `warn_hook`.
pub fn warn(msg : String) -> Unit {
  (warn_hook.val)(msg)
}

// A contract a transition did not keep. Three functions rather than one with a
// kind, because both callers are code GENERATORS as much as they are code: the
// interpreter picks one by matching, and the MoonBit backend writes the name
// into a file. A name is the one thing that survives being written as text.
//
// They report rather than raise for the reason the hook exists at all. "The
// transition did not happen" is already the framework's answer to everything —
// `Unchanged`, `None`, the same state back — and it is INVISIBLE: a state that
// did not move looks exactly like a state that had nothing to move. A contract
// is the author saying which of those silences is a bug, and this is where that
// distinction goes so a host can see it.
//
// Two channels, and exactly one of them fires. A host that installed a refusal
// listener gets the RECORD, with the rule's own sentence and the state that was
// rejected; a host that installed nothing gets the line `warn` has always
// printed, now carrying the sentence too. Reporting both would make switching
// the channel on cost a duplicate of every message.

///|
/// The half a `format` fills in: the sentence the rule produced about THIS
/// failure, and the state it was asked about.
///
/// Optional because a rule without a `format` is the common case and because
/// the two backends emitting these calls should not have to write `""` and
/// `Null` to say "nothing to add".
fn contract_failed(
  code : RefusalCode,
  handler : String,
  pred : String,
  sentence : String,
  state : Value,
  line : String,
) -> Unit {
  if refusing() {
    refuse({
      code,
      asked: handler,
      rule: pred,
      sentence,
      state,
      path: Path::new(),
    })
  } else if sentence == "" {
    warn(line)
  } else {
    warn(line + ": " + sentence)
  }
}

///|
/// A precondition did not hold, so the handler declined before touching
/// anything. `state` is the state as it ARRIVED — nothing has moved yet.
pub fn precondition_failed(
  handler~ : String,
  pred~ : String,
  sentence? : String = "",
  state? : Value = Null,
) -> Unit {
  contract_failed(
    Precondition,
    handler,
    pred,
    sentence,
    state,
    "contract: `\{handler}` declined — its precondition `\{pred}` does not hold",
  )
}

///|
/// A postcondition did not hold after the body ran, so the transition was
/// abandoned whole — state and effects together. `state` is the SUCCESSOR that
/// was thrown away, which is the one worth looking at.
pub fn postcondition_failed(
  handler~ : String,
  pred~ : String,
  sentence? : String = "",
  state? : Value = Null,
) -> Unit {
  contract_failed(
    Postcondition,
    handler,
    pred,
    sentence,
    state,
    "contract: `\{handler}` was abandoned — its postcondition `\{pred}` does not hold after it",
  )
}

///|
/// An invariant did not hold after the body ran. Same abandonment, different
/// reason: the rule is the component's rather than this handler's.
pub fn invariant_failed(
  handler~ : String,
  pred~ : String,
  sentence? : String = "",
  state? : Value = Null,
) -> Unit {
  contract_failed(
    Invariant,
    handler,
    pred,
    sentence,
    state,
    "contract: `\{handler}` was abandoned — it broke the invariant `\{pred}`",
  )
}
