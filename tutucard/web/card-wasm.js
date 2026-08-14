// The page's half of the guest boundary, and the packer.
//
// `abi.mjs` — the same file `dyncomp` ships, copied here unchanged by
// `build/assemble.mjs` — turns a core module into an object with an
// `Instance` class. This wraps that in the four calls the MoonBit `&Guest`
// impl makes over `globalThis.__cardguest`, keyed by an integer handle,
// because a MoonBit extern cannot hold a JS object.
//
// It is the js-target twin of `createTcompImports` in
// `dyncomp/host/wasm/loader.mjs`, minus everything a compiled card cannot do:
// no pending-children protocol (a card has no `make-instance`), no clock to
// freeze (a card asks for no capability), no bundle table (a playground holds
// one card).

import { instantiate } from "./abi.mjs";

// Compound guest values travel as u64 handles into a host-side arena. A card
// can neither read nor build one — the generator emits no `values` import at
// all, so `instantiate` never binds this interface — but a host may still
// hand a list into `handleEvent`, and it has to come back out the same shape.
function makeArena() {
  const cells = new Map();
  let next = 1n;
  const put = (v) => {
    const h = next++;
    cells.set(h, v);
    return h;
  };
  return {
    cells,
    put,
    clear: () => cells.clear(),
    api: {
      listLen: (h) => cells.get(h)?.length ?? 0,
      listGet: (h, i) => cells.get(h)?.[i] ?? { tag: "nil" },
      mapLen: (h) => cells.get(h)?.size ?? 0,
      mapKeys: (h) => [...(cells.get(h)?.keys() ?? [])],
      mapGet: (h, k) => cells.get(h)?.get(k),
      listNew: () => put([]),
      listPush: (h, v) => cells.get(h)?.push(v),
      mapNew: () => put(new Map()),
      mapSet: (h, k, v) => cells.get(h)?.set(k, v),
      toJson: (v) => JSON.stringify(guestToJson(v, cells)),
      fromJson: (s) => jsonToGuest(JSON.parse(s), put),
    },
  };
}

/** A guest `value` as the plain JSON `@tutuca.Value::to_json` speaks. */
function guestToJson(v, cells) {
  if (v === undefined) return null;
  switch (v.tag) {
    case "nil":
      return null;
    case "boolean":
    case "number":
    case "text":
      return v.val;
    case "list":
      return (cells.get(v.val) ?? []).map((x) => guestToJson(x, cells));
    case "map": {
      const out = {};
      for (const [k, x] of cells.get(v.val) ?? new Map()) out[k] = guestToJson(x, cells);
      return out;
    }
    // An `instance` is a same-bundle child, which a compiled card never makes.
    default:
      return null;
  }
}

/** The other direction. */
function jsonToGuest(j, put) {
  if (j === null || j === undefined) return { tag: "nil" };
  if (typeof j === "boolean") return { tag: "boolean", val: j };
  if (typeof j === "number") return { tag: "number", val: j };
  if (typeof j === "string") return { tag: "text", val: j };
  if (Array.isArray(j)) return { tag: "list", val: put(j.map((x) => jsonToGuest(x, put))) };
  const m = new Map();
  for (const [k, v] of Object.entries(j)) m.set(k, jsonToGuest(v, put));
  return { tag: "map", val: put(m) };
}

/**
 * Instantiate a compiled card and install it as `globalThis.__cardguest`.
 *
 * The grants list is empty and stays empty. A compiled card imports no
 * capability — `abi.mjs` checks the module's IMPORT SECTION rather than
 * anything the manifest claims — so a card that asked for a clock would be
 * refused here rather than quietly given one.
 */
