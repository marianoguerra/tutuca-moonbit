# marianoguerra/tutuca

A [MoonBit](https://docs.moonbitlang.com) port of
[tutuca](https://github.com/marianoguerra/tutuca), a small UI framework built
around a reactive value language, HTML-ish templates, and a virtual DOM.

A component declares its state and its views in one file, in a small subset
of WIT and HTML-ish templates, and both are compiled ahead of time into typed
MoonBit. Every handler is checked against the state it mutates, and so is
every `.field` a view reads — including inside a loop. It runs on all three
backends: **wasm-gc** (the default), **js** (the real-DOM adapter) and
**native** (the CLI).

```html
<!-- counter.html -->
<script type="tutuca/state">
  interface counter {
    record state { count: s32 }
  }
</script>

<template id="Counter">
  <button @on.click="$inc" @text=".count"></button>
</template>
```

```moonbit
// CounterState came from the schema above; `.count` was checked against it.
@component.component(
  views=counter_views(),
  name="Counter",
  init=CounterState::{ count: 0 },
  update=(s : CounterState, msg, _ctx) => {
    match CounterMsg::from_dispatch(msg) {
      Some(Dec) => Some({ count: s.count - 1 })
      _ => None
    }
  },
)
```

## Start here

- **[README.mbt.md](README.mbt.md)** — the detailed guide: the package stack,
  ahead-of-time views, the value language, the CLI, and what each backend
  adapter does. Every code block in it is compiled and run by `moon test`.
- **[docs/tutorial.mbt.md](docs/tutorial.mbt.md)** — build an app from a
  counter up, also executable.
- **[docs/first_principles.mbt.md](docs/first_principles.mbt.md)** — the same
  framework rebuilt layer by layer, if you want to know *why* it works.
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
