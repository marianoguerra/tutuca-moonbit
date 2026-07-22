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

# run the embedded tutuca CLI: just cli examples | just cli render <example> | just cli lint
cli *ARGS:
    {{cli}} {{ARGS}}

# render an example module to HTML via the CLI
render *ARGS:
    {{cli}} render {{ARGS}}

# lint the bundled example modules via the CLI
lint *ARGS:
    {{cli}} lint {{ARGS}}

# ── package ────────────────────────────────────────────────────────────────

# build all applicable targets (wasm-gc, native CLI, js)
build:
    {{dev}} build

# regenerate cli/skill_assets_gen.mbt from skill/tutuca/ (never edit it by hand)
skill-embed:
    {{dev}} skill-embed

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
    cd guests/counter && node build.mjs
    cd guests/todo && node build.mjs

# dry-run package the module for mooncakes.io
package:
    moon package

# ── publish ────────────────────────────────────────────────────────────────

# publish to mooncakes.io (runs the full ci gate first; needs `moon login`)
publish: ci
    moon publish
