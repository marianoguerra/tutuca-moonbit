// Which object-valued steps an `e.<path>` may traverse — under the SAFE
// profile.
//
// **The profile question comes first, and its default changed.** An
// `EventPathProfile` says which rule governs a path: `Open` lets any path
// resolve and is the default everywhere a view is the AUTHOR'S OWN code — a
// native component's views compile through `viewgen`, which reports an off-list
// step as a lint HINT (`lint`'s EventPathUnsafeStep finding), not an error.
// Someone writing their own template could have written the same read in JS,
// so holding their paths to this list is ceremony, not safety. `Safe` holds
// every traversed step to the list below; it is what a host that compiles
// guest-supplied views runs (`dyncomp/policy` carries it on `Policy`, refuses
// an off-list path at registration, and hands the same profile to the app so
// the runtime resolver enforces it too).
//
// This file answers the SAFE half only, and that makes it the one list in the
// repository that cannot be generated, which in turn makes it the only one
// that can grow by accident. Every other allow-list here is fetched from a
// specification at a pinned commit — the sanitizer baseline, the DOM property
// table beside this file — because a specification says what EXISTS. None of
// them says what a guest's view template should be allowed to reach, which is
// a judgment about authority, so this one is argued instead.
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
/// Which rule governs an `e.<path>`.
///
/// `Open` is the default for native component authoring: the views are the
/// author's own code, so any path resolves and an off-list step is reported as
/// a lint hint rather than refused. `Safe` is what a host that compiles
/// guest-supplied views runs — every traversed step is held to
/// `event_object_steps`, at registration by `dyncomp/policy` and again at run
/// time by the resolver that carries this profile.
pub(all) enum EventPathProfile {
  /// Any path may resolve; the list below only ADVISES.
  Open
  /// Every traversed step must be on the allowlist, with `dataset`/`detail`
  /// free below it. Guest-supplied views are held to this.
  Safe
} derive(Eq, @debug.Debug)

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
/// Layer 1's computed accessors, by name.
///
/// These are NOT properties of anything. A DOM `Event` has no `value` at all:
/// `value` is computed by the glue — the checked state on a checkbox, the
/// picked file's metadata on a file input, the `detail` on a `CustomEvent`, the
/// input's string otherwise — and `isSend` is `key == "Enter"`. So no
/// specification can answer for them and no generated table carries them.
///
/// Here, in the leaf package, because more than one place needs the same list
/// and had a copy of it: the runtime resolver (`render/dom_event.mbt`) asks
/// whether a name shadows the path walk, and the generator
/// (`viewgen/surface.mbt`) asks both what it decodes to and whether a bare name
/// is an event read. Two copies of one vocabulary is two ways to disagree about
/// `e.value`.
pub let event_accessors : Array[String] = [
  "value", "valueAsInt", "valueAsFloat", "key", "keyCode", "isAlt", "isShift", "isCtrl",
  "isCmd", "isUpKey", "isDownKey", "isSend", "isCancel", "isTabKey", "dragInfo",
  "dragKey", "dragValue", "dragType",
]

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
/// Whether `e.<segments>` is permitted under this profile.
///
/// `Open` permits everything — the caller asked the wrong question, but
/// cheaply. `Safe` is `check_event_path`.
pub fn EventPathProfile::allows(
  self : EventPathProfile,
  segments : Array[String],
) -> EventPathVerdict {
  match self {
    Open => PathOk
    Safe => check_event_path(segments)
  }
}

///|
/// Whether every traversed step of `e.<segments>` is allowed — the SAFE
/// profile's walk.
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
