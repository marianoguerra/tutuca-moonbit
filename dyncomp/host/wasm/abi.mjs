// The canonical ABI for `tutuca:component@0.10.0`, written once, host-side.
//
// This replaces the `*.component.js` that `jco transpile` emits into every
// bundle archive. That file is ~5,000-7,500 lines and 38-57% of a gzipped
// archive, and it carries no information about the component: across the
// fifteen shipped bundles it takes exactly EIGHT distinct values, and the one
// you get is a pure function of (which host functions the core module imports,
// which string encoding it was embedded with). Everything else is the world,
// and the world is fixed.
//
// So the world is described here as DATA — `WORLD` below is the whole of it,
// transcribed from `wit/tutuca-component.wit` — and one generic canonical-ABI
// implementation walks that description. A bundle then ships wasm and a
// four-field descriptor, and the host holds the only copy of the glue.
//
// Two consequences beyond the size:
//
//   - An archive stops carrying executable JS. `loader.mjs` used to
//     `import()` the guest's own transpiler output from a blob URL, which runs
//     at page authority and is the one channel the wasm sandbox does not cover
//     (SECURITY.md, and the note `bundles/audit-bundle.mjs` prints). There is
//     nothing left to import.
//   - Imports are bound BY NAME against `IMPORTS`, so an import outside the
//     contract is refused here rather than noticed later by an offline tool,
//     and `policy` can refuse a capability the module actually imports rather
//     than one its manifest admits to.
//
// The reference is the Canonical ABI section of the Component Model spec. Every
// layout this file computes was checked against the shipped core signatures —
// `value` flattens to (i32, i64, i32) and `with-field` really does take
// (i32 i32 i32 i32 i64 i32); `tuple<string, value>` really is 24 bytes with the
// value at +8 and its payload at +16.
//
// DEVIATIONS from jco, deliberate and total:
//
//   - `list<u32>` lifts to an Array, where jco lifts it to a Uint32Array.
//     `list<u8>` still lifts to a Uint8Array, which is what `persist` /
//     `restore` pass around.

// ---------------------------------------------------------------------------
// type descriptors
// ---------------------------------------------------------------------------

const BOOL = { k: "bool" };
const U8 = { k: "u8" };
const U32 = { k: "u32" };
const S32 = { k: "s32" };
const U64 = { k: "u64" };
const F64 = { k: "f64" };
const STRING = { k: "string" };
const OWN = { k: "own" };
const BORROW = { k: "borrow" };
const list = (t) => ({ k: "list", t });
const option = (t) => ({ k: "option", t });
// Field names are the JS spelling (kebab-case lowered to camelCase), because
// that is what a lifted record IS — `request-opts.live-path` reaches the host
// as `opts.livePath`. Declaration ORDER is not cosmetic: it is the memory
// layout.
const record = (fields) => ({ k: "record", fields });
const tuple = (ts) => ({ k: "tuple", ts });
// Cases are [name, payload|null]; a lifted variant is `{tag}` or `{tag, val}`.
const variant = (cases) => ({ k: "variant", cases });
// An enum lifts to its WIT name verbatim, not to a camelCased one.
const enumeration = (names) => ({ k: "enum", names });

// ---------------------------------------------------------------------------
// the world, transcribed from wit/tutuca-component.wit
// ---------------------------------------------------------------------------

const VALUE = variant([
  ["nil", null],
  ["boolean", BOOL],
  ["number", F64],
  ["text", STRING],
  ["list", U64],
  ["map", U64],
  ["instance", U64],
]);

const PATH_STEP = variant([
  ["field", STRING],
  ["item", record([["field", STRING], ["key", STRING]])],
  ["at", record([["field", STRING], ["index", U32]])],
]);

const LOG_LEVEL = enumeration(["debug", "info", "warn", "error"]);

// WIT `leg` / `intent-opts`, spelled exactly as the contract does.
//
// This used to be one U32 carrying a route code, which is what `tutucard`
// compiles a card against. That was cheaper and it was WRONG: a guest built by
// wit-bindgen lowers `intent(string, list<value>, intent-opts)` to sixteen
// i32s, the import binds by NAME, and eleven of them were being read as
// something else. The symptom was an intent whose answer names arrived as
// garbage — so a route that happened to be the default still worked and one
// that named `on-ok` silently answered nobody. The contract is the authority;
// the card compiler builds this record now too.
const LEG = enumeration(["dyn", "lex"]);
const INTENT_OPTS = record([
  ["route", list(LEG)],
  ["onOk", option(STRING)],
  ["onError", option(STRING)],
  ["onUnhandled", option(STRING)],
  ["livePath", BOOL],
]);
// Two buckets, and a case's position is its wire number.
const BUCKET = enumeration(["receive", "intent"]);
const SERVE_RESULT = variant([["ok", VALUE], ["err", VALUE]]);
const EVENT_RESULT = variant([
  ["unhandled", null],
  ["unchanged", null],
  ["changed", OWN],
]);

const ARGS = list(tuple([STRING, VALUE]));

