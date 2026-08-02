// Browser loader for the storybook gallery: the app's host machinery, from
// `app/wasm/loader.mjs` (copied beside this file in dist as ./app-loader.mjs —
// see dev/tasks.mbt).
//
// No `tcomp` bridge and no `tkv`: runtime-loaded component bundles live in the
// universal demo, which is the one page that hosts them, and this page links
// nothing from `dyncomp/host/wasm/loader.mjs` as a result.

import { instantiate } from "./app-loader.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl);
}
