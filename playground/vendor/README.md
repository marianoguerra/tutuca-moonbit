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
exact-hash selector, so **both halves of the pair are pinned in one file**:
`playground/build/toolchain.json`. `fetch-compiler.mjs` reads the
`mooncWorker` field; `assemble.mjs` reads `moonc` and refuses to assemble
unless `moon version --all` reports it (`TUTUCA_ALLOW_TOOLCHAIN_MISMATCH=1`
overrides). To build the playground you must have that `moon` installed.

Bumping is one edit plus a re-fetch:

```sh
$EDITOR playground/build/toolchain.json          # both fields, together
node playground/build/fetch-compiler.mjs --force
moon run --target native cmd/dev -- playground   # check-viewgen-tab proves the pair
```

Nothing else quotes the versions — don't reintroduce a second copy. What a
mismatch looks like if you skip the check: the payload assembles fine and the
browser reports errors that read like broken user code, typically
`[E4018] Type X does not implement trait ...Fields: no impl is defined`,
because the reader can't see impls the writer emitted.

If you have a `moonc-web.cjs` matching a toolchain that npm doesn't publish,
drop it in this directory manually — `ensureCompiler()` won't overwrite an
existing file unless you pass `--force`.
