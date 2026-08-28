// A recording, as something to look at.
//
// The components are in trace_view.html; this is the projection from a
// `@trace.Trace` onto them, and the reason it is a projection rather than a
// component that reads a trace is the same reason `record_to_entry` is one: a
// tutuca component holds STATE, and a trace is a value somebody else owns.
// What crosses the line is a list of rows.
//
// Everything decided here was decided when the recording was written. A row
// recomputing any of it would be a second opinion about what happened — so the
// verb, the address, the input/derived line and the causal depth are read
// straight off the event, and only the words and the classes are chosen.

///|
/// The word a row reads as, and the badge it wears.
///
/// Five verbs and four colours: an offer and an answer are the host boundary
/// and get their own, a refusal is the one thing that says nothing happened
/// ON PURPOSE, and a message and an intent are the ordinary case.
fn verb_of(op : @trace.Op) -> (String, String) {
  let colour = match op {
    Send(..) => "badge-neutral"
    Intent(..) => "badge-info"
    Offered(..) => "badge-warning"
    Answer(..) => "badge-success"
    Refused(..) => "badge-error"
  }
  let word = match op {
    Send(..) => "send"
    Intent(..) => "intent"
    Offered(..) => "offered"
    Answer(..) => "answer"
    Refused(..) => "refused"
  }
  // The WHOLE class list, because `:class` replaces the written one rather
  // than adding to it — so a computed class and a static class cannot share an
  // element, and the hook a test selects on has to be in here too.
  (word, "badge badge-sm row-verb \{colour}")
}

///|
/// What a row calls the thing that happened.
///
/// A refusal's name is what was ASKED FOR, not the code: the code is the badge,
/// and a reader scanning a column of names wants the same kind of word in all
/// of them.
fn name_of(op : @trace.Op) -> String {
  match op {
    Send(name~, ..) | Intent(name~, ..) | Offered(name~, ..) => name
    Answer(nth~, answer~) => {
      let word = match answer {
        Ok(_) => "ok"
        Failed(_) => "failed"
        Pass => "pass"
      }
      // The handler's index, and only when it is not the first: a chain of one
      // is the ordinary case and does not need a number on it.
      if nth == 0 {
        word
      } else {
        "\{word} #\{nth}"
      }
    }
    Refused(asked~, ..) => asked
  }
}

///|
/// The arguments, on one line.
///
/// Compact and lossy on purpose: this is the closed row, and a reader who
/// wants the whole value opens it. `to_display_string` is the framework's own
/// short form, so a row and a `@text` of the same value agree.
fn args_of(op : @trace.Op) -> String {
  let vs : Array[@tutuca.Value] = match op {
    Send(args~, ..) | Intent(args~, ..) | Offered(args~, ..) => args
    Answer(answer~, ..) =>
      match answer {
        Ok(v) | Failed(v) => [v]
        Pass => []
      }
    Refused(sentence~, ..) => if sentence == "" { [] } else { [Str(sentence)] }
  }
  vs.map(v => v.to_display_string()).join(", ")
}

///|
/// How deep in the causal chain an event sits.
///
/// Walked through `parent`, which is the link the whole recording is threaded
/// on: without it a cascade of twelve sends from one click is twelve unrelated
/// rows. Bounded, because a malformed or hand-edited file can point a parent at
/// a descendant and a walk over that does not terminate.
fn depths_of(events : Array[@trace.Event]) -> Map[Int, Int] {
  let by_seq : Map[Int, @trace.Event] = Map([])
  for e in events {
    by_seq[e.seq] = e
  }
  let out : Map[Int, Int] = Map([])
  for e in events {
    let mut d = 0
    let mut cur = e.parent
    while cur != 0 && d < 32 {
      d = d + 1
      cur = match by_seq.get(cur) {
        Some(p) => p.parent
        None => 0
      }
    }
    out[e.seq] = d
  }
  out
}

