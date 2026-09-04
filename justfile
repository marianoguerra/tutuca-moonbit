# tutuca-mb — a short front door to the task runner in cmd/dev, which is the
# single place workflows are defined. `just dev <task>` reaches any task; run
# it with no task to see them all. A recipe here that is not a one-line wrapper
# has started being a task in the wrong place. The `clean` pair at the bottom
# is the deliberate exception and says why.

dev := "moon run --target native cmd/dev --"
cli := "moon run --target native cmd/tutuca --"

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

# format sources and regenerate the .mbti interface files
fmt:
    {{dev}} fmt

# any cmd/dev task, and the task list itself: just dev | just dev check-skill
dev *ARGS:
    {{dev}} {{ARGS}}

# ── test ───────────────────────────────────────────────────────────────────

# full test suite across default, native, and js browser adapters
test:
    {{dev}} test

# fast inner-loop: test one package on the default target, e.g. `just t component`
t PKG:
    moon test {{PKG}}

# every gate — what CI runs
ci:
    {{dev}} ci

# ── use ────────────────────────────────────────────────────────────────────

# run the tutuca CLI: just cli help | just cli gen <file.html> | just cli gen-margaui-css
cli *ARGS:
    {{cli}} {{ARGS}}

# regenerate every checked-in *_view_gen.mbt (whole repo), then drift-check them
gen:
    {{dev}} gen

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

# stage + npm pack the playground's npm packages into _build/npm (run `just dist` first)
npm-pack:
    {{dev}} npm-pack

# ── clean ──────────────────────────────────────────────────────────────────
#
# The two recipes that are NOT thin wrappers over cmd/dev, and cannot be: the
# task runner is a native binary living in the `_build` these delete, so a
# `clean` task would be removing the ground it stands on mid-run.
#
# `moon clean` on its own reclaims `_build/` and nothing else — most of the
# weight, but it cannot reach the nested moon modules under `examples/`, whose
# `moon.mod` stops discovery, and it does not know about `dist/` or, in
# clean-all, `node_modules`.
#
# Both walk rather than listing directories, so a new nested module needs no
# edit here. And both delete only what `git check-ignore` agrees is ignored — a
# destructive recipe should be unable to reach a tracked file even if the walk
# is wrong.

# remove build output — offline-safe, nothing here needs the network to rebuild
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    doomed=()
    while IFS= read -r d; do doomed+=("$d"); done < <(
      find . \( -name node_modules -o -name .mooncakes -o -name .git \) -prune \
           -o \( -name _build -o -name dist \) -type d -print
    )
    doomed+=(playground/_examples_check skill/_snippets_check)
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
