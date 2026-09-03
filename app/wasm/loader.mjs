// Browser-side loader for a wasm-gc tutuca app: the import namespaces the
// MoonBit side of this package and `vdom/wasm` declare, plus the instantiate
// call that supplies them.
//
//  - `jscore`: what mizchi/js core needs on wasm-gc
//  - `tdom`:   typed DOM reads @core.Any can't do on wasm-gc, plus the event
//              bridge (deduped delegated listeners that call the exported
//              `on_event`, since a MoonBit closure cannot cross into JS on
//              wasm-gc)
//  - `instantiate`: fetch + instantiate a module with those imports, with a
//              `makeExtra` hook for whatever else a host links in
//
// It lives HERE rather than beside a demo page because `app/wasm` and
// `vdom/wasm` are published packages whose import contract this file IS: a
// consumer who adds marianoguerra/tutuca and builds for wasm-gc needs it, and
// cannot reach anything under demo/. The dynamic-component half — `tcomp` and
// `tkv`, the bundle unpacker, the guest arena — is in
// `tgc/host/loader.mjs` beside the packages that declare those, and
// is linked through `makeExtra`; a page that never loads a bundle then carries
// none of it.
//
// margaui styling is compiled in MoonBit (the host's mount() / refresh_margaui),
// not here — the page only pre-places an empty <style id="margaui-css">.

export function createJsCoreImports() {
  return {
    get: (o, k) => o[k],
    get_by_index: (o, i) => o[i],
    set: (o, k, v) => { o[k] = v; },
    set_by_index: (o, i, v) => { o[i] = v; },
    call0: (o, n) => o[n](),
    call1: (o, n, a) => o[n](a),
    call2: (o, n, a, b) => o[n](a, b),
    call3: (o, n, a, b, c) => o[n](a, b, c),
    call4: (o, n, a, b, c, d) => o[n](a, b, c, d),
    invoke0: (f) => f(),
    invoke1: (f, a) => f(a),
    invoke2: (f, a, b) => f(a, b),
    invoke3: (f, a, b, c) => f(a, b, c),
    invoke4: (f, a, b, c, d) => f(a, b, c, d),
    new0: (c) => new c(),
    new1: (c, a) => new c(a),
    new2: (c, a, b) => new c(a, b),
    new3: (c, a, b, cc) => new c(a, b, cc),
    new4: (c, a, b, cc, d) => new c(a, b, cc, d),
    typeof: (v) => typeof v,
    is_nullish: (v) => v == null,
    is_null: (v) => v === null,
    is_undefined: (v) => v === undefined,
    is_array: (v) => Array.isArray(v),
    is_object: (v) => typeof v === "object" && v !== null,
    instanceof: (v, c) => v instanceof c,
    equal: (a, b) => a === b,
    global_this: () => globalThis,
    undefined: () => undefined,
    null: () => null,
    new_object: () => ({}),
    new_array: () => [],
    object_keys: (o) => Object.keys(o),
    object_values: (o) => Object.values(o),
    object_assign: (t, s) => Object.assign(t, s),
    object_has_own: (o, k) => Object.hasOwn(o, k),
    array_from: (v) => Array.from(v),
    array_length: (a) => a.length,
    json_stringify: (v) => JSON.stringify(v),
    json_stringify_pretty: (v, s) => JSON.stringify(v, null, s),
    json_parse: (t) => JSON.parse(t),
    to_string: (v) => (v == null ? String(v) : v.toString()),
    log: (m) => console.log(m),
    throw: (v) => { throw v; },
    from_int: (v) => v,
    from_uint: (v) => v,
    from_int64: (v) => v,
    from_uint64: (v) => v,
    from_float: (v) => v,
    from_double: (v) => v,
    from_string: (v) => v,
    from_bool: (v) => v,
  };
}

// The files of the LAST drop, by id. A drop event's `value` carries these
// descriptors, and a handler acts on them by id (see `dropped_file` and
// tcomp's `load_dropped`) — the File object itself cannot cross into wasm-gc.
// Cleared on every drop, because a handler acts on the drop it just received.
const droppedFiles = new Map();
let nextDroppedId = 1;

