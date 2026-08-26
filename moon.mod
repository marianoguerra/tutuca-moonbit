name = "marianoguerra/tutuca"

version = "0.34.0"

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
  "moonbitlang/async@0.21.0",
  "moonbit-community/html@0.1.2",
  "mizchi/fswatch@0.2.1",
  // Only `mizchi/css/token` is used, by `anode/sanitize/css` — a css-syntax-3
  // tokenizer with no dependency of its own beyond `moonbitlang/core/string`.
  // The parser, cascade and computed packages are NOT used: `parse_inline_style`
  // returns a layout engine's `@style.Style`, which cannot round-trip a
  // declaration list, and round-tripping is the whole point. Apache-2.0, where
  // this module is MIT.
  "mizchi/css@0.7.3",
  // The Wax compiler, for `tutucard/wasm` — the card-to-core-wasm backend.
  // Dependency-free itself, and MoonBit links per package, so a consumer who
  // never compiles a card pays the fetch and nothing else.
  "marianoguerra/wax@0.2.0",
  "marianoguerra/tailwindcss@0.3.0",
  "moonbitlang/x@0.5.1",
}

// What `moon publish` ships. Consumers get the library packages, the CLI
// (cmd/tutuca -> cli/) and the docs; they don't get the demo/playground/guest
// hosts, the dev tooling, or the storybook — those only make sense inside
// this repo: `tutuca storybook` serves a pre-built bundle and needs no
// story registry, and the harness's demo test defines its own module rather
// than borrowing an example. The storybook packages stay in the repo as
// demos and as the corpus the lint/view sweeps run over. Check with
// `moon package --list`.
//
// `dyncomp/` SHIPS. It is the universal core — the `tutuca:component` contract,
// the host that loads a bundle from anywhere, the policy that decides what one
// may do, the catalog, the JSON Schema projection, and the universal UI over
// all of it — and a consumer who cannot reach it cannot host a dynamic
// component at all. It imports nothing that was not already published, and
// `docs/`, which ships, links into it.
//
// The one part that stays behind is `dyncomp/test`: its `*.test.mjs` drive real
// guest bundles out of `guests/*/dist/js`, a path that exists in this repo and
// in no tarball. The wasm-gc JS import shims (`app/wasm/loader.mjs`,
// `dyncomp/host/wasm/loader.mjs`) DO ship: they are the import contract of
// packages that ship.

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
    "guests",
    "playground",
    "demo",
    "dyncomp/test",
    "skill",
    "scripts",
    "dev",
    "cmd/dev",
    "cmd/css-bundle",
    // `cmd/cardwasm`, `cmd/card-corpus` and `cmd/conformance` are dev shells
    // over shipping packages (`tutucard/wasm`, `tscript`): the compilers are
    // the feature, and a terminal front end for them is not.
    // `tutucard/wasm/test` stays behind for the reason `dyncomp/test` does —
    // it drives node against real modules.
    "cmd/cardwasm",
    "cmd/card-corpus",
    "cmd/conformance",
    "tutucard/wasm/test",
    "storybook",
    "package.json",
    "package-lock.json",
  ],
)
