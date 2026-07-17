// Browser loader for the wasm-gc counter demo: plain host, no dynamic
// components. All the machinery lives in the shared lib (copied beside this
// file in dist — see dev/tasks.mbt).

import { instantiate } from "./wasm-loader-lib.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl);
}
