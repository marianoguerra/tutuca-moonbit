# tutuca-mb task index — thin wrappers over the MoonBit task runner in
# cmd/dev (the single place workflows are defined; see AGENTS.md). Anything
# not listed here: `just dev <task>`.

dev := "moon run --target native cmd/dev --"
cli := "moon run --target native cmd/main --"

# list available recipes
default:
    @just --list

# ── develop ────────────────────────────────────────────────────────────────

# one-time: install js-test deps (happy-dom) and enable the git hooks
setup:
    {{dev}} setup

# type-check every backend (wasm-gc default, js, native)
check:
    {{dev}} check

# compile-check the playground's editable examples (no moon package includes them)
check-examples:
    {{dev}} check-examples

# compile-check the MoonBit snippets in the bundled skill (skill/tutuca/)
check-skill:
    {{dev}} check-skill

# format sources and regenerate the .mbti interface files
fmt:
    {{dev}} fmt

# run any cmd/dev task directly (escape hatch): just dev <task>
dev *ARGS:
    {{dev}} {{ARGS}}

# ── test ───────────────────────────────────────────────────────────────────

# full test suite across default, native, and js browser adapters
test:
    {{dev}} test

# fast inner-loop: test one package on the default target, e.g. `just t component`
t PKG:
    moon test {{PKG}}

# coverage analysis
coverage:
    {{dev}} coverage

# check + test — what CI runs
ci:
    {{dev}} ci

# ── use ────────────────────────────────────────────────────────────────────

# run the tutuca CLI: just cli help | just cli gen-views <file.html>
cli *ARGS:
    {{cli}} {{ARGS}}

# compile a view file into its typed MoonBit module
gen-views *ARGS:
    {{cli}} gen-views {{ARGS}}

# compile a project's view classes into CSS (stock Tailwind)
gen-tailwind-css *ARGS:
    {{cli}} gen-tailwind-css {{ARGS}}

# compile a project's view classes into CSS (Tailwind + margaui)
gen-margaui-css *ARGS:
    {{cli}} gen-margaui-css {{ARGS}}

# ── package ────────────────────────────────────────────────────────────────

# build all applicable targets (wasm-gc, native CLI, js)
build:
    {{dev}} build

# regenerate cli/skill_assets_gen.mbt from skill/tutuca/ (never edit it by hand)
skill-embed:
    {{dev}} skill-embed

# regenerate css/{tailwind,margaui}_bundle_gen.mbt from the pinned upstreams (needs network)
css-bundle:
    {{dev}} css-bundle

# build demos + storybook + playground into a self-contained runnable dist/
dist:
    {{dev}} dist

# serve dist/ locally (build it first with `just dist`)
serve PORT="8000":
    python3 -m http.server {{PORT}} --directory dist

# assemble only dist/playground/ (needs the vendored compiler: `just dev fetch-moonc` once)
playground:
    {{dev}} playground

# build the wasm-component guest bundles (dyncomp demos)
guests:
    node guests/build-guest.mjs counter
    node guests/build-guest.mjs todo
    node guests/rust-counter/build.mjs

# regenerate the guests' MoonBit bindings from dyncomp/wit, then drift-check
guest-bindings:
    {{dev}} gen-guest-bindings

# dry-run package the module for mooncakes.io
package:
    moon package

# stage + npm pack the playground's npm packages into _build/npm (run `just dist` first)
npm-pack:
    {{dev}} npm-pack

# ── publish ────────────────────────────────────────────────────────────────

# publish to mooncakes.io (runs the full ci gate first; needs `moon login`)
publish: ci
    moon publish
