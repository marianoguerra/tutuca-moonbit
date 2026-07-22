name = "marianoguerra/tutuca"

version = "0.4.0"

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
  "moonbitlang/async@0.20.1",
  "moonbit-community/html@0.1.2",
  "mizchi/fswatch@0.2.1",
}

// What `moon publish` ships. Consumers get the library packages, the CLI
// (cmd/main -> cli/) and the docs; they don't get the demo/playground/guest
// hosts or the dev tooling, which only make sense inside this repo. storybook/
// stays: cli/ and testing/harness both import it. Check with
// `moon package --list`.

options(
  exclude: [
    "guests",
    "playground",
    "demo",
    "dyncomp",
    "skill",
    "scripts",
    "dev",
    "cmd/dev",
    "package.json",
    "package-lock.json",
  ],
)
