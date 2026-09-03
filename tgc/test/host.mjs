// The host, in about a hundred lines.
//
// That is the number worth looking at. Loading a component is
// `WebAssembly.instantiate` with one import object: no archive to unpack, no
// manifest file to fetch beside it, no value arena, no instance table, no
// `cabi_post_*`, and nothing to transpile. A module says what it is
// (`tgc.describe`), and what it hands back is an ordinary reference this file
// can hold and pass to somebody else's module.
//
// The read/build helpers exist for JAVASCRIPT, not for the format. A wasm
// module needs none of them — a value is a reference and reading one is a
// struct access — but JS cannot do struct accesses, so it asks `rt.wasm`. That
// is the same seam a browser page would use.
import { readFileSync } from "node:fs";
import { buildAll } from "./build.mjs";

export const TAG = {
  NULL: 0, BOOL: 1, NUM: 2, INT: 3, STR: 4, BIN: 5,
  INSTANT: 6, LIST: 7, MAP: 8, FUNC: 9, COMP: 10, EXT: 11,
};

export const OP = {
  WITH_FIELD: 1, HANDLE_MESSAGE: 2, HANDLE_INTENT: 3, COMPUTE: 4, WHEN: 5,
  ENRICH: 6, ENRICH_SCOPE: 7, GET_PROPERTY: 8, SET_PROPERTY: 9,
  SEQ_ENTRIES: 10, IMPLEMENTS: 11, PERSIST: 12, RESTORE: 13, IDENTITY: 14,
  DEBUG: 15,
};

/**
 * Load every prototype module against ONE import object.
 *
 * `tut` comes from `rt.wasm`, a core module carrying the same preamble, so the
 * import link is itself a structural type check over the frozen group. A JS
 * shim would have accepted anything; this does not.
 */
export async function loadAll() {
  const built = buildAll();
  const rt = (await WebAssembly.instantiate(readFileSync(built.rt), {})).instance;
  const x = rt.exports;
  // The WHOLE runtime is `tut`. A generated module reaches for the value
  // vocabulary as well as the two composition calls, and a host that exposed
  // only some of it would decide by omission what a card may do.
  const tut = { ...x };
  const modules = {};
  for (const [name, path] of Object.entries(built)) {
    if (name === "rt") continue;
    const { instance } = await WebAssembly.instantiate(readFileSync(path), { tut });
    modules[name] = instance.exports;
  }
  return { rt: x, tut, modules, built, host: makeHost(x) };
}

/** Everything every loaded module declares, keyed by component name. */
export function catalog({ modules, host }) {
  const out = new Map();
  for (const [file, ex] of Object.entries(modules)) {
    const desc = host.toJs(ex["tgc.describe"]());
    out.set(desc.name, {
      file,
      module: desc.module,
      protocols: desc.protocols,
      make: (args) => ex["tgc.make"](host.bytes(desc.name), args ?? null),
      exports: ex,
    });
  }
  return out;
}

/**
 * Find a component by PROTOCOL rather than by name.
 *
 * The whole of what replaces `ComponentStack`'s flat `by_name` and the
 * registry's "most recently loaded wins": a slot declares an id, and any module
 * that declares the same id can fill it. Two authors who never met agree because
 * they read the same protocol, not because they picked the same word.
 */
export function implementing(cat, protocolId) {
  return [...cat.values()].filter((c) => c.protocols.includes(protocolId));
}

