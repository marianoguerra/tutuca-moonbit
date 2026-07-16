# playground/vendor

Vendored third-party assets for the in-browser playground.

## `moonc-web.cjs` — the in-browser MoonBit compiler

`moonc-web.cjs` is a `js_of_ocaml` build of the MoonBit compiler (the
`@moonbit/moonc-worker` npm package). The playground's compiler worker
(`playground/web/compiler.worker.js`) loads it to compile user MoonBit in the
browser.

**It is not committed** — it is 5+ MB and lives in `.gitignore`. The build
fetches it on demand:

```sh
node playground/build/fetch-compiler.mjs          # fetch if missing
node playground/build/fetch-compiler.mjs --force   # re-fetch
```

`playground/build/assemble.mjs` also calls `ensureCompiler()` automatically, so
`cmd/dev -- playground` and `cmd/dev -- dist` fetch it for you on a fresh clone.

Only `moonc-web.cjs` is gitignored; `moonc-web.d.ts` (the tiny type stub) is
kept in the repo.

### Toolchain coupling — read before bumping

The playground bakes the **installed** `moon` toolchain's core `.mi`/`.core`
bundles into its payload (see `assemble.mjs`). The fetched `moonc-web.cjs` MUST
be built from the **same `moonc` version**, or in-browser linking fails.

`@moonbit/moonc-worker` publishes date-versioned nightly builds and offers no
exact-hash selector, so the version is pinned in
`playground/build/fetch-compiler.mjs` (`MOONC_WORKER_VERSION`). To build the
playground you must have the **matching `moon` nightly** installed.

Current pin: `@moonbit/moonc-worker@0.1.202607161` (moonc build `2cc641edf`,
nightly 2026-07-16). When you bump it, update all three in lockstep:

1. `MOONC_WORKER_VERSION` in `playground/build/fetch-compiler.mjs`
2. `TOOLCHAIN` in `playground/build/assemble.mjs`
3. this note

If you have a `moonc-web.cjs` matching a toolchain that npm doesn't publish,
drop it in this directory manually — `ensureCompiler()` won't overwrite an
existing file unless you pass `--force`.
