// Runtime warning hook: the port's equivalent of the JS console.warn calls
// sprinkled through the value runtime (mk404Handler, unsupported wraps).

///|
/// Where runtime warnings go. Defaults to println (the closest portable
/// analogue of JS console.warn); a host can redirect it — e.g. into an error
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

///|
/// A precondition did not hold, so the handler declined before touching
/// anything.
pub fn precondition_failed(handler~ : String, pred~ : String) -> Unit {
  warn(
    "contract: `\{handler}` declined — its precondition `\{pred}` does not hold",
  )
}

///|
/// A postcondition did not hold after the body ran, so the transition was
/// abandoned whole — state and effects together.
pub fn postcondition_failed(handler~ : String, pred~ : String) -> Unit {
  warn(
    "contract: `\{handler}` was abandoned — its postcondition `\{pred}` does not hold after it",
  )
}

///|
/// An invariant did not hold after the body ran. Same abandonment, different
/// reason: the rule is the component's rather than this handler's.
pub fn invariant_failed(handler~ : String, pred~ : String) -> Unit {
  warn(
    "contract: `\{handler}` was abandoned — it broke the invariant `\{pred}`",
  )
}
