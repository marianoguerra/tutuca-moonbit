// A recording to look at, and one example per level of the viewer.
//
// The trace here is written by hand rather than captured, and that is the same
// choice `deep_zoo` makes above it: a gallery example has to show the SHAPES a
// reader will meet — an intent that left for the host, an answer that came
// back, a refusal, a message a parent sent into a child — and arranging for a
// live app to produce each of them in one session is a longer story than
// writing them down.
//
// One example per level, on purpose. A row alone is where a verb's badge is
// checked; a log is where the filters are; a panel is the screen. A gallery
// that only ever showed the finished screen would be a gallery in which a
// single wrong badge is a thing you find in production.

///|
/// A place from its dotted spelling, for a fixture that has no runtime around
/// it to ask.
fn tp(src : String) -> @trace.Place {
  @trace.parse_place(src) catch {
    _ => @trace.Place([])
  }
}

///|
fn tev(
  seq : Int,
  turn : Int,
  at : String,
  op : @trace.Op,
  input? : Bool = true,
  walk? : Int = 0,
  parent? : Int = 0,
  after? : Json,
) -> @trace.Event {
  { seq, turn, walk, parent, at: tp(at), op, input, after, }
}

///|
/// The state the sample recording starts from: a two-row list whose rows are
/// components, which is the shape relocation is FOR.
fn sample_trace_root() -> Json {
  Json::object({
    "$component": Json::string("Board"),
    "title": Json::string("shopping"),
    "rows": Json::array([
      Json::object({
        "$component": Json::string("Row"),
        "label": Json::string("milk"),
        "n": Json::number(0),
      }),
      Json::object({
        "$component": Json::string("Row"),
        "label": Json::string("eggs"),
        "n": Json::number(0),
      }),
    ]),
  })
}

///|
/// One session: a click, the intent it raised, the host's answer, the reply,
/// a message the parent sent into the other row, and a rule saying no.
///
/// Six verbs and four turns in fourteen lines — enough that the log's turn
/// grouping, its input/derived colouring and its causal nesting all have
/// something to show, and short enough to read at a glance.
pub fn sample_trace() -> @trace.Trace {
  let row0 : Json = Json::object({
    "$component": Json::string("Row"),
    "label": Json::string("milk"),
    "n": Json::number(1),
  })
  {
    ..@trace.Trace::new(root=sample_trace_root(), origin={
      module_: "board",
      component: "Board",
      example: "Two rows",
      view: "",
      fingerprint: "ce65fc01e851b3ac",
    }),
    events: [
      tev(1, 1, "", Send(name="init", args=[])),
      tev(2, 2, ".rows[0]", Send(name="bump", args=[]), after=row0),
      tev(
        3,
        2,
        ".rows[0]",
        Intent(
          name="save",
          args=[Str("milk")],
          opts=@tutuca.IntentOpts::new(route=[Lex], on_ok_name="saved"),
        ),
        input=false,
        walk=1,
        parent=2,
      ),
      tev(
        4,
        2,
        ".rows[0]",
        Offered(name="save", args=[Str("milk")], nth=0),
        input=false,
        walk=1,
        parent=3,
      ),
      tev(5, 2, "", Answer(nth=0, answer=Ok(Str("stored"))), walk=1, parent=3),
      tev(
        6,
        2,
        ".rows[0]",
        Send(name="saved", args=[Str("stored")]),
        input=false,
        walk=1,
        parent=3,
      ),
      tev(7, 3, "", Send(name="touch", args=[])),
      // The cross-level event: a message the parent sent INTO a child. After a
      // cut to that child this is the one that has to survive as an input,
      // because there is no parent left to send it.
      tev(8, 3, ".rows[1]", Send(name="reset", args=[]), input=false, parent=7),
      tev(9, 4, ".rows[1]", Send(name="rename", args=[Str("")])),
      tev(
        10,
        4,
        ".rows[1]",
        Refused(
          code="PRECONDITION",
          asked="rename",
          rule="hasLabel",
          sentence="a row with no label cannot be renamed",
        ),
        input=false,
        parent=9,
      ),
    ],
  }
}

