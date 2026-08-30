// The Fuzz tab: generated dispatches driven at the story on screen, and the
// shrink that finds the shortest script that still breaks it.
//
// Host code for the reason the recorder is, and one more: driving a generated
// script means pushing at the transactor, and shrinking means remounting the
// component dozens of times. A component can do neither. The shell holds the
// PANEL; this holds the run.

///|
/// A property run over one story, and the story it is about.
///
/// Held by the HOST for the same reason `TraceSession` is, and one more.
/// Driving a generated script means pushing at the transactor, which a
/// component cannot reach; shrinking means remounting the component many
/// times, which a component can do even less. The shell holds the PANEL — a
/// value handed down through `setFuzzPanel` — and this holds the run.
///
/// The whole run is redrawn from `seed` rather than kept as a cursor into a
/// stored generator, which is what lets Reset be exact and what makes the
/// four knobs the run's entire address.
priv struct FuzzSession {
  mut plan : @fuzz.Plan?
  /// The story index the run is about, so the panel goes back to the pane that
  /// started it.
  mut idx : Int
  mut seed : UInt64
  mut steps : Int
  mut source : String
  /// The script as drawn. Redrawn whenever a knob moves, because a row list
  /// that outlived its seed would be a lie about what is going to be sent.
  mut script : Array[@fuzz.Action]
  /// What has run so far, and how far in.
  mut ran : Array[@fuzz.Step]
  mut at : Int
  /// What the next tick should do. `""` is idle.
  ///
  /// Every mode runs on the TICK and none of them runs inside the click that
  /// asked for it, and that is not a scheduling preference — it is what makes
  /// a run able to see its own refusals. A refusal is HELD for the duration of
  /// a dispatch and only the first one escapes ("one dispatch, one record,
  /// however many layers it walked" — `core/refusal.mbt`), so a run driven
  /// from inside a component's own dispatch chain is a run whose refusals are
  /// all deduplicated into the click that started it. Arming and stepping have
  /// to be two different turns.
  mut mode : String
  /// A Play is in flight: one dispatch per animation frame.
  mut playing : Bool
  mut outcome : @fuzz.Outcome?
  /// The shrunk reproducer, once somebody asked for one.
  mut reproducer : Array[@fuzz.Action]
}

///|
fn FuzzSession::new() -> FuzzSession {
  {
    plan: None,
    idx: -1,
    seed: 1,
    steps: 40,
    source: "public",
    mode: "",
    script: [],
    ran: [],
    at: -1,
    playing: false,
    outcome: None,
    reproducer: [],
  }
}

///|
/// The generator source a button names.
fn fuzz_source_of(name : String) -> @fuzz.Source {
  match name {
    "messages" => Declared(BEither)
    "properties" => Properties
    "internal" => InternalMutators
    _ => Public(BEither)
  }
}

///|
/// Everything about a run except the component: forget the steps, keep the
/// knobs.
fn FuzzSession::rearm(self : FuzzSession) -> Unit {
  self.ran = []
  self.at = -1
  self.outcome = None
  self.reproducer = []
  self.script = match self.plan {
    // A component with a `where` draws its dispatches AS IT GOES, against the
    // state each step lands in — an index cannot be drawn in range before the
    // list it indexes has a length. So there is no script to sample up front,
    // and `script` fills in one entry per step instead.
    Some(p) if p.state_aware() => []
    Some(p) => p.script(seed=self.seed, steps=self.steps)
    None => []
  }
}

///|
/// Rebuild the Fuzz panel and hand it down to the pane that owns it.
///
/// The mirror of `push_panel`, and the same shape for the same reason: the
/// host holds the run, so the host is the only thing that can say what the
/// panel shows.
fn[N] push_fuzz_panel(
  app : @app.App[N],
  insp : @inspector.Inspector,
  session : FuzzSession,
) -> Unit {
  guard session.idx >= 0 else { return }
  let panel = insp.fuzz_panel(
    seed=session.seed.to_string(),
    steps=session.steps.to_string(),
    source=session.source,
    run_steps=session.ran,
    at=session.at,
    planned=session.script.length(),
    playing=session.playing,
    can_run=session.plan is Some(_),
    no_plan_hint=if session.plan is Some(_) { "" } else { NO_SPEC_HINT },
    // A plan and an empty source are different states, and the panel says
    // which. A component can declare state, domains and rules and still put
    // nothing in its public API — `receive` in the script block is an
    // implementation, and the `message { … }` block is the declaration — and
    // the old panel answered that with a Play button that did nothing.
    can_draw=match session.plan {
      Some(p) => p.has_inputs()
      None => false
    },
    no_draw_hint=match session.plan {
      Some(p) if !p.has_inputs() => draw_hint(session.source)
      _ => ""
    },
    outcome?=session.outcome,
    unchecked=match session.plan {
      Some(p) => p.unchecked()
      None => []
    },
    reproducer=session.reproducer,
  )
  @sbui.push_panel(app, session.idx, "fuzz", panel)
}