///|
/// One event as a row.
///
/// `after` is prebuilt as a value inspector rather than kept as data, for the
/// reason every other builder here does it: an instance in state renders
/// through its own component, and building it at render time would mean the
/// row holding a function.
pub fn Inspector::trace_row(
  self : Inspector,
  e : @trace.Event,
  depth? : Int = 0,
  current? : Bool = false,
) -> @tutuca.Value {
  let (verb, verb_class) = verb_of(e.op)
  let after = match e.after {
    Some(j) => self.inspect_value(@tutuca.Value::from_json(j))
    None => Null
  }
  self.make_("TraceRow", args={
    "seq": Num(e.seq.to_double()),
    "turn": Num(e.turn.to_double()),
    "walk": Num(e.walk.to_double()),
    "hasWalk": Bool(e.walk != 0),
    "verb": Str(verb),
    "verbClass": Str(verb_class),
    "name": Str(name_of(e.op)),
    "place": Str(if e.at.label() == "" { "(root)" } else { e.at.label() }),
    "args": Str(args_of(e.op)),
    "input": Bool(e.input),
    "rowClass": Str(
      "trace-row flex flex-col gap-1 rounded border px-2 py-1 text-sm " +
      (if e.input {
        "border-primary/40 bg-primary/5"
      } else {
        "border-base-content/10"
      }),
    ),
    "depth": Num(depth.to_double()),
    "current": Bool(current),
    "after": after,
    "hasAfter": Bool(e.after is Some(_)),
    "open": Bool(false),
  })
}

///|
/// A recording's events as a log.
///
/// `at` marks the row a viewer is parked on, so a step control has something to
/// point at; `inputs_only` drops what the app did for itself, which is the view
/// a person takes when they are about to hand the file to somebody else.
pub fn Inspector::trace_log(
  self : Inspector,
  t : @trace.Trace,
  at? : Int = -1,
  inputs_only? : Bool = false,
  turn? : Int = 0,
) -> @tutuca.Value {
  let depths = depths_of(t.events)
  let rows : Array[@tutuca.Value] = []
  for i, e in t.events {
    if inputs_only && !e.input {
      continue
    }
    if turn != 0 && e.turn != 0 && e.turn != turn {
      continue
    }
    rows.push(
      self.trace_row(e, depth=depths.get(e.seq).unwrap_or(0), current=i == at),
    )
  }
  self.make_("TraceLog", args={
    "rows": List(rows),
    "hasRows": Bool(!rows.is_empty()),
    "inputsOnly": Bool(inputs_only),
    "turn": Num(turn.to_double()),
    "emptyHint": Str(
      if t.events.is_empty() {
        "Nothing was recorded."
      } else {
        "Every event is filtered out by the current view."
      },
    ),
  })
}

///|
/// What a recording says about itself.
pub fn Inspector::trace_header(
  self : Inspector,
  t : @trace.Trace,
) -> @tutuca.Value {
  self.make_("TraceHeader", args={
    "component": Str(
      if t.origin.component == "" {
        "(unnamed)"
      } else {
        t.origin.component
      },
    ),
    "module": Str(t.origin.module_),
    "example": Str(t.origin.example),
    "fingerprint": Str(t.origin.fingerprint),
    "events": Num(t.events.length().to_double()),
    "inputs": Num(t.input_count().to_double()),
    "turns": Num(t.turns().length().to_double()),
    "relocatedFrom": Str(t.relocated_from.map(p => p.label()).join(" › ")),
    "isRelocated": Bool(!t.relocated_from.is_empty()),
    "compacted": Bool(t.compacted),
  })
}

