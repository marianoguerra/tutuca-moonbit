name = "marianoguerra/tutuca"

version = "0.19.0"

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
  "mizchi/js@0.12.1",
  "mizchi/js_browser@0.12.1",
  "moonbitlang/async@0.20.3",
  "moonbit-community/html@0.1.2",
  "mizchi/fswatch@0.2.1",
  "marianoguerra/tailwindcss@0.2.0",
  "moonbitlang/x@0.4.47",
}

// What `moon publish` ships. Consumers get the library packages, the CLI
// (cmd/main -> cli/) and the docs; they don't get the demo/playground/guest
// hosts, the dev tooling, or the storybook — those only make sense inside
// this repo. storybook/ went the same way as demo/ once nothing published
// depended on it: `tutuca storybook` serves a pre-built bundle and needs no
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
// `docs/`, which ships, has always linked into it.
//
// The one part that stays behind is `dyncomp/test`: its `*.test.mjs` drive real
// guest bundles out of `guests/*/dist/js`, a path that exists in this repo and
// in no tarball. The wasm-gc JS import shims are the reverse case — they moved
// OUT of `demo/` (`app/wasm/loader.mjs`, `dyncomp/host/wasm/loader.mjs`)
// precisely so that a consumer gets them, since they are the import contract of
// packages that were already shipping without them.

// `examples/` is the reverse of everything else in this list: not a part of the
// project that does not belong in the tarball, but CONSUMERS of the tarball
// that happen to live here. Each is its own module depending on the published
// `marianoguerra/tutuca`, and shipping one inside the thing it depends on would
// be a loop. They exist to prove that a release is complete — see
// `examples/README.md`.

options(
  exclude: [
    "benchmarks",
    // `cardwasm/` is a module of its own for the reason `examples/` is, with
    // the sign flipped: it depends on things that are NOT in the tarball. Its
    // manifest path-depends on this checkout and on a sibling `wax` one, and a
    // path dependency in THIS manifest would be paid for by every consumer —
    // so it stays a nested module, checked and tested from its own directory.
    "cardwasm",
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
    "storybook",
    "package.json",
    "package-lock.json",
  ],
)
