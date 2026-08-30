// Assembling the standard panel layer.
//
// Five tabs, one Inspector they are all drawn by, and the two sessions that
// own what the shell cannot: `all()` wires them into the one value
// `@sbui.mount` takes.

///|
/// The gallery-wide fuzz knobs, declared here because they belong to the Fuzz
/// tab and not to the shell — a seed is what you carry from one story to the
/// next when you are looking for the same shape of bug, and the shell has no
/// idea what one is.
///
/// On the shell rather than in the panel because the panel is rebuilt by the
/// host on every change, so a knob that lived only there would be read back
/// from the thing that is about to be replaced.
pub let fuzz_fields : Map[String, @tutuca.Value] = {
  "fzSeed": Str("1"),
  "fzSteps": Str("40"),
  "fzSource": Str("public"),
}

///|
/// Every panel, wired to a gallery that has not been mounted yet.
///
/// The slot is the whole trick: the intents are registered before `App::new`
/// exists, so they close over a `Ref` that `attach` fills — the same shape the
/// gallery's own handlers used when they lived inside `storybook/ui`.
///
/// `effects` are the Fuzz tab's two browser effects; a headless mount passes
/// none and gets the tab minus the frame loop and the profiler marks.
pub fn[N] all(
  sections : Array[@sb.Section],
  effects? : FuzzEffects = FuzzEffects::none(),
) -> @sbui.PanelSet[N] {
  let insp = @inspector.Inspector::new()
  let slot : Ref[@app.App[N]?] = { val: None, }
  let trace = TraceSession::new()
  let fuzz = FuzzSession::new()
  let intents : Map[String, Array[@component.IntentFn]] = Map([])
  for name, fns in trace_handlers(slot, insp, trace, sections) {
    intents[name] = fns
  }
  for name, fns in fuzz_handlers(slot, insp, fuzz, sections, effects) {
    intents[name] = fns
  }
  {
    defs: [
      // The explorer over THIS story's live instance. `live`, so it tracks the
      // story as you drive it rather than showing the state as of the moment
      // the tab was opened; not `keep`, because an explorer is a whole
      // component tree and a closed tab has no use for one.
      {
        key: "instance",
        label: "Instance",
        field: "i",
        build: Some((inst, _read) => explorer_of(insp, slot, inst)),
        live: true,
        keep: false,
        with_story: false,
      },
      // Built once as an empty recorder bar; everything after that arrives
      // through `@sbui.push_panel`. Kept: a recording survives you looking
      // away from it, and a panel that reset itself would lose the session you
      // just captured.
      {
        key: "trace",
        label: "Trace",
        field: "r",
        build: Some((_inst, _read) => insp.trace_panel()),
        live: false,
        keep: true,
        with_story: false,
      },
      // Same rule, and the knobs come from the shell's own fields so an
      // unopened tab still has a seed. `with_story`, because a run you cannot
      // watch is the headless run with extra steps.
      {
        key: "fuzz",
        label: "Fuzz",
        field: "f",
        build: Some((_inst, read) => {
          insp.fuzz_panel(
            seed=read("fzSeed").str(default="1"),
            steps=read("fzSteps").str(default="40"),
            source=read("fzSource").str(default="public"),
          )
        }),
        live: false,
        keep: true,
        with_story: true,
      },
      // A declaration cannot go stale — the component behind a story is the
      // one thing about it that never changes — so both spec panels are built
      // once and then left alone. Lazily all the same: a gallery has ~50
      // stories, and re-parsing every block at mount to render none of them is
      // pure cost.
      {
        key: "spec",
        label: "Spec",
        field: "d",
        build: Some((inst, _read) => insp.spec_panel(comp?=comp_of(slot, inst))),
        live: false,
        keep: true,
        with_story: false,
      },
      // The same block, verbatim. The parse is what the runtime reads, the
      // source is what the author edits, and a reader reconciling a surprising
      // verdict wants both.
      {
        key: "raw",
        label: "Raw",
        field: "w",
        build: Some((inst, _read) => {
          insp.spec_source_panel(comp?=comp_of(slot, inst))
        }),
        live: false,
        keep: true,
        with_story: false,
      },
    ],
    fields: fuzz_fields,
    components: insp.components(),
    intents,
    attach: app => {
      slot.val = Some(app)
      // What the page's animation frame lands on. A CLOSURE in a slot rather
      // than a generic function the host calls, because the host has no `N` to
      // name: a wasm page knows it mounted on a `WasmNode` and should not have
      // to say so again to advance a run it did not start.
      fuzz_tick_slot.val = Some(() => fuzz_advance(app, insp, fuzz, effects))
    },
  }
}

///|
/// The component behind a story's instance, or None.
///
/// Resolved through the registry the gallery shares across every story's child
/// scope, and resolved EVERY time: a story's instance is replaced as it is
/// driven, and the component behind it is the stable thing.
fn[N] comp_of(
  slot : Ref[@app.App[N]?],
  instance : @tutuca.Value,
) -> @component.Component? {
  guard slot.val is Some(app) else { return None }
  app.scope.comps.get_comp_for(instance)
}

///|
/// The Instance tab's content: the inspector's explorer over the story's live
/// instance — its fields, and its component's definition beside them.
fn[N] explorer_of(
  insp : @inspector.Inspector,
  slot : Ref[@app.App[N]?],
  instance : @tutuca.Value,
) -> @tutuca.Value {
  guard instance is Obj(_) else { return Null }
  match slot.val {
    Some(app) => insp.explore_value(instance, comps=app.scope.comps)
    None => insp.explore_value(instance)
  }
}
