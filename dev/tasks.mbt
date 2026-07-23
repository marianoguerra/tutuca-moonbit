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

// --- build-output and dist layout paths (moon's default debug build) ---

///|
const COUNTER_JS = "_build/js/debug/build/demo/counter/counter.js"

///|
const COUNTER_WASM = "_build/wasm-gc/debug/build/demo/counter_wasm/counter_wasm.wasm"

///|
const STORYBOOK_WASM = "_build/wasm-gc/debug/build/demo/storybook_wasm/storybook_wasm.wasm"

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
/// One entry per repo-owned view file. Run after editing an .html view, and in
/// CI followed by `git diff --exit-code` to catch a generated module that has
/// drifted from its source. A file whose components carry template ids needs no
/// `--name`; a bare single-component `<template>` names its component with one.
///
/// The CLI emits unformatted source, so the run ends with `moon fmt` — that is
/// what makes the checked-in pair reproducible and the drift check meaningful.
fn gen_views_commands() -> Array[Command] {
  // (relative .html path, --name override or None)
  let files : Array[(String, String?)] = [
    ("demo/counterlib/counter.html", Some("Counter")),
    ("demo/universal_wasm/universal_wasm.html", None),
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
    ("storybook/examples/list_iteration.html", Some("ListIteration")),
    ("storybook/examples/personal_site.html", None),
    ("storybook/examples/pseudo_x.html", None),
    ("storybook/examples/render_child.html", None),
    ("storybook/examples/rendering.html", None),
    ("storybook/examples/request.html", Some("RequestExample")),
    ("storybook/examples/state_and_updates.html", None),
    ("storybook/examples/styles.html", None),
    ("storybook/examples/todo.html", None),
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
  commands
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
    (
      "ci",
      "check + check-examples + test + build (build-smokes every backend & demo)",
      ["check", "check-examples", "test", "build"],
    ),
  ]
}

///|
/// The `dist` step plan: build every target, then assemble a self-contained
/// `dist/` folder (bundles + repointed demo pages + a landing index.html + the
/// native CLI binary) that runs from any static file server.
fn dist_steps() -> Array[Step] {
  let steps : Array[Step] = []
  // refresh the CLI's embedded skill assets before the native build
  for step in skill_embed_steps() {
    steps.push(step)
  }
  for cmd in build_commands() {
    steps.push(Run(cmd))
  }
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
  steps.push(
    Copy(
      from="demo/counter_wasm/loader.mjs",
      to="\{DIST}/counter-wasm/loader.mjs",
    ),
  )
  steps.push(
    Copy(
      from="demo/wasm-loader-lib.mjs",
      to="\{DIST}/counter-wasm/wasm-loader-lib.mjs",
    ),
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
    Copy(
      from="demo/wasm-loader-lib.mjs",
      to="\{DIST}/storybook/wasm-loader-lib.mjs",
    ),
  )
  steps.push(Mkdir("\{DIST}/storybook/counter"))
  steps.push(
    Copy(
      from="demo/storybook_wasm/index.html",
      to="\{DIST}/storybook/index.html",
    ),
  )
  // the counter guest bundle for the Dynamic pane is copied by the
  // `storybook-bundle` task (it needs the component toolchain); without it the pane
  // shows a load error and everything else works.
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
  if name == "storybook-bundle" {
    return Some(storybook_bundle_steps())
  }
  if name == "universal" {
    return Some(universal_steps())
  }
  None
}

///|
/// Build the jco-transpiled counter guest bundle and copy it into
/// dist/storybook/counter, where the storybook "Dynamic" story loads it at
/// runtime. Kept out of `dist`: the guest pipeline needs the component
/// toolchain (wasm-tools + @bytecodealliance/jco — see guests/counter/README.md),
/// which plain dist users may not have. (The standalone dyncomp demo page was
/// removed — its loading UX lives in the universal demo, its state-migrating
/// hot-swap in this storybook story.)
pub fn storybook_bundle_steps() -> Array[Step] {
  let steps : Array[Step] = [
    Run({
      label: "build · counter guest bundle (wit-bindgen output → component → ESM)",
      prog: "node",
      args: ["guests/counter/build.mjs"],
    }),
    Mkdir("\{DIST}/storybook"),
    Mkdir("\{DIST}/storybook/counter"),
  ]
  for
    f in [
      "counter.component.js", "counter.component.core.wasm", "counter.component.core2.wasm",
      "counter.component.core3.wasm",
    ] {
    steps.push(
      Copy(
        from="guests/counter/dist/js/\{f}",
        to="\{DIST}/storybook/counter/\{f}",
      ),
    )
  }
  steps
}

