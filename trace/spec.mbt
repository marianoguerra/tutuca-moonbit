// The data types a trace is made of, plus the `declare` stubs. The
// implementations live in place.mbt, jsonl.mbt, recorder.mbt and ops.mbt.
//
//   a running app --Recorder--> Trace --to_jsonl--> a file
//   a file --from_jsonl--> Trace --prefix/rebase/relocate--> a shorter Trace
//   a Trace --@replay.mount--> the same app, doing the same thing
//
// READONLY by convention: concrete public data types plus `declare` stubs for
// every function. This file and the `*_test.mbt` suites define the contract.

///|
/// The format's version, written into every file's first line.
///
/// A reader that does not know a version REFUSES rather than guessing, because
/// the failure it would otherwise produce is a replay that diverges for a
/// reason nobody can find.
pub const VERSION : Int = 1

///|
/// A position in the state tree, as data.
///
/// The only form of a path that survives being written down. A `DispatchPath`
/// names render-time producers by component id — a counter that restarts every
/// process, so persisting one is persisting a number that will mean something
/// else tomorrow — and `Step`'s frame-only variants carry `Val` expressions and
/// `Value::Fn` closures, which JSON has no shape for.
///
/// So a `Place` is the TRANSACTION path: `DispatchPath::to_transaction_path()`
/// with its keys pinned, which is a plain sequence of fields and keys. For a
/// message that loses nothing that matters — `to_transaction_path` has already
/// teleported every dynamic marker to where the data actually lives, and that
/// teleported path is exactly what the message mutates.
pub(all) struct Place(Array[@tutuca.StepKey]) derive(Eq, Debug)

///|
/// What a dispatch was.
///
/// `Send` and `Intent` are the two things a component can raise; the other
/// three are the runtime and the host being visible. They are one enum rather
/// than two because a trace is read in one order, and the order is the whole
/// point: an answer that arrived between two clicks belongs between them.
pub(all) enum Op {
  Send(name~ : String, args~ : Array[@tutuca.Value])
  Intent(
    name~ : String,
    args~ : Array[@tutuca.Value],
    opts~ : @tutuca.IntentOpts
  )
  /// The intent reached the host: the lexical leg is asking handler `nth`.
  ///
  /// Derived — a rerun produces it again — but it is what makes the boundary
  /// legible, and it is what `relocate` reads to know an intent left the
  /// subtree it is cutting to.
  Offered(name~ : String, args~ : Array[@tutuca.Value], nth~ : Int)
  /// The host answered. An INPUT: nothing inside the tree can recompute it,
  /// and the same question asked twice may get two different answers.
  Answer(nth~ : Int, answer~ : @tutuca.IntentAnswer)
  /// The runtime declined. Never an input — a rerun raises its own — but a
  /// recording of a bug that ends in a refusal has to carry the refusal, or it
  /// is a recording of nothing happening.
  Refused(code~ : String, asked~ : String, rule~ : String, sentence~ : String)
} derive(Eq, Debug)

///|
/// One thing that happened.
pub(all) struct Event {
  /// Position in the recording. Unique and increasing; a reader orders by it.
  seq : Int
  /// Everything pushed between two drains shares a turn. One DOM event with two
  /// handlers is one turn, and a rerun that ignored this would settle twice
  /// where the recording settled once — and re-render twice.
  turn : Int
  /// The intent walk this belongs to, 0 for none. Shared by the intent, every
  /// hop of its route, every offer to a host, and the answer.
  walk : Int
  /// The `seq` of the event whose handler caused this one, 0 for none. What
  /// makes a cascade of twelve sends from one click readable as one thing.
  parent : Int
  at : Place
  op : Op
  /// Whether a rerun FEEDS this event.
  ///
  /// The line between "what happened to the app" and "what the app did about
  /// it". A derived event is kept to show, to check a rerun against, and to
  /// promote when relocating — and skipped by the driver, which produces it
  /// again.
  input : Bool
  /// The leaf after the handler ran, untagged, when the recorder kept it.
  /// `None` for a no-op, and `None` throughout when the recorder was told not
  /// to keep them. For the viewer and for saying WHERE a rerun diverged; a
  /// rerun never reads it.
  after : Json?
} derive(Eq, Debug)

