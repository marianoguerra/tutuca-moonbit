// The page's JS half: the three things MoonBit cannot do from here.
//
//   instantiate   `WebAssembly.compile` answers a promise, and there is nothing
//                 on the MoonBit side that can wait on one
//   fetch         same
//   drop          `drop` is the only DOM event that crosses component
//                 boundaries, and dispatch gives it to the first ancestor with
//                 a handler — so a hole claiming it would swallow the
//                 page-wide file drop. Listening OUTSIDE the tutuca tree
//                 sidesteps the collision rather than negotiating with it.
import { loadGuest, b64ToBytes } from "./card.js";

const host = () => globalThis.__universalHost;

globalThis.__universal = {
  async instantiate(key, wasmB64, manifestJson) {
    try {
      await loadGuest(b64ToBytes(wasmB64), key);
      host().finish(key, manifestJson);
    } catch (e) {
      console.error(e);
      host().finish(key, "");
    }
  },
  async fetchText(path, tag) {
    try {
      const res = await fetch(path);
      host().fetched(tag, res.ok ? await res.text() : "");
    } catch {
      host().fetched(tag, "");
    }
  },
};

// The runtime module the cards are instantiated against. `card.js` fetches it
// through `__tutucard.runtimeWasm`, which is the playground's entry point and
// not this page's — so this page answers the same question its own way.
globalThis.__tutucard = globalThis.__tutucard ?? {};
if (!globalThis.__tutucard.runtimeWasm) {
  globalThis.__tutucard.runtimeWasm = () =>
    JSON.stringify({ ok: true, wasm: globalThis.__universalRuntimeB64 ?? "" });
}

// The library index: names and paths, as two parallel lists, because the pump
// between here and the shell carries strings.
async function library() {
  try {
    const res = await fetch("./cards/index.json");
    if (!res.ok) return;
    const rows = await res.json();
    host().library(
      rows.map((r) => r.name).join(","),
      rows.map((r) => r.path).join(","),
    );
  } catch {
    /* no library is not an error: the kit is still there */
  }
}

function dropTarget() {
  const stop = (e) => {
    e.preventDefault();
    e.stopPropagation();
  };
  document.addEventListener("dragover", stop);
  document.addEventListener("drop", async (e) => {
    stop(e);
    for (const file of e.dataTransfer?.files ?? []) {
      // A `.wasm` is already a module and needs no compiler; anything else is
      // read as a card and compiled. Both end in the same place.
      if (file.name.endsWith(".wasm")) {
        const key = file.name.replace(/\.wasm$/, "");
        const bytes = new Uint8Array(await file.arrayBuffer());
        const { manifest } = await loadGuest(bytes, key);
        host().finish(manifest.moduleName ?? key, JSON.stringify(manifest));
      } else {
        host().dropped(file.name, await file.text());
      }
    }
  });
}

export async function start(runtimeB64) {
  globalThis.__universalRuntimeB64 = runtimeB64;
  host().boot();
  dropTarget();
  await library();
}
