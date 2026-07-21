# Contributing to tutuca (MoonBit)

Thanks for your interest! This is a [MoonBit](https://docs.moonbitlang.com)
port of [tutuca](https://github.com/marianoguerra/tutuca).

## Setup

You need the MoonBit toolchain (`moon`) and Node.js (for the happy-dom-based
js-target tests). Then:

```sh
moon run --target native cmd/dev -- setup
```

This runs `npm install` (happy-dom) and enables the git hooks
(`.githooks/pre-commit` runs `moon check`).

## Workflow

Common tasks live in the `cmd/dev` task runner — run it with no argument to see
the full list:

```sh
moon run --target native cmd/dev --            # list tasks
moon run --target native cmd/dev -- check      # moon check across wasm-gc, js, native
moon run --target native cmd/dev -- test       # moon test across the three targets
moon run --target native cmd/dev -- fmt        # moon fmt + moon info (regenerate .mbti)
moon run --target native cmd/dev -- ci         # check then test (what CI runs)
moon run --target native cmd/dev -- build      # build all targets
moon run --target native cmd/dev -- dist       # assemble a runnable dist/
```

### Targets

`preferred_target` is `wasm-gc`, so a bare `moon check` / `moon test` covers
only the target-agnostic packages. Full coverage needs all three targets — the
`check` and `test` tasks run wasm-gc, `--target js` (browser adapters,
happy-dom), and `--target native` (CLI shells) for you. Run the full `ci` task
before opening a PR.

### Before you commit

- Run `moon run --target native cmd/dev -- fmt` to format and regenerate the
  `.mbti` interface files; review the `.mbti` diffs to confirm the public API
  change is intentional.
- Make sure `... -- ci` passes.
- Some files are generated and committed on purpose — regenerate them rather
  than hand-editing: `cli/skill_assets_gen.mbt` (`... -- skill-embed`, from
  `skill/tutuca/`) and the `pkg.generated.mbti` interfaces (`moon info`).

## Releasing to mooncakes.io

The module is published as `marianoguerra/tutuca`. The account name on
[mooncakes.io](https://mooncakes.io) must match the `marianoguerra/` prefix in
`moon.mod`, so the first release needs `moon register` (or `moon login` if the
account already exists — it writes `~/.moon/credentials.json`).

```sh
moon run --target native cmd/dev -- ci   # all three targets must be green
moon package --list                      # review exactly what ships
moon publish
git tag -a v0.1.0 -m "v0.1.0" && git push origin v0.1.0
```

Then move the `CHANGELOG.md` `[Unreleased]` entries under the new version and
bump `version` in `moon.mod` — mooncakes versions are immutable, so a re-release
always needs a new semver number (MAJOR = breaking API, MINOR = additive,
PATCH = fixes).

### What ships

`options(exclude: ...)` in `moon.mod` keeps the tarball to the library
packages, the CLI, the storybook and `docs/`. The demo, playground, `dyncomp`
and wasm-component guest hosts, the `dev`/`cmd/dev` task runner, `scripts/`,
`skill/` and `package.json` are repo-only. If you add a package that a shipped
package imports, make sure it is not under an excluded directory — verify by
unpacking `_build/publish/*.zip` into an empty directory and running
`moon check` / `moon test` there, which is what a consumer sees.

### `moon doc` does not work here

`moon doc` builds *every* package of *every* dependency module and ignores
`supported_targets`, so it cannot resolve a module that depends on the js-only
`mizchi/js_browser` under a wasm-gc (or native) `preferred_target`:

```
Selected backend 'wasm-gc' is incompatible with the dependency graph.
'mizchi/js_browser/test_utils' requires 'mizchi/js_browser/dom' which supports [js].
```

This is not caused by anything in this repo — a module whose only content is an
empty package and an `import` of `mizchi/js_browser` reproduces it. It also
can't be worked around by switching `preferred_target`, because our own
`vdom/wasm` and `app/wasm` are wasm-gc-only while `vdom/browser` and
`app/browser` are js-only: no single backend covers the whole tree. Expect the
generated API docs on mooncakes.io to be unavailable until `moon doc` honours
`supported_targets` upstream; the hand-written guides in `docs/` and the
storybook are the fallback.

## Conventions

See [AGENTS.md](AGENTS.md) for the code-organization, tooling, and
component-testing conventions (block style, `deprecated.mbt`, the testing
harness and assertion mapping).

## License

By contributing you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
