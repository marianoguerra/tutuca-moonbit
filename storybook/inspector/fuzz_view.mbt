// A property run, as something to look at.
//
// The components are in fuzz_view.html; this is the projection from
// `testing/fuzz`'s values onto them, and it is a projection for the same
// reason `trace_view.mbt` is one: a tutuca component holds STATE, and a run is
// a value the host owns. What crosses the line is a list of rows.
//
// Everything decided here was decided when the step ran. A row recomputing any
// of it would be a second opinion about what happened — so the verb, the
// refusal, the break and the render count are read straight off the `Step`,
// and only the words and the classes are chosen.

///|
/// The word a dispatch reads as, and the badge it wears.
///
/// Two verbs, where a trace row has five: a generated script contains messages
/// and intents and nothing else. The offers, answers and refusals a recording
/// carries are things the RUNTIME did, and those reach a row here as badges on
/// the dispatch that caused them rather than as rows of their own — because a
/// script is a list of what was SENT, and a reader stepping through it is
/// counting the sends.
fn fuzz_verb_of(d : @fuzz.Action) -> (String, String) {
  let (word, colour) = match d {
    Message(Receive(_, _)) => ("send", "badge-neutral")
    Message(Intent(_, _)) => ("intent", "badge-info")
    SetProperty(_, _) => ("set", "badge-accent")
    SetField(_, _) => ("write", "badge-warning")
  }
  // The WHOLE class list, because `:class` replaces the written one rather
  // than adding to it — so the hook a test selects on has to be in here too.
  (word, "badge badge-sm row-verb \{colour}")
}

///|
/// A dispatch's name.
fn fuzz_name_of(d : @fuzz.Action) -> String {
  match d {
    Message(Receive(name, _)) | Message(Intent(name, _)) => name
    SetProperty(name, _) => name
    SetField(name, _) => name
  }
}

///|
/// A dispatch's arguments, on one line.
///
/// Compact and lossy on purpose: this is the closed row, and a reader who
/// wants the whole value opens it. `to_display_string` is the framework's own
/// short form, so a row and a `@text` of the same value agree.
fn fuzz_args_of(d : @fuzz.Action) -> String {
  let args = match d {
    Message(Receive(_, a)) | Message(Intent(_, a)) => a
    SetProperty(_, value) => [value]
    SetField(_, v) => [v]
  }
  args.map(v => v.to_display_string()).join(", ")
}

///|
/// One step of a run.
///
/// The border says the worst thing that happened on it, in the order the
/// driver ranks them: a rule nothing enforces beats two readings that
/// disagree, and both beat a refusal — which is not a failure at all.
pub fn Inspector::fuzz_row(
  self : Inspector,
  step : @fuzz.Step,
  at~ : Int,
  current? : Bool = false,
) -> @tutuca.Value {
  let (verb, verb_class) = fuzz_verb_of(step.dispatch)
  let broke = step.broke.length() > 0
  let disagreed = step.disagreed.length() > 0
  let refused = step.refused.length() > 0
  let border = if broke {
    "border-error"
  } else if disagreed {
    "border-secondary"
  } else if refused {
    "border-warning/40"
  } else {
    "border-base-content/10"
  }
  self.make_("FuzzRow", args={
    "at": Num(at.to_double()),
    "name": Str(fuzz_name_of(step.dispatch)),
    "args": Str(fuzz_args_of(step.dispatch)),
    "verb": Str(verb),
    "verbClass": Str(verb_class),
    "renders": Num(step.renders.to_double()),
    "refused": Bool(refused),
    // A refusal does not always name a rule: a dispatch nothing claims is
    // refused too, with `Unhandled` and an empty `rule`. The badge falls back
    // to the CODE there, because a badge with no text is a badge a reader
    // cannot read and looks like a rendering bug rather than a finding.
    "refusedRule": Str(
      if refused {
        refusal_label(step.refused[0])
      } else {
        ""
      },
    ),
    "refusedSentence": Str(if refused { step.refused[0].sentence } else { "" }),
    "broke": Bool(broke),
    "brokeRule": Str(if broke { step.broke[0] } else { "" }),
    "disagreed": Bool(disagreed),
    "rowClass": Str(
      "fuzz-row flex flex-col gap-1 rounded border px-2 py-1 text-sm " +
      border +
      (if current { " bg-base-200" } else { "" }),
    ),
    "current": Bool(current),
    "after": self.inspect_value(Map(step.after)),
    "open": Bool(false),
  })
}

///|
/// The steps that have run, with the cursor marked.
pub fn Inspector::fuzz_log(
  self : Inspector,
  steps : Array[@fuzz.Step],
  at? : Int = -1,
  planned? : Int = 0,
) -> @tutuca.Value {
  let rows : Array[@tutuca.Value] = []
  for i, s in steps {
    rows.push(self.fuzz_row(s, at=i, current=i == at))
  }
  self.make_("FuzzLog", args={
    "rows": List(rows),
    "hasRows": Bool(!rows.is_empty()),
    "emptyHint": Str(
      if planned > 0 {
        "A script of \{planned} dispatches is drawn. Press Play, Step or Burst."
      } else {
        "Nothing drawn yet."
      },
    ),
  })
}

