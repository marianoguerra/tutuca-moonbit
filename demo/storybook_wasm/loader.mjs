// Browser loader for the storybook gallery: the app's host machinery, from
// `app/wasm/loader.mjs` (copied beside this file in dist as ./app-loader.mjs —
// see dev/tasks.mbt), plus the file service the Trace tab's Download and Load
// buttons need (./files-loader.mjs, copied the same way).
//
// No `tcomp` bridge and no `tkv`: runtime-loaded component bundles live in the
// universal demo, which is the one page that hosts them, and this page links
// nothing from `dyncomp/host/wasm/loader.mjs` as a result.
//
// `tfiles` IS linked, because `@panelsw.all` names `files/wasm` — a gallery
// with the standard tabs can download a recording. The page's `on_file_text`
// export is the other half; without it a picked file is read and never
// delivered.

import { instantiate } from "./app-loader.mjs";
import { createFilesImports } from "./files-loader.mjs";

export async function loadWasm(wasmUrl) {
  return instantiate(wasmUrl, (getExports) => ({
    tfiles: createFilesImports(getExports),
  }));
}
