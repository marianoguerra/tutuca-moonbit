// Browser loader for the UNIVERSAL wasm-component demo (drag-and-drop).
//
// A superset of the dyncomp loader (same `jscore` + `tdom` + `tcomp`
// namespaces and value bridge). What's added here:
//  - loadArchive(file, loadId): unpack a dropped single-file bundle
//    (`.tutuca.tar.gz` = gzip of a tar of a guest's jco output) with the
//    native DecompressionStream + a tiny tar reader, instantiate the
//    `tutuca:component` guest from the in-memory bytes (no network fetch of
//    core wasm), register the bundle, and call the wasm host's exported
//    dyncomp_on_loaded — the same completion path a URL load uses.
//  - loadWasm wires document-level dragover/drop to loadArchive; the wasm
//    host's UniversalWasm shell (mounted at root) receives "dyncompLoaded"
//    and mounts every component the manifest declares.
// See dyncomp/host/wasm/glue.mbt for the tcomp/value conventions.

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

export function createTdomImports(getExports) {
  const installed = new WeakMap(); // node -> Set<event name>
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

// --- tcomp: the dynamic-component bridge ---

export function createTcompImports(getExports) {
  const bundles = new Map(); // id -> { guest, instances: Map<int, {inst, comp}>, next }
  let nextBundle = 1;
  let currentBundle = 0; // the bundle a tcomp call is executing against

  // JS-side arena for compound guest values; entries live for one tcomp call
  const arena = new Map();
  let nextArena = 1n;
  const put = (v) => { const h = nextArena++; arena.set(h, v); return h; };

  // control messages a guest buffers during one dispatch
  let controlBuf = [];
  // children whose construction was requested mid-call (see makeInstance)
  let pendingChildren = [];
  const drainChildren = () => {
    while (pendingChildren.length) {
      const { bundle, handle, component, args } = pendingChildren.shift();
      const b = bundles.get(bundle);
      b.instances.get(handle).inst = new b.guest.Instance(component, args);
    }
  };

  // plain JSON <-> guest-facing tagged values ({tag, val}, compounds in arena)
  const jsonToGuest = (j) => {
    if (j === null || j === undefined) return { tag: "nil" };
    if (typeof j === "boolean") return { tag: "boolean", val: j };
    if (typeof j === "number") return { tag: "number", val: j };
    if (typeof j === "string") return { tag: "text", val: j };
    if (Array.isArray(j)) return { tag: "list", val: put(j.map(jsonToGuest)) };
    if (j.$dyn && typeof j.$dyn.handle === "number")
      return { tag: "instance", val: BigInt(j.$dyn.handle) };
    return { tag: "map", val: put(new Map(Object.entries(j).map(([k, v]) => [k, jsonToGuest(v)]))) };
  };
  const guestToJson = (v) => {
    if (!v || v.tag === "nil") return null;
    switch (v.tag) {
      case "boolean": case "number": case "text": return v.val;
      case "list": return (arena.get(v.val) ?? []).map(guestToJson);
      case "map": {
        const out = {};
        for (const [k, x] of arena.get(v.val) ?? new Map()) out[k] = guestToJson(x);
        return out;
      }
      case "instance": {
        // nested-child token -> marker the host wraps as a DynObj
        const h = Number(v.val);
        const entry = bundles.get(currentBundle)?.instances.get(h);
        return entry ? { $dyn: { handle: h, comp: entry.comp } } : null;
      }
      default: return null;
    }
  };

  // the guests' imported interfaces (shared across bundles)
  const valuesImpl = {
    listLen: (h) => (arena.get(h) ?? []).length >>> 0,
    listGet: (h, i) => (arena.get(h) ?? [])[i] ?? { tag: "nil" },
    mapLen: (h) => (arena.get(h) ?? new Map()).size >>> 0,
    mapKeys: (h) => [...(arena.get(h) ?? new Map()).keys()],
    mapGet: (h, k) => (arena.get(h) ?? new Map()).get(k),
    listNew: () => put([]),
    listPush: (h, v) => { (arena.get(h) ?? []).push(v); },
    mapNew: () => put(new Map()),
    mapSet: (h, k, v) => { (arena.get(h) ?? new Map()).set(k, v); },
    toJson: (v) => JSON.stringify(guestToJson(v)),
    fromJson: (j) => { try { return jsonToGuest(JSON.parse(j)); } catch { return { tag: "nil" }; } },
  };
  const controlImpl = {
    log: (level, msg) => console.log(`[guest ${level}]`, msg),
    emit: (name, args) => controlBuf.push({ kind: "emit", name, args: args.map(guestToJson) }),
    send: (name, args) => controlBuf.push({ kind: "send", name, args: args.map(guestToJson) }),
    request: (name, args) => controlBuf.push({ kind: "request", name, args: args.map(guestToJson) }),
    // same-bundle child factory: the returned token is the bridge handle,
    // the ONLY instance-token space. The Component Model forbids re-entering
    // a component while a call into it is active, so the token is reserved
    // NOW and the child is constructed after the current guest call returns
    // (drainChildren, before the arena clears so captured args stay valid).
    makeInstance: (component, args) => {
      const b = bundles.get(currentBundle);
      const h = b.next++;
      b.instances.set(h, { inst: null, comp: component });
      pendingChildren.push({ bundle: currentBundle, handle: h, component, args });
      return BigInt(h);
    },
    dropInstance: (token) => {
      bundles.get(currentBundle)?.instances.delete(Number(token));
    },
  };
  const guestImports = {
    // jco 1.25 resolves unversioned keys at runtime; provide both spellings
    "tutuca:component/values": valuesImpl,
    "tutuca:component/values@0.1.0": valuesImpl,
    "tutuca:component/control": controlImpl,
    "tutuca:component/control@0.1.0": controlImpl,
  };
  // NOTE: guest constructors invoked from control.makeInstance re-enter the
  // guest while a tcomp call is active; the arena is shared and only cleared
  // at tcomp-call boundaries, so nested construction is safe.

  const instOf = (bundle, handle) => {
    currentBundle = bundle;
    const b = bundles.get(bundle);
    return b && b.instances.get(handle)?.inst;
  };
  const register = (bundle, inst, comp) => {
    const b = bundles.get(bundle);
    const h = b.next++;
    b.instances.set(h, { inst, comp });
    return h;
  };
  globalThis.__tcomp_stats = () => ({
    bundles: bundles.size,
    instances: [...bundles.values()].map((b) => b.instances.size),
  });

  // Instantiate an imported jco ESM against a core-module resolver, register
  // the bundle, and hand its manifest to the wasm host. Shared by the URL
  // loader (`load`) and the dropped-archive loader (`loadArchive`); only the
  // ESM source and the getCoreModule resolver differ between them.
  const finishLoad = async (mod, getCoreModule, loadId) => {
    const root = await mod.instantiate(getCoreModule, guestImports);
    const id = nextBundle++;
    bundles.set(id, { guest: root.guest, instances: new Map(), next: 1 });
    const manifest = JSON.stringify(root.guest.getManifest());
    getExports().dyncomp_on_loaded(loadId, id, manifest);
  };

  // Load a dropped single-file bundle: gunzip (native DecompressionStream) ->
  // untar -> import the *.component.js entry from a blob URL -> instantiate,
  // resolving each core module from the in-memory tar bytes. loadId is any
  // value not tracked in the host's notify_paths, so completion notifies the
  // root shell (see @dhw.notify).
  const loadArchive = (file, loadId) => {
    (async () => {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const files = untar(await gunzip(bytes));
      const entryName = Object.keys(files).find((n) => n.endsWith(".component.js"));
      if (!entryName) throw new Error("no *.component.js entry in archive");
      const blob = new Blob([files[entryName]], { type: "text/javascript" });
      const url = URL.createObjectURL(blob);
      try {
        const mod = await import(url);
        const getCoreModule = (path) => {
          const base = String(path).split("/").pop();
          const wasm = files[base];
          if (!wasm) throw new Error(`missing core module in archive: ${base}`);
          return WebAssembly.compile(wasm);
        };
        await finishLoad(mod, getCoreModule, loadId);
        // the bundle's views registered new margaui utility classes; re-publish
        // and recompile so guest styling (e.g. the counter/todo cards) applies
        getExports().refresh_classes?.();
        await applyMargaui(true);
      } finally {
        URL.revokeObjectURL(url);
      }
    })().catch((e) => {
      console.error("universal load failed:", e);
      getExports().dyncomp_on_load_error(loadId, String(e));
    });
  };

  return {
    loadArchive,
    load: (loadId, url) => {
      (async () => {
        const abs = new URL(url, document.baseURI);
        const mod = await import(abs);
        const getCoreModule = (path) =>
          WebAssembly.compileStreaming(fetch(new URL(path, abs)));
        await finishLoad(mod, getCoreModule, loadId);
      })().catch((e) => {
        console.error("dyncomp load failed:", e);
        getExports().dyncomp_on_load_error(loadId, String(e));
      });
    },
    create: (bundle, component, argsJson) => {
      currentBundle = bundle;
      const b = bundles.get(bundle);
      const args = Object.entries(JSON.parse(argsJson)).map(([k, v]) => [k, jsonToGuest(v)]);
      const h = register(bundle, new b.guest.Instance(component, args), component);
      drainChildren();
      arena.clear();
      return h;
    },
    get_field: (bundle, handle, name) => {
      const v = instOf(bundle, handle).getField(name);
      drainChildren();
      const out = v === undefined ? "" : JSON.stringify(guestToJson(v));
      arena.clear();
      return out;
    },
    seq_entries: (bundle, handle) => {
      const entries = instOf(bundle, handle).seqEntries();
      const out = entries === undefined
        ? ""
        : JSON.stringify(entries.map(([k, v]) => [k, guestToJson(v)]));
      arena.clear();
      return out;
    },
    dispatch: (bundle, handle, bucketInt, name, argsJson) => {
      const bucket = ["input", "receive", "response"][bucketInt] ?? "input";
      controlBuf = [];
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const inst = instOf(bundle, handle);
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const next = inst.handleEvent(bucket, name, undefined, args);
      drainChildren();
      const out = JSON.stringify({
        next: next === undefined ? null : register(bundle, next, comp),
        msgs: controlBuf,
      });
      arena.clear();
      controlBuf = [];
      return out;
    },
    call_method: (bundle, handle, name, argsJson) => {
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const v = instOf(bundle, handle).callMethod(name, args);
      drainChildren();
      const out = JSON.stringify(guestToJson(v));
      arena.clear();
      return out;
    },
    with_field: (bundle, handle, name, valueJson) => {
      const inst = instOf(bundle, handle);
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const v = jsonToGuest(JSON.parse(valueJson));
      const next = inst.withField(name, v);
      drainChildren();
      arena.clear();
      return next === undefined ? -1 : register(bundle, next, comp);
    },
    to_json: (bundle, handle) => instOf(bundle, handle).toJson(),
    drop_instance: (bundle, handle) => {
      const b = bundles.get(bundle);
      if (b) {
        b.instances.get(handle)?.inst?.[Symbol.dispose]?.();
        b.instances.delete(handle);
      }
    },
    drop_bundle: (bundle) => { bundles.delete(bundle); },
  };
}

// Compile the margaui class set the wasm module published on globalThis
// (__tutuca_classes) into CSS and inject it (used by the storybook page,
// which shares this loader for its tcomp imports).
export async function applyMargaui(force = false) {
  const classes = globalThis.__tutuca_classes ?? [];
  const existing = document.getElementById("margaui-css");
  // first call: skip if nothing to do or already compiled. force=true (after a
  // bundle loads) recompiles the now-larger class set, replacing the style.
  if (!classes.length || (existing && !force)) return;
  try {
    const { compile } = await import("https://cdn.jsdelivr.net/npm/margaui/+esm");
    const css = await compile(classes);
    const style = existing ?? document.createElement("style");
    style.id = "margaui-css";
    style.textContent = css;
    if (!existing) document.head.appendChild(style);
  } catch (err) {
    console.warn("margaui compile skipped:", err);
  }
}

// --- single-file bundle unpacking (native, dependency-free) ---

// Gunzip with the browser-native DecompressionStream (Chrome 80+, which the
// JS String Builtins host already requires) — no zip/gzip library.
async function gunzip(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

// Minimal tar reader for the archive scripts/pack-bundle.mjs writes: regular
// files only, sizes octal at offset 124, data padded to 512-byte blocks.
// Keys are basenames (matching getCoreModule's path.split('/').pop()).
function untar(bytes) {
  const files = {};
  const td = new TextDecoder();
  const octal = (buf) => parseInt(td.decode(buf).replace(/[\0 ]+$/g, "").trim() || "0", 8) | 0;
  let off = 0;
  while (off + 512 <= bytes.length) {
    const header = bytes.subarray(off, off + 512);
    if (header.every((b) => b === 0)) break; // end-of-archive zero block(s)
    const name = td.decode(header.subarray(0, 100)).replace(/\0.*$/s, "");
    const size = octal(header.subarray(124, 136));
    const typeflag = header[156]; // '0' (0x30) or NUL = regular file
    const dataStart = off + 512;
    if (name && (typeflag === 0x30 || typeflag === 0)) {
      const base = name.replace(/^\.\//, "").split("/").pop();
      files[base] = bytes.subarray(dataStart, dataStart + size);
    }
    off = dataStart + Math.ceil(size / 512) * 512;
  }
  return files;
}

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
  let exports = null;
  const tcomp = createTcompImports(() => exports);
  const imports = {
    jscore: createJsCoreImports(),
    tdom: createTdomImports(() => exports),
    tcomp,
    console: { log: (...a) => console.log(...a) },
  };
  const opts = { builtins: ["js-string"], importedStringConstants: "_" };
  const source = fetch(wasmUrl);
  const { instance } = await WebAssembly.instantiateStreaming(source, imports, opts);
  exports = instance.exports;
  if (exports._start) exports._start();
  installDropZone(tcomp);
  return exports;
}
