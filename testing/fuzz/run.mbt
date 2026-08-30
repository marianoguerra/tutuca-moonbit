// Sending it: one dispatch at a time, against a live app, reading back what
// the component became.

///|
/// What one dispatch did.
pub(all) struct Step {
  /// What was sent.
  dispatch : Action
  /// Everything the runtime refused while it was delivered.
  ///
  /// A refusal is not a failure. It is the runtime declining a transition
  /// whose precondition did not hold, which is the guard working — and it is
  /// the ONLY place a decline is visible, because the transition simply does
  /// not happen and "nothing changed" is what a handler with nothing to do
  /// looks like too.
  refused : Array[@tutuca.Refusal]
  /// The invariants that do NOT hold in the settled state, by name.
  ///
  /// Empty is the good answer, and it is the answer for almost every dispatch
  /// — because the runtime already enforces a compiled invariant, abandoning
  /// the transition and raising a `Refusal` with `code: Invariant` instead of
  /// letting the state land (see `component/invariant_test.mbt`). So a name
  /// here does not mean "a rule was broken and the runtime told you". It means
  /// the opposite: a rule the BLOCK declares does not hold in a state the
  /// component actually reached, and nothing stopped it. Either the rule never
  /// made it into the component's method bucket, or something wrote the state
  /// without going through a transition.
  broke : Array[String]
  /// Rules the runtime declined by name where the interpreted rule disagrees.
  ///
  /// The differential half, and the reason a run reads the block rather than
  /// trusting the component: on one side `@tscript.parse_bool` lowers the
  /// rule's source to a `@core.Val` and `Val::eval` answers it over the state
  /// as it stood; on the other is the guard `gen-views` compiled from the same
  /// line, whose verdict arrives as a `Refusal` carrying the rule's name. They
  /// agree, or one of them is wrong about the component's own contract — and
  /// the two only diverge on the states nobody thought to write down.
  disagreed : Array[String]
  /// The component's fields once the cascade settled.
  after : Map[String, @tutuca.Value]
  /// How many renders it caused. Usually 1 — the loop batches one morph per
  /// drained cascade — and 0 for a dispatch that changed nothing.
  renders : Int
}

///|
/// How a run ended.
pub(all) enum Outcome {
  /// Every step ran and every invariant held.
  Held
  /// An invariant does not hold in the state step `at` settled at, and nothing
  /// refused the transition that got there. `rule` names it and `sentence` is
  /// the rule's own `format` — the words the author wrote for exactly this
  /// moment, which is why they are carried rather than recomposed.
  Broke(rule~ : String, sentence~ : String, at~ : Int)
  /// The interpreted rule and the compiled one disagreed at step `at`.
  ///
  /// A distinct outcome from `Broke` because it is a distinct bug: `Broke`
  /// says a rule is not enforced, and this says two readings of one
  /// declaration do not mean the same thing.
  Disagreed(rule~ : String, at~ : Int)
  /// The run could not start: no plan, or the component would not mount.
  Stuck(String)
} derive(Eq, @debug.Debug)

///|
/// A finished run.
pub(all) struct Run {
  outcome : Outcome
  /// The steps that actually ran — the whole script when it held, and
  /// everything up to and including the breaking one when it did not.
  steps : Array[Step]
  /// The script as drawn, which is longer than `steps` after a break.
  script : Array[Action]
  seed : UInt64
}

///|
/// The dispatches that reproduce this run's outcome — its failing prefix.
///
/// The whole script when it held, since holding is about all of it.
pub fn Run::reproducer(self : Run) -> Array[Action] {
  match self.outcome {
    Broke(at~, ..) | Disagreed(at~, ..) => self.script[:at + 1].to_owned()
    _ => self.script
  }
}

///|
/// Where the driven component's value is read from.
///
/// A run against a component mounted AS the root reads `drive_value` and is
/// done. A run inside a host that mounts many — the storybook's gallery is one
/// app with every story under it — is dispatching at a place, and the value at
/// that place is what its rules are about. Reading the root there would ask
/// `neverEmpty` of the gallery shell, which has no `values` and is not the
/// thing being driven.
///
/// A closure and not a value, because it is re-read after every step: the
/// point of a run is that the component changes.
pub(all) struct Reader(() -> @tutuca.Value)

///|
/// The component's fields, as the map a rule reads.
///
/// A driven component answers `drive_value` with the root Value, which is an
/// `Obj` for a typed component and a `Map` for a value-level one. Both reach a
/// rule as the same fields map, and going through `obj_schema` rather than
/// guessing is what makes the second case honest: the fields are the ones the
/// component DECLARES, in its own order, with an absent one as `Null` rather
/// than missing.
pub fn[N] settled(
  h : @harness.Harness[N],
  read? : Reader,
) -> Map[String, @tutuca.Value] {
  let v = match read {
    Some(Reader(f)) => f()
    None => h.drive_value()
  }
  match v {
    Map(m) => m
    Obj(o) => {
      let out : Map[String, @tutuca.Value] = Map([])
      guard o.obj_schema() is Some(sc) else { return out }
      for f in sc.fields {
        out[f.name] = o.obj_field(f.name).unwrap_or(Null)
      }
      out
    }
    _ => Map([])
  }
}

