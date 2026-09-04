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
  `skill/tutuca/`), `cli/storybook_template_gen.mbt`
  (`... -- storybook-template-embed`, from `storybook/template`),
  `tgc/rt/rt_src_gen.mbt` (`node tgc/rt/embed.mjs`, from `tgc/rt/rt.wax`), and
  the `pkg.generated.mbti` interfaces (`moon info`).

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

One exception, and `ci` enforces it: `MODULE_VERSION` in `cli/version.mbt` is
what `tutuca new-storybook` pins in the `moon.mod` it writes, so it moves with
the module version. A change that makes the scaffold depend on packages a
released version does not have has to bump both at once — otherwise the
scaffold hands a new user a project resolving to a release without them.
`scripts/check-module-version.mjs` fails on the mismatch either way.

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
cd examples/storybook-gallery && node build.mjs   # per example
```

Then open each example's page and drive it. Announce after that, not before.

An example must never gain a path dependency, a `../` anywhere under its
directory, or a build step that runs something from this repository. That is
the one property it exists to hold, and losing it turns the check into
theatre. Its `import` pin moves to the version just published, in the same
commit that migrates its source.

### What ships

`options(exclude: ...)` in `moon.mod` keeps the tarball to the library
packages, `tgc/`, the storybook, the CLI and `docs/`. The demo and playground
trees, the `dev`/`cmd/dev` task runner, `scripts/`, `skill/` and `package.json`
are repo-only.

`storybook/` ships except for `storybook/examples` and `storybook/template`.
The model, the gallery shell, the panel layer and the two browser halves are how
a project gets a gallery of its OWN components (see
[docs/storybook.md](docs/storybook.md)); the corpus is this repo's own demos plus
the fixtures the lint and view-generation sweeps and `benchmarks` run over,
which is editorial content and not a library, and the template already travels
inside the CLI binary. Stories are projected from a module's own `examples`, so
nobody needs ours.

If you add a package that a shipped package imports, make sure it is not under
an excluded directory. `scripts/check-publish-graph.mjs` (in `ci`) fails on that
— including a `for "test"` import, since test files travel in the tarball too —
and the end-to-end check is still unpacking `_build/publish/*.zip` into an empty
directory and running `moon check` / `moon test` there, which is what a consumer
sees.

`tgc/` ships: it is the component format, and without it a consumer can host no
dynamic component at all — no preamble, no runtime module, no card compiler, no
host, no policy. Two consequences worth knowing when you edit around it:

- **`tgc/proto` and `tgc/test` are excluded.** They are the composition proof:
  hand-written modules in WAT and Wax, and the node harnesses that instantiate
  them together against one import object. Evidence about the format rather than
  part of it, and the harnesses build from `_build`, which no tarball has. Run
  them from the repo with `node --test tgc/test/*.test.mjs`.
- **`tgc/rt` ships, and it is a `.wax` file.** A page that hosts a component
  needs the runtime module and cannot fetch it from this repository's `_build`,
  so the source is embedded (`tgc/rt/rt_src_gen.mbt`) and `tgc/emit`'s
  `compile_runtime` builds it on demand. Same rule as `app/wasm/loader.mjs`,
  which is not `.mbt` either but is the only way a consumer's wasm-gc page can
  instantiate anything.

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
