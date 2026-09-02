// The Trace tab: recording what the gallery did, and pointing at the component
// to cut it down to.
//
// Host code, all of it, and the reason is one line long: recording is
// installing a `Recorder` on a transactor, and a transactor is the one thing a
// component cannot reach. The shell holds the PANEL — a value handed down
// through `@sbui.push_panel` — and this holds the recording.

///|
/// The gallery's own recording, and the story it is about.
priv struct TraceSession {
  mut recorder : @trace.TraceRecorder?
  mut scoped : @trace.ScopedRecorder?
  mut taken : @trace.Trace?
  /// The story index the recording is about, so the panel goes back to the
  /// pane that started it.
  mut idx : Int
  mut scope : String
  mut selected_place : String?
  /// Whether a click on the page means "pick this" rather than "use this".
  mut selecting : Bool
  /// The candidates a click produced, or the recording's own places when
  /// nobody has clicked. Two lists of the same things offered for the same
  /// reason, so one field holds either.
  mut candidates : Array[(String, String)]?
  /// Where somewhere else keeps files. `MemFiles` under `moon test`, the
  /// browser's download and file read in a page.
  files : &@files.FileService
  /// What the last thing the reader asked for had to say for itself — a file
  /// that would not parse, a cut that dropped something, a rerun that
  /// diverged. Cleared by the next thing they ask for.
  mut notice : String
  /// The text a trace is being pasted into, held so a rebuild does not lose
  /// a half-pasted recording.
  mut draft : String
  /// The rerun, once one is mounted.
  mut driver : @replay.Driver?
  /// The story's value before a rerun overwrote it, so Reset is exact.
  mut before_replay : @tutuca.Value?
  /// Where the loaded recording's root sits in the gallery. Known for a
  /// recording this session made or cut; ASKED for one that arrived as a file,
  /// because an `example`-scoped trace is story-relative and an `all`-scoped
  /// one is not, and guessing wrong aims every event at the wrong component.
  mut base : @trace.Place?
}

///|
fn TraceSession::new(files : &@files.FileService) -> TraceSession {
  {
    recorder: None,
    scoped: None,
    taken: None,
    idx: -1,
    scope: "all",
    selected_place: None,
    selecting: false,
    candidates: None,
    files,
    notice: "",
    draft: "",
    driver: None,
    before_replay: None,
    base: None,
  }
}

///|
/// What the session has recorded so far, whichever strategy is installed.
fn TraceSession::current(self : TraceSession) -> @trace.Trace? {
  match (self.scoped, self.recorder) {
    (Some(r), _) => Some(r.take())
    (_, Some(r)) => Some(r.take())
    _ => self.taken
  }
}

///|
fn TraceSession::recording(self : TraceSession) -> Bool {
  self.recorder is Some(_) || self.scoped is Some(_)
}

// ---------------------------------------------------------------------------
// recording the gallery
// ---------------------------------------------------------------------------

///|
/// Where a story's instance lives in the shell's state, as a `Place`.
///
/// A story IS a place — which is what makes "record only this example"
/// expressible at all: it is a cut at `.sN`, and the same operation that trims
/// a finished recording. The field name is the shell's to say
/// (`@sbui.story_field`); turning it into a place is ours.
fn story_place(idx : Int) -> @trace.Place {
  @trace.Place([{ field: @sbui.story_field(idx), key: None, }])
}

///|
/// Install a recorder, or say why not.
///
/// A scope of `all` records the gallery whole; `example` cuts to the story on
/// screen. `section` has no place of its own — a section is a sidebar grouping
/// and not a component — so it records whole and says so, which is honest in a
/// way that quietly recording something else would not be.
fn[N] start_recording(
  app : @app.App[N],
  session : TraceSession,
  idx : Int,
  scope : String,
) -> Unit {
  session.idx = idx
  session.scope = scope
  session.taken = None
  let root = app.root_value().to_component_json()
  if scope == "example" && idx >= 0 {
    let place = story_place(idx)
    let cut = @trace.cut_root(root, place).unwrap_or(Json::null())
    let r = @trace.ScopedRecorder::new(at=place, root=cut, origin={
      module_: "storybook",
      component: "",
      example: "",
      view: "",
      fingerprint: "",
    })
    session.scoped = Some(r)
    session.recorder = None
    session.base = Some(place)
    app.transactor.set_recorder(r)
  } else {
    let r = @trace.TraceRecorder::new(root~, origin={
      module_: "storybook",
      component: "",
      example: "",
      view: "",
      fingerprint: "",
    })
    session.recorder = Some(r)
    session.scoped = None
    // The whole gallery: the recording's addresses ARE the tree's.
    session.base = Some(@trace.Place([]))
    app.transactor.set_recorder(r)
  }
}

