// Mount a scene and run its steps. See spec.mbt for what comes back.

///|
pub fn run(
  guest : &@host.Guest,
  manifest : @host.DynManifest,
  scenes : Array[@scenedef.Scene],
  root? : String = "",
  take_log? : () -> Array[String] = () => [],
  on_bundle? : (@host.Module) -> Unit = _b => (),
  on_app? : (@app.App[@memdom.MemNode]) -> Unit = _a => (),
) -> Array[SceneResult] {
  scenes.map(s => run_one(guest, manifest, s, root, take_log, on_bundle, on_app))
}

///|
/// One scene, in its own scope, on its own DOM.
///
/// A fresh `ComponentStack` per scene rather than one shared across the block,
/// because a scene is supposed to be a statement about a component starting
/// from a known place. Sharing the scope would make the fourth scene's answer
/// depend on whether the third ran, which is the kind of test that passes
/// alone and fails in a suite.
fn run_one(
  guest : &@host.Guest,
  manifest : @host.DynManifest,
  scene : @scenedef.Scene,
  root : String,
  take_log : () -> Array[String],
  on_bundle : (@host.Module) -> Unit,
  on_app : (@app.App[@memdom.MemNode]) -> Unit,
) -> SceneResult {
  let failed = (why : String) => SceneResult::{
    name: scene.name,
    component: scene.component,
    ok: false,
    html: "",
    state: Null,
    styles: "",
    activity: [],
    refusals: [],
    steps: [],
    log: [],
    error: why,
  }
  let scope = @component.ComponentStack::new()
  let loaded = @host.register_module(
    scope,
    guest,
    manifest,
    policy=@policy.Policy::granted(),
  ) catch {
    e => return failed(e.message())
  }
  // A guest that has to know which module it was registered as is told here.
  // A scene registers its OWN, so a guest still holding the previous scene's
  // would wrap this scene's child tokens through a module left behind.
  on_bundle(loaded)
  // The component: the scene's own, then the caller's root, then the first the
  // manifest declares — which is the first `<template>` in the file, and the
  // only answer a card with one component has.
  let names = loaded.component_names()
  let comp = if scene.component != "" {
    scene.component
  } else if root != "" {
    root
  } else {
    match names.get(0) {
      Some(n) => n
      None => ""
    }
  }
  if comp == "" {
    return failed("the manifest declares no component to mount")
  }
  if !names.contains(comp) {
    return failed(
      "no component called `" +
      comp +
      "` — this card declares " +
      names.map(n => "`" + n + "`").join(", "),
    )
  }
  let args = start_args(loaded, comp, scene) catch {
    e => return failed(e.message())
  }
  // A fixture may carry its own steps and its own intent answers. The scene's
  // win where both name one: the scene is the more specific statement, and a
  // fixture is a starting point rather than a script the scene is inside.
  let (pre, fixture_intents) = match
    (if scene.init == "" { None } else { fixture_of(loaded, comp, scene.init) }) {
    Some(f) => fixture_drive(f)
    None => ([], Map([]))
  }
  let answers : Map[String, @tutuca.IntentAnswer] = Map([])
  for name, a in fixture_intents {
    answers[name] = a
  }
  for name, a in scene.intents {
    answers[name] = a
  }
  scope.register_intent_handlers(intent_handlers(answers))
  guard loaded.make_instance(comp, args~) is Some(inst) else {
    return failed("the guest would not create a `" + comp + "`")
  }
  let (doc, container) = @harness.new_mount()
  let app = @app.App::new(
    scope,
    inst.to_value(),
    container,
    @vdom.RenderOpts::new(doc),
  ) catch {
    _ => return failed("the module's views did not compile into an app")
  }
  let activity : Array[Json] = []
  app.transactor.observe(r => {
    if activity.length() < ACTIVITY_CAP {
      activity.push(r.to_json())
    }
  })
  |> ignore
  // A guest instance is superseded by every transition that answers a
  // successor, which is every interaction a scene drives — so a scene of fifty
  // steps leaves fifty dead handles behind without this. It is the host's job
  // whoever the host is, and a driver is one.
  @host.install_gc(app.transactor)
  // …and whatever else the caller wants to hang on this app. The card driver
  // installs a reachability sweep here, which needs the root and therefore the
  // app rather than the module.
  on_app(app)
  app.start()
  let h = @harness.Harness::over(app, container)
  // The fixture's steps first, and OUTSIDE the report: they are how this state
  // was reached rather than something the scene did. A scene whose starting
  // point cannot be built says so as a mount failure, since that is what it is.
  for step in pre {
    let _ = run_step(h, scene, -1, step, take_log)
  }
  let out = { ..drive_scene(h, scene, take_log~), component: comp, activity, }
  // Both halves of a mounted app are reference cycles the native backend does
  // not reclaim, and a block of scenes mounts one each.
  h.destroy()
  out
}