// What a guest may import, and nothing else. `impl` is the key on the host's
// implementation object; `cap` is the capability a host must have granted for
// this import to be legal at all — the gate that used to read the manifest.
//
// `tutuca:component/tables` is absent because it declares no functions.
export const IMPORTS = {
  "tutuca:component/values": {
    "list-len": { impl: "listLen", params: [U64], result: U32 },
    "list-get": { impl: "listGet", params: [U64, U32], result: VALUE },
    "map-len": { impl: "mapLen", params: [U64], result: U32 },
    "map-keys": { impl: "mapKeys", params: [U64], result: list(STRING) },
    "map-get": { impl: "mapGet", params: [U64, STRING], result: option(VALUE) },
    "list-new": { impl: "listNew", params: [], result: U64 },
    "list-push": { impl: "listPush", params: [U64, VALUE], result: null },
    "map-new": { impl: "mapNew", params: [], result: U64 },
    "map-set": { impl: "mapSet", params: [U64, STRING, VALUE], result: null },
    "to-json": { impl: "toJson", params: [VALUE], result: STRING },
    "from-json": { impl: "fromJson", params: [STRING], result: VALUE },
  },
  "tutuca:component/control": {
    log: { impl: "log", params: [LOG_LEVEL, STRING], result: null },
    send: { impl: "send", params: [STRING, list(VALUE)], result: null },
    "send-at": {
      impl: "sendAt",
      params: [list(PATH_STEP), STRING, list(VALUE)],
      result: null,
    },
    "send-reply": { impl: "sendReply", params: [STRING, list(VALUE)], result: null },
    // The first import that answers with a compound. `lowerImport` already
    // handles it: a `value` flattens to more core values than a result may
    // carry, so the guest appends a return pointer and the host stores into it.
    lookup: { impl: "lookup", params: [STRING], result: VALUE },
    "stop-propagation": { impl: "stopPropagation", params: [], result: null },
    intent: {
      impl: "intent",
      params: [STRING, list(VALUE), INTENT_OPTS],
      result: null,
    },
    "intent-at": {
      impl: "intentAt",
      params: [list(PATH_STEP), STRING, list(VALUE), INTENT_OPTS],
      result: null,
    },
    // An empty argument list is "no amendment", which is exactly what
    // `forward` with no arguments means — so there is no third state and no
    // discriminant.
    forward: { impl: "forward", params: [list(VALUE), INTENT_OPTS], result: null },
    reply: { impl: "reply", params: [VALUE], result: null },
    fail: { impl: "fail", params: [VALUE], result: null },
    after: {
      impl: "after",
      params: [U32, STRING, list(VALUE)],
      result: null,
      cap: "cap-timer",
    },
    "make-instance": { impl: "makeInstance", params: [STRING, ARGS], result: U64 },
    "drop-instance": { impl: "dropInstance", params: [U64], result: null },
  },
  "tutuca:component/env": {
    "now-ms": { impl: "nowMs", params: [], result: U64, cap: "cap-clock" },
    "tz-offset-min": { impl: "tzOffsetMin", params: [], result: S32, cap: "cap-clock" },
    locale: { impl: "locale", params: [], result: STRING, cap: "cap-clock" },
    "random-u64": { impl: "randomU64", params: [], result: U64, cap: "cap-random" },
    "new-id": { impl: "newId", params: [], result: STRING, cap: "cap-random" },
  },
  // No `cap`, and that is the design rather than an omission. A capability is
  // authority a guest would not otherwise have; these values are the host's
  // own, handed over deliberately, and reading one gives a guest nothing it
  // could not have been shipped as a constant. What the values REACH is
  // decided elsewhere — a view spending `cap-external-urls` on an origin
  // variable — and that grant is the host's, made by binding it.
  "tutuca:component/config": {
    get: { impl: "get", params: [STRING], result: STRING },
  },
};

const GUEST = "tutuca:component/guest@0.10.0";
const RESOURCE_NS = `[export]${GUEST}`;

// The export side. `post` names the `cabi_post_*` that frees what a lift
// returned; the four without one return nothing that owns memory.
const EXPORTS = {
  serveIntent: {
    core: `${GUEST}#serve-intent`,
    params: [STRING, list(VALUE)],
    result: SERVE_RESULT,
    post: true,
  },
  constructor: {
    core: `${GUEST}#[constructor]instance`,
    params: [STRING, ARGS],
    result: OWN,
  },
  restore: {
    core: `${GUEST}#[static]instance.restore`,
    params: [STRING, list(U8)],
    result: option(OWN),
  },
  getField: {
    core: `${GUEST}#[method]instance.get-field`,
    params: [BORROW, STRING],
    result: option(VALUE),
    post: true,
  },
  handleEvent: {
    core: `${GUEST}#[method]instance.handle-event`,
    params: [BORROW, BUCKET, STRING, list(VALUE)],
    result: EVENT_RESULT,
  },
  callMethod: {
    core: `${GUEST}#[method]instance.call-method`,
    params: [BORROW, STRING, list(VALUE)],
    result: VALUE,
    post: true,
  },
  withField: {
    core: `${GUEST}#[method]instance.with-field`,
    params: [BORROW, STRING, VALUE],
    result: option(OWN),
  },
  persist: {
    core: `${GUEST}#[method]instance.persist`,
    params: [BORROW],
    result: list(U8),
    post: true,
  },
};

