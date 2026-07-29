# @marianoguerra/tutuca-playground-payload

The prebuilt MoonBit interfaces and cores that
[`@marianoguerra/tutuca-playground`](https://www.npmjs.com/package/@marianoguerra/tutuca-playground)
compiles a visitor's code against: the standard library's `.mi` bundles, every
tutuca-mb package's `.mi`, and the ordered `.core` link closure — for both the
`js` and `wasm-gc` backends. On its own it does nothing; install it with the
playground.

```sh
npm install @marianoguerra/tutuca-playground \
            @marianoguerra/tutuca-playground-payload \
            @moonbit/moonc-worker
```

It ships as a separate package because it is a different kind of thing: ~22 MB
of build output that has to be regenerated whenever the MoonBit toolchain moves,
where the shell is a few hundred KB of code that doesn't.

## The pairing rule

These bundles are written by one exact `moonc` build and must be read by the
same one. Mixing builds does not fail cleanly — the compiler misreads the baked
interfaces and blames the visitor's code, classically with
`[E4018] Type X does not implement trait …: no impl is defined`.

So: install the `@moonbit/moonc-worker` version this package's
`peerDependencies` names. `playground/manifest.json` records the pin
(`toolchain`, `mooncBuild`, `moon`, `mooncWorker`), and the playground's worker
checks a served compiler against it before loading anything, so a mismatch
reports itself instead of turning into nonsense diagnostics.

## Layout

Unpacks into the same `playground/` folder the shell package uses, so copying
both into a static directory is all the wiring there is:

```sh
cp -r node_modules/@marianoguerra/tutuca-playground-payload/playground public/
```

| path | what |
| --- | --- |
| `playground/manifest.json` | per-target file lists, link order, and the toolchain pin |
| `playground/fs/<target>/std/` | standard-library `.mi` |
| `playground/fs/<target>/lib/` | tutuca-mb + dependency `.mi` |
| `playground/fs/<target>/cores/` | the ordered `.core` link closure |

MIT © the tutuca contributors.
