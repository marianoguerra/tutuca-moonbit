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

// --- what this host is willing to grant ---
//
// Capabilities are checked against a descriptor bundle's IMPORT SECTION,
// which is the difference between a gate and a promise. The static manifest
// remains useful for consent UI, but it cannot hide what the module imports.
//
// The default is what `Policy::untrusted()` says: nothing. A page that has
// asked a person calls this before loading, and `set_policy` is the MoonBit
// side of the same decision — wiring the two together is the piece still
// missing, and until it lands the strict answer is the one in force.
let grants = [];

/**
 * Capabilities (`cap-clock`, `cap-random`, `cap-timer`) that descriptor
 * bundles loaded from now on may import. Applies at LOAD, like the policy it
 * mirrors: narrowing it does not retract a bundle already registered.
 *
 * `cap-external-urls` gates no import — it is about what a guest's VIEW may
 * name — so it belongs on the MoonBit policy (`allowing_external_urls`) and
 * passing it here changes nothing either way.
 */
export function setGrants(caps) {
  grants = [...caps];
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
    "tutuca:component/values@0.6.0": valuesImpl,
    "tutuca:component/values@0.5.0": valuesImpl,
    "tutuca:component/control": controlImpl,
    "tutuca:component/control@0.6.0": controlImpl,
    "tutuca:component/control@0.5.0": controlImpl,
    "tutuca:component/env": envImpl,
    "tutuca:component/env@0.6.0": envImpl,
    "tutuca:component/env@0.5.0": envImpl,
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

  // A v0.6 descriptor carries the declaration as data. Views are separate
  // HTML assets so authors and editors handle HTML rather than a string inside
  // source code; hydrate them only after untarring, before MoonBit parses the
  // manifest exactly as it did for v0.5's get-manifest result.
  const hydrateManifest = (descriptor, files) => {
    const manifest = structuredClone(descriptor.manifest);
    if (!manifest || manifest.manifestVersion !== 1) {
      throw new Error("tutuca.json has no supported static manifest");
    }
    for (const component of manifest.components ?? []) {
      for (const view of component.views ?? []) {
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
        (g, i) => instantiate(g, i, { ...descriptor, policy: { grants } }),
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
    set_grants: (capsJson) => setGrants(JSON.parse(capsJson)),
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
        loadArchiveBytes(await readCompressedResponse(res), loadId);
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
    dispatch: (bundle, handle, bucketInt, name, argsJson) => {
      const bucket = ["input", "receive", "response", "bubble"][bucketInt] ?? "input";
      controlBuf = [];
      const args = JSON.parse(argsJson).map(jsonToGuest);
      const inst = instOf(bundle, handle);
      if (!inst) return JSON.stringify({ handled: false, next: null, msgs: [] });
      const comp = bundles.get(bundle).instances.get(handle).comp;
      const result = inst.handleEvent(bucket, name, args);
      drainChildren();
      const out = JSON.stringify({
        handled: result.tag !== "unhandled",
        next: result.tag === "changed" ? register(bundle, result.val, comp) : null,
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