///|
/// Send one dispatch at `at` and read back what it did.
///
/// `at` is the empty path for a component mounted as the root, and the story's
/// own place inside a gallery — the same addressing the trace recorder uses
/// (`Place::to_steps` -> `DispatchPath::of_steps`).
///
/// Unbounded in `N`, which is worth noticing: driving a component and reading
/// its state back touches the transactor and the root Value and never the
/// tree, so this half of a fuzz run is the same code on memdom, on a browser
/// node, and on a node type nobody has written yet. Only the harness's
/// SELECTOR verbs need `DomWalk`, and a generated script names messages rather
/// than selectors.
pub fn[N] Plan::step(
  self : Plan,
  h : @harness.Harness[N],
  d : Action,
  at? : @tutuca.DispatchPath = @tutuca.DispatchPath::new(),
  read? : Reader,
) -> Step raise {
  let renders_before = h.render_count()
  // The state a PRECONDITION is asked against is the one the dispatch arrived
  // at, so it has to be read before the dispatch and not after.
  let before = settled(h, read?)
  // Settling is INSIDE the capture, and that is not a detail: a contract is
  // checked as the transaction COMMITS, so the refusal an abandoned mutator
  // raises happens during `settle` and not during the push. Capturing only the
  // push returns an empty list, which reads exactly like a component that
  // refused nothing.
  //
  // Settling at all is what makes the read below meaningful: a dispatch can
  // cascade, and the state halfway through a cascade is not a state the
  // component was ever in.
  let refused = @harness.refusals_while(() => {
    match d {
      Message(Receive(name, args)) =>
        h.app.transactor.push_send(at, name, args) |> ignore
      Message(Intent(name, args)) =>
        h.app.transactor.push_intent(at, name, args) |> ignore
      InternalMutator(Receive(name, args)) =>
        h.app.transactor.push_send(at, name, args, provenance=Diagnostic)
        |> ignore
      InternalMutator(Intent(name, args)) =>
        h.app.transactor.push_intent(at, name, args) |> ignore
      SetProperty(name, value) =>
        h.app.transactor.set_property(at, name, value) |> ignore
    }
    h.app.transactor.settle() |> ignore
  })
  let after = settled(h, read?)
  {
    dispatch: d,
    refused,
    broke: self.rules.broken(after),
    disagreed: self.disagreements(refused, before),
    after,
    renders: h.render_count() - renders_before,
  }
}

///|
/// Rules the runtime declined where the interpreted rule says they held.
///
/// PRECONDITIONS only, and the exclusion is the whole subtlety. A
/// precondition is asked against the state the dispatch ARRIVED at, which is
/// the state passed in here, so the two readings are looking at the same
/// thing and can be compared. An invariant is asked against the state the
/// transition PROPOSED — the successor, which was then abandoned and which
/// the runtime never hands out — so `before` is not what it judged. Checking
/// an invariant refusal here would report a disagreement on every one of
/// them, since the state a component is sitting in is precisely the state its
/// invariants hold in.
///
/// One direction, too. "The runtime said no, and the block says yes" is always
/// checkable. The other direction — the runtime SHOULD have declined and did
/// not — needs to know which handler asks which rule, and a `requires` sits on
/// the handler's header in the SCRIPT block, not in the spec block. A run has
/// the spec block and nothing else, so it makes the claim it can support.
///
/// A rule the interpreter cannot answer (`Rules::holds` is None — not lowered,
/// or a field the state does not carry) is skipped rather than reported: no
/// opinion is not a disagreement.
fn Plan::disagreements(
  self : Plan,
  refused : Array[@tutuca.Refusal],
  before : Map[String, @tutuca.Value],
) -> Array[String] {
  let out : Array[String] = []
  for r in refused {
    guard r.code is Precondition else { continue }
    guard r.rule != "" else { continue }
    // `true` means the block says the rule HELD, and the runtime declined on
    // it anyway.
    if self.rules.holds(r.rule, before) is Some(true) && !out.contains(r.rule) {
      out.push(r.rule)
    }
  }
  out
}

