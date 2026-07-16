// Browser loader for the wasm-gc counter demo.
//
// Provides the `jscore` import namespace that mizchi/js's @core.Any operations
// call on the wasm-gc backend, plus a `tdom` namespace for the typed reads and
// the event bridge the tutuca adapter needs (things @core can't express on
// wasm-gc: reading Int/Bool out of a JS value, and — because MoonBit closures
// can't cross into JS — registering a listener that calls a wasm export back).
//
// Instantiation uses the JS String Builtins proposal (`builtins: ["js-string"]`
// + imported string constants under module "_"), which moon emits for
// `use-js-builtin-string: true`.

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

// `tdom`: the typed reads @core can't do on wasm-gc plus the event bridge.
// `getExports` yields the instantiated module's exports (set after
// instantiation) so a delegated DOM listener can call the wasm `on_event`.
export function createTdomImports(getExports) {
  return {
    node_type: (n) => n.nodeType | 0,
    has_prop: (o, k) => k in o,
    try_set_prop: (o, k, v) => { try { o[k] = v; return true; } catch { return false; } },
    json_parse: (s) => JSON.parse(s),
    json_stringify: (v) => { try { return JSON.stringify(v) ?? ""; } catch { return ""; } },
    file_meta: (t) => {
      const f = t.files && t.files[0];
      return f
        ? JSON.stringify({ name: f.name, size: f.size, type: f.type, lastModified: f.lastModified })
        : "";
    },
    get_int: (o, k) => o[k] | 0,
    get_bool: (o, k) => !!o[k],
    get_num: (o, k) => +(o[k] ?? 0),
    // register a delegated listener that calls the wasm export on each event
    add_listener: (node, name) => {
      node.addEventListener(name, (ev) => {
        const ex = getExports();
        if (ex && ex.on_event) ex.on_event(ev);
      });
    },
    // css injection (App.install_styles)
    inject_css: (doc, id, css) => {
      let el = doc.getElementById(id);
      if (!el) { el = doc.createElement("style"); el.id = id; doc.head.appendChild(el); }
      el.textContent = css;
    },
  };
}

// Compile the margaui class set the wasm module published on globalThis
// (__tutuca_classes) into CSS and inject it. Call this AFTER mount(): the
// page's own inline margaui script races the wasm module's top-level await and
// would see an empty set, so the examples-wasm page drives it from here instead.
export async function applyMargaui() {
  const classes = globalThis.__tutuca_classes ?? [];
  if (!classes.length || document.getElementById("margaui-css")) return;
  try {
    const { compile } = await import("https://cdn.jsdelivr.net/npm/margaui/+esm");
    const css = await compile(classes);
    const style = document.createElement("style");
    style.id = "margaui-css";
    style.textContent = css;
    document.head.appendChild(style);
  } catch (err) {
    console.warn("margaui compile skipped:", err);
  }
}

export async function loadWasm(wasmUrl) {
  let exports = null;
  const imports = {
    jscore: createJsCoreImports(),
    tdom: createTdomImports(() => exports),
    // MoonBit's println lowers to a `console.log` import on wasm-gc.
    console: { log: (...a) => console.log(...a) },
  };
  const opts = { builtins: ["js-string"], importedStringConstants: "_" };
  const source = fetch(wasmUrl);
  const { instance } = await WebAssembly.instantiateStreaming(source, imports, opts);
  exports = instance.exports;
  if (exports._start) exports._start();
  return exports;
}