///|
const UNIVERSAL_WASM = "_build/wasm-gc/debug/build/demo/universal_wasm/universal_wasm.wasm"

///|
/// Assemble the universal wasm-component demo into dist/universal: the wasm-gc
/// drop-shell app, its loader, and sample single-file bundles
/// (examples/*.tutuca.tar.gz) to drag onto the page. Like `storybook-bundle`,
/// kept out of `dist` — the guest bundles need the component toolchain
/// (wasm-tools + @bytecodealliance/jco; see guests/counter/README.md).
pub fn universal_steps() -> Array[Step] {
  [
    Run(
      moon("build · wasm-gc universal demo", [
        "build", "--target", "wasm-gc", "demo/universal_wasm",
      ]),
    ),
    Run({
      label: "build · counter guest bundle (wit-bindgen output → component → ESM)",
      prog: "node",
      args: ["guests/counter/build.mjs"],
    }),
    Run({
      label: "build · todo guest bundle (wit-bindgen output → component → ESM)",
      prog: "node",
      args: ["guests/todo/build.mjs"],
    }),
    // the Rust guest — a polyglot sample, same WIT, authored in Rust (needs
    // cargo + the wasm32-unknown-unknown target)
    Run({
      label: "build · rust-counter guest bundle (cargo → component → ESM)",
      prog: "node",
      args: ["guests/rust-counter/build.mjs"],
    }),
    Mkdir("\{DIST}/universal"),
    Mkdir("\{DIST}/universal/examples"),
    Copy(from=UNIVERSAL_WASM, to="\{DIST}/universal/universal_wasm.wasm"),
    Copy(
      from="demo/universal_wasm/loader.mjs",
      to="\{DIST}/universal/loader.mjs",
    ),
    Copy(
      from="demo/wasm-loader-lib.mjs",
      to="\{DIST}/universal/wasm-loader-lib.mjs",
    ),
    Copy(
      from="demo/universal_wasm/index.html",
      to="\{DIST}/universal/index.html",
    ),
    // pack each guest's jco output into one droppable .tutuca.tar.gz
    Run({
      label: "pack · counter bundle → examples/counter.tutuca.tar.gz",
      prog: "node",
      args: [
        "scripts/pack-bundle.mjs", "guests/counter/dist/js", "dist/universal/examples/counter.tutuca.tar.gz",
      ],
    }),
    Run({
      label: "pack · todo bundle → examples/todo.tutuca.tar.gz",
      prog: "node",
      args: [
        "scripts/pack-bundle.mjs", "guests/todo/dist/js", "dist/universal/examples/todo.tutuca.tar.gz",
      ],
    }),
    Run({
      label: "pack · rust-counter bundle → examples/rust-counter.tutuca.tar.gz",
      prog: "node",
      args: [
        "scripts/pack-bundle.mjs", "guests/rust-counter/dist/js", "dist/universal/examples/rust-counter.tutuca.tar.gz",
      ],
    }),
  ]
}

///|
/// Regenerate the CLI's embedded skill assets from skill/tutuca/. Run after
/// editing the skill docs, before building the native CLI.
pub fn skill_embed_steps() -> Array[Step] {
  [GenSkillAssets(src_dir="skill/tutuca", to="cli/skill_assets_gen.mbt")]
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
    "storybook-bundle", "build the counter guest bundle into dist/storybook/counter (the storybook Dynamic story)",
  )
  line(
    "universal", "assemble the drag-and-drop universal wasm demo + a sample .tutuca.tar.gz into dist/universal",
  )
  sb.to_string()
}