function makeHost(x) {
  const enc = new TextEncoder();
  const dec = new TextDecoder();

  const bytes = (s) => {
    const u8 = enc.encode(s);
    const b = x.bytes_new(u8.length);
    for (let i = 0; i < u8.length; i++) x.bytes_set(b, i, u8[i]);
    return b;
  };

  const readBytes = (b) => {
    const n = x.bytes_len(b);
    const u8 = new Uint8Array(n);
    for (let i = 0; i < n; i++) u8[i] = x.bytes_at(b, i);
    return u8;
  };

  /** A `tg_val` as plain JS, for a test to assert on. */
  const toJs = (v) => {
    if (v === null) return undefined; // absence, not null-the-value
    switch (x.kind_of(v)) {
      case TAG.NULL: return null;
      case TAG.BOOL: return x.as_bool(v) !== 0;
      case TAG.NUM: return x.as_num(v);
      case TAG.INT: return x.as_int(v);
      case TAG.STR: return dec.decode(readBytes(x.as_str(v)));
      case TAG.BIN: return readBytes(x.as_bin(v));
      case TAG.INSTANT:
        return { secs: x.instant_secs(v), nanos: x.instant_nanos(v) };
      case TAG.LIST: {
        const out = [];
        for (let i = 0; i < x.list_len(v); i++) out.push(toJs(x.list_at(v, i)));
        return out;
      }
      case TAG.MAP: {
        const out = {};
        for (let i = 0; i < x.map_len(v); i++) {
          out[dec.decode(readBytes(x.map_key(v, i)))] = toJs(x.map_val(v, i));
        }
        return out;
      }
      // A component stays a REFERENCE. Flattening it here would be the thing
      // the old format had to do and the thing this one exists not to do.
      case TAG.COMP: return { inst: x.as_inst(v) };
      default: return { opaque: x.kind_of(v) };
    }
  };

  const list = (items) => {
    const a = x.vals_new(items.length);
    items.forEach((v, i) => x.vals_set(a, i, v));
    return x.mk_list(a);
  };

  const map = (obj) => {
    const keys = Object.keys(obj);
    const a = x.entries_new(keys.length);
    keys.forEach((k, i) => x.entries_set(a, i, bytes(k), obj[k]));
    return x.mk_map(a);
  };

  /** A `tg_bytes` as a JS string. */
  const text = (b) => dec.decode(readBytes(b));

  /** The format's `$`-tagged JSON, built into the module's value world. */
  const ofJson = (j) => {
    if (j === null) return x.mk_null();
    if (typeof j === "boolean") return x.mk_bool(j ? 1 : 0);
    if (typeof j === "number") return x.mk_num(j);
    if (typeof j === "string") return x.mk_str(bytes(j));
    if (Array.isArray(j)) return list(j.map(ofJson));
    const tag = j["$"];
    if (tag === undefined) {
      const a = x.entries_new(Object.keys(j).length);
      Object.keys(j).forEach((k, i) => x.entries_set(a, i, bytes(k), ofJson(j[k])));
      return x.mk_map(a);
    }
    if (tag === "map") return ofJson(j.v);
    if (tag === "int") return x.mk_int(BigInt(j.v));
    if (tag === "bin") return x.mk_bin(bytes(atob(j.v)));
    throw new Error(`no such tagged type ${tag}`);
  };

  /** The reverse: a `tg_val` as the format's `$`-tagged JSON. */
  const toJson = (v) => {
    if (v === null) return undefined;
    switch (x.kind_of(v)) {
      case TAG.NULL: return null;
      case TAG.BOOL: return x.as_bool(v) !== 0;
      case TAG.NUM: return x.as_num(v);
      case TAG.INT: return { $: "int", v: String(x.as_int(v)) };
      case TAG.STR: return text(x.as_str(v));
      case TAG.LIST: {
        const out = [];
        for (let i = 0; i < x.list_len(v); i++) out.push(toJson(x.list_at(v, i)));
        return out;
      }
      case TAG.MAP: {
        const out = {};
        for (let i = 0; i < x.map_len(v); i++) out[text(x.map_key(v, i))] = toJson(x.map_val(v, i));
        return out;
      }
      default: return { opaque: x.kind_of(v) };
    }
  };

  return {
    bytes, readBytes, text, toJs, toJson, ofJson, list, map,
    int: x.mk_int, str: (s) => x.mk_str(bytes(s)), comp: x.mk_comp,
    // Read a field of an instance. One call, no host in the path when a module
    // does it — this is here only because JS is not a module.
    get: (inst, name) => toJs(x.get_field(inst, bytes(name))),
    getRaw: (inst, name) => x.get_field(inst, bytes(name)),
    call: (inst, op, name, args = [], v = null) => {
      const a = x.vals_new(args.length);
      args.forEach((val, i) => x.vals_set(a, i, val));
      return x.call_op(inst, op, bytes(name), a, v);
    },
    /** A successor, unwrapped: a transition answers `comp(next)` or nothing. */
    successor: (answer) => (answer === null ? null : x.as_inst(answer)),
    id: x.inst_id,
    /** Does this instance claim the protocol? Asked of IT, not of a registry. */
    implementsId(inst, id) {
      const a = x.vals_new(0);
      const answer = x.call_op(inst, OP.IMPLEMENTS, bytes(id), a, null);
      return answer !== null && x.as_bool(answer) !== 0;
    },
  };
}