// ---------------------------------------------------------------------------
// layout: alignment, size, flattening
// ---------------------------------------------------------------------------

const MAX_FLAT_PARAMS = 16;
const MAX_FLAT_RESULTS = 1;

// `Symbol.dispose` is recent enough that jco falls back too; a host that calls
// `inst[Symbol.dispose]()` and a runtime without it must still meet.
const symbolDispose = Symbol.dispose || Symbol.for("dispose");

const alignTo = (n, a) => Math.ceil(n / a) * a;

// A discriminant is the smallest integer that indexes the cases.
const discSize = (n) => (n <= 256 ? 1 : n <= 65536 ? 2 : 4);

const casesOf = (t) =>
  t.k === "variant" ? t.cases
  : t.k === "option" ? [["none", null], ["some", t.t]]
  : t.names.map((n) => [n, null]);

function alignment(t) {
  switch (t.k) {
    case "bool": case "u8": return 1;
    case "u32": case "s32": case "string": case "list": case "own": case "borrow":
      return 4;
    case "u64": case "f64": return 8;
    case "record": return t.fields.reduce((a, [, ft]) => Math.max(a, alignment(ft)), 1);
    case "tuple": return t.ts.reduce((a, ft) => Math.max(a, alignment(ft)), 1);
    case "enum": case "variant": case "option": {
      const cs = casesOf(t);
      return cs.reduce(
        (a, [, ct]) => Math.max(a, ct ? alignment(ct) : 1),
        discSize(cs.length),
      );
    }
    default: throw new Error(`alignment: unknown type ${t.k}`);
  }
}

function sizeOf(t) {
  switch (t.k) {
    case "bool": case "u8": return 1;
    case "u32": case "s32": case "own": case "borrow": return 4;
    case "u64": case "f64": return 8;
    case "string": case "list": return 8;
    case "record": {
      let s = 0;
      for (const [, ft] of t.fields) s = alignTo(s, alignment(ft)) + sizeOf(ft);
      return alignTo(s, alignment(t));
    }
    case "tuple": {
      let s = 0;
      for (const ft of t.ts) s = alignTo(s, alignment(ft)) + sizeOf(ft);
      return alignTo(s, alignment(t));
    }
    case "enum": case "variant": case "option": {
      const cs = casesOf(t);
      let s = alignTo(discSize(cs.length), maxCaseAlign(cs));
      s += cs.reduce((m, [, ct]) => Math.max(m, ct ? sizeOf(ct) : 0), 0);
      return alignTo(s, alignment(t));
    }
    default: throw new Error(`sizeOf: unknown type ${t.k}`);
  }
}

const maxCaseAlign = (cs) =>
  cs.reduce((a, [, ct]) => Math.max(a, ct ? alignment(ct) : 1), 1);

// Where a variant's payload starts, relative to the variant.
const payloadOffset = (t) => {
  const cs = casesOf(t);
  return alignTo(discSize(cs.length), maxCaseAlign(cs));
};

// The spec's `join`: what one flat slot must be to hold either of two types.
function join(a, b) {
  if (a === b) return a;
  if ((a === "i32" && b === "f32") || (a === "f32" && b === "i32")) return "i32";
  return "i64";
}

function flatten(t) {
  switch (t.k) {
    case "bool": case "u8": case "u32": case "s32": case "own": case "borrow":
      return ["i32"];
    case "u64": return ["i64"];
    case "f64": return ["f64"];
    case "string": case "list": return ["i32", "i32"];
    case "record": return t.fields.flatMap(([, ft]) => flatten(ft));
    case "tuple": return t.ts.flatMap(flatten);
    case "enum": return ["i32"];
    case "variant": case "option": {
      const payload = [];
      for (const [, ct] of casesOf(t)) {
        const fs = ct ? flatten(ct) : [];
        for (let i = 0; i < fs.length; i++) {
          payload[i] = i < payload.length ? join(payload[i], fs[i]) : fs[i];
        }
      }
      return ["i32", ...payload];
    }
    default: throw new Error(`flatten: unknown type ${t.k}`);
  }
}

// ---------------------------------------------------------------------------
// bit-level coercion between a case's own flat type and the joined slot
// ---------------------------------------------------------------------------

const scratch = new DataView(new ArrayBuffer(8));

function coerceOut(v, have, want) {
  if (have === want) return v;
  if (have === "i32" && want === "i64") return BigInt(v >>> 0);
  if (have === "f64" && want === "i64") {
    scratch.setFloat64(0, v, true);
    return scratch.getBigUint64(0, true);
  }
  if (have === "f32" && want === "i32") {
    scratch.setFloat32(0, v, true);
    return scratch.getInt32(0, true);
  }
  if (have === "f32" && want === "i64") {
    scratch.setFloat32(0, v, true);
    return BigInt(scratch.getUint32(0, true));
  }
  throw new Error(`coerceOut: ${have} -> ${want}`);
}

