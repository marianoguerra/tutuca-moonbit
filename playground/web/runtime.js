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
          call("init", { manifest: manifestUrl, target }).catch((e) => {
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
    compile(code, views, viewsIr) {
      return call("compile", { code, views, viewsIr }, []);
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

// --- wasm-gc mount ---------------------------------------------------------
// The js host returns a JS module string mounted as an iframe blob; the wasm-gc
// host returns a wasm-gc BINARY that must be instantiated with the same import
// surface the shipped counter_wasm demo uses (jscore/tdom/console + the
// JS-String-Builtins engine option). Events can't carry MoonBit closures across
// the wasm boundary, so JS installs a delegated listener that calls the module's
// exported `on_event`, and the inspector is read back through the exported
// `state_json`/`classes_json` rather than closures published on the page.

// The jscore namespace mizchi/js/core's @core.Any lowers to on wasm-gc.
function jsCoreImports() {
  return {
    get: (o, k) => o[k], get_by_index: (o, i) => o[i],
    set: (o, k, v) => { o[k] = v; }, set_by_index: (o, i, v) => { o[i] = v; },
    call0: (o, n) => o[n](), call1: (o, n, a) => o[n](a), call2: (o, n, a, b) => o[n](a, b),
    call3: (o, n, a, b, c) => o[n](a, b, c), call4: (o, n, a, b, c, d) => o[n](a, b, c, d),
    invoke0: (f) => f(), invoke1: (f, a) => f(a), invoke2: (f, a, b) => f(a, b),
    invoke3: (f, a, b, c) => f(a, b, c), invoke4: (f, a, b, c, d) => f(a, b, c, d),
    new0: (c) => new c(), new1: (c, a) => new c(a), new2: (c, a, b) => new c(a, b),
    new3: (c, a, b, cc) => new c(a, b, cc), new4: (c, a, b, cc, d) => new c(a, b, cc, d),
    typeof: (v) => typeof v, is_nullish: (v) => v == null, is_null: (v) => v === null,
    is_undefined: (v) => v === undefined, is_array: (v) => Array.isArray(v),
    is_object: (v) => typeof v === "object" && v !== null, instanceof: (v, c) => v instanceof c,
    equal: (a, b) => a === b, global_this: () => globalThis, undefined: () => undefined,
    null: () => null, new_object: () => ({}), new_array: () => [],
    object_keys: (o) => Object.keys(o), object_values: (o) => Object.values(o),
    object_assign: (t, s) => Object.assign(t, s), object_has_own: (o, k) => Object.hasOwn(o, k),
    array_from: (v) => Array.from(v), array_length: (a) => a.length,
    json_stringify: (v) => JSON.stringify(v), json_stringify_pretty: (v, s) => JSON.stringify(v, null, s),
    json_parse: (t) => JSON.parse(t), to_string: (v) => (v == null ? String(v) : v.toString()),
    log: (m) => console.log(m), throw: (v) => { throw v; },
    from_int: (v) => v, from_uint: (v) => v, from_int64: (v) => v, from_uint64: (v) => v,
    from_float: (v) => v, from_double: (v) => v, from_string: (v) => v, from_bool: (v) => v,
  };
}

// The tdom namespace: typed reads @core can't do on wasm-gc plus the event
// bridge (a delegated listener that calls the wasm export back) and CSS inject.
function tdomImports(getExports, doc) {
  return {
    node_type: (n) => n.nodeType | 0, has_prop: (o, k) => k in o,
    try_set_prop: (o, k, v) => { try { o[k] = v; return true; } catch { return false; } },
    json_parse: (s) => JSON.parse(s),
    json_stringify: (v) => { try { return JSON.stringify(v) ?? ""; } catch { return ""; } },
    file_meta: (t) => {
      const f = t.files && t.files[0];
      return f ? JSON.stringify({ name: f.name, size: f.size, type: f.type, lastModified: f.lastModified }) : "";
    },
    get_int: (o, k) => o[k] | 0, get_bool: (o, k) => !!o[k], get_num: (o, k) => +(o[k] ?? 0),
    add_listener: (node, name) => {
      node.addEventListener(name, (ev) => {
        const ex = getExports();
        if (ex && ex.on_event) ex.on_event(ev);
      });
    },
    inject_css: (d, id, css) => {
      let el = d.getElementById(id);
      if (!el) { el = d.createElement("style"); el.id = id; d.head.appendChild(el); }
      el.textContent = css;
    },
  };
}

// Mount a wasm-gc-linked module (the bytes `linkCore` returned) in a fresh
// iframe realm and drive the DOM from wasm. `onState` is polled through the
// module's exported `state_json`. Returns the iframe. Throws (rejects) if the
// module fails to compile/instantiate — the caller surfaces that to the user.
export async function mountWasm(container, wasmBytes, { onState } = {}) {
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
    jscore: jsCoreImports(),
    tdom: tdomImports(() => exports, doc),
    console: { log: (...a) => console.log(...a) },
  };
  // The JS-String-Builtins proposal: moon emits imported string constants under
  // module "_" for `use-js-builtin-string`. Chrome-class engines only.
  const opts = { builtins: ["js-string"], importedStringConstants: "_" };
  const { instance } = await WebAssembly.instantiate(wasmBytes, imports, opts);
  exports = instance.exports;
  if (exports._start) exports._start();
  // The user module's exported mount() targets #app in ITS document; @core's
  // global_this() is the shell realm, so document lookups resolve here — mount
  // into the iframe by pointing the wasm host at the iframe's document.
  exports.mount();

  let last = null;
  const readState = () => {
    try {
      const s = exports.state_json ? exports.state_json() : null;
      if (s == null || s === last) return;
      last = s;
      onState?.(s);
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
