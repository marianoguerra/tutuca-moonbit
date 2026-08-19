// Which object-valued steps an `e.<path>` may traverse.
//
// **This is the one list in the repository that cannot be generated**, and that
// makes it the only one that can grow by accident. Every other allow-list here
// is fetched from a specification at a pinned commit — the sanitizer baseline,
// the DOM property table beside this file — because a specification says what
// EXISTS. None of them says what a view template should be allowed to reach,
// which is a judgment about authority, so this one is argued instead.
//
// It is the second half of a pair, and the two answer different questions.
// `dom_props_gen.mbt` answers *does this interface have this property, and what
// is its type* — fetched. This answers *may a path go through it* — argued.
// Neither may answer the other's question.
//
// THE RULE THIS EXISTS FOR: **a permitted root is not a permitted path.** An
// earlier draft of the design allowlisted the first segment and let the rest
// run free. That does not hold, and one line shows why:
//
//     e.target.ownerDocument.defaultView.localStorage.length
//
// `target` is a permitted root, every step after it is an ordinary property
// read, and the leaf is a number — so it converts cleanly, and a view template
// has just read the window. Rule 1 ("an `e.` path always produces a `Value`")
// does not stop it, because the leaf IS representable. Every step is checked,
// or the list does nothing.
//
// A view is data the host compiles, including a view a dyncomp guest supplied
// (`dyncomp/DESIGN.md`, principle 2), so anything reachable here is ambient
// authority no guest declared — which is what principle 4 of that document
// forbids. See `dyncomp/SECURITY.md` §9.

///|
/// The object-valued steps a path may traverse.
///
/// Six, and each one is here for a stated reason. Adding a seventh is the whole
/// hole, which is why `event_paths_test.mbt` asserts this list EXACTLY: growing
/// it is a deliberate edit to an assertion, in a diff that says so.
///
/// - `target`, `currentTarget`, `relatedTarget` — the elements an event names.
///   A handler that wants the clicked element's `value`, `id` or `dataset` has
///   to go through one of them, and there is no other way to say it. What they
///   reach is bounded by the two rules below: the DOM property table has no
///   `Window` and no `Document`, and `ownerDocument` is not on this list.
/// - `detail` — a `CustomEvent`'s payload, which the application itself built.
///   Nothing of the host's is in there.
/// - `dataset` — `data-` attributes, which the author wrote into the template.
///   Same argument.
/// - `dataTransfer` — the drop's own declared types and files. A drag is a
///   thing the user did, and its payload is what they dropped.
///
/// What is deliberately NOT here, because a reader will ask:
/// `ownerDocument`, `parentNode`, `parentElement`, `children`, `form`,
/// `view` and `window`. Each leads out of the event and into the page, and
/// `e.target.form.action` is as much a read of the host as the `localStorage`
/// line above.
pub let event_object_steps : Array[String] = [
  "currentTarget", "dataTransfer", "dataset", "detail", "relatedTarget", "target",
]

///|
/// The steps below which traversal is FREE.
///
/// Two, and the reason they are different in kind from the four above is the
/// point of having a second list at all. `detail` is an object the application
/// constructed and `dataset` is a `DOMStringMap` of strings the author wrote —
/// once a step reaches AUTHOR DATA there is nothing left to escalate into, so
/// checking each further step would be ceremony rather than a boundary.
///
/// The allowlist governs exactly the boundary between host objects and data,
/// and no further. That is also what keeps the language open: `e.detail.a.b.c`
/// works with no framework release.
pub let event_data_terminals : Array[String] = ["dataset", "detail"]

///|
/// What a path walk answers.
pub(all) enum EventPathVerdict {
  PathOk
  /// A step that is not on the allowlist, and where in the path it sits.
  ///
  /// The INDEX matters to the message: `e.target.ownerDocument.defaultView` is
  /// refused at `ownerDocument`, and saying which step is what tells an author
  /// the difference between "this path is wrong" and "this path is not allowed
  /// to go that far".
  BadStep(step~ : String, index~ : Int)
} derive(Eq, @debug.Debug)

///|
/// Whether every traversed step of `e.<segments>` is allowed.
///
/// The LAST segment is the leaf and is not a traversal — it is converted to a
/// `Value` and the path ends. Everything before it goes through a host object,
/// and every one of those is checked. So `e.deltaY` traverses nothing and is
/// always allowed, and `e.target` alone is allowed here too — it produces
/// `Null`, because an `Element` is not representable, and that is rule 1's
/// answer rather than this list's.
///
/// Once a traversed step is an author-data terminal, the rest is free.
pub fn check_event_path(segments : Array[String]) -> EventPathVerdict {
  let mut free = false
  for i in 0..<(segments.length() - 1) {
    if free {
      break
    }
    let step = segments[i]
    if !event_object_steps.contains(step) {
      return BadStep(step~, index=i)
    }
    if event_data_terminals.contains(step) {
      free = true
    }
  }
  PathOk
}
