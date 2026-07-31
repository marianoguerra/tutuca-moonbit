// Shared browser-side loader library for the wasm-gc demos.
//
// Every wasm demo page ships a thin ./loader.mjs beside it that imports this
// file (also copied beside the page by the dist tasks — see dev/tasks.mbt).
// It provides:
//  - `jscore`: the import namespace mizchi/js core needs on wasm-gc
//  - `tdom`: typed DOM reads @core can't do on wasm-gc plus the event bridge
//    (deduped delegated listeners that call the exported `on_event`, since a
//    MoonBit closure can't cross into JS on wasm-gc)
//  - `tcomp`: the dynamic-component bridge for jco-transpiled
//    `tutuca:component` guests (URL loads and dropped .tutuca.tar.gz
//    archives; see dyncomp/host/wasm/glue.mbt for the conventions)
//  - `instantiate`: fetch + instantiate a wasm-gc module with those imports
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

// --- tkv: localStorage, as the four calls dyncomp/persist/wasm imports ---
//
// Every one of them swallows what the browser can throw: localStorage is
// absent in a sandboxed frame, throws on write in private mode, and throws
// again when the origin's quota is full. None of those are worth crashing a
// render over — a store that cannot store answers "nothing is there", which is
// the same shape as a first visit and is already a case every caller handles.
function createTkvImports() {
  const ls = () => {
    try {
      return globalThis.localStorage ?? null;
    } catch {
      return null;
    }
  };
  return {
    // "" for a missing key: wasm-gc strings are not nullable, and a stored
    // empty string is not a snapshot either way.
    get: (key) => {
      try {
        return ls()?.getItem(key) ?? '';
      } catch {
        return '';
      }
    },
    set: (key, value) => {
      try {
        ls()?.setItem(key, value);
      } catch {
        /* full, blocked, or absent — the write simply did not happen */
      }
    },
    remove: (key) => {
      try {
        ls()?.removeItem(key);
      } catch {
        /* nothing to remove if there is nowhere to remove it from */
      }
    },
    // One call rather than length + key(i) across the FFI: each hop copies a
    // string, and this is read once when a page starts.
    keys: (prefix) => {
      try {
        const store = ls();
        if (!store) return '[]';
        const out = [];
        for (let i = 0; i < store.length; i++) {
          const k = store.key(i);
          if (k !== null && k.startsWith(prefix)) out.push(k);
        }
        return JSON.stringify(out);
      } catch {
        return '[]';
      }
    },
  };
}

