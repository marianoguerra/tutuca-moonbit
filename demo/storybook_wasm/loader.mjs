// Browser loader for the storybook gallery: the shared lib's host machinery.
// Everything lives in the shared lib (copied beside this file in dist — see
// dev/tasks.mbt).
//
// No `tcomp` bridge: runtime-loaded component bundles live in the universal
// demo, which is the one page that hosts them.

import { instantiate } from "./wasm-loader-lib.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl);
}