function coerceIn(v, want, have) {
  if (have === want) return v;
  if (want === "i32" && have === "i64") return Number(BigInt.asUintN(32, v)) | 0;
  if (want === "f64" && have === "i64") {
    scratch.setBigUint64(0, BigInt.asUintN(64, v), true);
    return scratch.getFloat64(0, true);
  }
  if (want === "f32" && have === "i32") {
    scratch.setInt32(0, v, true);
    return scratch.getFloat32(0, true);
  }
  if (want === "f32" && have === "i64") {
    scratch.setUint32(0, Number(BigInt.asUintN(32, v)), true);
    return scratch.getFloat32(0, true);
  }
  throw new Error(`coerceIn: ${have} -> ${want}`);
}

const zeroOf = (ft) => (ft === "i64" ? 0n : 0);

// ---------------------------------------------------------------------------
// the context: guest memory, its allocator, its string encoding
// ---------------------------------------------------------------------------

class Cx {
  constructor(encoding) {
    if (encoding !== "utf8" && encoding !== "utf16") {
      throw new Error(`unsupported string encoding: ${encoding}`);
    }
    this.encoding = encoding;
    this.memory = null;
    this.realloc = null;
    this._buf = null;
    this._dv = null;
    this._u8 = null;
    this.enc8 = new TextEncoder();
    this.dec8 = new TextDecoder("utf-8");
    this.dec16 = new TextDecoder("utf-16le");
  }

  // Every allocation can grow the memory and detach the old buffer, so the
  // views are rebuilt whenever the buffer identity changes rather than cached
  // across a call.
  get dv() {
    if (this.memory.buffer !== this._buf) this._refresh();
    return this._dv;
  }

  get u8() {
    if (this.memory.buffer !== this._buf) this._refresh();
    return this._u8;
  }

  _refresh() {
    this._buf = this.memory.buffer;
    this._dv = new DataView(this._buf);
    this._u8 = new Uint8Array(this._buf);
  }

  // An empty allocation still goes through `cabi_realloc`. The spec allows any
  // aligned non-null pointer for a zero-length list, but a guest's allocator is
  // entitled to keep bookkeeping beside what it handed out — MoonBit's heap
  // starts at address 16 and its string header sits below the pointer — so a
  // made-up address is read as a corrupt allocation rather than as nothing.
  alloc(size, align) {
    const ptr = this.realloc(0, 0, align, size);
    if (ptr === 0 && size !== 0) throw new Error("cabi_realloc returned null");
    return ptr;
  }

  // A string's LENGTH is in code units of the guest's encoding, not in
  // characters and not always in bytes: utf16 counts `s.length`.
  lowerString(s) {
    if (typeof s !== "string") throw new TypeError(`expected string, got ${typeof s}`);
    if (this.encoding === "utf8") {
      const bytes = this.enc8.encode(s);
      const at = this.alloc(bytes.length, 1);
      if (bytes.length) this.u8.set(bytes, at);
      return [at, bytes.length];
    }
    const units = s.length;
    const at = this.alloc(units * 2, 2);
    const dv = this.dv;
    for (let i = 0; i < units; i++) dv.setUint16(at + i * 2, s.charCodeAt(i), true);
    return [at, units];
  }

  storeString(ptr, s) {
    const [at, len] = this.lowerString(s);
    this.dv.setUint32(ptr, at, true);
    this.dv.setUint32(ptr + 4, len, true);
  }

  loadString(ptr) {
    const at = this.dv.getUint32(ptr, true);
    const len = this.dv.getUint32(ptr + 4, true);
    return this.decodeString(at, len);
  }

  decodeString(at, len) {
    if (len === 0) return "";
    if (this.encoding === "utf8") {
      return this.dec8.decode(this.u8.subarray(at, at + len));
    }
    return this.dec16.decode(this.u8.subarray(at, at + len * 2));
  }
}

// ---------------------------------------------------------------------------
// load / store: a value in linear memory
// ---------------------------------------------------------------------------

function load(cx, ptr, t) {
  switch (t.k) {
    case "bool": return cx.dv.getUint8(ptr) !== 0;
    case "u8": return cx.dv.getUint8(ptr);
    case "u32": case "own": case "borrow": return cx.dv.getUint32(ptr, true);
    case "s32": return cx.dv.getInt32(ptr, true);
    case "u64": return cx.dv.getBigUint64(ptr, true);
    case "f64": return cx.dv.getFloat64(ptr, true);
    case "string": return cx.loadString(ptr);
    case "list": {
      const at = cx.dv.getUint32(ptr, true);
      const len = cx.dv.getUint32(ptr + 4, true);
      return loadList(cx, at, len, t.t);
    }
    case "record": {
      const out = {};
      let off = 0;
      for (const [name, ft] of t.fields) {
        off = alignTo(off, alignment(ft));
        out[name] = load(cx, ptr + off, ft);
        off += sizeOf(ft);
      }
      return out;
    }
    case "tuple": {
      const out = [];
      let off = 0;
      for (const ft of t.ts) {
        off = alignTo(off, alignment(ft));
        out.push(load(cx, ptr + off, ft));
        off += sizeOf(ft);
      }
      return out;
    }
    case "enum": {
      const d = loadDisc(cx, ptr, t.names.length);
      const name = t.names[d];
      if (name === undefined) throw new Error(`enum discriminant out of range: ${d}`);
      return name;
    }
    case "option": {
      const d = loadDisc(cx, ptr, 2);
      if (d === 0) return undefined;
      return load(cx, ptr + payloadOffset(t), t.t);
    }
    case "variant": {
      const d = loadDisc(cx, ptr, t.cases.length);
      const c = t.cases[d];
      if (c === undefined) throw new Error(`variant discriminant out of range: ${d}`);
      if (c[1] === null) return { tag: c[0] };
      return { tag: c[0], val: load(cx, ptr + payloadOffset(t), c[1]) };
    }
    default: throw new Error(`load: unknown type ${t.k}`);
  }
}

