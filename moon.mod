name = "marianoguerra/tutuca"

version = "0.57.0"

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
  "moonbitlang/quickcheck@0.15.0",
  "mizchi/js_core@0.13.0",
  "mizchi/js_browser@0.13.0",
  "moonbitlang/async@0.22.5",
  "moonbit-community/html@0.2.2",
  "mizchi/fswatch@0.2.1",
  // Not imported: pinned so the resolver lifts `mizchi/fswatch`'s transitive
  // `moonbitlang/regexp@0.3.5` (via `mizchi/x@0.4.0`), whose `moon.mod.json`
  // the current toolchain refuses to build. Drop once fswatch moves past it.
  "moonbitlang/regexp@0.3.6",
  // Only `mizchi/css/token` is used, by `anode/sanitize/css` — a css-syntax-3
  // tokenizer with no dependency of its own beyond `moonbitlang/core/string`.
  // The parser, cascade and computed packages are NOT used: `parse_inline_style`
  // returns a layout engine's `@style.Style`, which cannot round-trip a
  // declaration list, and round-tripping is the whole point. Apache-2.0, where
  // this module is MIT.
  "mizchi/css@0.7.4",
  // The wap compiler and the Wax backend under it, for `tgc/emit` — the
  // card-to-core-wasm route. `tgc` writes wap; wap lowers to the Wax AST.
  // Dependency-free itself, and MoonBit links per package, so a consumer who
  // never compiles a card pays the fetch and nothing else.
  "marianoguerra/wax@0.3.1",
  // The `.tutu` file reader: shrubbery notation (groups, blocks, alternatives,
  // keyword options) plus the diagnostic reports its errors are carried in.
  "marianoguerra/shrubbery@0.1.2",
  "marianoguerra/error-report@0.1.1",
  // The markup and CSS halves of the notation, and the two bridges to them.
  // A view IS Shrubbery HTML plus tutuca's extensions, so the name tables --
  // void elements, raw text, the integration points, SVG's casing, `_` to `-`
  // -- come from upstream rather than from a second copy here. `shrubbery-css`
  // is what a `style()` body written as notation rather than as raw text is
  // lowered by; it reaches the reader through `shrubbery-html`'s raw-text hook,
  // which exists for exactly this composition.
  "marianoguerra/html@0.1.1",
  "marianoguerra/shrubbery-html@0.1.1",
  "marianoguerra/css@0.1.2",
  "marianoguerra/shrubbery-css@0.2.1",
  "marianoguerra/tailwindcss@0.4.3",
  "moonbitlang/x@0.5.5",
  "marianoguerra/wap@0.3.2",
}

// `.moonignore` defines the published inventory. `check-publish-graph` checks
// every shipping package's main and test imports against `moon package --list`.
