// The event-path lint: one rule over `@on` handler arguments.
//
// It walks the events a parse registered (`px.events` — the same table
// `viewgen`'s surface pass reads) and reports every `e.<path>` argument whose
// traversal leaves `@eventpath`'s allowlist, as an EventPathUnsafeStep HINT.
// Under the open profile — the default for an author's own views — the path
// still resolves; the hint is advice for a view that might be compiled by a
// host holding guest-supplied views to the safe profile, where this same step
// is a registration REFUSAL. One vocabulary, one wording, two audiences.
//
// This is deliberately NOT part of `check_collected`: the collector sees
// attribute parses, and events are not among them — they register on the
// ParseContext itself, so the caller hands them over beside it (the CLI does;
// the dyncomp host does NOT, because there the same walk is a refusal under
// the policy, in `dyncomp/policy`, and doubling it here would print both).

///|
/// Every `e.<path>` handler argument these events carry that steps off the
/// allowlist, oldest first.
pub fn check_event_paths(events : Array[@anode.NodeEvents]) -> Array[Finding] {
  let out : Array[Finding] = []
  for ev in events {
    for h in ev.handlers {
      let site = "@on." + h.name
      for arg in h.handler.args {
        guard arg is EEventPath(segments~, ..) else { continue }
        guard @eventpath.EventPathProfile::allows(Safe, segments)
          is BadStep(step~, index~) else {
          continue
        }
        out.push({
          code: EventPathUnsafeStep,
          level: Hint,
          info: [
            ("site", site),
            ("path", "e." + segments.join(".")),
            ("step", step),
            ("index", "\{index}"),
          ],
          location: None,
          suggestion: None,
        })
      }
    }
  }
  out
}
