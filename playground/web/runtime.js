// Shared playground runtime: a compiler client (worker RPC) and an iframe
// mounter. Used by both the standalone playground driver (driver.js) and the
// embeddable <mb-playground> element (../site/embed.js). The worker URL is a
// parameter so the two callers can point at the same compiler.worker.js from
// different folders (the worker fetches its payload relative to its own URL, so
// the manifest/`fs`/cores resolve the same way regardless of the caller's path).

// A compiler client backed by one worker. `init()` is memoized, so many callers
// (e.g. a page full of embedded playgrounds) share a single compiler load.
export function makeCompiler(workerUrl, manifestUrl = "./manifest.json") {
  const worker = new Worker(workerUrl);
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

  let initPromise = null;
  return {
    // Load the compiler + interfaces + cores for `target` (once).
    init(target = "js") {
      // Memoize so a page full of playgrounds shares one compiler load. Drop the
      // memo on failure so a failed load (e.g. a network blip) can be retried by
      // the next init() instead of being cached as a permanently-rejected promise.
      initPromise ??= call("init", { manifest: manifestUrl, target }).catch((e) => {
        initPromise = null;
        throw e;
      });
      return initPromise;
    },
    // Compile + link one MoonBit source; returns { ok, diagnostics, result, ms }.
    compile(code) {
      return call("compile", { code }, []);
    },
  };
}

// margaui (the CSS class compiler the docs examples use) — same CDN build the
// compiled demo pages compile against. Loaded once, lazily, and only when a
// preview actually publishes classes.
const MARGAUI_THEME = "https://marianoguerra.github.io/margaui/themes/theme.css";
let _margauiCompile = null;
function margauiCompile() {
  _margauiCompile ??= import("https://cdn.jsdelivr.net/npm/margaui/+esm").then((m) => m.compile);
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
  const themeLink = margaui ? `<link rel="stylesheet" href="${MARGAUI_THEME}">` : "";
  doc.open();
  doc.write(
    `<!doctype html><html data-theme="${dark ? "dark" : "light"}"><head><meta charset="utf-8">` +
      themeLink +
      `<style>body{font-family:system-ui,sans-serif;margin:1rem}</style></head>` +
      `<body><div id="app"></div><script type="module" src="${blobUrl}"><\/script></body></html>`,
  );
  doc.close();

  const win = iframe.contentWindow;
  let last = null;
  const readState = () => {
    try {
      const s = win.__tutuca && win.__tutuca.state ? win.__tutuca.state() : null;
      if (s == null || s === last) return;
      last = s;
      onState?.(s);
    } catch {}
  };
  // Compile + inject the app's margaui class set (retry briefly: module scripts
  // may run just after the iframe's load event).
  let styled = false;
  const styleMargaui = async () => {
    if (styled) return;
    let classes = null;
    try {
      classes = win.__tutuca && win.__tutuca.classes ? JSON.parse(win.__tutuca.classes()) : null;
    } catch {}
    if (classes == null) return;
    styled = true;
    if (!classes.length) return;
    try {
      const compile = await margauiCompile();
      const css = await compile(classes);
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

// Keep only real compile errors ([E…], not warnings) from a diagnostics list.
export function errorDiagnostics(diagnostics) {
  return (diagnostics || []).filter((d) => /\[E\d/.test(d) && !/Warning/.test(d));
}
