// Browser loader for the universal drop-a-bundle demo: the shared lib's host
// machinery + tcomp bridge, and nothing else. The machinery lives in the
// shared lib (copied beside this file in dist — see dev/tasks.mbt).
//
// There is no drop-zone code here any more. A drop is an ordinary tutuca
// event: the app bridge registers the dropped files and hands their
// descriptors to the handler as `value` (`@on.drop="loadDropped value"` in
// universal_wasm.html), which loads one by id through the tcomp bridge. What
// this file used to do — a document-level listener reaching into
// dataTransfer.files, with its own load-id space — is now something every
// tutuca app gets from the framework.

import { instantiate, createTcompImports } from "./wasm-loader-lib.mjs";

export async function loadWasm(wasmUrl) {
  return await instantiate(wasmUrl, (getExports) => ({
    tcomp: createTcompImports(getExports),
  }));
}
