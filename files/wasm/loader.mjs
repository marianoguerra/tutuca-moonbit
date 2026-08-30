// The JS half of `files/wasm`: the `tfiles` import namespace.
//
// Linked through `instantiate`'s `makeExtra` hook rather than added to `tdom`,
// and that is deliberate. `tdom` is the namespace EVERY tutuca page declares,
// so a new function in it is a new import every page's loader must supply —
// and a page carrying an older copy of the loader stops instantiating at all.
// That has happened here before (see the note in playground/web/runtime.js
// about `dropped_files`). A namespace of its own has no such reach: a page
// that never links this never mentions `tfiles`, and nothing about it changes.
//
// Usage, in a page that wants downloads in its gallery:
//
//   import { instantiate } from "./app-loader.mjs";
//   import { createFilesImports } from "./files-loader.mjs";
//   const exports = await instantiate("./page.wasm", (getExports) => ({
//     tfiles: createFilesImports(getExports),
//   }));
//
// The page must also export `on_file_text` and forward it to
// `@fileswasm.on_file_text`, or a picked file is read and never delivered.
import { takeDroppedFile } from "../../app/wasm/loader.mjs";

/**
 * @param {() => WebAssembly.Exports} getExports
 */
export function createFilesImports(getExports) {
  return {
    // A download, by the only route a page has: a Blob, an object URL, a click
    // on an anchor nobody sees, and the URL released again. Synchronous and
    // one-way — the browser owns everything after the click, including whether
    // the viewer keeps the file, and none of that comes back.
    save_text: (name, mime, text) => {
      try {
        const blob = new Blob([text], { type: mime || "text/plain" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = name || "download.txt";
        a.click();
        URL.revokeObjectURL(a.href);
      } catch (e) {
        // A download the browser refused is not worth crashing a render over,
        // and there is no channel to report it on: `save_text` answers nothing
        // by design. The console is where a page's own failures go.
        console.error("tutuca files: save failed:", e);
      }
    },
    // The read, answered later through the page's `on_file_text` export.
    //
    // `takeDroppedFile` is the app bridge's own table — the same one
    // `@on.drop="load e.value"` fills and `dyncomp`'s bundle loader reads —
    // because a File cannot cross into wasm-gc and an integer can.
    read_text: (fileId, reqId) => {
      const file = takeDroppedFile(fileId);
      if (!file) {
        getExports().on_file_text(reqId, false, `no file #${fileId}`);
        return;
      }
      file
        .text()
        .then((text) => getExports().on_file_text(reqId, true, text))
        .catch((e) => getExports().on_file_text(reqId, false, String(e)));
    },
  };
}
