// Shared playground runtime: a compiler client (worker RPC) and an iframe
// mounter. Used by both the standalone playground driver (driver.js) and the
// embeddable <mb-playground> element (../site/embed.js).
//
// The wasm-gc mount's import object comes from ./app-loader.mjs — the SAME
// `app/wasm/loader.mjs` every other wasm-gc page in this repo instantiates
// with, copied in by assemble.mjs. It used to be a second, hand-kept copy of
// those two namespaces here, which is exactly as durable as it sounds: `tdom`
// grew `dropped_files`, the copy did not, and every wasm-gc preview died on a
// LinkError that the fallback reported as "wasm-gc not supported here".
//
// Every URL the worker needs is resolved HERE, absolutely, and handed over in
// the init message; the worker resolves nothing against its own location. That
// is what lets the three movable parts move independently — this shell's own
// scripts, the payload (manifest + `fs/`), and the compiler blob — instead of
// all three having to sit in one folder. `playgroundConfig` below is where a
// shell decides that layout.

// Where a shell's four URLs come from. `defaultBase` is the folder that shell's
// own bundle sits in, resolved by the caller against its `import.meta.url`
// ("./" for driver.js, which lives IN the payload folder; "../playground/" for
// site/embed.js). Overrides go on `globalThis.MB_PLAYGROUND` before the first
// compile — all optional, all resolved against the page:
//
//   payloadBase   folder holding manifest.json + fs/ (the toolchain-coupled
//                 half — the part worth versioning and shipping separately)
//   compilerUrl   moonc-web.cjs, e.g. an installed @moonbit/moonc-worker
//                 served from the consumer's own static dir
//   workerUrl     compiler.worker.js, if this shell's scripts were split off
//
// ES imports (runtime.js, editor.bundle.js, viewgen.js, margaui.wasm) are NOT
// covered by this: they are code, resolved by whoever imports them. This is for
// what has to be fetched by URL.
import { createJsCoreImports, createTdomImports } from "./app-loader.mjs";

export function playgroundConfig(defaultBase) {
  const cfg = globalThis.MB_PLAYGROUND ?? {};
  // a base must end in "/" or the last segment is a sibling, not a folder
  const dir = (u) => (String(u).endsWith("/") ? String(u) : String(u) + "/");
  const code = new URL(dir(defaultBase), document.baseURI);
  const payload = cfg.payloadBase ? new URL(dir(cfg.payloadBase), document.baseURI) : code;
  const at = (override, name) =>
    override ? new URL(override, document.baseURI) : new URL(name, code);
  return {
    workerUrl: at(cfg.workerUrl, "compiler.worker.js"),
    compilerUrl: at(cfg.compilerUrl, "moonc-web.cjs"),
    manifestUrl: new URL("manifest.json", payload),
    fsBase: new URL("fs/", payload),
  };
}

// Spawn the compiler worker. A Worker script must be same-origin, so one served
// from a CDN is wrapped in a one-line same-origin blob that importScripts() the
// real URL (the CDN has to send CORS headers; unpkg and jsdelivr do). The blob's
// own base URL is opaque, which is fine precisely because the worker fetches
// nothing relative to itself.
function spawnWorker(href) {
  if (new URL(href).origin === location.origin) return new Worker(href);
  const shim = `importScripts(${JSON.stringify(href)});`;
  return new Worker(URL.createObjectURL(new Blob([shim], { type: "text/javascript" })));
}

// A compiler client backed by one worker. `init()` is memoized, so many callers
// (e.g. a page full of embedded playgrounds) share a single compiler load.
// The three URLs default to siblings of the worker, which is the layout
// `assemble.mjs` produces; pass `playgroundConfig()`'s result to relocate them.
export function makeCompiler(workerUrl, { manifestUrl, compilerUrl, fsBase } = {}) {
  const workerHref = new URL(workerUrl, document.baseURI).href;
  const rel = (u, dflt) => new URL(u ?? dflt, workerHref).href;
  const urls = {
    manifest: rel(manifestUrl, "./manifest.json"),
    compiler: rel(compilerUrl, "./moonc-web.cjs"),
    fsBase: rel(fsBase, "./fs/"),
  };
  const worker = spawnWorker(workerHref);
  let seq = 0;
  const pending = new Map();
  worker.onmessage = (e) => {
    const { id, ok, value, error } = e.data;
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    ok ? p.resolve(value) : p.reject(new Error(error));
  };
  const call = (kind, args, transfer) =>
    new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, reject });
      worker.postMessage({ id, kind, args }, transfer || []);
    });

  // Memoize per target so a page full of same-target playgrounds shares one
  // compiler load, while a target toggle can still switch the worker's payload.
  const initPromises = new Map();
  return {
    // Load the compiler + interfaces + cores for `target` (once per target).
    init(target = "js") {
      // Drop the memo on failure so a failed load (e.g. a network blip) can be
      // retried by the next init() instead of being cached as a rejected promise.
      if (!initPromises.has(target)) {
        initPromises.set(
          target,
          call("init", { ...urls, target }).catch((e) => {
            initPromises.delete(target);
            throw e;
          }),
        );
      }
      return initPromises.get(target);
    },
    // Compile + link one MoonBit source; returns { ok, diagnostics, result, ms }.
    // `views` / `viewsIr` are the modules generated from the View tab; they
    // join the user's package as extra files (see the worker's compile()).
    // The target travels WITH the request: one worker serves every caller on
    // the page, and they need not agree on a backend, so it can't be left as
    // worker state that the last init() decides (see compiler.worker.js).
    // `init(target)` must have resolved first — it is what loads that payload.
    compile(code, views, viewsIr, target = "js") {
      return call("compile", { code, views, viewsIr, target }, []);
    },
  };
}