// `list<u8>` is the one element type worth special-casing: it is a guest's
// persisted bytes, it can be large, and it must be COPIED out because the
// post-return that follows frees the memory it sits in.
function loadList(cx, at, len, et) {
  if (et.k === "u8") return cx.u8.slice(at, at + len);
  const stride = sizeOf(et);
  const out = new Array(len);
  for (let i = 0; i < len; i++) out[i] = load(cx, at + i * stride, et);
  return out;
}

function loadDisc(cx, ptr, n) {
  const s = discSize(n);
  return s === 1 ? cx.dv.getUint8(ptr)
    : s === 2 ? cx.dv.getUint16(ptr, true)
    : cx.dv.getUint32(ptr, true);
}

function storeDisc(cx, ptr, n, d) {
  const s = discSize(n);
  if (s === 1) cx.dv.setUint8(ptr, d);
  else if (s === 2) cx.dv.setUint16(ptr, d, true);
  else cx.dv.setUint32(ptr, d, true);
}

function store(cx, ptr, v, t) {
  switch (t.k) {
    case "bool": cx.dv.setUint8(ptr, v ? 1 : 0); return;
    case "u8": cx.dv.setUint8(ptr, v & 0xff); return;
    case "u32": case "own": case "borrow": cx.dv.setUint32(ptr, v >>> 0, true); return;
    case "s32": cx.dv.setInt32(ptr, v | 0, true); return;
    case "u64": cx.dv.setBigUint64(ptr, BigInt.asUintN(64, BigInt(v)), true); return;
    case "f64": cx.dv.setFloat64(ptr, +v, true); return;
    case "string": cx.storeString(ptr, v); return;
    case "list": {
      const [at, len] = storeList(cx, v, t.t);
      cx.dv.setUint32(ptr, at, true);
      cx.dv.setUint32(ptr + 4, len, true);
      return;
    }
    case "record": {
      let off = 0;
      for (const [name, ft] of t.fields) {
        off = alignTo(off, alignment(ft));
        store(cx, ptr + off, v[name], ft);
        off += sizeOf(ft);
      }
      return;
    }
    case "tuple": {
      let off = 0;
      for (let i = 0; i < t.ts.length; i++) {
        const ft = t.ts[i];
        off = alignTo(off, alignment(ft));
        store(cx, ptr + off, v[i], ft);
        off += sizeOf(ft);
      }
      return;
    }
    case "enum": {
      const d = t.names.indexOf(v);
      if (d < 0) throw new TypeError(`not a member of the enum: ${v}`);
      storeDisc(cx, ptr, t.names.length, d);
      return;
    }
    case "option": {
      if (v === undefined || v === null) {
        storeDisc(cx, ptr, 2, 0);
        return;
      }
      storeDisc(cx, ptr, 2, 1);
      store(cx, ptr + payloadOffset(t), v, t.t);
      return;
    }
    case "variant": {
      const d = t.cases.findIndex(([name]) => name === v?.tag);
      if (d < 0) throw new TypeError(`not a case of the variant: ${v?.tag}`);
      storeDisc(cx, ptr, t.cases.length, d);
      const ct = t.cases[d][1];
      if (ct !== null) store(cx, ptr + payloadOffset(t), v.val, ct);
      return;
    }
    default: throw new Error(`store: unknown type ${t.k}`);
  }
}

function storeList(cx, v, et) {
  const len = v.length;
  const at = cx.alloc(len * sizeOf(et), alignment(et));
  if (len === 0) return [at, 0];
  if (et.k === "u8") {
    cx.u8.set(v instanceof Uint8Array ? v : Uint8Array.from(v), at);
    return [at, len];
  }
  const stride = sizeOf(et);
  for (let i = 0; i < len; i++) store(cx, at + i * stride, v[i], et);
  return [at, len];
}

// ---------------------------------------------------------------------------
// lift / lower: a value across the flat core-wasm boundary
// ---------------------------------------------------------------------------

