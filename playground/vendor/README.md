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
`mooncWorker` field; `assemble.mjs` reads `moonc` and compares it against
`moon version --all`.

The pin is the FAST PATH, not the rule. The rule is that the worker must be
built from the *installed* moonc, and when the pin disagrees with what is
installed, `assemble.mjs` goes looking for a worker that satisfies the rule
rather than failing: the registry drops SemVer build metadata (`npm view` says
`0.1.202608243` for a package whose own `package.json` says
`0.1.202608243+f8a486b6f`), so candidates are checked by downloading them,
newest same-day first — the worker for `moon 0.1.<YYYYMMDD>` is published as
`0.1.<YYYYMMDD><n>`. It fails only when npm publishes **no** worker built from
the installed moonc (`TUTUCA_ALLOW_TOOLCHAIN_MISMATCH=1` overrides that too,
and the payload will not work).

That is what CI needs: `cli.moonbitlang.com` serves `latest` and nothing else,
so without the self-heal every toolchain release turns the Pages deploy red and
freezes the site at whatever commit last matched the pin. It prints the exact
`toolchain.json` edit that makes it the fast path again — it does not apply
it, because a build step that rewrites a pinned file leaves every CI run with
a dirty tree and nobody deciding anything.

`playground/vendor/moonc-web.json` records which worker the blob beside it is,
so a later run can tell without downloading 5 MB. Delete it and the blob is
treated as hand-dropped (below) and left alone.

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

### Serving someone else's copy

Nothing in the shipped playground requires the compiler to sit beside the
payload: a host can point it at their own installed `@moonbit/moonc-worker`
with `globalThis.MB_PLAYGROUND = { compilerUrl }` (see `playgroundConfig` in
`playground/web/runtime.js`), which is how the playground can be packaged
without redistributing the blob. The pairing rule above still holds, and the
worker enforces what it can: `manifest.json` records the `mooncWorker` version
the payload was built against, and a compiler served out of an npm package —
`package.json` beside it — is checked against that before anything loads.