// margaui (the CSS class compiler the docs examples use) — the same MoonBit
// compiler (marianoguerra/tailwindcss + the embedded margaui bundle) the demo
// pages use, shipped as ./margaui.wasm (wasm-gc + wasm-opt, ~0.47 MB; see
// assemble.mjs). Instantiated once, lazily, and only when a preview actually
// publishes classes; its `compile(classesJson) -> css` export marshals strings
// directly via js-string-builtins. Light + dark theme vars are compiled into
// that CSS, so no external theme stylesheet is needed.
let _margauiCompile = null;
function margauiCompile() {
  _margauiCompile ??= (async () => {
    const url = new URL("./margaui.wasm", import.meta.url);
    const bytes = await (await fetch(url)).arrayBuffer();
    // moon emits js-string-builtin imports plus imported string constants
    // under module "_"; the engine supplies both from these opts (Chrome-class).
    const opts = { builtins: ["js-string"], importedStringConstants: "_" };
    const { instance } = await WebAssembly.instantiate(bytes, {}, opts);
    if (instance.exports._start) instance.exports._start();
    return (classesJson) => instance.exports.compile(classesJson);
  })();
  return _margauiCompile;
}

// Mount linked module JS text in a fresh same-origin iframe inside `container`
// (a new realm per run, so re-mounts never collide). Reads back the preview's
// `__tutuca.state()` on load and after any interaction, calling `onState(str)`
// whenever it changes. When the mounted app publishes margaui classes
// (`__tutuca.classes()`), they are compiled to CSS and injected so class-styled
// examples render the same as the compiled gallery. Returns the iframe.
export function mount(container, jsText, { onState, margaui = true } = {}) {
  container.innerHTML = "";
  const iframe = document.createElement("iframe");
  // same-origin (no sandbox): the shell reads iframe.__tutuca for the inspector,
  // and the iframe loads a parent-origin blob module. The user authored the code.
  container.appendChild(iframe);
  const doc = iframe.contentDocument;
  const blobUrl = URL.createObjectURL(new Blob([jsText], { type: "text/javascript" }));
  const dark = typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches;
  doc.open();
  doc.write(
    `<!doctype html><html data-theme="${dark ? "dark" : "light"}"><head><meta charset="utf-8">` +
      `<style>body{font-family:system-ui,sans-serif;margin:1rem}</style></head>` +
      `<body><div id="app"></div><script type="module" src="${blobUrl}"><\/script></body></html>`,
  );
  doc.close();

  const win = iframe.contentWindow;
  let last = null;
  const readState = () => {
    try {
      const t = win.__tutuca;
      const s = t && t.state ? t.state() : null;
      if (s == null || s === last) return;
      last = s;
      // The activity log is read with the state so the two panels always show
      // the same moment: it is the transactor's observer stream, one entry per
      // handler invocation, and the last of them is what produced this state.
      let a = null;
      try { a = t && t.activity ? t.activity() : null; } catch {}
      onState?.(s, a);
    } catch {}
  };
  // Compile + inject the app's margaui class set (retry briefly: module scripts
  // may run just after the iframe's load event).
  let styled = false;
  const styleMargaui = async () => {
    if (styled) return;
    let classesJson = null;
    try {
      classesJson = win.__tutuca && win.__tutuca.classes ? win.__tutuca.classes() : null;
    } catch {}
    if (classesJson == null) return;
    styled = true;
    let classes = [];
    try { classes = JSON.parse(classesJson); } catch {}
    if (!classes.length) return;
    try {
      // the published compiler parses the JSON class array and returns CSS
      const compile = await margauiCompile();
      const css = compile(classesJson);
      const style = doc.createElement("style");
      style.textContent = css;
      doc.head.appendChild(style);
    } catch {}
  };
  iframe.addEventListener("load", () => {
    setTimeout(readState, 30);
    if (margaui) for (const t of [30, 120, 300, 700]) setTimeout(styleMargaui, t);
    // any interaction in the preview may change state; re-read on the next tick
    for (const ev of ["click", "input", "change", "keydown"]) {
      doc.addEventListener(ev, () => setTimeout(readState, 0), true);
    }
  });
  setTimeout(readState, 80);
  return iframe;
}

