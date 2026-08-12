// The single "place with all the tasks" for tutuca-mb. Each task plans an
// ordered list of steps (spawn a process, or a file op for `dist`); cmd/dev
// executes them in order and stops on the first failure. This replaces the raw
// commands previously scattered across AGENTS.md / README / moon.pkg headers.

///|
/// One command to spawn: `prog` with `args`, announced under `label`.
pub struct Command {
  label : String
  prog : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// A single step in a task plan. Simple tasks are all `Run`; `dist` also emits
/// the file ops. cmd/dev is the only place that turns these into real effects.
pub enum Step {
  Run(Command)
  Mkdir(String)
  Copy(from~ : String, to~ : String)
  // copy `from` to `to`, replacing the first `old_src` with `new_src` (used to
  // repoint the demo pages' <script src> at the sibling bundle in dist/).
  WriteRewritten(
    from~ : String,
    to~ : String,
    old_src~ : String,
    new_src~ : String
  )
  // walk `src_dir`, read every file, and write the generated
  // skill_assets_source(...) MoonBit module to `to` (skill-embed codegen).
  GenSkillAssets(src_dir~ : String, to~ : String)
  // assemble a `tutuca:component` guest tree from its three sources and write
  // the generated guest_template_source(...) MoonBit module to `to`. Not a
  // GenSkillAssets with a different src_dir: the sources are three, and two of
  // them are remapped on the way in (see cmd/dev's gen_guest_template).
  GenGuestTemplate(to~ : String)
} derive(Eq, Debug)

///|
/// A named task: an ordered list of commands run until one fails.
pub struct Task {
  name : String
  about : String
  commands : Array[Command]
}

///|
fn moon(label : String, args : Array[String]) -> Command {
  { label, prog: "moon", args }
}

///|
/// Shrink a wasm-gc module in place with `moon-wasm-opt` (ships with moon, on
/// PATH via ~/.moon/bin). `-Oz` roughly halves the release module (~4.8 MB ->
/// ~2.6 MB for storybook). `--all-features` lets the optimizer read moon's
/// gc/js-string output; `--disable-custom-descriptors` stops it emitting `exact`
/// heap types, which browsers reject without an experimental flag.
fn wasm_opt(path : String) -> Command {
  {
    label: "wasm-opt -Oz · " + path,
    prog: "moon-wasm-opt",
    args: [
      "--all-features", "--disable-custom-descriptors", "-Oz", path, "-o", path,
    ],
  }
}

// --- build-output and dist layout paths (moon's default debug build) ---

///|
const COUNTER_JS = "_build/js/debug/build/demo/counter/counter.js"

///|
// dist ships the RELEASE wasm (the debug build is ~4x larger: 18 MB vs ~4.8 MB
// for storybook), then shrinks it further with wasm-opt (see wasm_opt / the
// `moon build … --release` steps in dist_steps / universal_steps).
const COUNTER_WASM = "_build/wasm-gc/release/build/demo/counter_wasm/counter_wasm.wasm"

///|
const STORYBOOK_WASM = "_build/wasm-gc/release/build/demo/storybook_wasm/storybook_wasm.wasm"

///|
// moon names the native executable `.exe` on every OS, including Linux.
const NATIVE_BIN = "_build/native/debug/build/cmd/main/main.exe"

///|
const DIST = "dist"

///|
/// All base (non-composite) tasks, in display order. Composite/special tasks
/// (`ci`, `dist`) are assembled in `plan`, so there is one source of truth.
pub fn tasks() -> Array[Task] {
  [
    {
      name: "check",
      about: "type-check every backend (default, js, native)",
      commands: [
        // +unnecessary_annotation (warning 73) keeps redundant Type::/@pkg.
        // prefixes from creeping back in
        moon("check · default", [
          "check", "--warn-list", "+unnecessary_annotation",
        ]),
        moon("check · js", [
          "check", "--target", "js", "--warn-list", "+unnecessary_annotation",
        ]),
        moon("check · native", [
          "check", "--target", "native", "--warn-list", "+unnecessary_annotation",
        ]),
      ],
    },
    {
      name: "fmt",
      about: "format sources and regenerate .mbti interface files",
      commands: [moon("fmt", ["fmt"]), moon("info", ["info"])],
    },
    {
      name: "test",
      about: "run tests across default, native, and js browser adapters",
      commands: [
        moon("test · default", ["test"]),
        moon("test · native", ["test", "--target", "native"]),
        moon("test · js browser adapters", [
          "test", "--target", "js", "vdom/browser", "app/browser",
        ]),
      ],
    },
    {
      name: "build",
      about: "build all applicable targets (wasm-gc, native CLI, js)",
      commands: build_commands(),
    },
    {
      name: "gen-views",
      about: "regenerate the checked-in *_view_gen.mbt from their .html sources",
      commands: gen_views_commands(),
    },
    {
      name: "gen-conformance",
      about: "project the conformance corpus into the view file the MoonBit backend is compiled from",
      commands: gen_conformance_commands(),
    },
    {
      name: "gen-guest-bindings",
      about: "regenerate the checked-in guest bindings from dyncomp/wit, then drift-check them",
      commands: gen_guest_bindings_commands(),
    },
    {
      name: "bench-views",
      about: "regenerate benchmarks/all_views.{html,_gen.mbt} — every repo view concatenated, names prefixed",
      commands: [
        {
          label: "build · benchmark view corpus",
          prog: "node",
          args: ["benchmarks/build.mjs"],
        },
        // The generator emits one `#|` line per source line, which `moon fmt`
        // leaves alone but the surrounding module needs formatting like any
        // other generated file (same reason gen-views formats).
        moon("fmt", ["fmt"]),
      ],
    },
    {
      name: "bench",
      about: "time the view pipeline, the render path and diff/patch (wasm-gc + native, release)",
      // report.mjs runs `moon bench` and collapses its three lines per
      // benchmark into one, which is the difference between reading 32 numbers
      // and scrolling past 96. It also takes --save/--baseline for A/B runs.
      commands: [
        {
          label: "bench · wasm-gc",
          prog: "node",
          args: ["benchmarks/report.mjs"],
        },
        {
          label: "bench · native",
          prog: "node",
          args: ["benchmarks/report.mjs", "--target", "native"],
        },
      ],
    },
    {
      name: "coverage",
      about: "run coverage analysis",
      commands: [moon("coverage analyze", ["coverage", "analyze"])],
    },
    {
      name: "check-examples",
      about: "compile-check the playground's editable examples (no moon package includes them)",
      commands: [
        // Each example's views live in a sibling .html that the page compiles
        // in the browser, so the check generates them the same way: with the
        // view generator built to js (the payload the playground ships).
        moon("build · js view generator", [
          "build", "--target", "js", "playground/viewgen_js",
        ]),
        {
          label: "check · playground examples",
          prog: "node",
          args: ["scripts/check-playground-examples.mjs"],
        },
      ],
    },
    {
      name: "check-skill",
      about: "compile-check the MoonBit snippets in the bundled skill (skill/tutuca/)",
      commands: [
        // The skill ships inside the CLI binary and is the only thing an agent
        // reads before writing tutuca code, so a snippet naming a parameter the
        // library dropped is worse than no snippet. Most recipes pair a view
        // file with the MoonBit that uses it, so the check generates the view
        // half the same way the playground does — with the js view generator.
        moon("build · js view generator", [
          "build", "--target", "js", "playground/viewgen_js",
        ]),
        {
          label: "check · skill snippets",
          prog: "node",
          args: ["scripts/check-skill-snippets.mjs"],
        },
      ],
    },
    {
      name: "check-guest-template",
      about: "scaffold a guest with the embedded template and compile it (the only coverage `tutuca new-guest` has)",
      commands: [
        // The template is what someone writing their first tutuca:component
        // guest reads, and nothing else compiles it: `ci` never builds a guest
        // (`guests` needs wasm-tools and jco), and the tree is assembled from
        // three sources with placeholders substituted at write time, so all
        // three can be fine and the result still not compile. Both steps are
        // needed because the template lives in the binary: regenerate the
        // embed, rebuild, then run what a stranger would get.
        moon("build · native CLI (with the guest template embedded)", [
          "build", "--target", "native", "cmd/main",
        ]),
        {
          label: "check · scaffolded guest compiles",
          prog: "node",
          args: ["scripts/check-guest-template.mjs"],
        },
      ],
    },
    {
      name: "fetch-moonc",
      about: "fetch the gitignored in-browser MoonBit compiler (playground/vendor/moonc-web.cjs) from npm; see playground/vendor/README.md",
      commands: [
        {
          label: "fetch playground compiler",
          prog: "node",
          args: ["playground/build/fetch-compiler.mjs"],
        },
      ],
    },
    {
      name: "playground",
      about: "assemble dist/playground/ (in-browser MoonBit playground): build the js library + mount host, then collect the compiler + prebuilt .core/.mi + web shell",
      commands: [
        moon("build · js library", ["build", "--target", "js"]),
        // `moon build --target js` alone does not build playground/host (it is
        // not in the default build set); assemble.mjs needs its host.core.
        moon("build · js playground host", [
          "build", "--target", "js", "playground/host",
        ]),
        // Likewise the module-root facade package (marianoguerra/tutuca) is not
        // reachable from the demo build roots, so it is not in the default build
        // set. assemble.mjs exposes its .mi to user code as @tutuca (it re-exports
        // core's value types — see reexport.mbt), so build it explicitly.
        moon("build · js root facade", ["build", "--target", "js", "."]),
        {
          label: "assemble dist/playground",
          prog: "node",
          args: ["playground/build/assemble.mjs"],
        },
        // The View tab generates a MoonBit module in the browser and feeds it
        // to the in-browser compiler. Nothing else can catch a generated
        // module that fails to compile THERE (no moon.pkg, @tutuca is the
        // root facade), so drive that path headlessly on every assemble.
        {
          label: "check · playground view tab",
          prog: "node",
          args: ["playground/build/check-viewgen-tab.mjs"],
        },
      ],
    },
    {
      name: "tutucard-playground",
      about: "assemble dist/tutucard/ (the compiler-free card playground): build the js host, copy the shell, then check every starter card loads",
      commands: [
        // No compiler, no worker, no prebuilt .mi/.core closure and no
        // toolchain pin — a card is parsed and mounted, so what ships is the
        // runtime and the page. assemble.mjs runs the build itself.
        {
          label: "assemble dist/tutucard",
          prog: "node",
          args: ["tutucard/build/assemble.mjs"],
        },
        // The starter cards are JavaScript strings no MoonBit test can reach,
        // so a card that stopped parsing would be found by whoever opened the
        // page. This runs the real loader over every one of them.
        {
          label: "check · starter cards load",
          prog: "node",
          args: ["tutucard/build/check-examples.mjs"],
        },
      ],
    },
    {
      name: "npm-pack",
      about: "stage + `npm pack` the playground's two npm packages from an assembled dist/ (packs only — publishing stays manual; see CONTRIBUTING.md)",
      commands: [
        {
          label: "pack npm packages",
          prog: "node",
          args: ["playground/build/pack-npm.mjs"],
        },
      ],
    },
    {
      name: "setup",
      about: "install js-test deps (happy-dom) and enable the git hooks",
      commands: [
        { label: "npm install", prog: "npm", args: ["install"] },
        {
          label: "enable git hooks",
          prog: "git",
          args: ["config", "core.hooksPath", ".githooks"],
        },
      ],
    },
  ]
}

///|
/// The corpus, projected and then compiled.
///
/// Two steps because the second is `gen-views`: the corpus is DATA and the
/// interpreter reads it directly, but the MoonBit backend's answers only exist
/// once `moonc` has compiled them — so the corpus becomes a view file and
/// takes the ordinary path from there. `gen-views` already lists corpus.html,
/// so `ci` re-runs and drift-checks the second half on its own; this task is
/// what to run after ADDING a case.
fn gen_conformance_commands() -> Array[Command] {
  [
    moon("conformance · project the corpus", [
      "run", "--target", "native", "cmd/conformance",
    ]),
    ..gen_views_commands(),
  ]
}

///|
/// One entry per repo-owned view file. Run after editing an .html view; it ends
/// in its own `git diff --exit-code`, which is what lets `ci` include it to
/// catch a generated module that has drifted from its source. A file whose
/// components carry template ids needs no `--name`; a bare single-component
/// `<template>` names its component with one.
///
/// The CLI emits unformatted source, so the run ends with `moon fmt` — that is
/// what makes the checked-in pair reproducible and the drift check meaningful.
fn gen_views_commands() -> Array[Command] {
  // (relative .html path, --name override or None)
  let files : Array[(String, String?)] = [
    ("demo/counterlib/counter.html", Some("Counter")),
    ("tscript/conformance/mbt/corpus.html", Some("Corpus")),
    ("dyncomp/shell/loader_bar.html", Some("LoaderBar")),
    ("dyncomp/ui/app.html", Some("UniversalApp")),
    ("dyncomp/ui/std/std.html", None),
    ("dyncomp/storybook/storybook.html", Some("DyncompStorybook")),
    ("inspector/activity.html", None),
    ("inspector/json.html", None),
    ("inspector/component_inspector.html", None),
    ("inspector/instance_inspector.html", None),
    ("inspector/state_editor.html", None),
    ("inspector/schema_components.html", None),
    ("inspector/schema.html", None),
    ("inspector/module.html", None),
    ("docs/tutorial.html", None),
    ("docs/first_principles.html", None),
    ("inspector/schema_viewer.html", Some("SchemaViewer")),
    ("storybook/examples/basics.html", None),
    ("storybook/examples/collections.html", None),
    ("storybook/examples/communication.html", None),
    ("storybook/examples/composability.html", Some("Composability")),
    ("storybook/examples/conditionals.html", None),
    ("storybook/examples/counter.html", Some("Counter")),
    ("storybook/examples/custom_collection.html", None),
    ("storybook/examples/dnd.html", Some("DnDExample")),
    ("storybook/examples/dynamic.html", None),
    ("storybook/examples/dynamic_selected_edit.html", None),
    ("storybook/examples/file_picker.html", Some("FilePicker")),
    ("storybook/examples/filter_paginate.html", None),
    ("storybook/examples/graphics.html", None),
    ("storybook/examples/json.html", None),
    ("storybook/examples/lint_errors.html", None),
    ("storybook/examples/list_iteration.html", Some("ListIteration")),
    ("storybook/examples/macros.html", None),
    ("storybook/examples/nested_state.html", Some("NestedState")),
    ("storybook/examples/personal_site.html", None),
    ("storybook/examples/pseudo_x.html", None),
    ("storybook/examples/render_child.html", None),
    ("storybook/examples/rendering.html", None),
    ("storybook/examples/request.html", Some("RequestExample")),
    ("storybook/examples/state_and_updates.html", None),
    ("storybook/examples/styles.html", None),
    ("storybook/examples/svg_more.html", None),
    ("storybook/examples/todo.html", None),
    ("storybook/examples/todo_macros.html", None),
    ("storybook/examples/visual_wasm.html", None),
    ("storybook/examples/web_component.html", Some("EmojiPicker")),
  ]
  let commands = files.map(entry => {
    let (path, name) = entry
    let args = [
      "run", "--target", "native", "cmd/main", "--", "gen-views", path,
    ]
    match name {
      Some(n) => {
        args.push("--name")
        args.push(n)
      }
      None => ()
    }
    moon("gen-views · " + path, args)
  })
  commands.push(moon("fmt", ["fmt"]))
  // The drift check, the same shape `gen-guest-bindings` uses: regenerating is
  // only a guarantee if the checked-in pair is what regenerating produces. This
  // is what makes `gen-views` safe to put in CI.
  //
  // Scoped to the generated modules by pathspec rather than run over the whole
  // tree, because the `moon fmt` above formats every source: an unrelated file
  // that was committed unformatted would otherwise fail here, reported as view
  // drift. `*_view_gen.mbt` matches at any depth, so a new view file is covered
  // the moment it is added to `files` above.
  // `HEAD` rather than a bare `git diff`: the question is whether the COMMIT
  // matches the sources, and a bare diff ignores anything already staged —
  // which would let a `git add` of a stale module walk straight past.
  commands.push({
    label: "drift check · generated view modules match their .html",
    prog: "git",
    args: [
      "diff", "--exit-code", "HEAD", "--", "*_view_gen.mbt", "*_view_ir_gen.mbt",
    ],
  })
  commands
}

///|
/// Regenerate BOTH MoonBit guest binding trees from the one WIT
/// (dyncomp/wit/tutuca-component.wit), then prove the checked-in output is
/// reproducible. Same shape as `gen-views`: the generator normalizes and
/// formats, so a clean `git diff` is the whole check. The Rust guest reads
/// the same WIT through its `generate!` macro and needs no checked-in
/// bindings. See guests/gen-bindings.mjs for why normalization is needed
/// (wit-bindgen emits its FFI shims in hash order).
fn gen_guest_bindings_commands() -> Array[Command] {
  [
    {
      label: "wit-bindgen · every MoonBit guest, from dyncomp/wit + guests/sdk.mbt",
      prog: "node",
      args: ["guests/gen-bindings.mjs"],
    },
    {
      label: "drift check · guests/ is reproducible from the WIT",
      prog: "git",
      args: ["diff", "--exit-code", "--", "guests"],
    },
  ]
}

///|
fn build_commands() -> Array[Command] {
  [
    moon("build · wasm-gc", ["build", "--target", "wasm-gc"]),
    moon("build · native cli", ["build", "--target", "native", "cmd/main"]),
    moon("build · js", ["build", "--target", "js"]),
    // playground/host is not in the default js build set; the playground
    // assembly (dist) needs its host.core, and this doubles as a build-smoke.
    moon("build · js playground host", [
      "build", "--target", "js", "playground/host",
    ]),
    // Nor is the module-root facade package (marianoguerra/tutuca): nothing
    // imports it, so it is unreachable from the demo build roots. assemble.mjs
    // exposes its .mi to playground user code as @tutuca (it re-exports core's
    // value types — see reexport.mbt), so build it explicitly here.
    moon("build · js root facade", ["build", "--target", "js", "."]),
  ]
}

///|
/// Composite tasks: name -> (about, member base-task names) whose commands are
/// concatenated.
fn composites() -> Array[(String, String, Array[String])] {
  // `build` is part of CI so wasm-gc codegen of the demo hosts (demo/*_wasm,
  // driven by the app/wasm + vdom/wasm adapters) is smoke-tested: `check` only
  // type-checks, but wasm-gc codegen fails on things check passes (e.g. a
  // MoonBit closure crossing into JS). The wasm DOM adapters have no
  // host-independent logic and can't be unit-tested without a browser host, so
  // this build-smoke is their regression guard. It also codegens the js/native
  // demo hosts, none of which have their own tests.
  [
    // `gen-views` runs FIRST, and for its drift check rather than its output:
    // every `*_view_gen.mbt` is checked in and compiled as an ordinary source,
    // so a stale one type-checks and tests green while no longer describing the
    // .html beside it. Catching that before `check` also means the rest of CI
    // runs against modules that provably match their sources.
    (
      "ci",
      "gen-views drift + check + check-examples + check-skill + check-guest-template + test + build (build-smokes every backend & demo)",
      [
        "gen-views", "check", "check-examples", "check-skill", "check-guest-template",
        "test", "build",
      ],
    ),
  ]
}

///|
/// The `dist` step plan: build every target, then assemble a self-contained
/// `dist/` folder (bundles + repointed demo pages + a landing index.html + the
/// native CLI binary) that runs from any static file server.
fn dist_steps() -> Array[Step] {
  let steps : Array[Step] = []
  // refresh the CLI's embedded assets before the native build — both of them,
  // since both are written out by a command in the binary being built
  for step in skill_embed_steps() {
    steps.push(step)
  }
  for step in guest_template_embed_steps() {
    steps.push(step)
  }
  for cmd in build_commands() {
    steps.push(Run(cmd))
  }
  // ship the RELEASE wasm demos (build_commands builds debug for the smoke).
  steps.push(
    Run(
      moon("build · wasm-gc demos (release)", [
        "build", "--target", "wasm-gc", "--release", "demo/counter_wasm", "demo/storybook_wasm",
      ]),
    ),
  )
  steps.push(Mkdir(DIST))
  steps.push(Mkdir("\{DIST}/counter"))
  steps.push(Mkdir("\{DIST}/counter-wasm"))
  steps.push(Mkdir("\{DIST}/storybook"))
  steps.push(Mkdir("\{DIST}/cli"))
  steps.push(Copy(from=COUNTER_JS, to="\{DIST}/counter/counter.js"))
  steps.push(Copy(from=NATIVE_BIN, to="\{DIST}/cli/tutuca"))
  // wasm counter: the .wasm plus its loader + host page. index.html already
  // loads ./loader.mjs and ./counter_wasm.wasm relative to its folder, so the
  // page and loader copy verbatim (no rewrite).
  steps.push(
    Copy(from=COUNTER_WASM, to="\{DIST}/counter-wasm/counter_wasm.wasm"),
  )
  steps.push(Run(wasm_opt("\{DIST}/counter-wasm/counter_wasm.wasm")))
  steps.push(
    Copy(
      from="demo/counter_wasm/loader.mjs",
      to="\{DIST}/counter-wasm/loader.mjs",
    ),
  )
  steps.push(
    Copy(from="app/wasm/loader.mjs", to="\{DIST}/counter-wasm/app-loader.mjs"),
  )
  steps.push(
    Copy(
      from="demo/counter_wasm/index.html",
      to="\{DIST}/counter-wasm/index.html",
    ),
  )
  // storybook: the gallery host page loads ./loader.mjs and ./storybook_wasm.wasm
  // relative to its folder (like counter-wasm), so page + loader copy verbatim.
  // This is also the bundle `tutuca storybook` serves (dist/storybook).
  steps.push(
    Copy(from=STORYBOOK_WASM, to="\{DIST}/storybook/storybook_wasm.wasm"),
  )
  steps.push(Run(wasm_opt("\{DIST}/storybook/storybook_wasm.wasm")))
  // the storybook host imports the dynamic-component bridge (tcomp namespace),
  // so it ships that loader plus the counter guest bundle its Dynamic pane
  // loads at runtime
  steps.push(
    Copy(
      from="demo/storybook_wasm/loader.mjs",
      to="\{DIST}/storybook/loader.mjs",
    ),
  )
  steps.push(
    Copy(from="app/wasm/loader.mjs", to="\{DIST}/storybook/app-loader.mjs"),
  )
  steps.push(
    Copy(
      from="demo/storybook_wasm/index.html",
      to="\{DIST}/storybook/index.html",
    ),
  )
  steps.push(
    WriteRewritten(
      from="demo/counter/index.html",
      to="\{DIST}/counter/index.html",
      old_src="../../" + COUNTER_JS,
      new_src="./counter.js",
    ),
  )
  // The in-browser playground compiler payload (assemble.mjs), reused by the
  // landing site's embedded <mb-playground> elements, then the landing site
  // itself — which becomes the dist root index.html (assemble-site.mjs).
  // build_commands above built the js library AND playground/host, so the host
  // core + library artifacts assemble.mjs collects are present.
  steps.push(
    Run({
      label: "assemble dist/playground",
      prog: "node",
      args: ["playground/build/assemble.mjs"],
    }),
  )
  steps.push(
    Run({
      label: "assemble landing site (dist root)",
      prog: "node",
      args: ["playground/build/assemble-site.mjs"],
    }),
  )
  steps
}

///|
/// Rewrite a demo page for dist by repointing its `<script src>` at the sibling
/// bundle. Exact first-occurrence replace — robust and pure (no HTML parsing).
pub fn rewrite(html : String, old_src~ : String, new_src~ : String) -> String {
  html.replace(old=old_src, new=new_src)
}

///|
/// Resolve a task name to the steps to run, or `None` if unknown.
pub fn plan(name : String) -> Array[Step]? {
  for task in tasks() {
    if task.name == name {
      return Some(task.commands.map(fn(c) { Run(c) }))
    }
  }
  for entry in composites() {
    let (cname, _, members) = entry
    if cname == name {
      let out : Array[Step] = []
      for base in members {
        // members always name real base tasks, so plan(base) is Some.
        for step in plan(base).unwrap_or([]) {
          out.push(step)
        }
      }
      return Some(out)
    }
  }
  if name == "dist" {
    return Some(dist_steps())
  }
  if name == "skill-embed" {
    return Some(skill_embed_steps())
  }
  if name == "guest-template-embed" {
    return Some(guest_template_embed_steps())
  }
  if name == "css-bundle" {
    return Some(css_bundle_steps())
  }
  if name == "universal" {
    return Some(universal_steps())
  }
  if name == "dyncomp-storybook" {
    return Some(dyncomp_storybook_steps())
  }
  if name == "guests" {
    return Some(guest_build_steps())
  }
  None
}

///|
/// Every guest bundle, in one list.
///
/// ONE list, because there used to be three — this file, the justfile's
/// `guests` recipe, and `guests/guests.mjs` — and adding a guest to two of
/// them left `just guests` building a bundle that no longer existed. The
/// justfile is a thin wrapper over the `guests` task below, and
/// `guests/guests.mjs` still owns which names `build-guest.mjs` accepts,
/// because that is a fact about the script rather than about the build.
///
/// The Rust one is separate: same WIT, but it builds through cargo rather than
/// moon, so it keeps its own script.
fn moonbit_guests() -> Array[String] {
  ["counter", "todo", "todomvc", "calculator", "tictactoe", "bluesky", "slack"]
}

///|
const RUST_GUEST = "rust-tempconv"

///|
/// Build every guest bundle: wit-bindgen output → component → ESM.
pub fn guest_build_steps() -> Array[Step] {
  let out : Array[Step] = []
  for name in moonbit_guests() {
    out.push(
      Run({
        label: "build · \{name} guest bundle (wit-bindgen output → component → ESM)",
        prog: "node",
        args: ["guests/build-guest.mjs", name],
      }),
    )
  }
  // the Rust guest — a polyglot sample, same WIT, authored in Rust (needs
  // cargo + the wasm32-unknown-unknown target)
  out.push(
    Run({
      label: "build · \{RUST_GUEST} guest bundle (cargo → component → ESM)",
      prog: "node",
      args: ["guests/\{RUST_GUEST}/build.mjs"],
    }),
  )
  out
}

///|
/// Pack each guest's core wasm + static assets into one droppable
/// `.tutuca.tar.gz`, into a page's examples/.
///
/// `into` is a parameter rather than a constant because two pages want the same
/// archives beside them — the universal host, where they are things to place,
/// and the dyncomp storybook, where they are the story set. Packing twice into
/// one directory and symlinking would tie the two pages' assembly together for
/// no gain; they are a few hundred KB.
pub fn guest_pack_steps(into~ : String) -> Array[Step] {
  let out : Array[Step] = []
  for name in [..moonbit_guests(), RUST_GUEST] {
    out.push(
      Run({
        label: "pack · \{name} bundle → \{into}/\{name}.tutuca.tar.gz",
        prog: "node",
        args: [
          "scripts/pack-bundle.mjs",
          "guests/\{name}/dist/js",
          "\{into}/\{name}.tutuca.tar.gz",
        ],
      }),
    )
  }
  out
}

///|
const UNIVERSAL_WASM = "_build/wasm-gc/release/build/demo/universal_wasm/universal_wasm.wasm"

///|
/// Assemble the universal wasm-component demo into dist/universal: the wasm-gc
/// drop-shell app, its loader, and sample single-file bundles
/// (examples/*.tutuca.tar.gz) to drop on the page or load by URL. Kept out of
/// `dist` — the guest bundles need the component toolchain (wasm-tools +
/// @bytecodealliance/jco; see guests/counter/README.md). This is the ONE page
/// that hosts runtime-loaded bundles; the storybook gallery used to carry a
/// second, smaller shell for the same job and no longer does.
pub fn universal_steps() -> Array[Step] {
  [
    Run(
      moon("build · wasm-gc universal demo (release)", [
        "build", "--target", "wasm-gc", "--release", "demo/universal_wasm",
      ]),
    ),
    ..guest_build_steps(),
    Mkdir("\{DIST}/universal"),
    Mkdir("\{DIST}/universal/examples"),
    Copy(from=UNIVERSAL_WASM, to="\{DIST}/universal/universal_wasm.wasm"),
    Run(wasm_opt("\{DIST}/universal/universal_wasm.wasm")),
    Copy(
      from="demo/universal_wasm/loader.mjs",
      to="\{DIST}/universal/loader.mjs",
    ),
    Copy(from="app/wasm/loader.mjs", to="\{DIST}/universal/app-loader.mjs"),
    // The dyncomp bridge imports the app one. In the repo (and in the published
    // tarball, where both sit under marianoguerra/tutuca) that relative path
    // resolves; in dist the two land flat beside the page, so repoint it — the
    // same repointing the demo pages' <script src> gets.
    WriteRewritten(
      from="dyncomp/host/wasm/loader.mjs",
      to="\{DIST}/universal/dyncomp-loader.mjs",
      old_src="../../../app/wasm/loader.mjs",
      new_src="./app-loader.mjs",
    ),
    // The THIRD file, and the one easiest to forget: `dyncomp-loader.mjs`
    // `import()`s it lazily, only when an archive is actually being unpacked —
    // so a page missing it mounts, draws, and fails on the first bundle with a
    // message about a module nobody mentioned. It is the canonical ABI, which
    // moved host-side in 0.12.0 (dyncomp/host/wasm/abi.mjs), and it has no
    // imports of its own, so it is copied verbatim.
    Copy(from="dyncomp/host/wasm/abi.mjs", to="\{DIST}/universal/abi.mjs"),
    Copy(
      from="demo/universal_wasm/index.html",
      to="\{DIST}/universal/index.html",
    ),
    // pack each guest's core wasm + static assets into one droppable archive
    ..guest_pack_steps(into="\{DIST}/universal/examples"),
  ]
}

///|
const DYNCOMP_STORYBOOK_WASM = "_build/wasm-gc/release/build/demo/dyncomp_storybook_wasm/dyncomp_storybook_wasm.wasm"

///|
/// Assemble the dyncomp storybook into dist/dyncomp-storybook: the wasm-gc
/// gallery, its two loaders, and every sample bundle beside it — which this
/// page FETCHES at mount rather than offering as buttons to press, because a
/// gallery that opens empty is a gallery with an extra step.
///
/// Kept out of `dist` for the same reason `universal` is: the guest bundles
/// need the component toolchain (wasm-tools + @bytecodealliance/jco), which CI
/// does not have.
///
/// This is the second page that hosts runtime-loaded bundles, and the split
/// between them is what each one is FOR: the universal host is a blank page a
/// person builds on, and this shows everything a bundle declares without
/// anybody building anything.
pub fn dyncomp_storybook_steps() -> Array[Step] {
  [
    Run(
      moon("build · wasm-gc dyncomp storybook (release)", [
        "build", "--target", "wasm-gc", "--release", "demo/dyncomp_storybook_wasm",
      ]),
    ),
    ..guest_build_steps(),
    Mkdir("\{DIST}/dyncomp-storybook"),
    Mkdir("\{DIST}/dyncomp-storybook/examples"),
    Copy(
      from=DYNCOMP_STORYBOOK_WASM,
      to="\{DIST}/dyncomp-storybook/dyncomp_storybook_wasm.wasm",
    ),
    Run(wasm_opt("\{DIST}/dyncomp-storybook/dyncomp_storybook_wasm.wasm")),
    Copy(
      from="demo/dyncomp_storybook_wasm/loader.mjs",
      to="\{DIST}/dyncomp-storybook/loader.mjs",
    ),
    Copy(
      from="app/wasm/loader.mjs",
      to="\{DIST}/dyncomp-storybook/app-loader.mjs",
    ),
    // The dyncomp bridge imports the app one; in dist the two land flat beside
    // the page, so repoint it. Same rewrite the universal page's copy gets.
    WriteRewritten(
      from="dyncomp/host/wasm/loader.mjs",
      to="\{DIST}/dyncomp-storybook/dyncomp-loader.mjs",
      old_src="../../../app/wasm/loader.mjs",
      new_src="./app-loader.mjs",
    ),
    // The canonical ABI, `import()`ed lazily by the loader above when an
    // archive is unpacked. See the note in `universal_steps`.
    Copy(
      from="dyncomp/host/wasm/abi.mjs",
      to="\{DIST}/dyncomp-storybook/abi.mjs",
    ),
    Copy(
      from="demo/dyncomp_storybook_wasm/index.html",
      to="\{DIST}/dyncomp-storybook/index.html",
    ),
    ..guest_pack_steps(into="\{DIST}/dyncomp-storybook/examples"),
  ]
}

///|
/// Regenerate the CLI's embedded skill assets from skill/tutuca/. Run after
/// editing the skill docs, before building the native CLI.
pub fn skill_embed_steps() -> Array[Step] {
  // The generator emits one tuple per file on one line and `moon fmt` reflows
  // them, so without this the checked-in module is whatever `skill-embed` left
  // and the next `gen-views` (which formats everything) rewrites it — a 140-line
  // diff nobody asked for, on a file nobody edited. Same reason gen-views ends
  // this way.
  [
    GenSkillAssets(src_dir="skill/tutuca", to="cli/skill_assets_gen.mbt"),
    Run(moon("fmt", ["fmt"])),
  ]
}

///|
/// Regenerate the CLI's embedded guest template — the tree `tutuca new-guest`
/// writes out. Run after editing `guests/template/`, the WIT, or anything under
/// `guests/counter` that the template borrows; `dist` runs it, and
/// `check-guest-template` is what proves the result still compiles.
///
/// Ends in `moon fmt` for the same reason `skill-embed` does: the generator
/// writes one tuple per file on one line, and the next task that formats
/// everything would otherwise rewrite a file nobody edited.
pub fn guest_template_embed_steps() -> Array[Step] {
  [GenGuestTemplate(to="cli/guest_template_gen.mbt"), Run(moon("fmt", ["fmt"]))]
}

///|
const CSS_BUNDLE_BIN = "_build/native/debug/build/cmd/css-bundle/css-bundle.exe"

///|
/// Where scripts/fetch-margaui.mjs puts the margaui checkout: a gitignored,
/// throwaway spot under _build/, so the regen needs nothing but network.
const MARGAUI_CHECKOUT = "_build/margaui"

///|
/// Where scripts/fetch-tailwind.mjs extracts the stock Tailwind stylesheets from
/// the pinned npm tarball. Kept separate from the margaui checkout on purpose:
/// margaui vendors its own tw/*.css as a hand-maintained mirror, and it has run
/// behind the upstream the compiler port is derived from.
const TAILWIND_CHECKOUT = "_build/tailwind"

///|
/// Regenerate both CSS bundles + their embedded modules (css/tailwind_bundle_gen.mbt,
/// css/margaui_bundle_gen.mbt) by running the tailwindcss `bundle` graph walk over
/// each entry. The stock Tailwind stylesheets come from the npm release pinned in
/// scripts/fetch-tailwind.mjs (which also fails if that pin drifts from the tag the
/// MoonBit compiler was ported from); margaui's component layers come from a shallow
/// clone at the ref pinned in scripts/fetch-margaui.mjs. No sibling checkout to set
/// up, and the pins make the committed bundles reproducible. Kept out of `dist`/`ci`:
/// it is a rare regen run (only when margaui or Tailwind changes) and it needs the
/// network. The generated modules are committed, so normal builds never run this.
pub fn css_bundle_steps() -> Array[Step] {
  [
    Run({
      label: "fetch tailwind (pinned version) → " + TAILWIND_CHECKOUT,
      prog: "node",
      args: ["scripts/fetch-tailwind.mjs"],
    }),
    Run({
      label: "fetch margaui (pinned ref) → " + MARGAUI_CHECKOUT,
      prog: "node",
      args: ["scripts/fetch-margaui.mjs"],
    }),
    Run(
      moon("build · css-bundle tool", [
        "build", "--target", "native", "cmd/css-bundle",
      ]),
    ),
    Run({
      label: "bundle tailwind CSS graph → css/assets/tailwind.bundle.json + embed",
      prog: CSS_BUNDLE_BIN,
      args: [
        "-i",
        "css/assets/tailwind.entry.css",
        "--base",
        TAILWIND_CHECKOUT,
        "-o",
        "css/assets/tailwind.bundle.json",
        "--emit-mbt",
        "css/tailwind_bundle_gen.mbt",
        "--prefix",
        "tailwind",
      ],
    }),
    Run({
      label: "bundle margaui CSS graph → css/assets/margaui.bundle.json + embed",
      prog: CSS_BUNDLE_BIN,
      args: [
        "-i",
        "css/assets/margaui.entry.css",
        "--base",
        MARGAUI_CHECKOUT,
        "-o",
        "css/assets/margaui.bundle.json",
        "--emit-mbt",
        "css/margaui_bundle_gen.mbt",
        "--prefix",
        "margaui",
        // margaui's own tw/*.css are stale; compile_margaui resolves ./tw/*
        // against tailwind_bundle instead.
        "--skip-prefix",
        "tw/",
      ],
    }),
    // the tool emits `#|` raw-string blocks unformatted; fmt settles them.
    Run(moon("fmt", ["fmt"])),
  ]
}

///|
/// Human-readable list of every task (base + ci + dist), for `--help` / unknown.
pub fn help_text() -> String {
  let sb = StringBuilder::new()
  sb.write_string(
    "Usage: moon run --target native cmd/dev -- <task>\n\nTasks:\n",
  )
  fn line(name : String, about : String) -> Unit {
    sb.write_string("  ")
    sb.write_string(name)
    // pad to a fixed column, but always leave at least one space so a name
    // wider than the column still separates from its description.
    let gap = 12 - name.length()
    let pad = if gap < 1 { 1 } else { gap }
    for _ in 0..<pad {
      sb.write_string(" ")
    }
    sb.write_string(about)
    sb.write_string("\n")
  }

  for task in tasks() {
    line(task.name, task.about)
  }
  for entry in composites() {
    let (cname, about, _) = entry
    line(cname, about)
  }
  line("dist", "build all + assemble a runnable dist/ folder")
  line("skill-embed", "regenerate cli/skill_assets_gen.mbt from skill/tutuca/")
  line(
    "guest-template-embed", "regenerate cli/guest_template_gen.mbt (the tree `tutuca new-guest` writes) from guests/counter + dyncomp/wit + guests/template",
  )
  line(
    "universal", "assemble the drag-and-drop universal wasm demo + a sample .tutuca.tar.gz into dist/universal",
  )
  line(
    "dyncomp-storybook", "assemble the dyncomp storybook + every sample .tutuca.tar.gz into dist/dyncomp-storybook",
  )
  line(
    "css-bundle", "regenerate css/{tailwind,margaui}_bundle_gen.mbt from the pinned tailwind npm release + margaui clone (needs network)",
  )
  sb.to_string()
}