function lowerFlat(cx, v, t, out) {
  switch (t.k) {
    case "bool": out.push(v ? 1 : 0); return;
    case "u8": out.push(v & 0xff); return;
    case "u32": case "own": case "borrow": out.push(v >>> 0); return;
    case "s32": out.push(v | 0); return;
    case "u64": out.push(BigInt.asUintN(64, BigInt(v))); return;
    case "f64": out.push(+v); return;
    case "string": {
      const [at, len] = cx.lowerString(v);
      out.push(at, len);
      return;
    }
    case "list": {
      const [at, len] = storeList(cx, v, t.t);
      out.push(at, len);
      return;
    }
    case "record": {
      for (const [name, ft] of t.fields) lowerFlat(cx, v[name], ft, out);
      return;
    }
    case "tuple": {
      for (let i = 0; i < t.ts.length; i++) lowerFlat(cx, v[i], t.ts[i], out);
      return;
    }
    case "enum": {
      const d = t.names.indexOf(v);
      if (d < 0) throw new TypeError(`not a member of the enum: ${v}`);
      out.push(d);
      return;
    }
    case "option": case "variant": {
      const cs = casesOf(t);
      const joined = flatten(t).slice(1);
      let d, ct, payload;
      if (t.k === "option") {
        d = v === undefined || v === null ? 0 : 1;
        ct = d === 0 ? null : t.t;
        payload = v;
      } else {
        d = cs.findIndex(([name]) => name === v?.tag);
        if (d < 0) throw new TypeError(`not a case of the variant: ${v?.tag}`);
        ct = cs[d][1];
        payload = v.val;
      }
      out.push(d);
      const own = [];
      if (ct !== null) lowerFlat(cx, payload, ct, own);
      const have = ct === null ? [] : flatten(ct);
      for (let i = 0; i < joined.length; i++) {
        out.push(i < own.length ? coerceOut(own[i], have[i], joined[i]) : zeroOf(joined[i]));
      }
      return;
    }
    default: throw new Error(`lowerFlat: unknown type ${t.k}`);
  }
}

function liftFlat(cx, it, t) {
  switch (t.k) {
    case "bool": return it.next() !== 0;
    case "u8": return it.next() & 0xff;
    case "u32": case "own": case "borrow": return it.next() >>> 0;
    case "s32": return it.next() | 0;
    case "u64": return BigInt.asUintN(64, it.next());
    case "f64": return it.next();
    case "string": {
      const at = it.next() >>> 0;
      const len = it.next() >>> 0;
      return cx.decodeString(at, len);
    }
    case "list": {
      const at = it.next() >>> 0;
      const len = it.next() >>> 0;
      return loadList(cx, at, len, t.t);
    }
    case "record": {
      const out = {};
      for (const [name, ft] of t.fields) out[name] = liftFlat(cx, it, ft);
      return out;
    }
    case "tuple": return t.ts.map((ft) => liftFlat(cx, it, ft));
    case "enum": {
      const d = it.next() >>> 0;
      const name = t.names[d];
      if (name === undefined) throw new Error(`enum discriminant out of range: ${d}`);
      return name;
    }
    case "option": case "variant": {
      const cs = casesOf(t);
      const joined = flatten(t).slice(1);
      const d = it.next() >>> 0;
      const c = cs[d];
      if (c === undefined) throw new Error(`discriminant out of range: ${d}`);
      const ct = c[1];
      const have = ct === null ? [] : flatten(ct);
      // Every case reads from the same joined slots, so the unused tail has to
      // be consumed whatever this case is.
      const raw = joined.map(() => it.next());
      const val = ct === null
        ? undefined
        : liftFlat(cx, iterate(raw.slice(0, have.length).map((x, i) => coerceIn(x, have[i], joined[i]))), ct);
      if (t.k === "option") return d === 0 ? undefined : val;
      return ct === null ? { tag: c[0] } : { tag: c[0], val };
    }
    default: throw new Error(`liftFlat: unknown type ${t.k}`);
  }
}

const iterate = (arr) => {
  let i = 0;
  return { next: () => arr[i++] };
};

// ---------------------------------------------------------------------------
// the export-side resource table
// ---------------------------------------------------------------------------
//
// `instance` is exported by the component, so the host holds the table: a
// handle is an index the host assigns, a rep is the guest's own pointer. The
// guest turns a rep into a handle through `[resource-new]instance` and the host
// turns a handle back into a rep before every method call — which is why a
// method receives the REP, not the handle.

class ResourceTable {
  constructor() {
    this.entries = new Map(); // handle -> { rep, own }
    this.next = 1; // 0 is never a handle, so a missing one is falsy
    this.free = [];
    this.dtor = null;
  }

  create(rep) {
    const handle = this.free.length ? this.free.pop() : this.next++;
    this.entries.set(handle, { rep, own: true });
    return handle;
  }

  rep(handle) {
    const e = this.entries.get(handle);
    if (!e) throw new TypeError(`not a valid "instance" resource: ${handle}`);
    return e.rep;
  }

  remove(handle) {
    const e = this.entries.get(handle);
    if (!e) throw new TypeError(`not a valid "instance" resource: ${handle}`);
    this.entries.delete(handle);
    this.free.push(handle);
    return e;
  }

  drop(handle) {
    const e = this.remove(handle);
    if (e.own && this.dtor) this.dtor(e.rep);
  }
}

// ---------------------------------------------------------------------------
// binding
// ---------------------------------------------------------------------------

const unversioned = (m) => m.replace(/@[\d.]+$/, "");

