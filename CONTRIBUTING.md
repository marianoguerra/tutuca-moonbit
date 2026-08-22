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
  `skill/tutuca/`), `cli/guest_template_gen.mbt` (`... -- guest-template-embed`,
  from `guests/counter` + `dyncomp/wit` + `guests/template`), the guest trees
  under `guests/*` (`... -- gen-guest-bindings`, from `dyncomp/wit` +
  `guests/sdk.mbt` — the canonical SDK, never a copy), and the
  `pkg.generated.mbti` interfaces (`moon info`).

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

The `moon.mod` version and the `CHANGELOG.md` section are prepared BEFORE the
publish, in a commit of their own that touches only those two files — mooncakes
versions are immutable, so a re-release always needs a new semver number
(MAJOR = breaking API, MINOR = additive, PATCH = fixes; a breaking change under
`0.x` takes the minor).

### Then the examples, and only then the announcement

`examples/*` are not packages of this module. Each has its own `moon.mod`
depending on the **published** `marianoguerra/tutuca` from mooncakes, and its
own `build.mjs`; `moon check`, `moon fmt` and `ci` never reach them. They are
the only thing that proves a release is complete **on its own** — that
everything a consumer needs is reachable from the tarball and nothing is
quietly coming from this checkout.

So the order is fixed and is not a preference:

```sh
# ...after `moon publish` has landed the new version
cd examples/dyncomp-dice && node build.mjs   # per example
```

Then open each example's page and drive it. Announce after that, not before.

An example must never gain a path dependency, a `../` anywhere under its
directory, or a build step that runs something from this repository. That is
the one property it exists to hold, and losing it turns the check into
theatre. Its `import` pin moves to the version just published, in the same
commit that migrates its source.

### What ships

`options(exclude: ...)` in `moon.mod` keeps the tarball to the library
packages, `dyncomp/`, the CLI and `docs/`. The storybook, demo, playground and
guest trees, the `dev`/`cmd/dev` task runner, `scripts/`, `skill/` and
`package.json` are repo-only. `storybook/` is excluded because
nothing published depends on it: `tutuca storybook` serves a pre-built bundle
and needs no story registry, and `testing/harness`'s demo test defines its own
module. It stays in the repo as a demo and as the corpus the lint and
view-generation sweeps run over. If you add a package that a shipped
package imports, make sure it is not under an excluded directory — verify by
unpacking `_build/publish/*.zip` into an empty directory and running
`moon check` / `moon test` there, which is what a consumer sees.

`dyncomp/` ships: it is the universal core, and without it a consumer can host
no dynamic component at all — no contract, no loader, no catalog, no universal
UI. Two consequences worth knowing when you edit around it:

- **`dyncomp/test` is the one part excluded.** Its `*.test.mjs` drive real
  guest bundles out of `guests/*/dist/js`, which no tarball has. Run them from
  the repo (`node --test 'dyncomp/test/*.test.mjs'` — the glob, quoted so node
  expands it; `--test` stopped accepting a bare directory).
- **The wasm-gc JS shims live beside their packages, not beside a page.**
  `app/wasm/loader.mjs` is the `jscore` + `tdom` import contract that
  `app/wasm` and `vdom/wasm` declare; `dyncomp/host/wasm/loader.mjs` is the
  `tcomp` + `tkv` half, linked through the first one's `makeExtra` hook. They
  are not `.mbt`, but they are the only way a consumer's wasm-gc page can
  instantiate anything, so they ship — and a page that loads no bundles links
  only the first. `dev/tasks.mbt` copies them beside each demo page in `dist/`
  as `app-loader.mjs` / `dyncomp-loader.mjs`, repointing the cross-import;
  in the repo and in the tarball the relative path resolves as written.

## Releasing the playground to npm

The playground ships as two npm packages, staged and packed from an assembled
`dist/` by `playground/build/pack-npm.mjs` (their manifests and READMEs live in
`playground/npm/`):

| package | holds | ~size |
| --- | --- | --- |
| `@marianoguerra/tutuca-playground` | the shell: `<mb-playground>`, worker, editor, view generator, margaui | 0.5 MB |
| `@marianoguerra/tutuca-playground-payload` | `manifest.json` + `fs/` — the `.mi`/`.core` bundles user code compiles against | ~22 MB |

Two packages because they turn over for different reasons — the payload is
rebuilt whenever the MoonBit toolchain moves, the shell isn't. They unpack into
the same `playground/` + `site/` layout, so a consumer copying both into a
static directory gets the arrangement everything resolves against by default.

The in-browser compiler (`moonc-web.cjs`) is **not** packed: it is upstream's
`@moonbit/moonc-worker` build, published with no license field, and the
playground can be pointed at a consumer's own copy. The payload names the exact
version in `peerDependencies` instead, and its `manifest.json` carries the pin
so the worker can check a served compiler against it.

```sh
moon run --target native cmd/dev -- dist       # or: -- playground, then assemble-site.mjs
moon run --target native cmd/dev -- npm-pack   # stages + packs into _build/npm/
tar tzf _build/npm/marianoguerra-tutuca-playground-<version>.tgz  # review what ships
npm publish _build/npm/<file>.tgz --access public              # scoped: public on first release
```

Both packages take their version from `moon.mod`, so they release with the
library; `npm-pack` refuses to run against a `dist/` assembled under a different
toolchain than `playground/build/toolchain.json` currently pins. Publishing is
deliberately manual — the script only packs, and prints the commands.

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
component-testing conventions (block style, the testing harness and assertion
mapping).

## License

By contributing you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
