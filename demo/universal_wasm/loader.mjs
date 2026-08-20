// Browser loader for the universal drop-a-bundle demo: the app's host
// machinery plus the dynamic-component bridge, and nothing else. Both live in
// published packages and are copied beside this file in dist (see
// dev/tasks.mbt): `app/wasm/loader.mjs` -> ./app-loader.mjs, and
// `dyncomp/host/wasm/loader.mjs` -> ./dyncomp-loader.mjs.
//
// This page is the only one that links the second: `tcomp` (the guest bridge)
// and `tkv` (localStorage, for what survives a reload) come in through
// `instantiate`'s makeExtra hook, so the counter and storybook pages carry
// neither.
//
// There is no drop-zone code here. A drop is an ordinary tutuca event: the app
// bridge registers the dropped files and hands their descriptors to the handler
// as `value` (`@on.drop="loadDropped e.value"` in universal_wasm.html), which
// loads one by id through the tcomp bridge. What this file used to do — a
// document-level listener reaching into dataTransfer.files, with its own load-id
// space — is now something every tutuca app gets from the framework.

import { instantiate } from "./app-loader.mjs";
import { createTcompImports, createTkvImports } from "./dyncomp-loader.mjs";

export async function loadWasm(wasmUrl) {
  return await instantiate(wasmUrl, (getExports) => ({
    tcomp: createTcompImports(getExports),
    tkv: createTkvImports(),
  }));
}
