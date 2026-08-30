// The single "place with all the tasks" for tutuca-mb. Each task plans an
// ordered list of steps (spawn a process, or a file op for `dist`); cmd/dev
// executes them in order and stops on the first failure.

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
  // copy `from` to `to`, replacing the first `old_src` with `new_src`.
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
  // walk storybook/template/, remap the .tmpl names, and write the generated
  // storybook_template_source(...) MoonBit module to `to`. Its own step rather
  // than a GenSkillAssets because the names are remapped on the way in — a
  // `moon.pkg.tmpl` that arrived as `moon.pkg` would make the template a
  // package of this module.
  GenStorybookTemplate(to~ : String)
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
  { label, prog: "moon", args, }
}

///|
/// How many jobs the NATIVE test run may use at once.
///
/// Capped, and this is the one command in the file that needs a cap. `moon test
/// --target native` links 49 separate test binaries, and a link is
/// whole-program: the two largest objects are ~100 MB (`benchmarks`,
/// `storybook`) and the `moonc` doing one peaks around 1.8 GB RESIDENT. With
/// moon's default fan-out of one job per core, eight of those coincide on an
/// 8-core machine and the machine is simply out of memory — the kernel kills
/// `moonc` (or, just as often, whatever else was running), and the run dies
/// with exit 137 rather than a test failure.
///
/// Measured on a 12 GB / 8-core box, whole suite, cold `_build`:
///
/// | jobs | peak RSS across all `moonc` | outcome |
/// | ---- | --------------------------- | ------- |
/// | 8 (default) | not measured | OOM-killed; the kill IS the observation |
/// | 4    | 4.5 GB | passes, 131 s |
/// | 2    | 3.5 GB | passes, slower |
///
/// The default row has no number on purpose: the run dies before a peak can be
/// read, and the evidence for it is the kernel's own log
/// (`Killed process … (moonc) anon-rss:1504960kB`) rather than a sample.
///
/// Four rather than two because the ceiling is what matters and not the
/// average: most of the 49 links are small, so the cap costs little wall time
/// and only bites when several heavy ones would have overlapped.
///
/// It is a fixed number rather than one derived from the machine because the
/// failure it prevents is silent and confusing — an OOM kill reads as a
/// mysterious crash, not as "too many jobs" — and a developer meeting it for
/// the first time has no reason to suspect parallelism. A machine with more
/// memory pays a little wall time for that; the trade is worth it.
///
/// The other native commands are deliberately uncapped: `build · native cli`
/// links ONE package, and `check · native` does not link at all.
const NATIVE_TEST_JOBS : String = "4"

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
const NATIVE_BIN = "_build/native/debug/build/cmd/tutuca/tutuca.exe"

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
        moon("test · native", [
          "test",
          "--target",
          "native",
          "-j",
          NATIVE_TEST_JOBS,
        ]),
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
      about: "regenerate the benchmark view corpus (all_views.html, one_big_view.html, corpus_gen.mbt)",
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
      name: "guest-harness",
      about: "build the guest bundles, then run the node harnesses over them (needs wasm-tools + jco)",
      // The only RUNTIME coverage the guest ABI, the table codec and the
      // bluesky/slack/rust guests have — eight node test files whose only
      // invocation instruction was a sentence in CONTRIBUTING.md. It cannot be
      // in `ci` (building a guest needs wasm-tools and jco, which CI has not
      // got), but it can at least be one command like everything else.
      commands: [
        guest_list_check(),
        {
          label: "build · every guest bundle (see the `guests` task)",
          prog: "node",
          args: ["scripts/run-guest-harnesses.mjs"],
        },
      ],
    },
    {
      name: "sanitizer-defaults",
      about: "regenerate anode/sanitize/spec_default_gen.mbt from the WHATWG spec's built-in config, then drift-check (needs network)",
      // The one generated-from-upstream file with no task: the CSS bundles have
      // `css-bundle` and the guest bindings have their own, while this was a
      // bare `node scripts/…` in two docs.
      //
      // Regenerate → fmt → drift-check, the same shape `skill-embed` and
      // `gen-views` use, rather than the script's own `--check`. That flag
      // compares the generator's RAW output against the committed file, which
      // `moon fmt` has since reformatted — so it reported "stale" on a file
      // whose content was byte-identical. Formatting first is what makes the
      // comparison mean what it says.
      commands: [
        {
          label: "regenerate · sanitizer defaults from the spec's builtins",
          prog: "node",
          args: ["scripts/fetch-sanitizer-defaults.mjs"],
        },
        moon("fmt", ["fmt"]),
        {
          label: "drift check · sanitizer defaults match the spec",
          prog: "git",
          args: [
            "diff", "--exit-code", "HEAD", "--", "anode/sanitize/spec_default_gen.mbt",
          ],
        },
      ],
    },
    {
      name: "dom-props",
      about: "regenerate eventpath/dom_props_gen.mbt from the browser specs' machine-extracted IDL, then drift-check (needs network)",
      // The type oracle an `e.<path>` is checked against. Same shape as
      // `sanitizer-defaults` above and for the same reason: the table has to
      // come from the specifications rather than from a summary of them, and
      // the drift check has to compare like with like, so the format step is
      // between the two.
      //
      // Not in `ci` — it fetches. What `ci` gets instead is the checked-in
      // file, which a person regenerates and commits when a pin moves.
      commands: [
        {
          label: "regenerate · DOM properties from webref's extracted IDL",
          prog: "node",
          args: ["scripts/fetch-dom-props.mjs"],
        },
        moon("fmt", ["fmt"]),
        {
          label: "drift check · DOM properties match the specs",
          prog: "git",
          args: [
            "diff", "--exit-code", "HEAD", "--", "eventpath/dom_props_gen.mbt",
          ],
        },
      ],
    },
    {
      name: "css-properties",
      about: "regenerate anode/sanitize/css/properties_gen.mbt from the W3C's CSS extracts, then drift-check (needs network)",
      // The same shape as `sanitizer-defaults`, and for the same reason: the
      // script's own `--check` compares raw generator output against a file
      // `moon fmt` has reformatted, so formatting first is what makes the
      // comparison mean what it says.
      //
      // Read the diff rather than the exit code. This is the table that decides
      // which properties can reach a URL, and a name ENTERING `url_properties`
      // is a property the validator has to stop admitting freely.
      commands: [
        {
          label: "regenerate · css property facts from the W3C extracts",
          prog: "node",
          args: ["scripts/fetch-css-properties.mjs"],
        },
        moon("fmt", ["fmt"]),
        {
          label: "drift check · css property facts match the specs",
          prog: "git",
          args: [
            "diff", "--exit-code", "HEAD", "--", "anode/sanitize/css/properties_gen.mbt",
          ],
        },
      ],
    },
    {
      name: "check-guest-list",
      about: "hold dev/tasks.mbt's guest list against guests/guests.mjs",
      // `guests` runs this too, but it belongs in `ci` on its own: the guest
      // build needs wasm-tools + jco and so can never be in CI, which is
      // exactly how `table` stayed unbuilt. This check is plain node.
      commands: [guest_list_check()],
    },
    {
      name: "check-storybook-template",
      about: "scaffold a gallery with the embedded template and check its shape (structural: it depends on a PUBLISHED tutuca, so ci cannot compile it)",
      commands: [
        // The guest template can be compiled in `ci` because the tree it writes
        // depends on no module at all. This one depends on the published
        // `marianoguerra/tutuca` — which will not contain the packages the
        // scaffold imports until the release that adds them — so the compile
        // check belongs to `examples/`, after a release. What is checkable here
        // is the shape: no placeholder left unsubstituted, the export list and
        // the page's `pub fn`s agreeing, and every file index.html asks for
        // being one build.mjs writes.
        moon("build · native CLI (with the storybook template embedded)", [
          "build", "--target", "native", "cmd/tutuca",
        ]),
        {
          label: "check · scaffolded gallery is well-formed",
          prog: "node",
          args: ["scripts/check-storybook-template.mjs"],
        },
      ],
    },
    {
      name: "check-publish-graph",
      about: "no shipping package may import one moon.mod excludes (test blocks included)",
      commands: [
        // The invariant the tarball does not enforce for you: an excluded
        // package is sitting right here in the working tree, so `moon check` is
        // happy and only a consumer who unpacked the archive sees the break.
        {
          label: "check · published package graph is closed",
          prog: "node",
          args: ["scripts/check-publish-graph.mjs"],
        },
        {
          label: "check · MODULE_VERSION matches moon.mod",
          prog: "node",
          args: ["scripts/check-module-version.mjs"],
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
          "build", "--target", "native", "cmd/tutuca",
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
      about: "assemble dist/tutucard/ (the card playground, which carries the card compiler and no MoonBit one): build the js host, the margaui class compiler and the CodeMirror bundle, copy the shell, then check every starter card checks AND compiles AND that every scene its `tutuca/test` block declares passes",
      commands: [
        // No MoonBit compiler, no worker, no prebuilt .mi/.core closure and no
        // toolchain pin — a card is parsed and mounted, so what ships is the
        // runtime and the page, plus the two things a card can ask for:
        // margaui.wasm (the starter cards are written in margaui classes and
        // the page compiles them in the browser) and editor.bundle.js (the
        // CodeMirror the page upgrades its textareas to, and an `<mb-card
        // codemirror>` its own). Both are fetched lazily, after the first card
        // is mounted, so neither is ever in front of the page.
        // assemble.mjs runs all three builds itself.
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
        // …and every scene every card DECLARES. The three gates above prove a
        // card loads: it checks, it compiles, the host takes the bytes. None of
        // them presses a button, so a card whose `inc` adds two passes all
        // three. This mounts each card on the in-memory DOM and runs the steps
        // its `<script type="tutuca/test">` block names.
        {
          label: "check · card scenes pass",
          prog: "node",
          args: ["tutucard/build/run-tests.mjs"],
        },
        // …and a card does not grow a table entry per keystroke. Both halves of
        // the collector: the superseded handle a successor replaced, and the
        // row that was simply removed and superseded by nothing.
        {
          label: "check · card instances are collected",
          prog: "node",
          args: ["tutucard/build/check-instances.mjs"],
        },
        // The structured view EDITS the card by character offset, which is the
        // one part of this page that can corrupt what an author typed. Held to
        // its contract without a browser.
        {
          label: "check · card regions split and splice",
          prog: "node",
          args: ["tutucard/build/check-regions.mjs"],
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
        { label: "npm install", prog: "npm", args: ["install"], },
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
/// wasm backend reads it as JSON, but the MoonBit backend's answers only exist
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
    ("storybook/inspector/activity.html", None),
    ("storybook/inspector/json.html", None),
    ("storybook/inspector/component_inspector.html", None),
    ("storybook/inspector/instance_inspector.html", None),
    ("storybook/inspector/state_editor.html", None),
    ("storybook/inspector/schema_components.html", None),
    ("storybook/inspector/schema.html", None),
    ("storybook/inspector/module.html", None),
    ("storybook/inspector/fuzz_view.html", None),
    ("storybook/inspector/spec_view.html", None),
    ("storybook/inspector/trace_view.html", None),
    ("docs/tutorial.html", None),
    ("docs/first_principles.html", None),
    ("storybook/inspector/schema_viewer.html", Some("SchemaViewer")),
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
    // Not a package of this module — it is the demo component inside the
    // project `tutuca new-storybook` writes. It is swept here so the generated
    // module the template hands a stranger is the one this generator produces.
    ("storybook/template/page/counter.html", None),
  ]
  // Snapshot the generated modules BEFORE regenerating, so the check at the end
  // can ask whether regenerating changed anything rather than whether the tree
  // matches a commit. See that check for why the two are not the same question.
  let commands = [view_drift_snapshot(VIEW_DRIFT_BEFORE)]
  for entry in files {
    let (path, name) = entry
    let args = [
      "run", "--target", "native", "cmd/tutuca", "--", "gen-views", path,
    ]
    match name {
      Some(n) => {
        args.push("--name")
        args.push(n)
      }
      None => ()
    }
    commands.push(moon("gen-views · " + path, args))
  }
  commands.push(moon("fmt", ["fmt"]))
  // The drift check: regenerating is only a guarantee if the checked-in modules
  // are what regenerating produces. This is what makes `gen-views` safe to put
  // in CI — a stale generated module type-checks and tests green, so nothing
  // else catches it.
  //
  // It compares the generated modules BEFORE this run against the same modules
  // after, which is the question the check means to ask: did regenerating change
  // anything? This used to ask git whether they matched `HEAD`, which is a
  // different question and only the same one on a clean tree. Edit a `.html`,
  // regenerate its module, and the pair is perfectly consistent while neither
  // half is committed — the git form failed the whole of `ci` on correct work,
  // which made `ci` unrunnable during exactly the kind of change it guards.
  // (`skill-embed` had the same defect and is fixed the same way; the
  // guest-binding and fetched-upstream checks still have it.)
  //
  // Scoped to the generated modules by pathspec rather than run over the whole
  // tree, because the `moon fmt` above formats every source: an unrelated file
  // that was committed unformatted would otherwise be reported as view drift.
  // `*_view_gen.mbt` matches at any depth, so a new view file is covered the
  // moment it is added to `files` above.
  //
  // Nothing is lost by leaving git's own comparison behind. The `HEAD --` form
  // was chosen so a `git add` of a stale module could not walk past a bare
  // `git diff`; a before/after comparison never consults the index or the
  // commit for its VERDICT at all, so there is no state a stale module can
  // hide in.
  commands.push(view_drift_snapshot(VIEW_DRIFT_AFTER))
  commands.push({
    label: "drift check · generated view modules match their .html",
    prog: "diff",
    args: [VIEW_DRIFT_BEFORE, VIEW_DRIFT_AFTER],
  })
  commands
}

///|
/// Where the two views of the generated modules are parked.
///
/// In `_build` because it is already gitignored — a drift check that littered
/// the tree with files the next drift check then had to ignore would be its own
/// small joke.
const VIEW_DRIFT_BEFORE : String = "_build/view_drift.before"

///|
const VIEW_DRIFT_AFTER : String = "_build/view_drift.after"

///|
/// Record what the generated view modules look like right now.
///
/// `git diff` is used as a CONTENT READER here and not as the verdict: it
/// prints the modules as they currently stand against a fixed reference, so two
/// such readings taken either side of a regeneration differ exactly when
/// regenerating changed a file. Which commit it diffs against does not matter,
/// as long as both readings use the same one.
///
/// A shell, because a `Command` spawns a program with arguments and has nowhere
/// to put a redirect. The `mkdir -p` is part of it since `_build` is absent in a
/// fresh clone, which is precisely the case CI runs in.
fn view_drift_snapshot(to : String) -> Command {
  {
    label: "snapshot · generated view modules",
    prog: "sh",
    args: [
      "-c",
      "mkdir -p _build && git diff HEAD -- '*_view_gen.mbt' '*_view_ir_gen.mbt' > " +
      to,
    ],
  }
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
      label: "drift check · guests/ + dice are reproducible from the WIT",
      prog: "git",
      args: [
        "diff", "--exit-code", "--", "guests", "examples/dyncomp-dice/dice",
      ],
    },
  ]
}

///|
fn build_commands() -> Array[Command] {
  [
    moon("build · wasm-gc", ["build", "--target", "wasm-gc"]),
    moon("build · native cli", ["build", "--target", "native", "cmd/tutuca"]),
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
/// Assembled tasks: name -> (about, the steps it plans).
///
/// These cannot be `tasks()` entries because they are not a list of commands —
/// each builds its plan, with mkdirs, copies and rewrites interleaved.
/// One list, walked by both.
fn assembled() -> Array[(String, String, () -> Array[Step])] {
  [
    ("dist", "build all + assemble a runnable dist/ folder", dist_steps),
    (
      "skill-embed", "regenerate cli/skill_assets_gen.mbt from skill/tutuca/", skill_embed_steps,
    ),
    (
      "guest-template-embed", "regenerate cli/guest_template_gen.mbt (the tree `tutuca new-guest` writes) from guests/counter + dyncomp/wit + guests/template",
      guest_template_embed_steps,
    ),
    (
      "storybook-template-embed", "regenerate cli/storybook_template_gen.mbt (the gallery project `tutuca new-storybook` writes) from storybook/template",
      storybook_template_embed_steps,
    ),
    (
      "universal", "assemble the drag-and-drop universal wasm demo + a sample .tutuca.tar.gz into dist/universal",
      universal_steps,
    ),
    (
      "dyncomp-storybook", "assemble the dyncomp storybook + every sample .tutuca.tar.gz into dist/dyncomp-storybook",
      dyncomp_storybook_steps,
    ),
    (
      "guests", "build every guest bundle (wit-bindgen output → component → ESM); needs wasm-tools + jco",
      guest_build_steps,
    ),
    (
      "css-bundle", "regenerate css/{tailwind,margaui}_bundle_gen.mbt from the pinned tailwind npm release + margaui clone (needs network)",
      css_bundle_steps,
    ),
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
    //
    // `skill-embed` is here for exactly the same reason:
    // `cli/skill_assets_gen.mbt` is checked in, compiles whatever it
    // holds, and ships inside the binary — so a skill doc edited without
    // re-embedding is invisible until somebody runs `tutuca install-skill` and
    // reads the wrong thing. It runs AFTER `gen-views`, because that task ends
    // in `moon fmt` over everything.
    (
      "ci",
      "gen-views drift + skill-embed drift + check + the example/skill/guest checks + test + build (build-smokes every backend & demo)",
      [
        "gen-views", "skill-embed", "storybook-template-embed", "check", "check-examples",
        "check-skill", "check-guest-list", "check-guest-template", "check-storybook-template",
        "check-publish-graph", "test", "build",
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
  for step in storybook_template_embed_steps() {
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
  // The Trace tab's Download and Load. `@panelsw.all` names `files/wasm`, so
  // the gallery's wasm declares the `tfiles` import and a page without this
  // file does not instantiate at all. Rewritten on the way, for the reason
  // `dyncomp-loader.mjs` is: it imports the app loader by a repo-relative
  // path, and in dist the two land flat beside the page.
  steps.push(
    WriteRewritten(
      from="files/wasm/loader.mjs",
      to="\{DIST}/storybook/files-loader.mjs",
      old_src="../../app/wasm/loader.mjs",
      new_src="./app-loader.mjs",
    ),
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
  // The card runtime, which the landing site's <mb-card> embeds load, and the
  // margaui class compiler an `<mb-card margaui>` fetches. Assembled BEFORE the
  // site, because assemble-site.mjs copies both out of dist/tutucard/ — the
  // card playground itself is a separate task, but its runtime is what makes an
  // embedded card on the landing page work at all.
  steps.push(
    Run({
      label: "assemble dist/tutucard (the card runtime the site embeds)",
      prog: "node",
      args: ["tutucard/build/assemble.mjs"],
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
  for entry in assembled() {
    let (aname, _, steps) = entry
    if aname == name {
      return Some(steps())
    }
  }
  None
}

///|
/// Every guest bundle, in one list.
///
/// ONE list. The justfile is a thin wrapper over the `guests` task below, and
/// `guests/guests.mjs` still owns which names `build-guest.mjs` accepts,
/// because that is a fact about the script rather than about the build.
///
/// The Rust one is separate: same WIT, but it builds through cargo rather than
/// moon, so it keeps its own script.
fn moonbit_guests() -> Array[String] {
  [
    "counter", "table", "todo", "todomvc", "calculator", "tictactoe", "bluesky",
    "mastodon", "slack", "dice",
  ]
}

///|
/// Where a guest's tree is, relative to the repo root.
///
/// The mirror of `guestDir` in `guests/guests.mjs`, and it exists for the one
/// guest that is not under `guests/`: the die that `examples/dyncomp-dice`
/// ships. That example is a CONSUMER of the published package — no path
/// dependency anywhere under it, deliberately — but its guest implements this
/// repo's WIT, and being out of the way is exactly how it came to sit at
/// `tutuca:component@0.5.0` through two package bumps while everything else
/// moved. Building and packing it here is what keeps it honest.
fn guest_src_dir(name : String) -> String {
  if name == "dice" {
    "examples/dyncomp-dice/dice"
  } else {
    "guests/\{name}"
  }
}

///|
const RUST_GUEST = "rust-tempconv"

///|
/// Hold the list above against `guests/guests.mjs`, which owns the names
/// `build-guest.mjs` accepts.
///
/// The two lists cannot become one: this package is I/O-free by design, so it
/// cannot read the other. They can be made to disagree loudly instead. Pure
/// node, so unlike the guest build itself it costs nothing and runs in `ci`.
fn guest_list_check() -> Command {
  {
    label: "check · guest list matches guests/guests.mjs",
    prog: "node",
    args: ["scripts/check-guest-list.mjs", ..moonbit_guests()],
  }
}

///|
/// Build every guest bundle: wit-bindgen output → component → ESM.
pub fn guest_build_steps() -> Array[Step] {
  let out : Array[Step] = [Run(guest_list_check())]
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
          "\{guest_src_dir(name)}/dist/js",
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
/// that hosts runtime-loaded bundles.
pub fn universal_steps() -> Array[Step] {
  dyncomp_page_steps(
    label="universal demo",
    demo="demo/universal_wasm",
    wasm=UNIVERSAL_WASM,
    into="universal",
  )
}

///|
/// Assemble one bundle-hosting page into `dist/<into>/`.
///
/// The two such pages differ in what they SHOW — a blank host to build on
/// versus a gallery that fetches everything at mount — and in nothing about
/// how they are assembled: same release build, same guest bundles, same four
/// loader files with the same repointing, same packed archives beside them.
/// That was eleven steps written out twice, which is eleven chances for the
/// pages to be assembled differently for no reason anybody chose.
fn dyncomp_page_steps(
  label~ : String,
  demo~ : String,
  wasm~ : String,
  into~ : String,
) -> Array[Step] {
  let dir = "\{DIST}/\{into}"
  // The .wasm keeps the demo package's own name beside the page, which is what
  // that page's index.html and loader already fetch.
  let wasm_name = wasm.split("/").last().unwrap_or(wasm).to_owned()
  [
    Run(
      moon("build · wasm-gc \{label} (release)", [
        "build", "--target", "wasm-gc", "--release", demo,
      ]),
    ),
    ..guest_build_steps(),
    Mkdir(dir),
    Mkdir("\{dir}/examples"),
    Copy(from=wasm, to="\{dir}/\{wasm_name}"),
    Run(wasm_opt("\{dir}/\{wasm_name}")),
    Copy(from="\{demo}/loader.mjs", to="\{dir}/loader.mjs"),
    Copy(from="app/wasm/loader.mjs", to="\{dir}/app-loader.mjs"),
    // The dyncomp bridge imports the app one. In the repo (and in the published
    // tarball, where both sit under marianoguerra/tutuca) that relative path
    // resolves; in dist the two land flat beside the page, so repoint it — the
    // same repointing the demo pages' <script src> gets.
    WriteRewritten(
      from="dyncomp/host/wasm/loader.mjs",
      to="\{dir}/dyncomp-loader.mjs",
      old_src="../../../app/wasm/loader.mjs",
      new_src="./app-loader.mjs",
    ),
    // The THIRD file, and the one easiest to forget: `dyncomp-loader.mjs`
    // `import()`s it lazily, only when an archive is actually being unpacked —
    // so a page missing it mounts, draws, and fails on the first bundle with a
    // message about a module nobody mentioned. It is the canonical ABI, which
    // moved host-side in 0.12.0 (dyncomp/host/wasm/abi.mjs), and it has no
    // imports of its own, so it is copied verbatim.
    Copy(from="dyncomp/host/wasm/abi.mjs", to="\{dir}/abi.mjs"),
    Copy(from="\{demo}/index.html", to="\{dir}/index.html"),
    // pack each guest's core wasm + static assets into one droppable archive
    ..guest_pack_steps(into="\{dir}/examples"),
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
  dyncomp_page_steps(
    label="dyncomp storybook",
    demo="demo/dyncomp_storybook_wasm",
    wasm=DYNCOMP_STORYBOOK_WASM,
    into="dyncomp-storybook",
  )
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
    // Snapshot FIRST, so the check below can compare the file against what
    // regenerating produces rather than against a commit. See the comment on
    // the diff step for why that difference matters.
    //
    // The mkdir is not optional: `copy_file` writes the file and does not make
    // its parent, and `_build` is absent in a fresh clone — which is precisely
    // the case CI runs in.
    Mkdir("_build"),
    Copy(from=SKILL_EMBED, to=SKILL_EMBED_WAS),
    GenSkillAssets(src_dir="skill/tutuca", to=SKILL_EMBED),
    Run(moon("fmt", ["fmt"])),
    // The drift check: is the checked-in module what regenerating from
    // `skill/tutuca/` produces? What it exists to catch is real and has
    // happened — `skill/tutuca/cli.md` lost two sections and every paragraph
    // blank line, and the broken text was embedded and shipped inside the CLI
    // binary, which is what `tutuca install-skill` writes out and the first
    // thing an agent reads before writing any tutuca code.
    //
    // It compares CONTENT — the file as it was against the file as regenerated
    // — where this used to ask git whether the file matched `HEAD`. The git
    // form answers a different question than the one the check means to ask,
    // and the two only agree when the working tree is clean. Edit a skill file
    // and re-embed it, and the pair on disk is perfectly consistent while
    // neither half is committed yet: the content check passes, and the git form
    // failed the whole of `ci` on work that was correct. Which made `ci`
    // unrunnable during exactly the change it was meant to guard.
    //
    // Nothing is lost by moving off git. The `HEAD --` form was chosen so that
    // a `git add` of a stale module could not walk past a bare `git diff`, and
    // a content comparison is stronger still: it never consults the index or
    // the commit at all, so there is no state a stale file can hide in.
    Run({
      label: "drift check · cli/skill_assets_gen.mbt matches skill/tutuca/",
      prog: "diff",
      args: [SKILL_EMBED_WAS, SKILL_EMBED],
    }),
  ]
}

///|
/// The embedded-skill module, and where its pre-regeneration copy is parked.
///
/// The snapshot sits in `_build` because that is already gitignored: a drift
/// check that littered the tree with a file the next drift check then had to
/// ignore would be its own small joke.
const SKILL_EMBED : String = "cli/skill_assets_gen.mbt"

///|
const SKILL_EMBED_WAS : String = "_build/skill_assets_gen.mbt.was"

///|
const STORYBOOK_EMBED : String = "cli/storybook_template_gen.mbt"

///|
const STORYBOOK_EMBED_WAS : String = "_build/storybook_template_gen.mbt.was"

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
/// Regenerate the CLI's embedded storybook template — the gallery project
/// `tutuca new-storybook` writes out. Run after editing `storybook/template/`;
/// `dist` runs it, and `check-storybook-template` is what proves the result is
/// still well-formed.
///
/// Ends in `moon fmt` for the reason the other two embeds do: the generator
/// writes one tuple per file on one line, and the next task that formats
/// everything would otherwise rewrite a file nobody edited.
pub fn storybook_template_embed_steps() -> Array[Step] {
  [
    // Snapshot, regenerate, compare — the shape `skill-embed` uses, and for the
    // reason it was given one: this embed IS what a stranger reads. It shipped
    // once carrying a scaffold README that showed an API the same release had
    // renamed, because editing `storybook/template/` and forgetting to re-embed
    // leaves a file that compiles, passes `check-storybook-template` (which
    // reads the SCAFFOLD, not this) and is wrong.
    Mkdir("_build"),
    Copy(from=STORYBOOK_EMBED, to=STORYBOOK_EMBED_WAS),
    GenStorybookTemplate(to=STORYBOOK_EMBED),
    Run(moon("fmt", ["fmt"])),
    Run({
      label: "drift check · cli/storybook_template_gen.mbt matches storybook/template/",
      prog: "diff",
      args: [STORYBOOK_EMBED_WAS, STORYBOOK_EMBED],
    }),
  ]
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
  let sb = StringBuilder()
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
  for entry in assembled() {
    let (aname, about, _) = entry
    line(aname, about)
  }
  sb.to_string()
}
