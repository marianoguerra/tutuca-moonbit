# marianoguerra/tutuca

A [MoonBit](https://docs.moonbitlang.com) port of
[tutuca](https://github.com/marianoguerra/tutuca), a small UI framework built
around a reactive value language, HTML-ish templates, and a virtual DOM.

A component declares its state and views in one file, using a small state
language and HTML-ish templates, and both compile ahead of time into typed
MoonBit. Every handler is checked against the state it mutates, and so is
every `.field` a view reads — including inside a loop. It runs on all three
backends: **wasm-gc** (the default), **js** (the real-DOM adapter) and
**native** (the CLI).

```html
<!-- counter.html -->
<script type="tutuca/state">
  state Counter { count: Int }
</script>

<script type="tutuca/script">
  receive inc { .count += 1 }
</script>

<template id="Counter">
  <button @on.click="inc" @text=".count"></button>
</template>
```

```moonbit
// `tutuca gen-views` made CounterState and counter_component out of the three
// blocks above, checked `.count` against the schema in both the view and the
// handler, and compiled `inc` into the update the wrapper already passes. The
// name, the views, the styles, the codec and the schema are not arguments —
// the view file states them.
counter_component()
```

A handler the block cannot compile — one that walks a path, or builds a child
component — is REFUSED by name, with the reason, and comes back as an
`update~` argument. The rest stay in the file.

## Start here

- **[README.mbt.md](README.mbt.md)** — the detailed guide: the package stack,
  ahead-of-time views, the value language, the CLI, and what each backend
  adapter does. Every code block in it is compiled and run by `moon test`.
- **[docs/tutorial.mbt.md](docs/tutorial.mbt.md)** — build an app from a
  counter up, also executable.
- **[docs/first_principles.mbt.md](docs/first_principles.mbt.md)** — the same
  framework rebuilt layer by layer, if you want to know *why* it works.
- **[skill/tutuca/messages-and-intents.md](skill/tutuca/messages-and-intents.md)**
  — the two ways a component is reached: a message is addressed and stops at
  one component, an intent is routed and walks until something answers.
- **[docs/dynamic-components.md](docs/dynamic-components.md)** — the part that
  is *not* decided before the program runs: a WebAssembly component fetched at
  runtime, from someone you have no reason to trust, mounted into a page that
  is already running. How to host them, and `tutuca new-guest` to write one.
- **[docs/playground-wasm.md](docs/playground-wasm.md)** — how the in-browser
  playground compiles and runs on both backends: the string ABI, the
  worker-per-target rule, and how to verify a change to either.
- **[docs/card-examples-design.md](docs/card-examples-design.md)** — what a
  card's `tutuca/init` fixtures would need to describe a state with CHILDREN,
  and to be arrived at by driving rather than by being written down. A design
  rather than shipped behaviour; it says so at the top, and it opens with the
  correction that there should not be a second block.
- **[docs/generative-dyncomps-in-the-browser-design.md](docs/generative-dyncomps-in-the-browser-design.md)**
  — a design for building a bundle client-side, with no server and no native
  toolchain. A plan rather than a description of shipped behaviour; it says so
  at the top.
- **[AGENTS.md](AGENTS.md)** — repo layout, tooling and testing conventions.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — how to propose a change.

Live demos, playground and storybook:
<https://marianoguerra.github.io/tutuca-moonbit/>

## Install

```sh
moon add marianoguerra/tutuca
```

## Build and test

Common workflows live in a MoonBit task runner rather than loose commands; run
it with no task to print the list.

```sh
moon run --target native cmd/dev -- setup   # npm install (happy-dom) + git hooks
moon run --target native cmd/dev -- ci      # check + test, across all targets
```

## License

MIT — see [LICENSE](LICENSE).