// A host may key its implementations with or without the version; `loader.mjs`
// supplies both spellings, jco resolved either, so both work here. The
// versioned fallbacks are tried newest-first and cover the worlds this host
// still accepts, so a harness that keys its table one way keeps working across
// a package bump.
const IMPL_VERSIONS = ["@0.10.0", "@0.9.0"];

function implFor(imports, iface, spec, fnName) {
  const table = imports[iface] ??
    IMPL_VERSIONS.map((v) => imports[`${iface}${v}`]).find(Boolean);
  const fn = table?.[spec.impl];
  if (typeof fn !== "function") {
    throw new Error(`host does not implement ${iface}#${fnName}`);
  }
  return fn;
}

// Wrap a host function as the core function the guest imports: lift the flat
// params, call it, and put the answer back where the caller expects it —
// either as the single flat result, or into the return pointer the caller
// appended to the params.
function lowerImport(cx, spec, fn) {
  const flatParams = spec.params.flatMap(flatten);
  const indirectParams = flatParams.length > MAX_FLAT_PARAMS;
  const flatResults = spec.result === null ? [] : flatten(spec.result);
  const indirectResult = flatResults.length > MAX_FLAT_RESULTS;

  return (...core) => {
    let args;
    if (indirectParams) {
      // The caller stored the params as a tuple in its own memory.
      const ptr = core[0];
      const t = tuple(spec.params);
      args = load(cx, ptr, t);
    } else {
      const it = iterate(core);
      args = spec.params.map((t) => liftFlat(cx, it, t));
    }
    const ret = fn(...args);
    if (spec.result === null) return undefined;
    if (indirectResult) {
      const retptr = core[core.length - 1];
      store(cx, retptr, ret, spec.result);
      return undefined;
    }
    const out = [];
    lowerFlat(cx, ret, spec.result, out);
    return out[0];
  };
}

// Wrap a guest export as a host function: lower the params into guest memory,
// call it, read the answer back, and let the guest free what it returned.
function liftExport(cx, spec, coreFn, postFn) {
  const flatParams = spec.params.flatMap(flatten);
  const indirectParams = flatParams.length > MAX_FLAT_PARAMS;
  const flatResults = spec.result === null ? [] : flatten(spec.result);
  const indirectResult = flatResults.length > MAX_FLAT_RESULTS;

  return (...args) => {
    let core;
    if (indirectParams) {
      const t = tuple(spec.params);
      const ptr = cx.alloc(sizeOf(t), alignment(t));
      store(cx, ptr, args, t);
      core = [ptr];
    } else {
      core = [];
      for (let i = 0; i < spec.params.length; i++) {
        lowerFlat(cx, args[i], spec.params[i], core);
      }
    }
    const ret = coreFn(...core);
    if (spec.result === null) return undefined;
    if (!indirectResult) return liftFlat(cx, iterate([ret]), spec.result);
    const out = load(cx, ret >>> 0, spec.result);
    if (postFn) postFn(ret);
    return out;
  };
}

// ---------------------------------------------------------------------------
// instantiate
// ---------------------------------------------------------------------------

/**
 * Instantiate a `tutuca:component@0.10.0` guest from its core module alone.
 *
 * `getCoreModule(name)` resolves a name to a `WebAssembly.Module` (or a promise
 * of one), exactly as it does for a transpiled bundle. `imports` is the host's
 * implementation of the world, keyed by interface then by camelCase function
 * name — the object `createTcompImports` already builds.
 *
 * `descriptor` is what the archive carries in place of 200KB of JavaScript:
 *
 *   { world: "tutuca:component@0.10.0", encoding: "utf16" | "utf8",
 *     core: "<name>.component.core.wasm" }
 *
 * `policy.grants` is the list of capabilities the host is willing to give this
 * bundle. It is checked against the module's IMPORT SECTION rather than
 * against the manifest, which is the difference between a gate and a promise:
 * a guest chooses what it imports, and cannot choose what that means.
 *
 * The two trampoline modules a transpiled bundle carries are not needed. They
 * exist because jco captures `memory` in its closures at instantiation time and
 * has to break the resulting cycle; every import here reads memory at CALL
 * time, so the main module is the only one instantiated.
 */