///|
/// Take the recording and put the recorder back.
///
/// Back to `NullRecorder` and not merely "stopped": the default records nothing
/// and costs nothing, and leaving a live recorder installed after somebody
/// pressed Stop would be the gallery quietly still recording.
fn[N] stop_recording(app : @app.App[N], session : TraceSession) -> Unit {
  session.taken = session.current()
  session.recorder = None
  session.scoped = None
  app.transactor.set_recorder(@transactor.NullRecorder::{ })
}

///|
/// Rebuild the panel and hand it to the pane that owns it.
///
/// Through `send_at_root` because that is the host's door into a running app,
/// and the shell routes it to `rN` — the host knows the story index and nothing
/// else about where the pane lives.
fn[N] push_trace_panel(
  app : @app.App[N],
  insp : @inspector.Inspector,
  session : TraceSession,
  tab? : String = "",
) -> Unit {
  guard session.idx >= 0 else { return }
  let t = session.current()
  let tab = if tab != "" {
    tab
  } else if t is Some(_) && !session.recording() {
    "trace"
  } else {
    "record"
  }
  let panel = insp.trace_panel(
    trace?=t,
    tab~,
    recording=session.recording(),
    scope=session.scope,
    selecting=session.selecting,
    selected_place?=session.selected_place,
    notice=session.notice,
    draft=session.draft,
    // A rerun can be mounted once there is a recording AND somewhere to aim
    // it. An imported trace with no base yet is a trace nobody has said where
    // to put, and offering Step for it would aim it at the gallery's root.
    can_replay=t is Some(_) &&
      session.base.unwrap_or(@trace.Place([])).depth() > 0,
    replaying=session.driver is Some(_),
    at=match session.driver {
      Some(d) => d.at() - 1
      None => -1
    },
    // A click replaces the picker's list with what is under it. The same
    // component either way: "the places this recording touched" and "the
    // components under what you clicked" are the same list of the same things,
    // offered for the same reason.
    places?=match session.candidates {
      Some(cs) =>
        Some(
          insp.place_candidates(
            candidates_for(session, cs),
            t.unwrap_or(@trace.Trace::new(root=Json::null())),
            selected?=session.selected_place,
          ),
        )
      None => None
    },
  )
  @sbui.push_panel(app, session.idx, "trace", panel)
}

///|
/// Whether a click on the page means "pick this" rather than "use this".
///
/// A module-level flag, and the reason is that a gallery mounts ONCE per page:
/// the shell is the whole page, so there is one of these to be in. A host has
/// to ask before it dispatches a click — the answer decides whether the click
/// drives the app or points at it — and the alternative was threading a handle
/// out of `mount` into the one export a wasm host is allowed.
let selecting_now : Ref[Bool] = { val: false, }

///|
/// The gallery's current recording, for a page that wants to do something with
/// it that the tab does not.
///
/// Public for the reason `pick_at` is: some things belong to whoever owns the
/// page. Posting a recording to an issue tracker, writing it somewhere the
/// browser's download does not reach, holding it for a crash reporter — none
/// of those are a gallery's business, and all of them need the `Trace`.
///
/// `None` until something has been recorded or loaded. Reading it does not
/// stop a recording in progress: this is a snapshot, the same one the Trace
/// tab shows.
pub fn current_trace() -> @trace.Trace? {
  match current_session.val {
    Some(s) => s.current()
    None => None
  }
}

///|
/// The session the last `all()` built, so `current_trace` has something to ask.
///
/// A module-level slot for the reason the selection flag below is one: a
/// gallery mounts ONCE per page.
let current_session : Ref[TraceSession?] = { val: None, }

///|
/// Whether the gallery is waiting to be pointed at.
///
/// Asked by a host's DOM listener before it dispatches: while this is true a
/// click is a pick, and letting it also reach the app would drive the app with
/// the click that was meant to point at it.
pub fn trace_selecting() -> Bool {
  selecting_now.val
}