///|
/// The places a recording is ABOUT, as relocation candidates.
///
/// The recording's own places and not every component that happens to exist:
/// a picker offering somewhere nothing ever happened is a picker offering an
/// empty trace. `mountable` is answered from the snapshot, because a cut onto
/// a list is a correct cut and an unmountable result, and saying so before the
/// click is cheaper than saying it after.
pub fn Inspector::trace_places(
  self : Inspector,
  t : @trace.Trace,
  selected? : String,
  heading? : String = "Relocate to",
  empty_hint? : String = "This recording touched nothing below the root.",
) -> @tutuca.Value {
  let counts : Map[String, Int] = Map([])
  for e in t.events {
    let k = e.at.label()
    counts[k] = counts.get(k).unwrap_or(0) + 1
  }
  let places : Array[@tutuca.Value] = []
  for place in t.places() {
    let label = place.label()
    let cut = @trace.cut_root(t.root, place)
    let component = match cut {
      Some(Object(m)) =>
        match m.get(@tutuca.component_key) {
          Some(String(s)) => s
          _ => ""
        }
      _ => ""
    }
    places.push(
      self.make_("TracePlace", args={
        "label": Str(label),
        "display": Str(if label == "" { "(the whole thing)" } else { label }),
        "component": Str(component),
        "events": Num(counts.get(label).unwrap_or(0).to_double()),
        "depth": Num(place.depth().to_double()),
        // `None` and not `""`: the ROOT's label is the empty string, so a
        // default of `""` would show the whole thing as chosen before anybody
        // chose anything.
        "selected": Bool(selected is Some(sel) && sel == label),
        "rowClass": Str(
          "trace-place text-left rounded px-2 py-1 text-sm flex items-center gap-2 hover:bg-base-200 " +
          (if selected is Some(sel) && sel == label {
            "bg-primary/10 ring-1 ring-primary/40"
          } else {
            ""
          }),
        ),
        "mountable": Bool(component != ""),
      }),
    )
  }
  self.make_("TracePlaces", args={
    "places": List(places),
    "hasPlaces": Bool(!places.is_empty()),
    "selected": Str(selected.unwrap_or("")),
    "heading": Str(heading),
    "emptyHint": Str(empty_hint),
  })
}

///|
/// The components under something somebody clicked, offered as places to cut to.
///
/// The same list as `trace_places` and built the same way, from a different
/// source: `@render.components_at` reads the ancestry back out of the DOM
/// markers the renderer stamped, so "this row" can be pointed at rather than
/// spelled. `counts` is the recording, so a candidate can say how much of it is
/// about that place — a component nothing ever happened in is still offered,
/// and saying it holds nothing is better than hiding it.
///
/// `cut` says which addresses would yield something mountable; a candidate that
/// would not is marked rather than dropped, for the same reason.
pub fn Inspector::place_candidates(
  self : Inspector,
  crossings : Array[(String, String)],
  t : @trace.Trace,
  selected? : String,
) -> @tutuca.Value {
  let counts : Map[String, Int] = Map([])
  for e in t.events {
    let k = e.at.label()
    counts[k] = counts.get(k).unwrap_or(0) + 1
  }
  let places : Array[@tutuca.Value] = []
  for c in crossings {
    let (label, component) = c
    let depth = if label == "" { 0 } else { label.split(".").count() }
    places.push(
      self.make_("TracePlace", args={
        "label": Str(label),
        "display": Str(if label == "" { "(the whole thing)" } else { label }),
        "component": Str(component),
        "events": Num(counts.get(label).unwrap_or(0).to_double()),
        "depth": Num(depth.to_double()),
        // `None` and not `""`: the ROOT's label is the empty string, so a
        // default of `""` would show the whole thing as chosen before anybody
        // chose anything.
        "selected": Bool(selected is Some(sel) && sel == label),
        "rowClass": Str(
          "trace-place text-left rounded px-2 py-1 text-sm flex items-center gap-2 hover:bg-base-200 " +
          (if selected is Some(sel) && sel == label {
            "bg-primary/10 ring-1 ring-primary/40"
          } else {
            ""
          }),
        ),
        "mountable": Bool(component != ""),
      }),
    )
  }
  self.make_("TracePlaces", args={
    "places": List(places),
    "hasPlaces": Bool(!places.is_empty()),
    "selected": Str(selected.unwrap_or("")),
    "heading": Str("Components under what you clicked"),
    "emptyHint": Str("Nothing the app rendered is there."),
  })
}

