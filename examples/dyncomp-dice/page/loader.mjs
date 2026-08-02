// Browser loader for the universal host page: the app's machinery plus the
// dynamic-component bridge, and nothing else.
//
// Both files it imports come from the published package and are copied flat
// beside this one by ../build.mjs:
//
//   .mooncakes/marianoguerra/tutuca/app/wasm/loader.mjs        -> ./app-loader.mjs
//   .mooncakes/marianoguerra/tutuca/dyncomp/host/wasm/loader.mjs -> ./dyncomp-loader.mjs
//
// The second imports the first by a relative path that is correct where they
// live and wrong once they land side by side, so build.mjs rewrites it. That
// rewrite is the one piece of wiring the published docs do not spell out — they
// show these as bare specifiers, which no browser resolves.
//
// There is no drop-zone code here. A drop is an ordinary tutuca event: the app
// bridge registers the dropped files and hands their descriptors to the handler
// as `value`, and the host loads one by id through the tcomp bridge.

import { instantiate } from "./app-loader.mjs";
import { createTcompImports, createTkvImports } from "./dyncomp-loader.mjs";

export async function loadWasm(wasmUrl) {
  return await instantiate(wasmUrl, (getExports) => ({
    tcomp: createTcompImports(getExports),
    tkv: createTkvImports(),
  }));
}