///|
/// Where the initial state came from, when the recorder knew.
///
/// Never load-bearing — `root` is the state, and a trace with an empty origin
/// replays exactly as well. What it buys is a trace somebody can act on: which
/// module to open, and whether the component still has the shape it had.
pub(all) struct Origin {
  module_ : String
  component : String
  example : String
  view : String
  /// `SchemaInfo::shape_fingerprint()` of the root component when the recording
  /// was made. This is what turns "it replays wrong" — which could be anything
  /// — into "the component changed", which is one thing.
  fingerprint : String
} derive(Eq, Debug)

///|
/// A recording: where it started, and everything that happened after.
pub(all) struct Trace {
  version : Int
  origin : Origin
  /// The initial root as a tagged document (`Value::to_component_json`), which
  /// is the only projection that can be read back into instances. Rebuilt
  /// through a `@tutuca.ComponentSource`; a `ComponentStack` is one.
  root : Json
  /// What was cut away to get here, outermost first. Empty for a recording as
  /// it was taken. Provenance, so a reader of a relocated trace knows the paths
  /// were rewritten and against what.
  relocated_from : Array[Place]
  /// Whether the derived events have been dropped.
  ///
  /// A fact the trace carries rather than one a reader infers, because the two
  /// things it would have to tell apart look identical: a recording that was
  /// compacted, and one where nothing derived ever happened. Only the first is
  /// missing something, and only the first should be warned about.
  compacted : Bool
  events : Array[Event]
} derive(Eq, Debug)

///|
/// Anything that makes a trace file unusable.
///
/// Every case carries a line number, because the file this reads is routinely
/// a hundred thousand lines and "expected an object" with no position in it is
/// a sentence nobody can act on.
pub suberror TraceError {
  /// The file is empty, or has fewer than the two header lines.
  NoHeader(String)
  /// A line is not JSON.
  NotJson(line~ : Int, why~ : String)
  /// The first line does not name this format.
  NotATrace(line~ : Int)
  /// The first line names a version this reader does not know.
  BadVersion(line~ : Int, got~ : Int, want~ : Int)
  /// The second line is not the root snapshot.
  NoRoot(line~ : Int)
  /// A header line appeared after the events began.
  LateHeader(line~ : Int)
  /// An event line names no verb this reader knows.
  NoOp(line~ : Int, keys~ : Array[String])
  /// An event line is missing a key its verb cannot be read without, or has one
  /// with the wrong shape.
  BadField(line~ : Int, key~ : String, want~ : String)
  /// An address that does not read as one.
  BadPlace(line~ : Int, why~ : String)
}

///|
/// The one-line message, in the shape the rest of the repo's errors use.
declare pub fn TraceError::message(self : TraceError) -> String

// --- Place ------------------------------------------------------------------

///|
/// The transaction path as an address. `pin_keys` first if the caller wants a
/// field-resolved key frozen; this reports what the path already says.
declare pub fn Place::of_path(p : @tutuca.Path) -> Place

///|
/// The addressing steps, ready for `@tutuca.DispatchPath::of_steps`.
declare pub fn Place::to_steps(self : Place) -> Array[@tutuca.Step]

///|
/// The path a dispatch is aimed at.
declare pub fn Place::to_path(self : Place) -> @tutuca.Path

///|
/// `todos.items[1].title` — the repo's one spelling of an address, shared with
/// a printed `Path` and an activity log line.
declare pub fn Place::label(self : Place) -> String

///|
/// How many steps deep.
declare pub fn Place::depth(self : Place) -> Int

///|
/// Whether this address is at or below `prefix`. The test `relocate` cuts on.
declare pub fn Place::starts_with(self : Place, prefix : Place) -> Bool

