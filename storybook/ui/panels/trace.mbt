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
}

///|
fn TraceSession::new() -> TraceSession {
  {
    recorder: None,
    scoped: None,
    taken: None,
    idx: -1,
    scope: "all",
    selected_place: None,
    selecting: false,
    candidates: None,
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
      @component.IntentFn((call, answer) => {
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
      @component.IntentFn((_call, answer) => {
        with_app(app => {
          stop_recording(app, session)
          push_trace_panel(app, insp, session)
        })
        answer(Ok(Null))
      }),
    ],
    "traceDiscard": [
      @component.IntentFn((_call, answer) => {
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
      @component.IntentFn((_call, answer) => {
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
      @component.IntentFn((call, answer) => {
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
    // Which candidate the reader chose. Kept rather than acted on: cutting the
    // recording is a separate press, and choosing a place is the thing a person
    // does several times before they mean it.
    "tracePick": [
      @component.IntentFn((call, answer) => {
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