///|
/// A clicked node turned into relocation candidates.
///
/// The one piece of selection mode a host cannot do without: a person can point
/// at a row far more easily than they can spell `.s3.rows[1]`, and the renderer
/// already stamped everything needed to read the ancestry back out of the DOM.
///
/// Public because the CLICK is the host's — a document listener is not
/// something a component can install, and the browser glue is where one lives.
/// This is what such a listener calls with the node it got.
///
/// The addresses are relative to the story when the recording was scoped to
/// one, because that is what the recording's own addresses are relative to:
/// offering a candidate a recording cannot be cut to would be offering an
/// empty trace.
pub fn[N : @vdom.DomWalk] pick_at(
  app : @app.App[N],
  node : N,
  root_node : N,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let root = app.root_value()
  for c in @render.components_at(node, root_node, app.scope.comps) {
    let place = @trace.Place::of_path(c.path.to_transaction_path())
    // The component's NAME, from the instance the address resolves to. Not
    // from the crossing's `cid`, which is a process-global counter and means
    // nothing outside this run.
    let name = match place.to_path().lookup(root) {
      Some(v) =>
        match v.schema() {
          Some(sc) => sc.name
          None => ""
        }
      None => ""
    }
    out.push((place.label(), name))
  }
  out
}

///|
/// The same, cut to the story a scoped recording is about.
///
/// A recording scoped to one story has story-relative addresses, so a candidate
/// has to be one too — and a click outside that story yields nothing, which is
/// the honest answer rather than an address the recording cannot use.
fn candidates_for(
  session : TraceSession,
  crossings : Array[(String, String)],
) -> Array[(String, String)] {
  guard session.scope == "example" && session.idx >= 0 else { return crossings }
  let prefix = "s\{session.idx}"
  let out : Array[(String, String)] = []
  for c in crossings {
    let (label, name) = c
    if label == prefix {
      out.push(("", name))
    } else if label.has_prefix(prefix + ".") {
      out.push((label[prefix.length() + 1:].to_owned(), name))
    }
  }
  out
}

///|
/// A click on the page, while selection mode is on.
///
/// The host's whole half of pointing at a component: it hands the node its
/// listener got, this reads the ancestry back out of the renderer's own DOM
/// markers and sends it in, and the panel comes back offering each one as
/// somewhere to cut the recording to.
///
/// Answers whether the click was consumed, so a caller knows whether to let it
/// through — a pick and a use are two different meanings for one click, and
/// doing both is doing the wrong one.
pub fn[N : @vdom.DomWalk] take_select_click(
  app : @app.App[N],
  node : N,
  root_node : N,
) -> Bool {
  if !selecting_now.val {
    return false
  }
  let found = pick_at(app, node, root_node)
  @sbui.raise_panel_intent(
    app,
    "traceCandidates",
    List(
      found.map(c => {
        (Map({ "place": Str(c.0), "component": Str(c.1) }) : @tutuca.Value)
      }),
    ),
  )
  true
}

///|
/// Make sure the session knows which story it is about.
///
/// `start_recording` sets this, and for a long time nothing else needed to:
/// every verb the panel had began with a recording. Importing one does not —
/// a reader who just opened the gallery and pasted somebody else's file has a
/// session that has never been told which story is on screen, and a panel
/// pushed at story -1 goes nowhere. So the verbs that can come first ask.
fn[N] ensure_story(
  app : @app.App[N],
  session : TraceSession,
  sections : Array[@sb.Section],
) -> Unit {
  if session.idx < 0 {
    session.idx = @sbui.active_story(app, sections)
  }
}

