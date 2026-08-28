// Serializing a mounted DOM the way a person reads it.
//
// One line, because the stripping itself belongs beside the harness that
// produced the DOM: a card's report and a replayed recording want the same
// thing for the same reason — a component id comes from a process-global
// counter, so the same tree rendered twice differs in every `data-cid`.
// Two copies of the predicate list is one copy plus a stamp that stops being
// stripped the day a new one is added to the other.

///|
pub fn clean_html(node : @memdom.MemNode) -> String {
  @harness.clean_html(node)
}