///|
/// The same address seen from `prefix`, or `None` when it is not below it.
/// Relocating a trace is this, applied to every event that survives.
declare pub fn Place::strip_prefix(self : Place, prefix : Place) -> Place?

///|
/// The same address seen from ABOVE `prefix` — `strip_prefix` undone.
///
/// What a rerun into a live tree needs and a rerun into its own app does not.
/// A recording cut to a story addresses `.rows[1]`; the gallery the story is
/// mounted in addresses that same component `.s3.rows[1]`, so every event has
/// to be re-prefixed on its way back in. `relocate` wrote the addresses down
/// one way and this reads them the other, which is why the two live together:
/// if they ever disagree, a replay aims at the wrong component and the symptom
/// is a divergence with nothing wrong at either end.
declare pub fn Place::under(self : Place, prefix : Place) -> Place

///|
declare pub fn Place::to_json(self : Place) -> Json

///|
/// `None` when any step does not read as one — the caller knows which line it
/// came from and says so.
declare pub fn Place::from_json(j : Json) -> Place?

///|
/// Read a dotted place — `.rows[0].label`, `.byId['a']` — the spelling a scene
/// already uses. The CLI's `--at` takes one of these.
declare pub fn parse_place(src : String) -> Place raise TraceError

// --- Trace ------------------------------------------------------------------

///|
/// An empty recording of a tree in the state `root` describes.
declare pub fn Trace::new(root~ : Json, origin? : Origin) -> Trace

///|
/// Nothing known about where the state came from.
declare pub fn Origin::empty() -> Origin

///|
/// How many events a rerun would FEED, as opposed to hold.
declare pub fn Trace::input_count(self : Trace) -> Int

///|
/// The turns, in order, with the events in each. What a viewer groups rows by
/// and what a rerun steps through.
declare pub fn Trace::turns(self : Trace) -> Array[Array[Event]]

///|
/// Every position any event touched, deduplicated, in first-seen order.
///
/// What a relocation picker offers: the places this recording is actually
/// ABOUT, rather than every component that happens to exist.
declare pub fn Trace::places(self : Trace) -> Array[Place]

// --- the file format --------------------------------------------------------

///|
/// The recording as JSONL: two header lines, then one line per event.
///
/// One line per event because a recording of a real session is long and is
/// almost entirely a list of them — so a recorder can append rather than
/// buffer, and every shortening operation is a line operation. The root is its
/// own line rather than a field of the header because it is the one thing in
/// the file that can be megabytes.
declare pub fn Trace::to_jsonl(self : Trace) -> String

///|
/// A file back.
declare pub fn from_jsonl(text : String) -> Trace raise TraceError

///|
/// The header lines and the event lines, unparsed.
///
/// What `trim` uses, and the reason the CLI can shorten a trace it does not
/// understand: slicing lines never reads a `Value`, so an event kind written by
/// a newer runtime passes through instead of failing.
declare pub fn split_lines(
  text : String,
) -> (Array[String], Array[String]) raise TraceError

///|
/// The whole recording as ONE JSON value, events and all.
///
/// Beside the line format rather than instead of it: a `moon test` snapshot and
/// a clipboard both want one value, and neither wants to be appended to.
declare pub fn Trace::to_json(self : Trace) -> Json

///|
declare pub fn Trace::from_json(j : Json) -> Trace raise TraceError

///|
declare pub fn Event::to_json(self : Event) -> Json

///|
declare pub fn Event::from_json(j : Json, line~ : Int) -> Event raise TraceError

// --- the recorders ----------------------------------------------------------