///|
/// The scope words, in one place: the label a bar shows and the value a host
/// reads back are the same three strings, and spelling them twice is how they
/// stop agreeing.
pub fn trace_scope_label(scope : String) -> String {
  match scope {
    "section" => "the active section"
    "example" => "this example"
    _ => "the whole storybook"
  }
}

///|
fn pick_class(scope : String, want : String) -> String {
  "btn btn-sm pick-\{want} " +
  (if scope == want { "btn-primary" } else { "btn-outline" })
}

///|
/// The recorder, as a control.
pub fn Inspector::recorder_bar(
  self : Inspector,
  recording? : Bool = false,
  scope? : String = "all",
  events? : Int = 0,
  turns? : Int = 0,
  has_trace? : Bool = false,
  picking? : Bool = false,
) -> @tutuca.Value {
  self.make_("RecorderBar", args={
    "recording": Bool(recording),
    "scope": Str(scope),
    "scopeLabel": Str(trace_scope_label(scope)),
    "allClass": Str(pick_class(scope, "all")),
    "sectionClass": Str(pick_class(scope, "section")),
    "exampleClass": Str(pick_class(scope, "example")),
    "events": Num(events.to_double()),
    "turns": Num(turns.to_double()),
    "hasTrace": Bool(has_trace),
    "picking": Bool(picking),
  })
}

///|
fn tab_class(name : String, on : Bool) -> String {
  "btn btn-xs btn-ghost tab-\{name} " + (if on { "btn-active" } else { "" })
}

///|
/// The whole screen: the bar, and — once there is something to read — the
/// header, the picker and the log.
///
/// Recording and reading are two tabs because they are two activities. While a
/// session is being recorded nobody is reading it, and a reader is not about to
/// click the app.
pub fn Inspector::trace_panel(
  self : Inspector,
  trace? : @trace.Trace,
  tab? : String = "record",
  recording? : Bool = false,
  scope? : String = "all",
  picking? : Bool = false,
  selecting? : Bool = false,
  at? : Int = -1,
  selected_place? : String,
  inputs_only? : Bool = false,
  places? : @tutuca.Value,
) -> @tutuca.Value {
  let has_trace = trace is Some(_)
  let empty = @trace.Trace::new(root=Json::null())
  let t = trace.unwrap_or(empty)
  self.make_("TracePanel", args={
    "bar": self.recorder_bar(
      recording~,
      scope~,
      events=t.events.length(),
      turns=t.turns().length(),
      has_trace~,
      picking~,
    ),
    "header": self.trace_header(t),
    // The recording's own places, unless a caller has a different list to
    // offer — which is what selection mode hands in.
    "places": places.unwrap_or(self.trace_places(t, selected?=selected_place)),
    "log": self.trace_log(t, at~, inputs_only~),
    "tab": Str(tab),
    "hasTrace": Bool(has_trace),
    "showTrace": Bool(has_trace && tab == "trace"),
    "selecting": Bool(selecting),
    "selectLabel": Str(
      if selecting {
        "Click an element…"
      } else {
        "Pick a component"
      },
    ),
    "recordTabClass": Str(tab_class("record", tab == "record")),
    "traceTabClass": Str(tab_class("trace", tab == "trace")),
    "selectTabClass": Str(tab_class("select", selecting)),
    "at": Num((at + 1).to_double()),
    "total": Num(t.events.length().to_double()),
  })
}

// --- the components ----------------------------------------------------------

///|
fn trace_row_comp() -> @component.Component {
  trace_row_component()
}

///|
fn trace_log_comp() -> @component.Component {
  trace_log_component()
}

///|
fn trace_header_comp() -> @component.Component {
  trace_header_component()
}

///|
fn trace_place_comp() -> @component.Component {
  trace_place_component()
}

///|
fn trace_places_comp() -> @component.Component {
  trace_places_component()
}

///|
fn recorder_bar_comp() -> @component.Component {
  recorder_bar_component()
}

///|
fn trace_panel_comp() -> @component.Component {
  trace_panel_component()
}
