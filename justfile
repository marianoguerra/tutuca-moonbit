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
    {{dev}} guests

# regenerate the guests' MoonBit bindings from dyncomp/wit, then drift-check
guest-bindings:
    {{dev}} gen-guest-bindings

# dry-run package the module for mooncakes.io
package:
    moon package

# stage + npm pack the playground's npm packages into _build/npm (run `just dist` first)
npm-pack:
    {{dev}} npm-pack

# ── clean ──────────────────────────────────────────────────────────────────
#
# The two recipes that are NOT thin wrappers over cmd/dev, and cannot be: the
# task runner is a native binary living in the `_build` these delete, so a
# `clean` task would be removing the ground it stands on mid-run.
#
# `moon clean` on its own reclaims `_build/` and nothing else. That IS most of
# the weight — a session's worth of CI across four targets took `_build` past
# 1.7G here — but it cannot reach the nested moon modules (guests/*, examples/*),
# because a nested moon.mod stops discovery, the same rule that keeps
# check/fmt/ci out of them. Nor does it know about the Rust guest's `target/`
# (159M), `dist/` (51M), or, in clean-all, node_modules (597M across two trees).
#
# Both walk rather than listing directories, because the list goes stale: this
# repo gained `guests/table` and `guests/rust-tempconv` since the last time
# anyone counted. And both delete only what `git check-ignore` agrees is
# ignored — a destructive recipe should be unable to reach a tracked file even
# if the walk is wrong.

# remove build output — offline-safe, nothing here needs the network to rebuild
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    doomed=()
    while IFS= read -r d; do doomed+=("$d"); done < <(
      find . \( -name node_modules -o -name .mooncakes -o -name .git \) -prune \
           -o \( -name _build -o -name dist -o -name target \) -type d -print
    )
    doomed+=(.playwright-mcp playground/_examples_check)
    just _rm "${doomed[@]}"

# also remove fetched trees — the next build will need the network
clean-all: clean
    #!/usr/bin/env bash
    set -euo pipefail
    doomed=()
    while IFS= read -r d; do doomed+=("$d"); done < <(
      find . -name .git -prune \
           -o \( -name node_modules -o -name .mooncakes \) -print -prune
    )
    # Re-fetch with: `just setup` (node_modules), `moon install` (.mooncakes),
    # `just dev fetch-moonc` (the in-browser compiler).
    doomed+=(playground/vendor/moonc-web.cjs)
    just _rm "${doomed[@]}"
    echo "fetched trees are gone: run 'just setup' before the next js-target test"

# internal: delete each argument, but only where git agrees it is ignored
_rm *PATHS:
    #!/usr/bin/env bash
    set -euo pipefail
    freed=0
    for d in {{PATHS}}; do
      [ -e "$d" ] || continue
      if git check-ignore -q "$d"; then
        size=$(du -sm "$d" 2>/dev/null | cut -f1 || echo 0)
        rm -rf "$d"
        freed=$((freed + size))
        echo "  removed $d (${size}M)"
      else
        echo "  SKIPPED, not gitignored: $d" >&2
      fi
    done
    echo "freed ${freed}M"

# ── publish ────────────────────────────────────────────────────────────────

# publish to mooncakes.io (runs the full ci gate first; needs `moon login`)
publish: ci
    moon publish