///|
/// The Fuzz panel as it looks before anything has been pressed.
///
/// It resolves the component and derives a plan, which is the only way to know
/// whether the buttons can act — the panel used to claim they could until the
/// first press, so a component with no spec block, or with an empty public
/// API, opened on a full set of controls that did nothing.
fn[N] opening_panel(
  insp : @inspector.Inspector,
  slot : Ref[@app.App[N]?],
  instance : @tutuca.Value,
  read : (String) -> @tutuca.Value,
) -> @tutuca.Value {
  let source = read("fzSource").str(default="public")
  let plan = match slot.val {
    Some(app) =>
      match app.scope.comps.get_comp_for(instance) {
        Some(comp) =>
          @fuzz.Plan::of_component(comp, source=fuzz_source_of(source))
        None => None
      }
    None => None
  }
  insp.fuzz_panel(
    seed=read("fzSeed").str(default="1"),
    steps=read("fzSteps").str(default="40"),
    source~,
    can_run=plan is Some(_),
    no_plan_hint=if plan is Some(_) { "" } else { NO_SPEC_HINT },
    can_draw=match plan {
      Some(p) => p.has_inputs()
      None => false
    },
    no_draw_hint=match plan {
      Some(p) if !p.has_inputs() => draw_hint(source)
      _ => ""
    },
  )
}

///|
/// What a component with no `<script type="tutuca/spec">` block gets told.
const NO_SPEC_HINT : String = "This story's component declares no <script type=\"tutuca/spec\"> block, so there is nothing to derive generators from."

///|
/// Why the chosen source draws nothing, named for the source.
///
/// It says what to DO, twice over: another source may draw (the switcher is
/// right there), and the lasting fix is a declaration in the block.
fn draw_hint(source : String) -> String {
  let what = match source {
    "messages" => "declares no messages"
    "properties" => "declares no writable properties"
    "internal" => "has no fields a generated mutator could write"
    _ => "declares no messages and no writable properties"
  }
  "This story's component \{what}, so this source has nothing to draw. " +
  "A `receive` in the script block is an implementation; the surface is the " +
  "`message { … }` and `property { … }` blocks in the spec. Try another source, " +
  "or declare one."
}

///|
/// Point the session at the story on screen, drawing its plan from the
/// component's own spec block.
///
/// Re-derived on every press rather than cached against the index: a story's
/// instance is replaced as it is driven, and the component behind it is the
/// stable thing — so the plan is cheap to rebuild and impossible to have stale.
fn[N] aim_fuzz(
  app : @app.App[N],
  session : FuzzSession,
  sections : Array[@sb.Section],
) -> Unit {
  let idx = @sbui.active_story(app, sections)
  session.idx = idx
  session.plan = None
  guard idx >= 0 else { return }
  // The component behind the story's instance, resolved through the registry
  // the gallery already shares.
  let inst = @sbui.story_value(app, idx)
  guard app.scope.comps.get_comp_for(inst) is Some(comp) else { return }
  session.plan = @fuzz.Plan::of_component(
    comp,
    source=fuzz_source_of(session.source),
  )
}

