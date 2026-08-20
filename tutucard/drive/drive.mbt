// Mount a scene and run its steps. See spec.mbt for what comes back.

///|
pub fn run(
  guest : &@dyncomp.Guest,
  manifest : @dyncomp.DynManifest,
  scenes : Array[@scenedef.Scene],
  root? : String = "",
) -> Array[SceneResult] {
  scenes.map(s => run_one(guest, manifest, s, root))
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
  guest : &@dyncomp.Guest,
  manifest : @dyncomp.DynManifest,
  scene : @scenedef.Scene,
  root : String,
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
    error: why,
  }
  let scope = @component.ComponentStack::new()
  scope.register_intent_handlers(fixtures(scene))
  let bundle = @dyncomp.register_bundle(
    scope,
    guest,
    manifest,
    policy=@policy.Policy::granted(),
  ) catch {
    e => return failed(e.message())
  }
  // The component: the scene's own, then the caller's root, then the first the
  // manifest declares — which is the first `<template>` in the file, and the
  // only answer a card with one component has.
  let names = bundle.component_names()
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
  let args = start_args(bundle, comp, scene) catch {
    e => return failed(e.message())
  }
  guard bundle.make_instance(comp, args~) is Some(inst) else {
    return failed("the guest would not create a `" + comp + "`")
  }
  let (doc, container) = @harness.new_mount()
  let app = @app.App::new(
    scope,
    inst.to_value(),
    container,
    @vdom.RenderOpts::new(doc),
  ) catch {
    _ => return failed("the bundle's views did not compile into an app")
  }
  let activity : Array[Json] = []
  app.transactor.observe(r => {
    if activity.length() < ACTIVITY_CAP {
      activity.push(r.to_json())
    }
  })
  |> ignore
  app.start()
  let h = @harness.Harness::over(app, container)
  let out = { ..drive_scene(h, scene), component: comp, activity }
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
  h : @harness.Harness,
  scene : @scenedef.Scene,
) -> SceneResult {
  reset_refusals()
  // Every refusal the whole scene raised, so a report can show the ones no
  // step asked about. `refusals_while` swaps the channel back off on the way
  // out of a failure too, which is what keeps one scene's guard out of the
  // next one's report.
  let all_refusals : Array[String] = []
  let steps : Array[StepResult] = []
  let mut ok = true
  for at, step in scene.steps {
    let (result, refused) = run_step(h, scene, at, step)
    for r in refused {
      all_refusals.push(r)
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
      clean_html(h.container)
    },
    state: h.drive_value(),
    styles: h.styles(),
    activity: [],
    refusals: all_refusals,
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
fn start_args(
  bundle : @dyncomp.Bundle,
  comp : String,
  scene : @scenedef.Scene,
) -> Map[String, @tutuca.Value] raise MountError {
  let args : Map[String, @tutuca.Value] = Map([])
  if scene.init != "" {
    let mut found = false
    for def in bundle.manifest().components {
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
            "no `tutuca/init` fixture called `" +
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
fn fixtures(scene : @scenedef.Scene) -> Map[String, Array[@component.IntentFn]] {
  let out : Map[String, Array[@component.IntentFn]] = Map([])
  for name, a in scene.intents {
    let answer : @tutuca.IntentAnswer = match a {
      AOk(v) => Ok(v)
      AFailed(v) => Failed(v)
      APass => Pass
    }
    out[name] = [@component.IntentFn((_call, reply) => reply(answer))]
  }
  out
}