// Fetch + instantiate a demo wasm-gc module. `makeExtra` (optional) receives
// a getExports thunk and returns extra import namespaces (e.g. tcomp) that
// need to call back into the instantiated module.
export async function instantiate(wasmUrl, makeExtra) {
  let exports = null;
  const getExports = () => exports;
  const imports = {
    jscore: createJsCoreImports(),
    tdom: createTdomImports(getExports),
    tkv: createTkvImports(),
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

// --- single-file bundle unpacking (native, dependency-free) ---

async function gunzip(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

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

// --- tcomp: the dynamic-component bridge ---

// A guest's persisted bytes cross the wasm-gc FFI as base64 text, the same
// encoding they travel in inside a snapshot and inside a KV store. btoa/atob
// are byte-wise, which is why the Uint8Array is walked as latin-1 rather than
// decoded as UTF-8: these are bytes, not text, and the host never reads them.
function bytesToB64(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function b64ToBytes(b64) {
  if (!b64) return new Uint8Array(0);
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

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
  // a WIT path-step variant -> the shape glue.mbt's path_step reads
  const stepToJson = (s) =>
    s.tag === "field"
      ? { field: s.val }
      : s.tag === "item"
        ? { item: [s.val.field, s.val.key] }
        : { at: [s.val.field, Number(s.val.index)] };
  const optsToJson = (o) => ({
    onOk: o?.onOk ?? null,
    onError: o?.onError ?? null,
    onRes: o?.onRes ?? null,
    livePath: !!o?.livePath,
  });
  const controlImpl = {
    log: (level, msg) => console.log(`[guest ${level}]`, msg),
    emit: (name, args) => controlBuf.push({ kind: "emit", name, args: args.map(guestToJson) }),
    send: (name, args) => controlBuf.push({ kind: "send", name, args: args.map(guestToJson) }),
    sendAt: (path, name, args) => controlBuf.push({
      kind: "sendAt", path: path.map(stepToJson), name, args: args.map(guestToJson),
    }),
    bubbleAt: (path, name, args) => controlBuf.push({
      kind: "bubbleAt", path: path.map(stepToJson), name, args: args.map(guestToJson),
    }),
    stopPropagation: () => controlBuf.push({ kind: "stopPropagation" }),
    request: (name, args, opts) => controlBuf.push({
      kind: "request", name, args: args.map(guestToJson), opts: optsToJson(opts),
    }),
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
    // Declared in the contract, not yet implemented: it needs a timer the
    // transactor owns, so that a delayed message arrives through the same
    // dispatch path as every other one. Present and LOUD rather than absent:
    // an absent import makes jco throw something about a missing function,
    // which says nothing about why. See dyncomp/DESIGN.md "Still open".
    after: (delayMs, name) => {
      console.warn(
        `[guest] control.after("${name}", ${delayMs}ms) ignored: ` +
        "the host has no timer yet",
      );
    },
  };
  // The three ambient facts a guest cannot compute for itself. Each answer is
  // deliberately WEAKER than the platform's own:
  //
  //  - `nowMs` is coarsened to 1s and frozen for the duration of one tcomp
  //    call, so every read inside one handler agrees. That is what lets a
  //    dispatch replay, and it is why a guest cannot build a fine-grained
  //    timer — and therefore a timing side channel — out of it.
  //  - `randomU64` is a seeded xorshift, not `crypto.getRandomValues`: a
  //    session that records its seed replays exactly. A guest that needs
  //    unpredictability an attacker cannot reproduce asks the host instead.
  //  - `newId` is monotonic per bundle, for keying a list — not for naming
  //    anything outside the page.
  //
  // The host decides whether a bundle gets any of this (manifest
  // `capabilities`); until it grants, these are simply not reached, because
  // jco elides an import the guest never calls.
  let frozenNow = 0;
  let rngState = 0x9e3779b97f4a7c15n;
  let idCounter = 0;
  const freezeClock = () => {
    frozenNow = Math.floor(Date.now() / 1000) * 1000;
  };
  const envImpl = {
    nowMs: () => BigInt(frozenNow || Math.floor(Date.now() / 1000) * 1000),
    tzOffsetMin: () => -new Date().getTimezoneOffset(),
    locale: () => globalThis.navigator?.language ?? "en",
    randomU64: () => {
      // xorshift64*, masked to 64 bits — deterministic given the seed
      rngState ^= rngState >> 12n;
      rngState ^= (rngState << 25n) & 0xffffffffffffffffn;
      rngState ^= rngState >> 27n;
      return (rngState * 0x2545f4914f6cdd1dn) & 0xffffffffffffffffn;
    },
    newId: () => `id-${++idCounter}`,
  };
  const guestImports = {
    // jco 1.25 resolves unversioned keys at runtime; provide both spellings
    // (the versioned one tracks the WIT package version)
    "tutuca:component/values": valuesImpl,
    "tutuca:component/values@0.4.0": valuesImpl,
    "tutuca:component/control": controlImpl,
    "tutuca:component/control@0.4.0": controlImpl,
    "tutuca:component/env": envImpl,
    "tutuca:component/env@0.4.0": envImpl,
  };
  // NOTE: guest constructors invoked from control.makeInstance re-enter the
  // guest while a tcomp call is active; the arena is shared and only cleared
  // at tcomp-call boundaries, so nested construction is safe.

  // A handle this table does not have is a HOST bookkeeping slip — something
  // is holding an instance of a bundle that was retired, or one the superseded
  // sweep already collected. It says so and answers with nothing: the wrong
  // answer to one call is recoverable, and an exception thrown mid-render is
  // not.
  const instOf = (bundle, handle) => {
    currentBundle = bundle;
    freezeClock();
    const inst = bundles.get(bundle)?.instances.get(handle)?.inst;
    if (!inst) {
      const live = bundles.get(bundle);
      console.warn(
        `tutuca dyncomp: no live instance ${handle} in bundle ${bundle}`,
        live ? [...live.instances.keys()] : 'no such bundle',
      );
    }
    return inst;
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
        // the bundle's views registered new margaui utility classes; the host
        // recompiles + reinjects <style id="margaui-css"> in MoonBit so guest
        // styling (e.g. the counter/todo cards) applies
        getExports().refresh_margaui?.();
      } finally {
        URL.revokeObjectURL(url);
      }
    })().catch((e) => {
      console.error("universal load failed:", e);
      getExports().dyncomp_on_load_error(loadId, String(e));
    });
  };

  return {
    // A bundle is a `.tutuca.tar.gz` archive, and there are two ways to name
    // one: the id of a file the user dropped, or a URL to fetch it from. Both
    // end in the same unpack-and-instantiate path.
    load_dropped: (fileId, loadId) => {
      const file = takeDroppedFile(fileId);
      if (!file) {
        getExports().dyncomp_on_load_error(loadId, `no dropped file #${fileId}`);
        return;
      }
      loadArchive(file, loadId);
    },
    load_url: (url, loadId) => {
      (async () => {
        const res = await fetch(new URL(url, document.baseURI));
        if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
        loadArchive(await res.blob(), loadId);
      })().catch((e) => {
        console.error("dyncomp load failed:", e);
        getExports().dyncomp_on_load_error(loadId, String(e));
      });
    },
    create: (bundle, component, argsJson) => {
      currentBundle = bundle;
      freezeClock();
      const b = bundles.get(bundle);
      const args = Object.entries(JSON.parse(argsJson)).map(([k, v]) => [k, jsonToGuest(v)]);
      const h = register(bundle, new b.guest.Instance(component, args), component);
      drainChildren();
      arena.clear();
      return h;
    },
    get_field: (bundle, handle, name) => {
      const inst = instOf(bundle, handle);
      if (!inst) return '';
      const v = inst.getField(name);
      drainChildren();
      const out = v === undefined ? "" : JSON.stringify(guestToJson(v));
      arena.clear();
      return out;
    },
    seq_entries: (bundle, handle) => {
      const entries = instOf(bundle, handle)?.seqEntries();
      const out = entries === undefined
        ? ""
        : JSON.stringify(entries.map(([k, v]) => [k, guestToJson(v)]));
      arena.clear();
      return out;
    },
    dispatch: (bundle, handle, bucketInt, name, argsJson) => {
      const bucket = ["input", "receive", "response", "bubble"][bucketInt] ?? "input";
      controlBuf = [];
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const inst = instOf(bundle, handle);
      if (!inst) return JSON.stringify({ next: null, msgs: [] });
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const next = inst.handleEvent(bucket, name, args);
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
      const inst = instOf(bundle, handle);
      if (!inst) return '';
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const v = inst.callMethod(name, args);
      drainChildren();
      const out = JSON.stringify(guestToJson(v));
      arena.clear();
      return out;
    },
    // a request the BUNDLE serves; module-scoped, so no instance handle
    handle_request: (bundle, name, argsJson) => {
      currentBundle = bundle;
      freezeClock();
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const res = bundles.get(bundle).guest.handleRequest(name, args);
      drainChildren();
      const out = JSON.stringify(
        res.tag === "ok" ? { ok: guestToJson(res.val) } : { err: guestToJson(res.val) },
      );
      arena.clear();
      return out;
    },
    with_field: (bundle, handle, name, valueJson) => {
      const inst = instOf(bundle, handle);
      if (!inst) return -1;
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const v = jsonToGuest(JSON.parse(valueJson));
      const next = inst.withField(name, v);
      drainChildren();
      arena.clear();
      return next === undefined ? -1 : register(bundle, next, comp);
    },
    // The guest's own bytes, base64 on the way across: the wasm-gc FFI here
    // speaks strings, and base64 is already what a snapshot uses to sit in
    // JSON and in a KV store. "" is the guest saying it does not persist.
    persist: (bundle, handle) => {
      const bytes = instOf(bundle, handle)?.persist();
      arena.clear();
      return bytes && bytes.length ? bytesToB64(bytes) : "";
    },
    // The inverse, and the one call that makes an instance out of nothing but
    // stored bytes. -1 is the guest REFUSING them, which the host reads as
    // "rebuild from the declared fields instead".
    restore: (bundle, component, stateB64) => {
      const b = bundles.get(bundle);
      if (!b) return -1;
      currentBundle = bundle;
      freezeClock();
      const inst = b.guest.Instance.restore(component, b64ToBytes(stateB64));
      drainChildren();
      arena.clear();
      return inst === undefined ? -1 : register(bundle, inst, component);
    },
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
