name = "marianoguerra/tutuca"

version = "0.5.3"

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
  "moonbitlang/async@0.20.2",
  "moonbit-community/html@0.1.2",
  "mizchi/fswatch@0.2.1",
  "mizchi/wit@0.3.1",
  "marianoguerra/tailwindcss@0.2.0",
  "moonbitlang/x@0.4.46",
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

options(
  exclude: [
    "benchmarks",
    "guests",
    "playground",
    "demo",
    "dyncomp",
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