///|
/// Mount the rerun if it is not mounted, and hand it back.
///
/// Seeding the story is the whole of "mounting" here, because there is nothing
/// else to mount: the story is already on screen, in a transactor the gallery
/// owns. What a rerun needs is that instance put back to the state the
/// recording started from, and `set_story_value` is the gallery's own exact
/// reset — the same one a panel uses to undo a fuzz run.
///
/// The three guards come from `@replay.root_for` rather than being repeated
/// here, and that is the point of it being public: a recording made against a
/// component whose fields have since moved has ONE useful thing to say, and it
/// is `ShapeChanged` naming the component. Losing that on the browser path
/// would leave a replay that quietly does the wrong thing.
fn[N] replay_mount(
  app : @app.App[N],
  session : TraceSession,
) -> Result[@replay.Driver, String] {
  match session.driver {
    Some(d) => return Ok(d)
    None => ()
  }
  guard session.current() is Some(t) else {
    return Err("There is no recording to replay.")
  }
  guard session.base is Some(base) else {
    return Err("Say where this recording belongs before replaying it.")
  }
  // A recording of the WHOLE gallery cannot be replayed here, and the reason
  // is not a limitation to work around later: seeding it means replacing the
  // gallery's root, and the gallery's root is where the panels live — the
  // Trace tab would replace itself mid-press and the reader would be watching
  // a rerun through a panel that no longer exists.
  //
  // A recording OF something is what a rerun wants anyway. `Cut to the picked
  // place` is one press away and produces exactly that, so this says so rather
  // than half-doing it.
  if base.depth() == 0 {
    return Err(
      "This recording covers the whole storybook. Pick a component above and " +
      "cut to it — a rerun drives one example, not the gallery it lives in.",
    )
  }
  // The STORY's scope, not the gallery's. A story's components are registered
  // in a scope of its own, so `app.scope` does not know their names, and a
  // snapshot rebuilt against it fails with `RootUnbuildable` — a true sentence
  // about the wrong scope, which is the worst kind of error message.
  guard @sbui.story_scope(session.idx) is Some(scope) else {
    return Err("There is no story on screen to replay into.")
  }
  let root = @replay.root_for(t, scope) catch { e => return Err(e.message()) }
  // Kept before anything is fed, so Reset is exact rather than approximate:
  // `set_story_value` is the gallery's own reset, and what it puts back is
  // whatever was there.
  match story_place(session.idx).to_path().lookup(app.root_value()) {
    Some(v) => session.before_replay = Some(v)
    None => ()
  }
  @sbui.set_story_value(app, session.idx, root)
  // `verify` off: the gallery's transactor carries the shell, the panels and
  // every other story, and at a story's base their dispatches are outside it —
  // but a rerun that diverges mid-run would abandon the step rather than let
  // the reader watch the rest, which is the opposite of what this view is for.
  // Divergence is worth reporting in a test; here the reader is watching.
  let d = @replay.Driver::new(t, app.transactor, base~, verify=false)
  session.driver = Some(d)
  Ok(d)
}

///|
/// One turn, mounting first if this is the first press.
fn[N] replay_step(
  app : @app.App[N],
  session : TraceSession,
) -> Result[Unit, String] {
  match replay_mount(app, session) {
    Err(msg) => Err(msg)
    Ok(d) =>
      try {
        d.step()
        session.notice = ""
        Ok(())
      } catch {
        e => Err(e.message())
      }
  }
}

