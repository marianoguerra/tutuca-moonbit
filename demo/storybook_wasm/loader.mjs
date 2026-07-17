// Browser loader for the storybook gallery: the shared lib's host machinery
// plus the `tcomp` dynamic-component bridge (the Dynamic pane loads
// `tutuca:component` bundles at runtime). Everything lives in the shared lib
// (copied beside this file in dist — see dev/tasks.mbt).

import { instantiate, createTcompImports } from "./wasm-loader-lib.mjs";

export { applyMargaui } from "./wasm-loader-lib.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl, (getExports) => ({
    tcomp: createTcompImports(getExports),
  }));
}
