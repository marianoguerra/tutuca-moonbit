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

## Conventions

See [AGENTS.md](AGENTS.md) for the code-organization, tooling, and
component-testing conventions (block style, `deprecated.mbt`, the testing
harness and assertion mapping).

## License

By contributing you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