///|
/// Run a whole script, stopping at the first broken invariant.
///
/// Stopping is not an optimization. An invariant that is broken and then
/// repaired by the next message is still broken, and a run that read only the
/// final state would call that a pass — so the rules are asked after EVERY
/// step, and the first one that fails is the answer.
pub fn[N] Plan::run(
  self : Plan,
  h : @harness.Harness[N],
  script : Array[Action],
  seed? : UInt64 = 0,
  at? : @tutuca.DispatchPath = @tutuca.DispatchPath::new(),
  read? : Reader,
) -> Run raise {
  let steps : Array[Step] = []
  for i, d in script {
    let s = self.step(h, d, at~, read?)
    steps.push(s)
    // `broke` first: a rule nothing enforces is a worse answer than two
    // readings that disagree, and a state that broke one usually disagrees
    // about it too.
    if s.broke.length() > 0 {
      let rule = s.broke[0]
      return {
        outcome: Broke(rule~, sentence=self.sentence_of(rule), at=i),
        steps,
        script,
        seed,
      }
    }
    if s.disagreed.length() > 0 {
      return {
        outcome: Disagreed(rule=s.disagreed[0], at=i),
        steps,
        script,
        seed,
      }
    }
  }
  { outcome: Held, steps, script, seed, }
}

///|
/// Run `steps` dispatches, each drawn against the state the last one left.
///
/// The state-aware twin of `run`, and the one a component with a `where`
/// wants. `run` takes a script sampled before the first dispatch, when no
/// field has a value — so `setCurrentIndex` could only ever be drawn at
/// `Int`'s edges, and almost every step was a state no interaction could
/// reach. Drawing per step is what lets the same declaration produce an index
/// that is actually in range.
///
/// The outcomes and the stopping rule are `run`'s, unchanged: the rules are
/// asked after every step and the first break is the answer.
///
/// `Run.script` is the dispatches that were ACTUALLY SENT, recorded as they
/// were drawn. That is what the shrinker needs — a shortened script replayed
/// against a different state would redraw different arguments, so shrinking
/// has to work on the concrete dispatches rather than on the seed.
pub fn[N] Plan::run_live(
  self : Plan,
  h : @harness.Harness[N],
  steps~ : Int,
  seed? : UInt64 = 0,
  at? : @tutuca.DispatchPath = @tutuca.DispatchPath::new(),
  read? : Reader,
) -> Run raise {
  let out : Array[Step] = []
  let script : Array[Action] = []
  for i in 0..<steps {
    // The state the NEXT dispatch is drawn against: what the component is
    // sitting in right now, which after step zero is what the run itself put
    // there.
    let now = settled(h, read?)
    guard self.next_at(now, seed~, step=i) is Some(d) else { break }
    script.push(d)
    let s = self.step(h, d, at~, read?)
    out.push(s)
    if s.broke.length() > 0 {
      let rule = s.broke[0]
      return {
        outcome: Broke(rule~, sentence=self.sentence_of(rule), at=i),
        steps: out,
        script,
        seed,
      }
    }
    if s.disagreed.length() > 0 {
      return {
        outcome: Disagreed(rule=s.disagreed[0], at=i),
        steps: out,
        script,
        seed,
      }
    }
  }
  { outcome: Held, steps: out, script, seed, }
}

///|
/// The words a rule says when it does not hold.
///
/// Public because a caller that reports a break it found itself — the
/// storybook steps one dispatch at a time and decides the outcome as it goes,
/// rather than calling `run` — needs the same sentence `run` would have used.
///
/// A rule's `format` is the half nobody can reconstruct afterwards — it names
/// the count that made it fail, from the state that failed it — so a break
/// reports the author's sentence rather than a rendering of the expression.
/// Falls back to the rule's own EXPRESSION when the block declared no format:
/// `(len .values) > 0` is a worse sentence than the author's, and a better one
/// than the bare name.
pub fn Plan::sentence_of(self : Plan, rule : String) -> String {
  for r in self.def.rules {
    if r.name == rule {
      return if r.format != "" {
        unquote(r.format)
      } else if r.source != "" {
        r.source
      } else {
        rule
      }
    }
  }
  rule
}

///|
/// A block-language string literal, as the sentence it spells.
///
/// A `format` is kept as SOURCE — `'…'`, or `$'…'` for one that interpolates —
/// because that is what the block says and `statedef` does not evaluate. The
/// delimiters are not part of the sentence, so they go.
///
/// An interpolated format keeps its `{…}` placeholders: filling them in is the
/// runtime's job, and the runtime already did it on the `Refusal` when there
/// was one to fill. What this answers is the case where there was NOT one —
/// a rule nothing enforced — and there the template is the honest answer.
fn unquote(s : String) -> String {
  let body = if s.has_prefix("$") { s[1:].to_owned() } else { s }
  for q in ["'", "\""] {
    if body.has_prefix(q) && body.has_suffix(q) && body.length() >= 2 {
      return body[1:body.length() - 1].to_owned()
    }
  }
  body
}