///|
/// One dispatch, at the story's own place.
///
/// Returns false when there is nothing left to send — which is what stops a
/// Play rather than a counter kept somewhere else.
fn[N] fuzz_step_once(app : @app.App[N], session : FuzzSession) -> Bool {
  guard session.plan is Some(plan) else { return false }
  let next = session.at + 1
  // How many steps are LEFT differs between the two draws: a sampled script
  // knows its own length, and a live one is bounded by the knob instead.
  let planned = if plan.state_aware() {
    session.steps
  } else {
    session.script.length()
  }
  guard next < planned else { return false }
  // A story lives at `.sN`, so a dispatch is addressed there and not at the
  // root — the same addressing the scoped recorder cuts at.
  let at = @tutuca.DispatchPath::of_steps(story_place(session.idx).to_steps())
  let h = @harness.Harness::over(app, app.root_node)
  // WHERE to read the state back from. The gallery is one app with every story
  // mounted under it, so the ROOT value is the shell — asking `neverEmpty` of
  // that would ask it of a thing with no `values` and get a confident answer
  // about the wrong component. `.sN` is the instance the rules are about, and
  // it is the same field the Story tab renders.
  let read = story_reader(app, session.idx)
  // Drawn now, from the state the last step left, and RECORDED — a reproducer
  // and the shrinker both work on the dispatches that were actually sent,
  // because replaying a shortened script would redraw different arguments.
  if plan.state_aware() {
    let now = @fuzz.settled(h, read~)
    guard plan.next_at(now, seed=session.seed, step=next) is Some(d) else {
      return false
    }
    session.script.push(d)
  }
  let step = plan.step(h, session.script[next], at~, read~) catch {
    _ => return false
  }
  session.ran.push(step)
  session.at = next
  if step.broke.length() > 0 {
    let rule = step.broke[0]
    session.outcome = Some(
      Broke(rule~, sentence=plan.sentence_of(rule), at=next),
    )
    return false
  }
  if step.disagreed.length() > 0 {
    session.outcome = Some(Disagreed(rule=step.disagreed[0], at=next))
    return false
  }
  if next == planned - 1 {
    session.outcome = Some(Held)
    return false
  }
  true
}

///|
/// The two browser effects a run needs, supplied by the host.
///
/// `storybook/ui` never touches the JS FFI — the same split the URL handlers
/// follow, and for the same reason: this package is checked and tested on
/// every backend, and a `globalThis` in it would make that untrue. The host
/// wires these to the page; a headless mount gets the defaults and the tab
/// still works, minus the two things a terminal has no use for.
pub(all) struct FuzzEffects {
  /// Ask the page to call the run's tick export on the next animation frame.
  ///
  /// A call OUT rather than a callback in, because a closure cannot cross into
  /// JS on wasm-gc — which is why every other browser effect in the gallery
  /// has this shape. One shot: the host arms the next frame only while a run
  /// is live, so there is no permanent frame loop.
  arm_frame : () -> Unit
  /// Bracket a step for the profiler, `(name, "start" | "end")`.
  ///
  /// It writes to DevTools' own Timings track rather than collecting a number
  /// here: the measurement is the browser's, and what a run owes it is a
  /// label. No fallback clock, on purpose — a second timebase nobody asked for
  /// is worse than none.
  mark : (String, String) -> Unit
}

///|
/// Effects that do nothing, for a mount with no page under it.
pub fn FuzzEffects::none() -> FuzzEffects {
  { arm_frame: () => (), mark: (_name, _phase) => (), }
}

///|
/// One step, marked for the profiler.
fn[N] fuzz_step_marked(
  app : @app.App[N],
  session : FuzzSession,
  fx : FuzzEffects,
) -> Bool {
  let next = session.at + 1
  let name = if next < session.script.length() {
    match session.script[next] {
      Message(Receive(n, _)) | Message(Intent(n, _)) => n
      SetProperty(n, _) => n
      InternalMutator(Receive(n, _)) | InternalMutator(Intent(n, _)) => n
    }
  } else {
    ""
  }
  if name != "" {
    (fx.mark)(name, "start")
  }
  let more = fuzz_step_once(app, session)
  if name != "" {
    (fx.mark)(name, "end")
  }
  more
}

