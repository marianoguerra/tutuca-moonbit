// Browser loader for the dyncomp storybook: the app's host machinery plus the
// dynamic-component bridge, and nothing else. Both live in published packages
// and are copied beside this file in dist (see dev/tasks.mbt):
// `app/wasm/loader.mjs` -> ./app-loader.mjs, and
// `dyncomp/host/wasm/loader.mjs` -> ./dyncomp-loader.mjs.
//
// `tkv` comes in beside `tcomp` because the dyncomp bridge declares both import
// namespaces; this page keeps no session, so nothing reaches localStorage — but
// an undeclared import is a link error rather than a dormant one.
//
// There is no drop-zone code here. A drop is an ordinary tutuca event: the app
// bridge registers the dropped files and hands their descriptors to the handler
// as `value` (`@on.drop="filesDropped value"` in storybook.html), which loads
// one by id through the tcomp bridge.

import { instantiate } from "./app-loader.mjs";
import { createTcompImports, createTkvImports } from "./dyncomp-loader.mjs";

export async function loadWasm(wasmUrl) {
  return await instantiate(wasmUrl, (getExports) => ({
    tcomp: createTcompImports(getExports),
    tkv: createTkvImports(),
  }));
}