///|
/// Keeps everything, until somebody takes it.
///
/// With a `sink` it writes JSONL lines as they happen and holds no events, so a
/// long session costs a constant amount of memory. Without one it buffers,
/// which is what a test and a devtool panel want.
pub struct TraceRecorder {
  priv origin : Origin
  /// Mutable because a `RingRecorder` rebases onto a fresh snapshot when it
  /// drops a turn — which is what keeps what it holds a complete recording
  /// rather than a suffix of one.
  priv mut root : Json
  priv events : Array[Event]
  priv sink : ((String) -> Unit)?
  priv keep_after : Bool
  priv mut header_written : Bool
  /// The refusal channel's unsubscribe, when one was installed. Held so
  /// `stop_watching_refusals` can be called by a caller that did not keep the
  /// closure `watch_refusals` handed back — which a devtool panel, whose start
  /// and stop are two different buttons, generally has not.
  priv mut off : (() -> Unit)?
}

///|
/// `keep_after` records the state each handler produced — worth having in a
/// devtool and not worth the size in a long session, so it is off by default.
declare pub fn TraceRecorder::new(
  root~ : Json,
  origin? : Origin,
  sink? : (String) -> Unit,
  keep_after? : Bool,
) -> TraceRecorder

///|
/// The recording so far. Recording continues; this is a snapshot, not a stop.
declare pub fn TraceRecorder::take(self : TraceRecorder) -> Trace

///|
/// Also record refusals, through the global notice channel. Returns the
/// unsubscribe, which the caller must run when it removes the recorder —
/// otherwise the channel keeps a dead recorder alive.
declare pub fn TraceRecorder::watch_refusals(self : TraceRecorder) -> () -> Unit

///|
/// Detach the refusal channel, if it was attached. Idempotent, so a panel whose
/// stop button is pressed twice does not have to remember.
declare pub fn TraceRecorder::stop_watching_refusals(
  self : TraceRecorder,
) -> Unit

///|
/// The last `turns` turns and nothing older.
///
/// A flight recorder: in a long session the recording you want is the one just
/// before it broke, and keeping the whole thing to get the end of it is the
/// wrong trade. When it drops a turn it rebases onto a snapshot taken at that
/// moment, so what it holds is always a COMPLETE recording and never a suffix
/// of one — a suffix would start from a state nothing describes.
pub struct RingRecorder {
  priv inner : TraceRecorder
  priv turns : Int
  priv snapshot : () -> Json
  priv mut cur_turn : Int
}

///|
declare pub fn RingRecorder::new(
  turns~ : Int,
  snapshot~ : () -> Json,
  origin? : Origin,
  keep_after? : Bool,
) -> RingRecorder

///|
declare pub fn RingRecorder::take(self : RingRecorder) -> Trace

///|
/// Everything at or below one place, and nothing else.
///
/// The third strategy, and the one that makes "record only this part" mean
/// something when the parts are not separate apps. A storybook gallery is ONE
/// transactor with every story mounted under it, so narrowing what a recording
/// covers cannot be done by mounting less — it is done by keeping less, here,
/// as it happens.
///
/// It is `relocate` applied live, and it applies the same rule for the same
/// reason: an event whose CAUSE was not kept is promoted to an input, because
/// after the cut nothing remains to produce it. What it cannot do is what
/// `relocate` cannot do either — carry across a name the subtree reads from an
/// ancestor, since a read is not a dispatch.
///
/// The trade against recording everything and relocating afterwards is
/// straightforward: this holds less, and what it drops is gone.
pub struct ScopedRecorder {
  priv inner : TraceRecorder
  priv at : Place
  /// The `seq`s that were kept, so a derived event can be asked whether its
  /// cause survived. The same question `relocate` answers from the finished
  /// list; asked one event at a time, because there is no finished list yet.
  priv kept : Map[Int, Bool]
  /// Walks raised inside the scope. An offer and an answer belong to their
  /// walk rather than to a position — an offer's address is the sender's and
  /// an answer has none at all — so they are kept by whose walk it is.
  priv walks : Map[Int, Bool]
}

///|
/// `root` is the SUBTREE's snapshot, which the caller cuts with `cut_root`:
/// a recording of a subtree that started from the whole app's state would be a
/// recording nothing can mount.
declare pub fn ScopedRecorder::new(
  at~ : Place,
  root~ : Json,
  origin? : Origin,
  keep_after? : Bool,
) -> ScopedRecorder