export async function loadGuest(bytes, descriptor) {
  const arena = makeArena();
  let control = [];
  const root = await instantiate(
    () => WebAssembly.compile(bytes),
    {
      "tutuca:component/values": arena.api,
      "tutuca:component/control": {
        log: (level, msg) => console.log(`[card ${level}]`, msg),
        emit: (name, args) =>
          control.push({ kind: "emit", name, args: args.map((a) => guestToJson(a, arena.cells)) }),
        send: (name, args) =>
          control.push({ kind: "send", name, args: args.map((a) => guestToJson(a, arena.cells)) }),
        stopPropagation: () => control.push({ kind: "stopPropagation" }),
        sendAt: () => {},
        bubbleAt: () => {},
        request: () => {},
        after: () => {},
        makeInstance: () => 0n,
        dropInstance: () => {},
      },
    },
    { ...descriptor, policy: { grants: [] } },
  );

  const table = new Map();
  let nextHandle = 1;
  const register = (inst) => {
    const h = nextHandle++;
    table.set(h, inst);
    return h;
  };
  const to = (j) => jsonToGuest(j, arena.put);
  const from = (v) => guestToJson(v, arena.cells);

  globalThis.__cardguest = {
    create(component, argsJson) {
      const args = Object.entries(JSON.parse(argsJson)).map(([k, v]) => [k, to(v)]);
      const h = register(new root.guest.Instance(component, args));
      arena.clear();
      return h;
    },
    getField(handle, name) {
      const v = table.get(handle)?.getField(name);
      const out = v === undefined ? "" : JSON.stringify(from(v));
      arena.clear();
      return out;
    },
    dispatch(handle, bucketInt, name, argsJson) {
      control = [];
      const bucket = ["input", "receive", "response", "bubble"][bucketInt] ?? "input";
      const inst = table.get(handle);
      if (!inst) return JSON.stringify({ handled: false, next: null, msgs: [] });
      const result = inst.handleEvent(bucket, name, JSON.parse(argsJson).map(to));
      const out = JSON.stringify({
        handled: result.tag !== "unhandled",
        next: result.tag === "changed" ? register(result.val) : null,
        msgs: control,
      });
      arena.clear();
      control = [];
      return out;
    },
    callMethod(handle, name, argsJson) {
      const inst = table.get(handle);
      if (!inst) return "";
      const v = inst.callMethod(name, JSON.parse(argsJson).map(to));
      const out = JSON.stringify(from(v));
      arena.clear();
      return out;
    },
    withField(handle, name, valueJson) {
      const inst = table.get(handle);
      if (!inst) return -1;
      const next = inst.withField(name, to(JSON.parse(valueJson)));
      arena.clear();
      return next === undefined ? -1 : register(next);
    },
  };
  return root;
}

// --- packing ---------------------------------------------------------------
//
// `scripts/pack-bundle.mjs` ported: the same hand-rolled 512-byte ustar
// writer, with `CompressionStream("gzip")` for `node:zlib` and `Uint8Array`
// for `Buffer`. The output is the archive shape the universal host page
// already accepts — `tutuca.json` plus one core wasm, and no executable
// JavaScript anywhere in it.
//
// Views ride inside the descriptor's manifest as `html` rather than as files
// beside it. `loader.mjs` hydrates a `src` into an `html` and leaves an `html`
// alone, so both shapes load; this one is what a page that never had files has.

const enc = new TextEncoder();

function tarHeader(name, size) {
  const h = new Uint8Array(512);
  const put = (s, at) => h.set(enc.encode(s), at);
  const octal = (n, len) => n.toString(8).padStart(len - 1, "0") + "\0";
  put(name, 0);
  put(octal(0o644, 8), 100);
  put(octal(0, 8), 108);
  put(octal(0, 8), 116);
  put(size.toString(8).padStart(11, "0") + "\0", 124);
  put(octal(0, 12), 136);
  put("        ", 148); // checksum placeholder: eight spaces, per POSIX
  put("0", 156);
  put("ustar\0", 257);
  put("00", 263);
  let sum = 0;
  for (const b of h) sum += b;
  put(sum.toString(8).padStart(6, "0") + "\0 ", 148);
  return h;
}

function buildTar(files) {
  const parts = [];
  let total = 0;
  for (const { name, data } of files) {
    const header = tarHeader(name, data.length);
    const pad = new Uint8Array((512 - (data.length % 512)) % 512);
    parts.push(header, data, pad);
    total += header.length + data.length + pad.length;
  }
  const end = new Uint8Array(1024); // two zero blocks = end of archive
  parts.push(end);
  total += end.length;
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

/**
 * The wasm as bytes.
 *
 * It crosses from MoonBit as base64 because a MoonBit extern cannot hand
 * JavaScript a byte array, and the page needs the real thing: to instantiate
 * it, and to put it in the archive.
 */
export const b64ToBytes = (b64) =>
  Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

/** A `.tutuca.tar.gz` for a compiled card, as a Blob. */
export async function packBundle(report, wasmBytes) {
  const descriptor = { ...report.descriptor, manifest: report.manifest };
  const files = [
    { name: "tutuca.json", data: enc.encode(JSON.stringify(descriptor)) },
    { name: descriptor.core, data: wasmBytes },
  ];
  const tar = buildTar(files);
  const gz = new Response(
    new Blob([tar]).stream().pipeThrough(new CompressionStream("gzip")),
  );
  return new Blob([await gz.arrayBuffer()], { type: "application/gzip" });
}