export async function instantiate(getCoreModule, imports, descriptor = {}) {
  const { world = "tutuca:component@0.10.0", encoding = "utf16", core } = descriptor;
  if (world !== "tutuca:component@0.10.0") {
    throw new Error(`unsupported world: ${world} (this host implements tutuca:component@0.10.0)`);
  }
  const grants = descriptor.policy?.grants ?? [];

  const module = await getCoreModule(core);
  const cx = new Cx(encoding);
  const table = new ResourceTable();

  // Bind by name against the contract. Anything else is refused HERE, with the
  // name that was asked for, before a single guest instruction runs.
  const importObject = {};
  const bind = (ns, name, fn) => {
    (importObject[ns] ??= {})[name] = fn;
  };

  for (const imp of WebAssembly.Module.imports(module)) {
    if (importObject[imp.module]?.[imp.name]) continue;
    if (imp.module === RESOURCE_NS) {
      if (imp.name === "[resource-new]instance") {
        bind(imp.module, imp.name, (rep) => table.create(rep));
      } else if (imp.name === "[resource-rep]instance") {
        bind(imp.module, imp.name, (handle) => table.rep(handle));
      } else if (imp.name === "[resource-drop]instance") {
        bind(imp.module, imp.name, (handle) => table.drop(handle));
      } else {
        throw new Error(`bundle imports an unknown resource intrinsic: ${imp.name}`);
      }
      continue;
    }
    const iface = unversioned(imp.module);
    const spec = IMPORTS[iface]?.[imp.name];
    if (!spec) {
      throw new Error(
        `bundle imports ${imp.module}#${imp.name}, which is outside ` +
        `tutuca:component@0.10.0 — refused`,
      );
    }
    if (spec.cap && !grants.includes(spec.cap)) {
      throw new Error(
        `bundle imports ${iface}#${imp.name}, which requires ${spec.cap}; ` +
        `this host granted [${grants.join(", ") || "nothing"}] — refused`,
      );
    }
    bind(imp.module, imp.name, lowerImport(cx, spec, implFor(imports, iface, spec, imp.name)));
  }

  const { exports } = await WebAssembly.instantiate(module, importObject);
  cx.memory = exports.memory;
  cx.realloc = exports.cabi_realloc;
  if (!cx.memory || typeof cx.realloc !== "function") {
    throw new Error("core module exports no `memory` / `cabi_realloc`");
  }
  // A bundle built against an older package exports its functions under that
  // package's namespace, so every lookup below would miss and the first one to
  // report would say "core module exports no
  // tutuca:component/guest@0.10.0#[constructor]instance" — which is true and
  // tells nobody what to do. This says what to do.
  //
  // The ABI bump is deliberate and is not backwards compatible: the `bucket`
  // enum renumbered when it lost its three unrouted cases, and `emit` /
  // `bubble-at` / `request` are no longer imports this host provides. A bundle
  // built against an older package would half-work rather than work. Every
  // downstream guest needs a rebuild — see CHANGELOG.
  const older = Object.keys(exports).find(
    (k) => k.startsWith("tutuca:component/guest@") && !k.startsWith(GUEST),
  );
  if (older) {
    const found = older.slice(0, older.indexOf("#"));
    throw new Error(
      `bundle exports ${found}, but this host implements ${GUEST} — ` +
        `rebuild it against the current WIT`,
    );
  }
  table.dtor = exports[`${GUEST}#[dtor]instance`];

  // Null-prototype: one of the export names is `constructor`, and it should
  // mean the guest's constructor rather than Object's.
  const call = Object.create(null);
  for (const [name, spec] of Object.entries(EXPORTS)) {
    const fn = exports[spec.core];
    if (typeof fn !== "function") {
      throw new Error(`core module exports no ${spec.core}`);
    }
    const post = spec.post ? exports[`cabi_post_${spec.core}`] : null;
    if (spec.post && typeof post !== "function") {
      throw new Error(`core module exports no cabi_post_${spec.core}`);
    }
    call[name] = liftExport(cx, spec, fn, post);
  }

  // The host-facing shape, which is the one `createTcompImports` already
  // speaks: a handle wrapped in an object, methods that take the rep.
  const wrap = (handle) => (handle === undefined ? undefined : new Instance(handle));

  class Instance {
    #handle;

    constructor(...args) {
      // `new Instance(component, args)` constructs; the one-argument form is
      // internal, for a handle a guest just returned.
      if (args.length === 1 && typeof args[0] === "number") {
        this.#handle = args[0];
      } else {
        this.#handle = call.constructor(...args);
      }
    }

    static restore(component, state) {
      return wrap(call.restore(component, state));
    }

    get [Symbol.toStringTag]() {
      return "Instance";
    }

    #rep() {
      return table.rep(this.#handle);
    }

    getField(name) {
      return call.getField(this.#rep(), name);
    }

    handleEvent(bucket, name, args) {
      const result = call.handleEvent(this.#rep(), bucket, name, args);
      return result.tag === "changed"
        ? { tag: "changed", val: wrap(result.val) }
        : result;
    }

    callMethod(name, args) {
      return call.callMethod(this.#rep(), name, args);
    }

    withField(name, v) {
      return wrap(call.withField(this.#rep(), name, v));
    }

    persist() {
      return call.persist(this.#rep());
    }

    [symbolDispose]() {
      if (this.#handle === undefined) return;
      const handle = this.#handle;
      this.#handle = undefined;
      table.drop(handle);
    }
  }

  const guest = {
    Instance,
    serveIntent: (name, args) => call.serveIntent(name, args),
  };
  return { guest, [GUEST]: guest };
}

// Exposed for the differential test and for tooling that wants to reason about
// the world without instantiating anything.
export const _abi = {
  alignment, sizeOf, flatten, payloadOffset, discSize,
  WORLD: { IMPORTS, EXPORTS, VALUE, EVENT_RESULT, SERVE_RESULT, PATH_STEP, LOG_LEVEL, INTENT_OPTS, ARGS },
  // The two codecs, so a test can check they agree. They are written
  // independently — one walks linear memory, the other walks flat core values
  // — and a type they disagree about is a type that survives being passed one
  // way and not the other.
  codec: { Cx, store, load, lowerFlat, liftFlat, iterate },
};