export function takeDroppedFile(id) {
  return droppedFiles.get(id);
}

// The `value` of a drop event: [{id, name, size, type, lastModified}, ...],
// or "" when the drop carried no files (an in-app drag).
export function registerDroppedFiles(ev) {
  const files = ev?.dataTransfer?.files;
  if (!files || !files.length) return "";
  droppedFiles.clear();
  const out = [];
  for (const f of files) {
    const id = nextDroppedId++;
    droppedFiles.set(id, f);
    out.push({ id, name: f.name, size: f.size, type: f.type, lastModified: f.lastModified });
  }
  return JSON.stringify(out);
}

export function createTdomImports(getExports) {
  const installed = new WeakMap(); // node -> Set<event name>
  return {
    node_type: (n) => n.nodeType | 0,
    has_prop: (o, k) => k in o,
    try_set_prop: (o, k, v) => { try { o[k] = v; return true; } catch { return false; } },
    json_parse: (s) => JSON.parse(s),
    json_stringify: (v) => { try { return JSON.stringify(v) ?? ""; } catch { return ""; } },
    // The LEAF of an allowlisted `e.` path, as JSON text, or "" for anything
    // that must not cross. A stricter test than "can this be stringified": an
    // Element stringifies to `{}` — its own enumerable properties, of which it
    // has none — so trusting JSON.stringify would answer an empty map for
    // `e.target` where the design says Null. The test is on the SHAPE.
    leaf_json: (o, k) => {
      const v = o?.[k];
      if (v === null || v === undefined) return "";
      const t = typeof v;
      if (t === "string" || t === "number" || t === "boolean") return JSON.stringify(v);
      if (t !== "object") return "";
      const p = Object.getPrototypeOf(v);
      if (!Array.isArray(v) && p !== Object.prototype && p !== null) return "";
      try { return JSON.stringify(v) ?? ""; } catch { return ""; }
    },
    dropped_files: (ev) => registerDroppedFiles(ev),
    file_meta: (t) => {
      const f = t.files && t.files[0];
      return f
        ? JSON.stringify({ name: f.name, size: f.size, type: f.type, lastModified: f.lastModified })
        : "";
    },
    get_int: (o, k) => o[k] | 0,
    get_bool: (o, k) => !!o[k],
    get_num: (o, k) => +(o[k] ?? 0),
    // delegated listener calling the wasm export; deduped so install() can
    // be re-run after a bundle load without double-dispatching
    add_listener: (node, name) => {
      let names = installed.get(node);
      if (!names) { names = new Set(); installed.set(node, names); }
      if (names.has(name)) return;
      names.add(name);
      node.addEventListener(name, (ev) => {
        const ex = getExports();
        if (ex && ex.on_event) ex.on_event(ev);
      });
    },
    inject_css: (doc, id, css) => {
      let el = doc.getElementById(id);
      if (!el) { el = doc.createElement("style"); el.id = id; doc.head.appendChild(el); }
      el.textContent = css;
    },
  };
}

// Fetch + instantiate a wasm-gc tutuca module. `makeExtra` (optional) receives
// a getExports thunk and returns extra import namespaces — `tcomp` and `tkv`
// from `tgc/host/loader.mjs`, or anything else a host links in — that
// need to call back into the instantiated module.
export async function instantiate(wasmUrl, makeExtra) {
  let exports = null;
  const getExports = () => exports;
  const imports = {
    jscore: createJsCoreImports(),
    tdom: createTdomImports(getExports),
    // MoonBit's println lowers to a `console.log` import on wasm-gc.
    console: { log: (...a) => console.log(...a) },
    ...(makeExtra ? makeExtra(getExports) : {}),
  };
  const opts = { builtins: ["js-string"], importedStringConstants: "_" };
  const source = fetch(wasmUrl);
  const { instance } = await WebAssembly.instantiateStreaming(source, imports, opts);
  exports = instance.exports;
  if (exports._start) exports._start();
  return exports;
}

// margaui compilation now happens in MoonBit: the host's mount() compiles the
// collected class set to CSS (marianoguerra/tailwindcss) and injects
// <style id="margaui-css">, and refresh_margaui() recompiles after a bundle
// loads. No page-side compile / CDN import remains.