///|
/// Run a scene's steps against an app somebody else mounted.
///
/// The half of this package with the interesting decisions in it — what a verb
/// does, what a reader answers, what counts as a disagreement — and the half
/// with no guest, no manifest and no wasm anywhere near it. So `moon test`
/// drives it against an ordinary `ModuleDef` on every backend, which is how
/// the vocabulary gets tested without a fake of the whole component model
/// standing in the way.
///
/// `component` and `activity` are left for the mounter to fill in: they are
/// facts about how the app came to exist, and this is handed one that already
/// does.
pub fn drive_scene(
  h : @harness.Harness[@memdom.MemNode],
  scene : @scenedef.Scene,
  take_log? : () -> Array[String] = () => [],
) -> SceneResult {
  reset_refusals()
  // Every refusal the whole scene raised, so a report can show the ones no
  // step asked about. `refusals_while` swaps the channel back off on the way
  // out of a failure too, which is what keeps one scene's guard out of the
  // next one's report.
  let all_refusals : Array[String] = []
  let all_log : Array[String] = []
  let steps : Array[StepResult] = []
  let mut ok = true
  for at, step in scene.steps {
    let (result, refused, logged) = run_step(h, scene, at, step, take_log)
    for r in refused {
      all_refusals.push(r)
    }
    for l in logged {
      all_log.push(l)
    }
    if !result.ok {
      ok = false
    }
    steps.push(result)
  }
  {
    name: scene.name,
    component: "",
    ok,
    html: if scene.raw {
      h.container.to_html()
    } else {
      @harness.clean_html(h.container)
    },
    state: h.drive_value(),
    styles: h.styles(),
    activity: [],
    refusals: all_refusals,
    log: all_log,
    steps,
    error: "",
  }
}

///|
/// The field values a scene starts from: its `init` fixture, with its own
/// `args` written over the top.
///
/// Merged here rather than by mounting the fixture and then setting fields,
/// because a component is built once — `make_instance` is the only place args
/// reach a guest's constructor, and a card's `init` handler runs against
/// whatever it was built with.
pub fn fixture_of(
  loaded : @host.Module,
  comp : String,
  name : String,
) -> @host.DynInitDef? {
  for def in loaded.manifest().components {
    if def.name == comp {
      for i in def.inits {
        if i.name == name {
          return Some(i)
        }
      }
    }
  }
  None
}

///|
/// A fixture's own steps, as the scene vocabulary they were validated as.
///
/// They cross the manifest as JSON — a wire format passes through what it does
/// not interpret — so this is where they become steps again. A fixture that
/// declares none is an empty list, which is what most are.
pub fn fixture_drive(
  f : @host.DynInitDef,
) -> (Array[@scenedef.Step], Map[String, @tutuca.IntentAnswer]) {
  let steps = if f.drive_json == "" {
    []
  } else {
    @scenedef.parse_steps(@json.parse(f.drive_json), "fixture `" + f.name + "`") catch {
      _ => []
    }
  }
  let answers = if f.intents_json == "" {
    Map([])
  } else {
    @scenedef.parse_answers(
      @json.parse(f.intents_json),
      "fixture `" + f.name + "`",
    ) catch {
      _ => Map([])
    }
  }
  (steps, answers)
}

///|
fn start_args(
  loaded : @host.Module,
  comp : String,
  scene : @scenedef.Scene,
) -> Map[String, @tutuca.Value] raise MountError {
  let args : Map[String, @tutuca.Value] = Map([])
  if scene.init != "" {
    let mut found = false
    for def in loaded.manifest().components {
      if def.name == comp {
        for i in def.inits {
          if i.name == scene.init {
            found = true
            for k, v in i.args {
              args[k] = v
            }
          }
        }
        if !found {
          raise MountError(
            "no `tutuca/fixtures` fixture called `" +
            scene.init +
            "` on `" +
            comp +
            "`" +
            (if def.inits.is_empty() {
              "; this component declares none"
            } else {
              " — it declares " +
              def.inits.map(i => "`" + i.name + "`").join(", ")
            }),
          )
        }
      }
    }
  }
  for k, v in scene.args {
    args[k] = v
  }
  args
}

///|
/// The scene's intent fixtures as handlers, answering AT ONCE.
///
/// A page's fixtures answer late on purpose — an answer that lands before the
/// transaction finishes never shows a card its own loading state, which is the
/// half of asynchrony a card author has to write for. A runner has nothing to
/// wait with: it drives, it settles, and it returns. So a scene's fixtures
/// answer synchronously, and a card's loading state is asserted by driving the
/// step that raises the intent and reading the DOM before the answer — which
/// is a thing to add when a scene needs it, not a thing to fake with a clock.
///
/// A name with no fixture answers NOTHING, which is the point rather than a
/// gap: the route runs out, nobody claimed it, and the card hears
/// `<name>Unhandled`. That is a different sentence from a failure's, and it is
/// the path a test is likeliest to leave uncovered — nothing in a card raises
/// it, only the absence of an answer does.
pub fn intent_handlers(
  intents : Map[String, @tutuca.IntentAnswer],
) -> Map[String, Array[@component.IntentFn]] {
  let out : Map[String, Array[@component.IntentFn]] = Map([])
  for name, answer in intents {
    out[name] = [IntentFn((_call, reply) => reply(answer))]
  }
  out
}