///|
/// The gallery entries for the trace viewer, one per level.
pub fn Inspector::trace_examples(
  self : Inspector,
) -> Array[@component.ExampleDef] {
  let insp = self
  let t = sample_trace()
  let rows = t.events
  fn row(title : String, e : @trace.Event) -> @component.ExampleDef {
    {
      component: "TraceRow",
      title,
      args: insp.trace_row(e).snapshot(),
      view: None,
    }
  }

  [
    // --- one row per verb, which is where a badge is checked ---
    row("Trace Row · a message", rows[1]),
    row("Trace Row · an intent", rows[2]),
    row("Trace Row · offered to the host", rows[3]),
    row("Trace Row · the host answered", rows[4]),
    row("Trace Row · refused", rows[9]),
    // --- the log, and the two questions asked of it ---
    {
      component: "TraceLog",
      title: "Trace Log",
      args: insp.trace_log(t).snapshot(),
      view: None,
    },
    {
      component: "TraceLog",
      title: "Trace Log · only what a rerun feeds",
      args: insp.trace_log(t, inputs_only=true).snapshot(),
      view: None,
    },
    {
      component: "TraceLog",
      title: "Trace Log · one turn",
      args: insp.trace_log(t, turn=2).snapshot(),
      view: None,
    },
    {
      component: "TraceLog",
      title: "Trace Log · nothing recorded",
      args: insp.trace_log(@trace.Trace::new(root=Json::null())).snapshot(),
      view: None,
    },
    // --- the header, as it was recorded and after a cut ---
    {
      component: "TraceHeader",
      title: "Trace Header",
      args: insp.trace_header(t).snapshot(),
      view: None,
    },
    {
      component: "TraceHeader",
      title: "Trace Header · relocated and compacted",
      args: insp.trace_header(t.compact().relocate(tp(".rows[0]")).0).snapshot(),
      view: None,
    },
    // --- the relocation picker ---
    {
      component: "TracePlaces",
      title: "Relocation Picker",
      args: insp.trace_places(t).snapshot(),
      view: None,
    },
    {
      component: "TracePlaces",
      title: "Relocation Picker · one chosen",
      args: insp.trace_places(t, selected="rows[0]").snapshot(),
      view: None,
    },
    // --- the recorder, in each of its states ---
    {
      component: "RecorderBar",
      title: "Recorder · idle",
      args: insp.recorder_bar().snapshot(),
      view: None,
    },
    {
      component: "RecorderBar",
      title: "Recorder · recording",
      args: insp
      .recorder_bar(recording=true, scope="example", events=10, turns=4)
      .snapshot(),
      view: None,
    },
    {
      component: "RecorderBar",
      title: "Recorder · stopped, with a trace",
      args: insp.recorder_bar(has_trace=true, scope="section").snapshot(),
      view: None,
    },
    {
      component: "RecorderBar",
      title: "Recorder · choosing a scope",
      args: insp.recorder_bar(picking=true, scope="section").snapshot(),
      view: None,
    },
    // --- the screen ---
    {
      component: "TracePanel",
      title: "Trace Panel · nothing yet",
      args: insp.trace_panel().snapshot(),
      view: None,
    },
    {
      component: "TracePanel",
      title: "Trace Panel · recording",
      args: insp.trace_panel(recording=true, scope="example").snapshot(),
      view: None,
    },
    {
      component: "TracePanel",
      title: "Trace Panel · reading a recording",
      args: insp
      .trace_panel(trace=t, tab="trace", at=5, selected_place="rows[0]")
      .snapshot(),
      view: None,
    },
    {
      component: "TracePanel",
      title: "Trace Panel · picking a component",
      args: insp.trace_panel(trace=t, tab="trace", selecting=true).snapshot(),
      view: None,
    },
  ]
}