///|
/// The three intents the recorder bar raises, answered by the host.
fn[N] trace_handlers(
  app_slot : Ref[@app.App[N]?],
  insp : @inspector.Inspector,
  session : TraceSession,
  sections : Array[@sb.Section],
) -> Map[String, Array[@component.IntentFn]] {
  fn with_app(f : (@app.App[N]) -> Unit) -> Unit {
    match app_slot.val {
      Some(app) => f(app)
      None => ()
    }
  }

  {
    "traceStart": [
      @tutuca.IntentFn((call, answer) => {
        let scope = match call.args {
          [Str(s), ..] => s
          _ => "all"
        }
        with_app(app => {
          start_recording(
            app,
            session,
            @sbui.active_story(app, sections),
            scope,
          )
          push_trace_panel(app, insp, session, tab="record")
        })
        answer(Ok(Str(scope)))
      }),
    ],
    "traceStop": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => {
          stop_recording(app, session)
          push_trace_panel(app, insp, session)
        })
        answer(Ok(Null))
      }),
    ],
    "traceDiscard": [
      @tutuca.IntentFn((_call, answer) => {
        session.taken = None
        session.selected_place = None
        session.selecting = false
        selecting_now.val = false
        session.candidates = None
        with_app(app => push_trace_panel(app, insp, session, tab="record"))
        answer(Ok(Null))
      }),
    ],
    // Selection mode on and off. Turning it OFF puts the recording's own
    // places back, because a stale list of candidates from a click nobody
    // remembers making is worse than no list.
    "traceSelect": [
      @tutuca.IntentFn((_call, answer) => {
        session.selecting = !session.selecting
        selecting_now.val = session.selecting
        if !session.selecting {
          session.candidates = None
        }
        with_app(app => push_trace_panel(app, insp, session, tab="trace"))
        answer(Ok(Bool(session.selecting)))
      }),
    ],
    // What a click on the page found. Raised by the shell on the host's
    // behalf, because the CLICK is the host's — a document listener is not
    // something a component can install — and the host is the only thing that
    // can rebuild the panel around the answer.
    "traceCandidates": [
      @tutuca.IntentFn((call, answer) => {
        let cs : Array[(String, String)] = []
        match call.args {
          [List(items), ..] =>
            for it in items {
              cs.push(
                (
                  it.field("place").str(default=""),
                  it.field("component").str(default=""),
                ),
              )
            }
          _ => ()
        }
        session.candidates = Some(cs)
        session.selecting = false
        selecting_now.val = false
        with_app(app => push_trace_panel(app, insp, session, tab="trace"))
        answer(Ok(Num(cs.length().to_double())))
      }),
    ],
    // Hand the recording to the viewer as a file.
    //
    // JSONL and not the single-JSON form, because this is the artifact: the
    // CLI reads `.trace.jsonl`, every shortening operation is a line
    // operation, and a recording of a real session is mostly a list of events.
    "traceExport": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => ensure_story(app, session, sections))
        match session.current() {
          Some(t) => {
            let name = @files.trace_filename(
              if t.origin.component == "" {
                "storybook"
              } else {
                t.origin.component
              },
            )
            session.files.save_text(name~, mime=@files.TRACE_MIME, t.to_jsonl())
            session.notice = ""
            with_app(app => push_trace_panel(app, insp, session, tab="trace"))
            answer(Ok(Str(name)))
          }
          None => {
            session.notice = "There is no recording to download yet."
            with_app(app => push_trace_panel(app, insp, session))
            answer(Ok(Null))
          }
        }
      }),
    ],
    // Read a recording somebody else made.
    //
    // The failure is the interesting half. `TraceError` carries a line number
    // in every case, and showing that sentence is the difference between "this
    // file is wrong" and "this file is wrong on line 412" — so a parse that
    // fails puts the message on the panel and changes nothing else. A trace
    // half-loaded over a good one would be worse than no import at all.
    "traceImport": [
      @tutuca.IntentFn((call, answer) => {
        with_app(app => ensure_story(app, session, sections))
        let text = match call.args {
          [Str(s), ..] => s
          _ => ""
        }
        if text.trim(chars=" \n\t").is_empty() {
          session.notice = "Paste a recording first."
          with_app(app => push_trace_panel(app, insp, session))
          answer(Ok(Null))
          return
        }
        let parsed = Some(@trace.from_jsonl(text)) catch {
          e => {
            session.notice = e.message()
            with_app(app => push_trace_panel(app, insp, session))
            answer(Failed(Str(e.message())))
            None
          }
        }
        match parsed {
          Some(t) => {
            session.taken = Some(t)
            session.recorder = None
            session.scoped = None
            session.driver = None
            session.before_replay = None
            session.selected_place = None
            session.candidates = None
            session.draft = ""
            // An imported recording does not say where it belongs. A relocated
            // one is story-relative and a whole-gallery one is not, and the
            // file carries `relocatedFrom` but not what it was relocated OUT
            // of. So the reader is told to aim it rather than having it
            // aimed for them at the wrong component.
            session.base = if t.relocated_from.is_empty() {
              Some(@trace.Place([]))
            } else {
              Some(story_place(session.idx))
            }
            session.notice = if t.relocated_from.is_empty() {
              ""
            } else {
              "Loaded a recording cut to " +
              t.relocated_from.map(p => p.label()).join(" > ") +
              " — it will be replayed into this example."
            }
            with_app(app => push_trace_panel(app, insp, session, tab="trace"))
            answer(Ok(Num(t.events.length().to_double())))
          }
          // The parse already reported itself.
          None => ()
        }
      }),
    ],
    // Cut the recording down to the place that was picked.
    //
    // The press the picker has been waiting for since it was written. What a
    // cut could not carry across is REPORTED — `relocate` answers gaps beside
    // the result rather than failing — because a relocated trace missing
    // something is usually missing something that did not matter, and is still
    // worth having.
    "traceRelocate": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => ensure_story(app, session, sections))
        guard session.current() is Some(t) else {
          session.notice = "There is no recording to cut."
          with_app(app => push_trace_panel(app, insp, session))
          answer(Ok(Null))
          return
        }
        guard session.selected_place is Some(label) else {
          session.notice = "Pick a place first — click one in the list above."
          with_app(app => push_trace_panel(app, insp, session, tab="trace"))
          answer(Ok(Null))
          return
        }
        let place = Some(
          @trace.parse_place(if label == "" { "." } else { label }),
        ) catch {
          e => {
            session.notice = e.message()
            with_app(app => push_trace_panel(app, insp, session, tab="trace"))
            answer(Failed(Str(e.message())))
            None
          }
        }
        match place {
          None => ()
          Some(at) => {
            let (cut, gaps) = t.relocate(at)
            session.taken = Some(cut)
            session.recorder = None
            session.scoped = None
            session.driver = None
            session.selected_place = None
            session.candidates = None
            // A cut recording is about the subtree, so a rerun of it aims
            // there — under whatever the recording was already relative to.
            session.base = Some(
              at.under(session.base.unwrap_or(@trace.Place([]))),
            )
            session.notice = if gaps.is_empty() {
              ""
            } else {
              gaps.map(g => g.message()).join("; ")
            }
            with_app(app => push_trace_panel(app, insp, session, tab="trace"))
            answer(Ok(Num(cut.events.length().to_double())))
          }
        }
      }),
    ],
    // Feed one turn of the recording into the story on screen.
    //
    // Mounts on the first press rather than on a button of its own: "start the
    // rerun" and "take the first step" are one thing a reader wants, and a
    // mount that has to be asked for separately is a mode nobody remembers
    // they are in.
    "traceReplayStep": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => {
          match replay_step(app, session) {
            Ok(_) => ()
            Err(msg) => session.notice = msg
          }
        })
        with_app(app => push_trace_panel(app, insp, session, tab="replay"))
        answer(Ok(Null))
      }),
    ],
    "traceReplayRun": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => ensure_story(app, session, sections))
        with_app(app => {
          match replay_mount(app, session) {
            Err(msg) => session.notice = msg
            Ok(d) =>
              try {
                d.run()
                session.notice = ""
              } catch {
                e => session.notice = e.message()
              }
          }
        })
        with_app(app => push_trace_panel(app, insp, session, tab="replay"))
        answer(Ok(Null))
      }),
    ],
    // Put the story back the way it was before the rerun touched it.
    "traceReplayReset": [
      @tutuca.IntentFn((_call, answer) => {
        with_app(app => {
          match session.driver {
            Some(d) => d.stop()
            None => ()
          }
          session.driver = None
          match session.before_replay {
            Some(v) => {
              @sbui.set_story_value(app, session.idx, v)
              session.before_replay = None
            }
            None => ()
          }
          session.notice = ""
          push_trace_panel(app, insp, session, tab="replay")
        })
        answer(Ok(Null))
      }),
    ],
    // Which pane the reader asked for. The component set its own `.tab` on the
    // way past; this is what makes the panes and the tab classes agree with it,
    // both of which are computed here because only the host knows whether
    // there is a recording behind them.
    "traceSetTab": [
      @tutuca.IntentFn((call, answer) => {
        let want = match call.args {
          [Str(s), ..] => s
          _ => "record"
        }
        with_app(app => {
          ensure_story(app, session, sections)
          push_trace_panel(app, insp, session, tab=want)
        })
        answer(Ok(Str(want)))
      }),
    ],
    // Which candidate the reader chose. Kept rather than acted on: cutting the
    // recording is a separate press, and choosing a place is the thing a person
    // does several times before they mean it.
    "tracePick": [
      @tutuca.IntentFn((call, answer) => {
        session.selected_place = match call.args {
          [Str(p), ..] => Some(p)
          _ => None
        }
        with_app(app => push_trace_panel(app, insp, session, tab="trace"))
        answer(Ok(Str(session.selected_place.unwrap_or(""))))
      }),
    ],
  }
}