///|
/// The Fuzz tab's intents, answered here because only the host has a
/// transactor to push at and a scope to remount from.
fn[N] fuzz_handlers(
  app_slot : Ref[@app.App[N]?],
  insp : @inspector.Inspector,
  session : FuzzSession,
  sections : Array[@sb.Section],
  fx : FuzzEffects,
) -> Map[String, Array[@component.IntentFn]] {
  fn with_app(f : (@app.App[N]) -> Unit) -> Unit {
    match app_slot.val {
      Some(app) => f(app)
      None => ()
    }
  }

  {
    // A knob moved. Every one of them invalidates the drawn script, so all
    // three arrive together and the script is redrawn whole — a seed that no
    // longer describes the rows under it is the one state this must not have.
    "fuzzConfig": [
      @component.IntentFn((call, answer) => {
        match call.args {
          [Str(seed), Str(steps), Str(source), ..] => {
            session.seed = @string.parse_uint64(seed) catch {
              _ => session.seed
            }
            session.steps = @string.parse_int(steps) catch {
              _ => session.steps
            }
            session.source = source
          }
          _ => ()
        }
        with_app(app => {
          @sbui.set_panel_fields(app, {
            "fzSeed": Str(session.seed.to_string()),
            "fzSteps": Str(session.steps.to_string()),
            "fzSource": Str(session.source),
          })
          aim_fuzz(app, session, sections)
          session.rearm()
          push_fuzz_panel(app, insp, session)
        })
        answer(Ok(Str(session.source)))
      }),
    ],
    // The three run buttons ARM a mode and nothing more. The work happens on
    // the next tick, outside this dispatch — see `FuzzSession::mode` for why
    // that is a correctness requirement and not a scheduling choice.
    "fuzzStep": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, insp, session, fx, "step", sections))
        answer(Ok(Str("step")))
      }),
    ],
    // The whole script with no yield. What a flame chart wants: settle,
    // render and morph back to back, with no scheduler noise between them.
    "fuzzBurst": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, insp, session, fx, "burst", sections))
        answer(Ok(Str("burst")))
      }),
    ],
    // One dispatch per frame, until the script runs out or something breaks.
    // What a person wants, and what makes a DevTools recording show real
    // layout and paint rather than one blocking call.
    "fuzzPlay": [
      @component.IntentFn((_call, answer) => {
        with_app(app => arm_run(app, insp, session, fx, "play", sections))
        answer(Ok(Bool(true)))
      }),
    ],
    "fuzzStop": [
      @component.IntentFn((_call, answer) => {
        session.playing = false
        session.mode = ""
        with_app(app => push_fuzz_panel(app, insp, session))
        answer(Ok(Bool(false)))
      }),
    ],
    // Back to the story's initial state, script and all. Remounting is what
    // makes it exact: rewinding a component by sending it the reverse of what
    // it received is not a thing that exists.
    "fuzzReset": [
      @component.IntentFn((_call, answer) => {
        session.playing = false
        with_app(app => {
          remount_story(app, session.idx, sections)
          aim_fuzz(app, session, sections)
          session.rearm()
          push_fuzz_panel(app, insp, session)
        })
        answer(Ok(Null))
      }),
    ],
    // The shortest script that still does it.
    //
    // Every candidate runs from a FRESH story, which is why this is the host's
    // and why it ends by putting the story back: shrinking drives the
    // component dozens of times, and what is on screen afterwards must be the
    // reproducer's own result rather than wherever the last candidate landed.
    "fuzzShrink": [
      @component.IntentFn((_call, answer) => {
        with_app(app => {
          guard session.plan is Some(plan) else { return }
          let idx = session.idx
          let failing = match session.outcome {
            Some(Broke(at~, ..)) | Some(Disagreed(at~, ..)) =>
              session.script[:at + 1].to_owned()
            _ => session.script
          }
          let at = @tutuca.DispatchPath::of_steps(story_place(idx).to_steps())
          // Always `Some`: the story is already mounted and this only puts
          // its value back, so unlike a remount that builds a fresh app from a
          // module, there is nothing here that can fail.
          let remount = () => {
            remount_story(app, idx, sections)
            Some(@harness.Harness::over(app, app.root_node))
          }
          session.reproducer = @fuzz.shrink(
            plan,
            failing,
            remount,
            at~,
            read=story_reader(app, idx),
          )
          // Leave the story showing what the reproducer does, not what the
          // last discarded candidate did.
          remount_story(app, idx, sections)
          session.ran = []
          session.at = -1
          session.outcome = None
          session.script = session.reproducer
          while fuzz_step_once(app, session) {

          }
          push_fuzz_panel(app, insp, session)
        })
        answer(Ok(Num(session.reproducer.length().to_double())))
      }),
    ],
  }
}