///|
declare pub fn ScopedRecorder::take(self : ScopedRecorder) -> Trace

// --- the three operations ---------------------------------------------------

///|
/// The first `n` events. The cheapest of the three: a prefix of a recording is
/// a recording, because the state it starts from has not changed.
declare pub fn Trace::prefix(self : Trace, n : Int) -> Trace

///|
/// The first index at or after `n` that starts a turn — where a cut can
/// actually be made. `rebase` rounds through this, and a caller who wants to
/// know where it will land can ask first.
declare pub fn Trace::turn_boundary(self : Trace, n : Int) -> Int

///|
/// Replace the first `n` events with the state they produced.
///
/// `at` is rounded FORWARD to a turn boundary: half a turn is not a thing that
/// happened, and a tail beginning with a consequence whose cause was discarded
/// is a tail nothing can produce again.
///
/// `root` is the snapshot the caller replayed to — this package cannot compute
/// it, because computing it means running the app. The tail keeps its events,
/// renumbered from 1, with walk ids and `parent` links remapped so an answer
/// still names its intent. An answer whose intent fell in the discarded prefix
/// goes with it: there is nothing left for it to answer.
declare pub fn Trace::rebase(self : Trace, at~ : Int, root~ : Json) -> Trace

///|
/// Everything the subtree at `place` saw, with `place` as the new root.
///
/// The new root is cut out of the old one by walking the TAGGED JSON down
/// `place` — no runtime and no rerun needed, because a snapshot's shape is the
/// state's shape.
///
/// Events under `place` keep their op and lose the prefix from their address.
/// Everything else is dropped, EXCEPT a derived event that lands inside the
/// cut, which is promoted to an input: a message a parent sent into the subtree
/// is not the subtree's own doing, and after the cut there is no parent left to
/// send it. An answer that came from outside is promoted the same way, and that
/// is not a compromise — to the relocated subtree, the outside IS the host.
declare pub fn Trace::relocate(
  self : Trace,
  place : Place,
) -> (Trace, Array[Gap])

///|
/// Drop the derived events.
///
/// A smaller file, and the trade is explicit rather than silent: `relocate` and
/// a scripted rerun both read the derived stream, and neither works afterwards.
declare pub fn Trace::compact(self : Trace) -> Trace

///|
/// What a cut could not carry across, reported rather than silently dropped.
///
/// A relocated trace that is missing something is still worth having — it is
/// usually missing something that did not matter — so these are warnings beside
/// a result and not an error instead of one.
pub(all) enum Gap {
  /// The subtree raised an intent that something outside answered, and no
  /// answer was recorded for it. A rerun will hear `<name>Unhandled` where the
  /// recording heard a reply.
  UnansweredIntent(name~ : String, seq~ : Int)
  /// The subtree reads a name an ancestor provided. A read is not a dispatch,
  /// so nothing recorded it, and after the cut nothing remains to answer it.
  UnprovidedName(name~ : String)
  /// The trace was compacted, so nothing could be promoted: an event that
  /// crossed into the subtree is indistinguishable from one that never was.
  NoDerivedStream
  /// `place` names nothing in the root snapshot, so there is no subtree to
  /// relocate to and the result is empty.
  NoSuchPlace(place~ : String)
  /// `place` names something that is not a component — a list, a map, a scalar.
  /// The trace is cut correctly and cannot be MOUNTED, because a root has to be
  /// an instance. Almost always one step too far, or one too few: `.rows` where
  /// `.rows[0]` was meant.
  NotAComponent(place~ : String)
} derive(Eq, Debug)

///|
declare pub fn Gap::message(self : Gap) -> String

///|
/// The subtree of a tagged snapshot at `place`, or `None` when the address
/// names nothing there.
///
/// Public because it is the other half of relocation a caller may want alone:
/// the state to mount a subtree from, with no trace attached.
declare pub fn cut_root(root : Json, place : Place) -> Json?