///|
/// The knobs a run is addressed by.
pub fn Inspector::fuzz_controls(
  self : Inspector,
  seed~ : String,
  steps~ : String,
  source~ : String,
  playing? : Bool = false,
  can_run? : Bool = true,
  no_plan_hint? : String = "",
  can_draw? : Bool = true,
  no_draw_hint? : String = "",
) -> @tutuca.Value {
  self.make_("FuzzControls", args={
    "seed": Str(seed),
    "steps": Str(steps),
    "source": Str(source),
    "publicClass": Str(source_class("public", source)),
    "messagesClass": Str(source_class("messages", source)),
    "propertiesClass": Str(source_class("properties", source)),
    "fieldsClass": Str(source_class("fields", source)),
    "playing": Bool(playing),
    "canRun": Bool(can_run),
    "noPlanHint": Str(no_plan_hint),
    // The two states NEST: no plan is also nothing to draw, so a caller that
    // says the first need not say the second. Derived here rather than asked
    // of every caller, because the pair is what the panel's own invariants are
    // written against — a `canRun: false, canDraw: true` panel would offer
    // buttons for a plan that does not exist.
    "canDraw": Bool(can_run && can_draw),
    "noDrawHint": Str(if can_run { no_draw_hint } else { no_plan_hint }),
  })
}

///|
fn source_class(name : String, cur : String) -> String {
  "btn btn-xs src-\{name} " +
  (if name == cur { "btn-primary" } else { "btn-ghost" })
}

///|
/// What the run came to, in the words the declaration used.
///
/// The three verdicts are three different claims, and the badge says which:
/// `held` is a claim about the ENFORCEMENT — a generated mutator that would
/// break a rule was abandoned and the state never landed — `broke` says a
/// declared rule is enforced by nothing, and `disagreed` says the block's
/// reading of a rule and the compiled one do not mean the same thing.
pub fn Inspector::fuzz_verdict(
  self : Inspector,
  outcome? : @fuzz.Outcome,
  unchecked? : Array[(String, String)] = [],
  reproducer? : Array[@fuzz.Action] = [],
) -> @tutuca.Value {
  let (kind, colour, headline, sentence, rule, at) = match outcome {
    None => ("none", "badge-ghost", "", "", "", -1)
    Some(Held) =>
      (
        "held", "badge-success", "every invariant held, and the runtime is what held them",
        "", "", -1,
      )
    Some(Broke(rule~, sentence~, at~)) =>
      (
        "broke", "badge-error", "a declared rule does not hold, and nothing stopped it",
        sentence, rule, at,
      )
    Some(Disagreed(rule~, at~)) =>
      (
        "disagreed", "badge-secondary", "the block's reading of this rule and the compiled one disagree",
        "", rule, at,
      )
    Some(Stuck(why)) => ("stuck", "badge-warning", why, "", "", -1)
  }
  let lines : Array[@tutuca.Value] = []
  for i, d in reproducer {
    lines.push(
      self.fuzz_row(
        {
          dispatch: d,
          refused: [],
          broke: [],
          disagreed: [],
          after: Map([]),
          renders: 0,
        },
        at=i,
      ),
    )
  }
  self.make_("FuzzVerdict", args={
    "kind": Str(kind),
    "badgeClass": Str("badge badge-sm verdict-kind \{colour}"),
    "headline": Str(headline),
    "sentence": Str(sentence),
    "rule": Str(rule),
    "at": Num(at.to_double()),
    "unchecked": Str(unchecked.map(u => "\{u.0} (\{u.1})").join(", ")),
    "hasUnchecked": Bool(!unchecked.is_empty()),
    "reproducer": List(lines),
    "hasReproducer": Bool(!lines.is_empty()),
  })
}

///|
/// The whole pane: the knobs, the verdict, and the script as rows.
pub fn Inspector::fuzz_panel(
  self : Inspector,
  seed~ : String,
  steps~ : String,
  source~ : String,
  run_steps? : Array[@fuzz.Step] = [],
  at? : Int = -1,
  planned? : Int = 0,
  playing? : Bool = false,
  can_run? : Bool = true,
  no_plan_hint? : String = "",
  can_draw? : Bool = true,
  no_draw_hint? : String = "",
  outcome? : @fuzz.Outcome,
  unchecked? : Array[(String, String)] = [],
  reproducer? : Array[@fuzz.Action] = [],
) -> @tutuca.Value {
  self.make_("FuzzPanel", args={
    "controls": self.fuzz_controls(
      seed~,
      steps~,
      source~,
      playing~,
      can_run~,
      no_plan_hint~,
      can_draw~,
      no_draw_hint~,
    ),
    "verdict": self.fuzz_verdict(outcome?, unchecked~, reproducer~),
    "log": self.fuzz_log(run_steps, at~, planned~),
    "hasRun": Bool(!run_steps.is_empty()),
    // 1-based for display: a reader counting steps starts at one.
    "at": Num((at + 1).to_double()),
    "total": Num(planned.to_double()),
  })
}

///|
fn fuzz_row_comp() -> @component.Component {
  fuzz_row_component()
}

///|
fn fuzz_log_comp() -> @component.Component {
  fuzz_log_component()
}

///|
fn fuzz_controls_comp() -> @component.Component {
  fuzz_controls_component()
}

///|
fn fuzz_verdict_comp() -> @component.Component {
  fuzz_verdict_component()
}

///|
fn fuzz_panel_comp() -> @component.Component {
  fuzz_panel_component()
}

///|
/// What a refusal's badge says: its rule, or the code when it names none.
fn refusal_label(r : @tutuca.Refusal) -> String {
  if r.rule != "" {
    return r.rule
  }
  match r.code {
    PathUnresolved => "no such path"
    NoHandler => "unhandled"
    Precondition => "precondition"
    Postcondition => "postcondition"
    Invariant => "invariant"
    // Only reached when the refusal names no field, which a domain refusal
    // always does — so this is the label for a code that in practice arrives
    // labelled. Kept because the match is total and a silent arm is worse.
    OutOfRange => "out of range"
    IntentDepth => "intent depth"
    TypeNotFound => "no such type"
    NoSender => "no sender"
    BadPayload => "bad payload"
  }
}
