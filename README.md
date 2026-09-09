# marianoguerra/tutuca

A [MoonBit](https://docs.moonbitlang.com) port of
[tutuca](https://github.com/marianoguerra/tutuca), a small UI framework built
around a reactive value language, a declarative view notation, and a virtual
DOM.

A component declares its spec, its logic and its views in one `.tutu` file,
and all three compile ahead of time into typed MoonBit. Every handler is
checked against the state it mutates, and so is every field a view reads —
including inside a loop. It runs on all three
backends: **wasm-gc** (the default), **js** (the real-DOM adapter) and
**native** (the CLI).

Follow the same five components everywhere: **Quantity picker → Notification preferences → Task list → Contact directory → Document workspace**.

[Try them in your browser](https://marianoguerra.github.io/tutuca-moonbit/) or [follow the tutorial](docs/tutorial.mbt.md). The small examples run directly as cards; the MoonBit examples show host integration and compiled assembly.

## Start here

- **[README.mbt.md](README.mbt.md)** — the detailed guide: the package stack,
  ahead-of-time views, the value language, the CLI, and what each backend
  adapter does. Every code block in it is compiled and run by `moon test`.
- **[docs/](docs/)** — the guides. Start with
  [tutorial.mbt.md](docs/tutorial.mbt.md), which builds five practical components; [first_principles.mbt.md](docs/first_principles.mbt.md) rebuilds the
  framework layer by layer if you want to know *why* it works. Their examples have interaction tests. [dynamic-components.md](docs/dynamic-components.md) is the part
  that is *not* decided before the program runs: a WebAssembly module fetched at
  runtime, from someone you have no reason to trust, mounted into a page that is
  already running.
- **[skill/tutuca/](skill/tutuca/)** — the authoring reference an agent reads,
  shipped inside the CLI: the spec and script languages, views, events,
  protocols, testing and cards. `tutuca install-skill` writes it out.
- **[tgc/SPEC.md](tgc/SPEC.md)** — the component format itself: the frozen rec
  group, the freeze rule, the op space, the exports, and the JSON encoding.
  **[tgc/SECURITY.md](tgc/SECURITY.md)** is what a loaded module can and cannot
  do, tested rather than asserted.
- **[AGENTS.md](AGENTS.md)** — repo layout, tooling and testing conventions.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — how to propose a change.

Live demos, playground and storybook:
<https://marianoguerra.github.io/tutuca-moonbit/>

## Install

As a library:

```sh
moon add marianoguerra/tutuca
```

The CLI is the `cmd/tutuca` package, and `moon install` names the binary after
that package's last segment:

```sh
moon install marianoguerra/tutuca/cmd/tutuca
```

That lands `tutuca` in `~/.moon/bin/`, which the MoonBit toolchain already puts
on your PATH — no symlink needed. Check it with `tutuca help`.

## Build and test

Common workflows live in a MoonBit task runner rather than loose commands; run
it with no task to print the list.

```sh
moon run --target native cmd/dev -- setup   # npm install (happy-dom) + git hooks
moon run --target native cmd/dev -- ci      # check + test, across all targets
```

## License

MIT — see [LICENSE](LICENSE).
