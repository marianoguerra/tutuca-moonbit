// Browser loader for the universal drop-a-bundle demo: the shared lib's host
// machinery + tcomp bridge, plus this page's drop-zone behavior (drop a
// .tutuca.tar.gz anywhere to load it). The machinery lives in the shared lib
// (copied beside this file in dist — see dev/tasks.mbt).

import { instantiate, createTcompImports } from "./wasm-loader-lib.mjs";

export { applyMargaui } from "./wasm-loader-lib.mjs";

// Make the page a drop target: cancel the browser's default file-open on both
// dragover and drop, and feed each dropped file to loadArchive. JS allocates
// the load ids (negative, never in the host's notify_paths) so completion
// notifies the root shell.
function installDropZone(tcomp) {
  let nextLoad = -1;
  document.addEventListener("dragover", (ev) => ev.preventDefault());
  document.addEventListener("drop", (ev) => {
    ev.preventDefault();
    const files = ev.dataTransfer?.files;
    if (!files?.length) return;
    for (const file of files) tcomp.loadArchive(file, nextLoad--);
  });
}

export async function loadWasm(wasmUrl) {
  let tcomp = null;
  const exports = await instantiate(wasmUrl, (getExports) => {
    tcomp = createTcompImports(getExports);
    return { tcomp };
  });
  installDropZone(tcomp);
  return exports;
}