///|
/// Put a story back the way it was mounted.
///
/// The gallery builds `sN` from the component and the story's args at mount;
/// this is that line again, which is what makes a reset exact rather than
/// approximately undone.
fn[N] remount_story(
  app : @app.App[N],
  idx : Int,
  sections : Array[@sb.Section],
) -> Unit {
  guard idx >= 0 else { return }
  let mut i = 0
  for sec in sections {
    for s in sec.stories {
      if i == idx {
        // Through the REGISTRY and not the root scope: a story's components
        // are registered in a child scope of their own, so same-named
        // components across examples do not collide — and `lookup_component`
        // at the root would find none of them. The registry is shared by id
        // across every child scope, which is what makes this resolvable at
        // all, and it is the same route the Instance tab's explorer takes.
        guard s.renderable &&
          app.scope.comps.get_comp_for(@sbui.story_value(app, idx))
          is Some(comp) else {
          return
        }
        @sbui.set_story_value(app, idx, comp.make(s.args))
        return
      }
      i = i + 1
    }
  }
}

///|
/// The running gallery's frame handler, or none when nothing is mounted.
///
/// Package-level because there is one gallery per page — the same reason
/// `demo/storybook_wasm` keeps its app in a `Ref` for `on_popstate`.
let fuzz_tick_slot : Ref[(() -> Unit)?] = { val: None, }

///|
/// Point the session at the story, draw a fresh script, and ask for a frame.
///
/// The whole of what a run button does. Nothing is dispatched here — see
/// `FuzzSession::mode`.
fn[N] arm_run(
  app : @app.App[N],
  insp : @inspector.Inspector,
  session : FuzzSession,
  fx : FuzzEffects,
  mode : String,
  sections : Array[@sb.Section],
) -> Unit {
  // Step continues a run in progress; Play and Burst start one. That is the
  // difference between the three and the only place it lives.
  //
  // A FINISHED run is not one in progress, so Step at the end of a script
  // starts a fresh one rather than doing nothing — which is what it did before
  // this clause, and what a dead button looks like.
  let finished = session.at >= session.script.length() - 1
  if mode != "step" ||
    finished ||
    session.plan is None ||
    session.script.is_empty() {
    aim_fuzz(app, session, sections)
    session.rearm()
  }
  session.mode = mode
  session.playing = mode == "play"
  push_fuzz_panel(app, insp, session)
  (fx.arm_frame)()
}

///|
/// Do what the armed mode says, then arm the next frame if there is more.
///
/// Called from the page's animation frame, and — crucially — from OUTSIDE any
/// dispatch. That is what lets each step be its own dispatch chain, so a
/// refusal it provokes is a refusal it can see.
///
/// Safe to call at any time: nothing armed, or nothing left to send, and it
/// stops. A page that arms one frame too many gets a no-op rather than a wrong
/// answer.
fn[N] fuzz_advance(
  app : @app.App[N],
  insp : @inspector.Inspector,
  session : FuzzSession,
  fx : FuzzEffects,
) -> Unit {
  guard session.mode != "" else { return }
  let mode = session.mode
  match mode {
    // The whole script in one frame: settle, render and morph back to back,
    // which is the shape a flame chart is worth reading.
    "burst" => {
      (fx.mark)("burst", "start")
      while fuzz_step_marked(app, session, fx) {

      }
      (fx.mark)("burst", "end")
      session.mode = ""
    }
    _ => {
      let more = fuzz_step_marked(app, session, fx)
      if mode == "play" && more {
        // stays armed
      } else {
        session.playing = false
        session.mode = ""
      }
    }
  }
  // The panel every frame, because watching a run IS the point: the rows and
  // the component on screen have to move together, and a panel refreshed only
  // at the end would make Play look exactly like Burst.
  push_fuzz_panel(app, insp, session)
  if session.mode != "" {
    (fx.arm_frame)()
  }
}

///|
/// The page's animation-frame entry point.
///
/// Public and argument-free: it is called from JS through a wasm export, and
/// an export cannot be generic or take a node.
pub fn fuzz_tick() -> Unit {
  match fuzz_tick_slot.val {
    Some(f) => f()
    None => ()
  }
}

///|
/// The story's own instance, re-read on demand.
///
/// A closure rather than the value, because a run reads it back after every
/// step and the whole point is that it changed.
fn[N] story_reader(app : @app.App[N], idx : Int) -> @fuzz.Reader {
  @fuzz.Reader(() => @sbui.story_value(app, idx))
}
