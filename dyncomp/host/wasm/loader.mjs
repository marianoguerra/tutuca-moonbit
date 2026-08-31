// Browser-side bridge for dynamic wasm components: the two import namespaces
// this package and `dyncomp/persist/wasm` declare, and the unpacker that turns
// a dropped `.tutuca.tar.gz` into the modules behind them.
//
//  - `tcomp`: the `tutuca:component` bridge — bundle registry, the JS-side
//             arena for compound guest values, the control buffer, and the
//             pending-children protocol. It implements the conventions in
//             ./glue.mbt; the two are one contract in two languages.
//  - `tkv`:   localStorage, as the four calls `dyncomp/persist/wasm` imports.
//
// Both are linked through `instantiate`'s `makeExtra` hook rather than being
// built into it (`app/wasm/loader.mjs`), so a page that never loads a bundle
// carries none of this — which is most pages.
//
// Usage from a host page's loader:
//
//   import { instantiate } from "./app-loader.mjs";
//   import { createTcompImports, createTkvImports } from "./dyncomp-loader.mjs";
//
//   export async function loadWasm(wasmUrl) {
//     return await instantiate(wasmUrl, (getExports) => ({
//       tcomp: createTcompImports(getExports),
//       tkv: createTkvImports(),
//     }));
//   }
import { takeDroppedFile } from "../../../app/wasm/loader.mjs";

// --- tkv: localStorage, as the four calls dyncomp/persist/wasm imports ---
//
// Every one of them swallows what the browser can throw: localStorage is
// absent in a sandboxed frame, throws on write in private mode, and throws
// again when the origin's quota is full. None of those are worth crashing a
// render over — a store that cannot store answers "nothing is there", which is
// the same shape as a first visit and is already a case every caller handles.
export function createTkvImports() {
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

// --- archives a page already holds ---

// A bundle the page BUILT rather than fetched: bytes that are already in this
// process, named by an int so MoonBit can ask for them. The same shape a drop
// uses (`app/wasm/loader.mjs`'s `takeDroppedFile`), for the same reason — a
// Uint8Array cannot cross into wasm-gc — and the alternative is worse than it
// looks: without this a page has to `URL.createObjectURL` bytes it is holding,
// carry the URL through wasm and back, `fetch` a blob that never left the
// process, and then revoke the URL in the one window that is neither too early
// (racing the load) nor too late (never).
//
// Consumed individually rather than cleared like `droppedFiles`, because these
// are not "the files of the last drop": each one is a load somebody asked for.
const heldArchives = new Map();
let nextArchive = 1;

/**
 * Hold `.tutuca.tar.gz` bytes for one load and answer the id that names them.
 *
 * Pass the id to `@dhw.load_bytes(path, id)` on the MoonBit side. The entry is
 * consumed by that load — an id loads once, and an id nobody loads is a leak
 * the page owns, so register at the point you are about to load.
 */
export function registerArchive(bytes) {
  const id = nextArchive++;
  heldArchives.set(id, bytes);
  return id;
}

// --- single-file bundle unpacking (native, dependency-free) ---

// These bounds apply BEFORE the manifest's structural quotas. A manifest
// cannot protect the work needed to reach it: the archive has already been
// downloaded, decompressed and walked by then. Deliberately generous relative
// to the shipped bundles, but finite so a dropped gzip/tar is not a tab-sized
// allocation or an unbounded parser loop.
export const ARCHIVE_LIMITS = Object.freeze({
  compressedBytes: 16 * 1024 * 1024,
  expandedBytes: 64 * 1024 * 1024,
  entryBytes: 32 * 1024 * 1024,
  files: 8192,
});

export async function gunzip(bytes, limits = ARCHIVE_LIMITS) {
  if (bytes.byteLength > limits.compressedBytes) {
    throw new Error(
      `bundle archive is too large: ${bytes.byteLength} compressed bytes ` +
      `(the limit is ${limits.compressedBytes})`,
    );
  }
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limits.expandedBytes) {
        await reader.cancel("expanded archive limit exceeded");
        throw new Error(
          `bundle archive expands past ${limits.expandedBytes} bytes`,
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.byteLength;
  }
  return out;
}

export async function readCompressedResponse(response, limits = ARCHIVE_LIMITS) {
  const advertised = Number(response.headers.get("content-length"));
  if (Number.isFinite(advertised) && advertised > limits.compressedBytes) {
    throw new Error(
      `bundle archive is too large: ${advertised} compressed bytes ` +
      `(the limit is ${limits.compressedBytes})`,
    );
  }
  if (!response.body) {
    throw new Error("bundle response has no readable body");
  }
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limits.compressedBytes) {
        await reader.cancel("compressed archive limit exceeded");
        throw new Error(
          `bundle archive exceeds ${limits.compressedBytes} compressed bytes`,
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    out.set(chunk, at);
    at += chunk.byteLength;
  }
  return out;
}

function tarNumber(header, start, end, field) {
  const raw = new TextDecoder()
    .decode(header.subarray(start, end))
    .replace(/[\0 ]+$/g, "")
    .trim();
  if (!/^[0-7]+$/.test(raw)) {
    throw new Error(`invalid tar ${field}: expected octal digits`);
  }
  const value = Number.parseInt(raw, 8);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`invalid tar ${field}: out of range`);
  }
  return value;
}

