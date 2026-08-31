// A CONSUMER of tutuca, not a part of it.
//
// Scaffolded by `tutuca new-storybook` and committed as it came out, so the
// example and the template in the binary cannot drift: if this stops building,
// so does the first thing a new user runs.
//
// It sits inside the tutuca checkout for convenience — so a release cannot
// quietly break it — but depends on the PUBLISHED `marianoguerra/tutuca`,
// fetched from mooncakes.io like anyone else's. No path dependency, no `../`
// anywhere under this directory.
//
// A gallery of this project's own tutuca components.
//
// `mizchi/js` is declared directly because `page/` imports `mizchi/js/core`
// for the `@core.Any` in `on_event`, and a package may only import from a
// module its own module declares. Pin it to the version tutuca resolves, so
// there is one copy of it in the graph.
//
// Build: node build.mjs   Serve: tutuca storybook dist

name = "marianoguerra/tutuca-example-storybook-gallery"

version = "0.1.0"

description = "A storybook gallery built only from published packages, exactly as `tutuca new-storybook` writes it"

preferred_target = "wasm-gc"

import {
  "marianoguerra/tutuca@0.43.0",
  "mizchi/js@0.12.2",
}
