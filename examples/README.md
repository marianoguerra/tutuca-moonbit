# examples

Projects that use tutuca the way somebody outside this repository would: each
one has its **own** `moon.mod` depending on the **published**
`marianoguerra/tutuca` from mooncakes.io, with no path dependency, no `../` out
of its own directory, and no step that runs anything from this checkout.

That is what makes them worth having. `moon check` never leaves the module, so
it cannot tell you whether a release is actually usable — whether the files a
page needs survived `moon publish`, whether the paths between them still
resolve once they are unpacked somewhere else, whether a scaffolder emits a tree
that builds. An example is the only thing here that answers those.

They live inside the repository so that a release cannot quietly break one, and
they are excluded from the published package, because shipping a consumer inside
the thing it consumes would be a loop.

| example | covers |
| --- | --- |
| [`dyncomp-dice`](dyncomp-dice/) | the universal dynamic-component host, and writing a `tutuca:component` guest — one page that loads WebAssembly components at runtime, plus a die of its own to load into it |
| [`storybook-gallery`](storybook-gallery/) | the storybook as a library: a gallery of a project's own components, with stories projected from its modules' `examples`. Committed exactly as `tutuca new-storybook` emits it, so the example and the scaffold in the binary cannot drift |

## Running them

Each has a `build.mjs` and a README:

```sh
cd examples/dyncomp-dice
node build.mjs
python3 -m http.server 8099 -d dist

cd examples/storybook-gallery
node build.mjs
tutuca storybook dist
```

Run them after a release, before announcing one. They are not part of `cmd/dev
-- ci`: they need npm and a mooncakes fetch, and — deliberately — they build the
*published* package rather than the working tree, so a green CI on an unreleased
change tells you nothing about them.

## Adding one

Cover a seam the others do not, name the directory after it, and keep the rule:
nothing inside may reach out of its own directory. If an example needs something
from this repository to work, that is a finding about the package, not a reason
to reach for it.