function checkTarHeader(header) {
  const expected = tarNumber(header, 148, 156, "checksum");
  let actual = 0;
  for (let i = 0; i < header.length; i++) {
    actual += i >= 148 && i < 156 ? 0x20 : header[i];
  }
  if (actual !== expected) {
    throw new Error(`invalid tar header checksum: got ${expected}, expected ${actual}`);
  }
}

export function untar(bytes, limits = ARCHIVE_LIMITS) {
  if (bytes.byteLength > limits.expandedBytes) {
    throw new Error(
      `bundle archive is too large: ${bytes.byteLength} expanded bytes ` +
      `(the limit is ${limits.expandedBytes})`,
    );
  }
  const files = Object.create(null);
  const td = new TextDecoder();
  let off = 0;
  let fileCount = 0;
  let payloadBytes = 0;
  while (off + 512 <= bytes.length) {
    const header = bytes.subarray(off, off + 512);
    if (header.every((b) => b === 0)) break; // end-of-archive zero block(s)
    checkTarHeader(header);
    const name = td.decode(header.subarray(0, 100)).replace(/\0.*$/s, "");
    const size = tarNumber(header, 124, 136, "size");
    const typeflag = header[156]; // '0' (0x30) or NUL = regular file
    const dataStart = off + 512;
    const dataEnd = dataStart + size;
    const next = dataStart + Math.ceil(size / 512) * 512;
    if (dataEnd > bytes.length || next > bytes.length || next <= off) {
      throw new Error(`truncated or non-advancing tar entry: ${name || "<unnamed>"}`);
    }
    if (typeflag !== 0x30 && typeflag !== 0) {
      throw new Error(`unsupported tar entry type ${typeflag}: ${name || "<unnamed>"}`);
    }
    if (!name) throw new Error("tar archive contains an unnamed file");
    if (size > limits.entryBytes) {
      throw new Error(
        `tar entry is too large: ${name} has ${size} bytes ` +
        `(the limit is ${limits.entryBytes})`,
      );
    }
    fileCount += 1;
    payloadBytes += size;
    if (fileCount > limits.files) {
      throw new Error(`tar archive has too many files (the limit is ${limits.files})`);
    }
    if (payloadBytes > limits.expandedBytes) {
      throw new Error(`tar payloads exceed ${limits.expandedBytes} bytes`);
    }
    const base = name.replace(/^\.\//, "").split("/").pop();
    if (!base || Object.hasOwn(files, base)) {
      throw new Error(`duplicate or ambiguous tar basename: ${base || name}`);
    }
    files[base] = bytes.subarray(dataStart, dataEnd);
    off = next;
  }
  return files;
}

export function requireDescriptor(files) {
  const descriptor = files["tutuca.json"];
  if (!descriptor) {
    throw new Error(
      "archive has no tutuca.json descriptor; legacy JavaScript bundles are not supported",
    );
  }
  return descriptor;
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
  // Which guest entry point is active. Public property access is a pure,
  // synchronous transition even for a hand-written guest, so the bridge — not
  // merely tutuca's source checker — refuses control effects from it.
  let callPhase = "idle";
  const inPhase = (phase, fn) => {
    const previous = callPhase;
    callPhase = phase;
    try { return fn(); } finally { callPhase = previous; }
  };
  const requirePhase = (name, ...allowed) => {
    if (!allowed.includes(callPhase)) {
      throw new Error(`control.${name} is not available during ${callPhase}`);
    }
  };

  // JS-side arena for compound guest values; entries live for one tcomp call
  const arena = new Map();
  let nextArena = 1n;
  const put = (v) => { const h = nextArena++; arena.set(h, v); return h; };

  // control messages a guest buffers during one dispatch
  let controlBuf = [];
  const bufferControl = (name, message) => {
    requirePhase(name, "dispatch");
    controlBuf.push(message);
  };
  // The host's answers to the dispatching component's declared lookups, valid
  // for the duration of one dispatch. Empty outside one.
  let bindings = {};
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
  // WIT `intent-opts`. `route` is a list of the `leg` enum, which jco lowers to
  // the case names; an empty one means "the default", which the HOST supplies
  // so a guest that says nothing cannot disagree with it.
  const optsToJson = (o) => ({
    route: (o?.route ?? []).map((leg) => (typeof leg === "string" ? leg : leg?.tag)),
    onOk: o?.onOk ?? null,
    onError: o?.onError ?? null,
    onUnhandled: o?.onUnhandled ?? null,
    livePath: !!o?.livePath,
  });
  const controlImpl = {
    log: (level, msg) => console.log(`[guest ${level}]`, msg),
    send: (name, args) => bufferControl("send", { kind: "send", name, args: args.map(guestToJson) }),
    sendAt: (path, name, args) => bufferControl("send-at", {
      kind: "sendAt", path: path.map(stepToJson), name, args: args.map(guestToJson),
    }),
    intent: (name, args, opts) => bufferControl("intent", {
      kind: "intent", name, args: args.map(guestToJson), opts: optsToJson(opts),
    }),
    intentAt: (path, name, args, opts) => bufferControl("intent-at", {
      kind: "intentAt", path: path.map(stepToJson), name,
      args: args.map(guestToJson), opts: optsToJson(opts),
    }),
    // Empty `args` means "the ones that arrived" and an empty `route` means
    // "the one the walk is already on"; both are decided host-side, so both
    // cross as they came.
    forward: (args, opts) => bufferControl("forward", {
      kind: "forward", args: args.map(guestToJson), opts: optsToJson(opts),
    }),
    reply: (v) => bufferControl("reply", { kind: "reply", value: guestToJson(v) }),
    fail: (e) => bufferControl("fail", { kind: "fail", value: guestToJson(e) }),
    stopPropagation: () => bufferControl("stop-propagation", { kind: "stopPropagation" }),
    // A reply names itself, so it carries a name the way a `send` does.
    sendReply: (name, args) => bufferControl("send-reply", {
      kind: "sendReply", name, args: args.map(guestToJson),
    }),
    // The one import that ANSWERS rather than buffering. `bindings` is what
    // the host resolved this component's declared lookups to before entering
    // the guest — see the WIT: everything else here is an effect applied
    // afterwards, and a value a handler is using cannot wait for that.
    //
    // Both entry-point families fill it: handlers from the dispatch position,
    // render operations from the render one. A value body that reads `*name` goes
    // through the second, and read nil until it did.
    lookup: (name) =>
      Object.hasOwn(bindings, name)
        ? jsonToGuest(bindings[name])
        : { tag: "nil" },
    // same-bundle child factory: the returned token is the bridge handle,
    // the ONLY instance-token space. The Component Model forbids re-entering
    // a component while a call into it is active, so the token is reserved
    // NOW and the child is constructed after the current guest call returns
    // (drainChildren, before the arena clears so captured args stay valid).
    makeInstance: (component, args) => {
      requirePhase("make-instance", "construct", "dispatch");
      const b = bundles.get(currentBundle);
      const h = b.next++;
      b.instances.set(h, { inst: null, comp: component });
      pendingChildren.push({ bundle: currentBundle, handle: h, component, args });
      return BigInt(h);
    },
    dropInstance: (token) => {
      requirePhase("drop-instance", "construct", "dispatch");
      bundles.get(currentBundle)?.instances.delete(Number(token));
    },
  };
  // What the HOST decided this bundle's variables are. Filled by
  // `set_bundle_config` once MoonBit has resolved the manifest's declarations
  // against the policy's bindings — which happens inside `dyncomp_on_loaded`,
  // before anything can construct an instance, so no guest call can arrive
  // ahead of it.
  //
  // Keyed off `currentBundle` rather than closed over per instantiation
  // because `guestImports` is one table shared by every bundle: two
  // registrations of the same code with different variables are the entire
  // point, and they are told apart by which bundle is executing.
  const configImpl = {
    get: (name) => {
      const b = bundles.get(currentBundle);
      const config = b?.config;
      // A name the manifest does not declare. Loud rather than "": an empty
      // string is a plausible value, so a guest that got one back could not
      // tell a variable it misspelled from one deliberately set to nothing.
      if (!config || !Object.hasOwn(config, name)) {
        throw new Error(
          `tutuca dyncomp: bundle ${currentBundle} read config '${name}', ` +
          `which its manifest does not declare` +
          (config ? ` (it declares: ${Object.keys(config).join(", ") || "nothing"})` : ""),
        );
      }
      return config[name];
    },
  };
  // One version, and the unversioned spelling jco 1.25 resolves at runtime.
  // There are no older keys: a bundle built against an older contract calls
  // functions this host no longer implements, so binding it would half-work
  // rather than work. `abi.mjs` refuses such a guest by its export namespace,
  // which is a legible error rather than a missing import.
  const guestImports = {
    "tutuca:component/values": valuesImpl,
    "tutuca:component/values@0.11.0": valuesImpl,
    "tutuca:component/control": controlImpl,
    "tutuca:component/control@0.11.0": controlImpl,
    "tutuca:component/config": configImpl,
    "tutuca:component/config@0.11.0": configImpl,
  };
  // `tutuca:component/tables` is deliberately absent: it declares types and no
  // functions, so there is nothing for a host to implement and jco asks for
  // nothing. That is the whole reason the shared table vocabulary costs a guest
  // no runtime surface — it is a contract about SHAPES, not about calls.
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

  // Instantiate against a core-module resolver, register the bundle, and hand
  // its manifest to the wasm host. Shared by the URL loader (`load`) and the
  // dropped-archive loader (`loadArchive`); only where the bytes came from
  // differs between them.
  const finishLoad = async (instantiate, getCoreModule, loadId, manifest = null) => {
    const root = await instantiate(getCoreModule, guestImports);
    const id = nextBundle++;
    bundles.set(id, { guest: root.guest, instances: new Map(), next: 1 });
    const manifestJson = JSON.stringify(manifest ?? root.guest.getManifest());
    getExports().dyncomp_on_loaded(loadId, id, manifestJson);
  };

  // A v3 descriptor carries the declaration as data. Views are separate
  // HTML assets so authors and editors handle HTML rather than a string inside
  // source code; hydrate them only after untarring, before MoonBit parses the
  // manifest exactly as it did for v0.5's get-manifest result.
  const hydrateManifest = (descriptor, files) => {
    const manifest = structuredClone(descriptor.manifest);
    if (!manifest || manifest.manifestVersion !== 3) {
      throw new Error("tutuca.json has no supported static manifest");
    }
    for (const component of manifest.components ?? []) {
      for (const view of component.views ?? []) {
        // A card compiled straight to a bundle has no view files to hydrate
        // from: `tutucard/wasm/manifest.mbt` projects the `<template>`s into
        // `html` already, because there is no archive there, only a page that
        // has the card. Leave that shape alone; only a `src` names a file.
        if (typeof view.html === "string") continue;
        const name = String(view.src ?? "").split("/").pop();
        const bytes = files[name];
        if (!name || !bytes) {
          throw new Error(`static manifest view is missing from archive: ${view.src}`);
        }
        view.html = new TextDecoder().decode(bytes);
        delete view.src;
      }
    }
    return manifest;
  };

  // Load a dropped single-file bundle: gunzip (native DecompressionStream) ->
  // untar -> instantiate, resolving each core module from the in-memory tar
  // bytes. loadId is any value not tracked in the host's notify_paths, so
  // completion notifies the root shell (see @dhw.notify).
  //
  // A descriptor names the world, string encoding and main core module.
  // `./abi.mjs` implements that world once, here, and the archive carries no
  // JavaScript at all. The older `*.component.js` archive shape is deliberately
  // not accepted: warning before importing page-authority code is not a sandbox.
  const loadArchiveBytes = (bytes, loadId) => {
    (async () => {
      const files = untar(await gunzip(bytes));
      const getCoreModule = (path) => {
        const base = String(path).split("/").pop();
        const wasm = files[base];
        if (!wasm) throw new Error(`missing core module in archive: ${base}`);
        return WebAssembly.compile(wasm);
      };

      const descriptorBytes = requireDescriptor(files);
      const descriptor = JSON.parse(new TextDecoder().decode(descriptorBytes));
      const { instantiate } = await import("./abi.mjs");
      const manifest = hydrateManifest(descriptor, files);
      await finishLoad(
        (g, i) => instantiate(g, i, descriptor),
        getCoreModule,
        loadId,
        manifest,
      );
      // the bundle's views registered new margaui utility classes; the host
      // recompiles + reinjects <style id="margaui-css"> in MoonBit so guest
      // styling (e.g. the counter/todo cards) applies
      getExports().refresh_margaui?.();
    })().catch((e) => {
      console.error("universal load failed:", e);
      getExports().dyncomp_on_load_error(loadId, String(e));
    });
  };

  const loadArchive = (file, loadId) => {
    if (file.size > ARCHIVE_LIMITS.compressedBytes) {
      getExports().dyncomp_on_load_error(
        loadId,
        `bundle archive is too large: ${file.size} compressed bytes ` +
          `(the limit is ${ARCHIVE_LIMITS.compressedBytes})`,
      );
      return;
    }
    file.arrayBuffer()
      .then(buffer => loadArchiveBytes(new Uint8Array(buffer), loadId))
      .catch((e) => {
        console.error("universal load failed:", e);
        getExports().dyncomp_on_load_error(loadId, String(e));
      });
  };

  return {
    // What `config.get` answers with, for one bundle.
    //
    // Per BUNDLE rather than per host: a config is a decision about what THIS
    // registration is. Two registrations of one archive with different
    // variables are the case the whole mechanism exists for, and a host-wide
    // table could not tell them apart.
    //
    // Called from `dyncomp_on_loaded`, after MoonBit resolved the manifest's
    // declarations against the policy's bindings and before anything can
    // construct an instance.
    set_bundle_config: (bundleId, configJson) => {
      const b = bundles.get(bundleId);
      if (!b) {
        console.warn(`tutuca dyncomp: no bundle ${bundleId} to configure`);
        return;
      }
      b.config = JSON.parse(configJson);
    },
    // A bundle is a `.tutuca.tar.gz` archive, and there are three ways to name
    // one: the id of a file the user dropped, a URL to fetch it from, or the id
    // of bytes the page already holds. All three end in the same
    // unpack-and-instantiate path.
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
        loadArchiveBytes(await readCompressedResponse(res), loadId);
      })().catch((e) => {
        console.error("dyncomp load failed:", e);
        getExports().dyncomp_on_load_error(loadId, String(e));
      });
    },
    // No size check before the unpack: `gunzip` already refuses more than
    // ARCHIVE_LIMITS.compressedBytes, and unlike a dropped File there is no
    // `.size` to read without touching the bytes anyway.
    load_bytes: (archiveId, loadId) => {
      const bytes = heldArchives.get(archiveId);
      if (!bytes) {
        getExports().dyncomp_on_load_error(loadId, `no held archive #${archiveId}`);
        return;
      }
      heldArchives.delete(archiveId);
      loadArchiveBytes(bytes, loadId);
    },
    create: (bundle, component, argsJson) => {
      currentBundle = bundle;
      const b = bundles.get(bundle);
      const args = Object.entries(JSON.parse(argsJson)).map(([k, v]) => [k, jsonToGuest(v)]);
      const h = inPhase("construct", () => {
        const handle = register(bundle, new b.guest.Instance(component, args), component);
        drainChildren();
        return handle;
      });
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
    dispatch: (bundle, handle, bucketInt, name, argsJson, bindingsJson) => {
      controlBuf = [];
      bindings = bindingsJson ? JSON.parse(bindingsJson) : {};
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const inst = instOf(bundle, handle);
      if (!inst) return JSON.stringify({ handled: false, next: null, msgs: [] });
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const result = inPhase("dispatch", () => {
        const handled = bucketInt === 1
          ? inst.handleIntent(name, args)
          : inst.handleMessage(name, args);
        drainChildren();
        return handled;
      });
      const out = JSON.stringify({
        handled: result.tag !== "unhandled",
        next: result.tag === "changed" ? register(bundle, result.val, comp) : null,
        msgs: controlBuf,
      });
      arena.clear();
      controlBuf = [];
      bindings = {};
      return out;
    },
    // `bindings` for the same reason `dispatch` has them, resolved for the
    // RENDER position instead of the dispatch one: a `compute`, a `pred`, a
    // `@when` or an `enrich` that reads `*name` compiles `control.lookup`, and
    // this is the only thing that answers it. Set and cleared around the call
    // exactly as `dispatch` does — a binding must not outlive the call it was
    // resolved for.
    render_call: (bundle, handle, category, name, argsJson, bindingsJson) => {
      const inst = instOf(bundle, handle);
      if (!inst) return '';
      bindings = bindingsJson ? JSON.parse(bindingsJson) : {};
      const args = JSON.parse(argsJson).map(jsonToGuest);
      try {
        const v = inPhase("render", () => category === "when"
          ? { tag: "boolean", val: inst.when(name, args) }
          : category === "enrich"
            ? inst.enrich(name, args)
            : category === "enrichScope"
              ? inst.enrichScope(name)
              : inst.compute(name, args));
        const out = JSON.stringify(guestToJson(v));
        arena.clear();
        return out;
      } finally {
        bindings = {};
      }
    },
    get_property: (bundle, handle, name) => {
      const inst = instOf(bundle, handle);
      if (!inst) return "";
      let value;
      try {
        value = inPhase("property", () => inst.getProperty(name));
      } catch (error) {
        console.warn(`tutuca dyncomp: property '${name}' getter refused`, error);
        value = undefined;
      }
      pendingChildren = [];
      controlBuf = [];
      const out = value === undefined ? "" : JSON.stringify(guestToJson(value));
      arena.clear();
      return out;
    },
    set_property: (bundle, handle, name, valueJson) => {
      const inst = instOf(bundle, handle);
      if (!inst) return JSON.stringify({ tag: "missing" });
      const comp = bundles.get(bundle).instances.get(handle).comp;
      let result;
      try {
        result = inPhase("property", () =>
          inst.setProperty(name, jsonToGuest(JSON.parse(valueJson))));
      } catch (error) {
        console.warn(`tutuca dyncomp: property '${name}' refused`, error);
        result = { tag: "refused" };
      }
      pendingChildren = [];
      controlBuf = [];
      const out = result.tag === "changed"
        ? { tag: "changed", next: register(bundle, result.val, comp) }
        : { tag: result.tag };
      arena.clear();
      return JSON.stringify(out);
    },
    // a request the BUNDLE serves; module-scoped, so no instance handle
    serve_intent: (bundle, name, argsJson) => {
      currentBundle = bundle;
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const res = bundles.get(bundle).guest.serveIntent(name, args);
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
      const next = inPhase("mutation", () => inst.withField(name, v));
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
      const inst = inPhase("construct", () => {
        const restored = b.guest.Instance.restore(component, b64ToBytes(stateB64));
        drainChildren();
        return restored;
      });
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
