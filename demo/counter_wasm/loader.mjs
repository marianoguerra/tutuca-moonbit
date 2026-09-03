// Browser loader for the wasm-gc counter demo: plain host, no dynamic
// components. The machinery lives in `app/wasm/loader.mjs`, copied beside this
// file in dist as ./app-loader.mjs (see dev/tasks.mbt) — and this page links
// none of the guest bridge, which is the point of the two being separate.

import { instantiate } from "./app-loader.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl);
}
