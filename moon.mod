name = "marianoguerra/tutuca"

version = "0.52.0"

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/tutuca-moonbit"

license = "MIT"

keywords = [ "ui", "framework", "vdom", "reactive", "moonbit" ]

// Fast pure-logic default: every package except the js/native shells checks
// and tests under wasm-gc. Full coverage needs the other targets too — see
// "Targets" in AGENTS.md.

preferred_target = "wasm-gc"

description = "MoonBit port of the tutuca UI framework (value language, templates, vdom, components, app runtime, lint, CLI)"

import {
  "moonbitlang/quickcheck@0.14.0",
  "mizchi/js@0.12.2",
  "mizchi/js_browser@0.12.2",
  "moonbitlang/async@0.21.2",
  "moonbit-community/html@0.2.1",
  "mizchi/fswatch@0.2.1",
  // Only `mizchi/css/token` is used, by `anode/sanitize/css` — a css-syntax-3
  // tokenizer with no dependency of its own beyond `moonbitlang/core/string`.
  // The parser, cascade and computed packages are NOT used: `parse_inline_style`
  // returns a layout engine's `@style.Style`, which cannot round-trip a
  // declaration list, and round-tripping is the whole point. Apache-2.0, where
  // this module is MIT.
  "mizchi/css@0.7.3",
  // The Wax compiler, for `tgc/emit` — the card-to-core-wasm backend.
  // Dependency-free itself, and MoonBit links per package, so a consumer who
  // never compiles a card pays the fetch and nothing else.
  "marianoguerra/wax@0.2.1",
  "marianoguerra/tailwindcss@0.4.0",
  "moonbitlang/x@0.5.1",
}

// What `moon publish` ships. Consumers get the library packages, the CLI
// (cmd/tutuca -> cli/) and the docs; they don't get the demo/playground/guest
// hosts or the dev tooling — those only make sense inside this repo. Check
// with `moon package --list`.
//
// `storybook/` SHIPS, except its corpus and its scaffold. The model
// (`storybook`), the gallery shell (`storybook/ui`), the panel layer
// (`storybook/ui/panels`) and the two browser halves (`storybook/ui/wasm`,
// `storybook/ui/panels/wasm`) are how a project gets a gallery of ITS OWN
// components, which is the point of having written them. What stays behind is
// `storybook/examples` — this repo's own demos plus the fixtures the lint and
// view sweeps and `benchmarks` run over, editorial content rather than a
// library — and `storybook/template`, which already travels inside the CLI.
// The split is what `stories_of_module` is for: a consumer's story set is a
// projection of their own modules, so nobody needs ours.
//
// The rule that keeps this honest is `scripts/check-publish-graph.mjs` in `ci`:
// no shipping package may import an excluded one, in a `for "test"` block
// either — test files are in the tarball too.
//
// `tgc/` SHIPS. It is the component format — the frozen preamble, the value
// codecs, the runtime module, the card compiler, and the host that loads a
// module from anywhere and decides what it may do — and a consumer who cannot
// reach it cannot host a dynamic component at all. It imports nothing that was
// not already published, and `docs/`, which ships, links into it.
//
// The wasm-gc JS import shim `app/wasm/loader.mjs` ships too: it is the import
// contract of packages that ship.

// `examples/` is the reverse of everything else in this list: not a part of the
// project that does not belong in the tarball, but CONSUMERS of the tarball
// that happen to live here. Each is its own module depending on the published
// `marianoguerra/tutuca`, and shipping one inside the thing it depends on would
// be a loop. They exist to prove that a release is complete — see
// `examples/README.md`.

options(
  exclude: [
    "benchmarks",
    "examples",
    // Both playgrounds: the top-level one and `tutucard/playground`. They are
    // this repo's PAGES — a `publish` extern that installs a global, assembled
    // by `cmd/dev` and deployed to Pages — rather than a library a consumer
    // links. `tutucard/drive`, the headless card driver, is the part that IS
    // one, and it ships.
    "playground",
    // …and the card one, by its own name. "playground" above does not reach it:
    // exclusion matches a package path exactly or as a directory prefix, and
    // `tutucard/playground` is neither. The comment above has claimed both were
    // out since they were written; only one of them was.
    "tutucard/playground",
    "tutucard/build",
    "tutucard/web",
    // The `&Guest` over a compiled card. One half of a bridge whose other half
    // is `tutucard/web/card.js`, which does not ship — and half a bridge is
    // worse than none.
    "tutucard/guest",
    "demo",
    "skill",
    "scripts",
    "dev",
    "cmd/dev",
    "cmd/css-bundle",
    // `cmd/tgc` is the toolchain shell for the component format: it prints the
    // canonical preamble and compiles a `.wax` module that carries it. A dev
    // shell over shipping packages — the compilers are the feature, and a
    // terminal front end for them is not. `cmd/tgc-corpus` is the same kind of
    // thing for the conformance table: it projects `tscript/conformance` into
    // compiled modules so node can drive them, because a compiled card can only
    // be RUN from node. `cmd/conformance` is the third.
    "cmd/tgc",
    "cmd/tgc-corpus",
    "cmd/conformance",
    // `tgc/proto` and `tgc/test` are the composition proof: hand-written and
    // hand-compiled modules and the node harnesses that instantiate them
    // together. Evidence about the format rather than part of it.
    //
    // `tgc/rt` SHIPS, because a page that hosts a component needs the runtime
    // module and cannot fetch it from this repository's `_build`. Its `.wax` is
    // embedded and `tgc/emit`'s `compile_runtime` builds it.
    "tgc/proto",
    "tgc/test",
    // this repo's own stories and view fixtures; the gallery itself ships
    "storybook/examples",
    // the scaffold `tutuca new-storybook` writes out. It is already IN the
    // binary (cli/storybook_template_gen.mbt), and shipping the source beside
    // it would put a second copy in the tarball that nothing reads — and a
    // `page/moon.pkg.tmpl` that no longer looks like a package only by
    // extension.
    "storybook/template",
    "package.json",
    "package-lock.json",
  ],
)
