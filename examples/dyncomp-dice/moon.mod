// A CONSUMER of tutuca, not a part of it.
//
// This module sits inside the tutuca checkout for convenience — so that a
// release cannot quietly break it — but it depends on the PUBLISHED
// `marianoguerra/tutuca`, fetched from mooncakes.io like anyone else's would
// be. There is no path dependency and no `../` anywhere under this directory,
// and that is the property this example exists to prove: everything the
// universal dynamic-component host needs is reachable from the tarball.
//
// It is one of `examples/`, not "the" example: it covers the dynamic-component
// seam and nothing else, and a second example covering a different one should
// need no change here.
//
// `mizchi/js` is declared directly because `page/` imports `mizchi/js/core`
// for the `@core.Any` in `on_event`, and a package may only import from a
// module its own module declares. It is pinned to the version tutuca
// resolves, so there is one copy of it in the graph.
//
// Build: node build.mjs  (see README.md — NOT `just`, which lives upstairs)

name = "marianoguerra/tutuca-example-dyncomp-dice"

version = "0.1.0"

description = "A self-contained tutuca universal host, and one guest of its own, built only from published packages"

preferred_target = "wasm-gc"

import {
  "marianoguerra/tutuca@0.41.5",
  "mizchi/js@0.12.2",
}