// --- wasm-gc mount ---------------------------------------------------------
// The js host returns a JS module string mounted as an iframe blob; the wasm-gc
// host returns a wasm-gc BINARY that must be instantiated with the same import
// surface the shipped counter_wasm demo uses (jscore/tdom/console + the
// JS-String-Builtins engine option). Events can't carry MoonBit closures across
// the wasm boundary, so JS installs a delegated listener that calls the module's
// exported `on_event`, and the inspector is read back through the exported
// `state_json`/`classes_json` rather than closures published on the page.

// The jscore namespace, as `app/wasm/loader.mjs` defines it, with ONE
// substitution: `realm`, the window every `global_this()` resolves against. The
// wasm host reaches the DOM as `global_this()._get("document")`
// (app/wasm/glue.mbt), so pointing it at the preview iframe's window is what
// makes the app mount THERE instead of hunting for #app in the shell page and
// warning that it is missing. Everything else is the shipped contract — this
// file has no business restating it.
function jsCoreImports(realm) {
  return { ...createJsCoreImports(), global_this: () => realm };
}

// Mount a wasm-gc-linked module (the bytes `linkCore` returned) in a fresh
// iframe realm and drive the DOM from wasm. `onState` is polled through the
// module's exported `state_json`, and the margaui class set is read back
// through `classes_json` — the twin of what the js mount reads off
// `__tutuca`. Returns the iframe. Throws (rejects) if the module fails to
// compile/instantiate — the caller surfaces that to the user.
export async function mountWasm(container, wasmBytes, { onState, margaui = true } = {}) {
  container.innerHTML = "";
  const iframe = document.createElement("iframe");
  container.appendChild(iframe);
  const doc = iframe.contentDocument;
  const dark = typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches;
  doc.open();
  doc.write(
    `<!doctype html><html data-theme="${dark ? "dark" : "light"}"><head><meta charset="utf-8">` +
      `<style>body{font-family:system-ui,sans-serif;margin:1rem}</style></head>` +
      `<body><div id="app"></div></body></html>`,
  );
  doc.close();

  let exports = null;
  const imports = {
    jscore: jsCoreImports(iframe.contentWindow),
    tdom: createTdomImports(() => exports),
    console: { log: (...a) => console.log(...a) },
  };
  // The JS-String-Builtins proposal: moon emits imported string constants under
  // module "_" for `use-js-builtin-string`. Chrome-class engines only.
  const opts = { builtins: ["js-string"], importedStringConstants: "_" };
  const { instance } = await WebAssembly.instantiate(wasmBytes, imports, opts);
  exports = instance.exports;
  if (exports._start) exports._start();
  // The user module's exported mount() targets #app in whatever document
  // global_this() names — the iframe's, via the `realm` handed to jsCoreImports.
  exports.mount();

  // The margaui class set, compiled to CSS and injected — what makes a
  // class-styled example look the same here as in the compiled gallery. The js
  // mount has to retry this on a timer (its blob module runs after the iframe's
  // load event); here mount() is a plain synchronous call, so by this line the
  // classes are already collected and one read is enough.
  if (margaui) {
    try {
      const classesJson = exports.classes_json ? exports.classes_json() : null;
      if (classesJson && JSON.parse(classesJson).length) {
        const style = doc.createElement("style");
        style.textContent = (await margauiCompile())(classesJson);
        doc.head.appendChild(style);
      }
    } catch {}
  }

  let last = null;
  const readState = () => {
    try {
      const s = exports.state_json ? exports.state_json() : null;
      if (s == null || s === last) return;
      last = s;
      let a = null;
      try { a = exports.activity_json ? exports.activity_json() : null; } catch {}
      onState?.(s, a);
    } catch {}
  };
  iframe.addEventListener("load", () => setTimeout(readState, 30));
  for (const ev of ["click", "input", "change", "keydown"]) {
    doc.addEventListener(ev, () => setTimeout(readState, 0), true);
  }
  setTimeout(readState, 30);
  return iframe;
}

// Keep only real compile errors ([E…], not warnings) from a diagnostics list.
export function errorDiagnostics(diagnostics) {
  return (diagnostics || []).filter((d) => /\[E\d/.test(d) && !/Warning/.test(d));
}
