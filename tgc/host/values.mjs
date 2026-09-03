// `core.Value` JSON <-> `tg_val`, over the runtime module's accessors.
//
// ONE copy, imported by everything that crosses this boundary. A second
// hand-kept spelling of a value's JSON is a second answer to what a value IS,
// which the format spent a whole release removing.
//
// JavaScript cannot do struct accesses, so it asks `tut`. A wasm module needs
// none of this — a value is a reference and reading one is a `struct.get` —
// which is why the runtime is a module rather than a JS object: the accessors
// below are the seam, and they are the same seam a page uses.
//
// The JSON is `core.Value`'s own: `$`-tagged for the three arms JSON has no
// shape for, with the `{"$":"map"}` escape for a map that carries the
// discriminator as data. `Value::to_json` and `Value::from_json` are the other
// end of it, and the two have to agree exactly or a field written by MoonBit
// reads back as something else in wasm.

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

const enc = new TextEncoder();
const dec = new TextDecoder();

const b64encode = (u8) => {
  let s = "";
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s);
};
const b64decode = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

/** Everything a host needs to read and build values, bound to one runtime. */
export function makeValues(rt) {
  const bytes = (s) => {
    const u8 = enc.encode(s);
    const b = rt.bytes_new(u8.length);
    for (let i = 0; i < u8.length; i++) rt.bytes_set(b, i, u8[i]);
    return b;
  };

  const readBytes = (b) => {
    const n = rt.bytes_len(b);
    const u8 = new Uint8Array(n);
    for (let i = 0; i < n; i++) u8[i] = rt.bytes_at(b, i);
    return u8;
  };

  const text = (b) => dec.decode(readBytes(b));

  /**
   * A `tg_val` as `core.Value`'s JSON.
   *
   * `undefined` for `ref.null` and `null` for the null VALUE — the distinction
   * the format keeps, carried across in the one spelling JS already has for it.
   */
  const toJson = (v) => {
    if (v === null) return undefined;
    switch (rt.kind_of(v)) {
      case TAG.NULL: return null;
      case TAG.BOOL: return rt.as_bool(v) !== 0;
      case TAG.NUM: return rt.as_num(v);
      case TAG.INT: return { $: "int", v: String(rt.as_int(v)) };
      case TAG.STR: return text(rt.as_str(v));
      case TAG.BIN: return { $: "bin", v: b64encode(readBytes(rt.as_bin(v))) };
      case TAG.INSTANT:
        return { $: "instant", v: instantText(rt.instant_secs(v), rt.instant_nanos(v)) };
      case TAG.LIST: {
        const out = [];
        for (let i = 0; i < rt.list_len(v); i++) out.push(toJson(rt.list_at(v, i)));
        return out;
      }
      case TAG.MAP: {
        const out = {};
        for (let i = 0; i < rt.map_len(v); i++) {
          out[text(rt.map_key(v, i))] = toJson(rt.map_val(v, i));
        }
        // The escape: a map that carries the discriminator as data is written
        // under it, so reading one back is never a guess.
        return "$" in out ? { $: "map", v: out } : out;
      }
      // A component crossing as JSON is a component leaving its reference
      // behind. Nothing here can rebuild one, so it says what it was.
      case TAG.COMP: return { $: "comp", v: {} };
      default: return null;
    }
  };

  const ofJson = (j) => {
    if (j === undefined || j === null) return rt.mk_null();
    if (typeof j === "boolean") return rt.mk_bool(j ? 1 : 0);
    if (typeof j === "number") return rt.mk_num(j);
    if (typeof j === "string") return rt.mk_str(bytes(j));
    if (Array.isArray(j)) {
      const a = rt.vals_new(j.length);
      j.forEach((x, i) => rt.vals_set(a, i, ofJson(x)));
      return rt.mk_list(a);
    }
    const tag = j["$"];
    if (tag === "map") return ofJson(j.v);
    if (tag === "int") return rt.mk_int(BigInt(j.v));
    if (tag === "bin") {
      const u8 = b64decode(j.v);
      const b = rt.bytes_new(u8.length);
      for (let i = 0; i < u8.length; i++) rt.bytes_set(b, i, u8[i]);
      return rt.mk_bin(b);
    }
    if (tag === "instant") {
      const [secs, nanos] = instantParts(j.v);
      return rt.mk_instant(secs, nanos);
    }
    // An unknown tag, or none: it is a map, which is what it looks like.
    const keys = Object.keys(j);
    const a = rt.entries_new(keys.length);
    keys.forEach((k, i) => rt.entries_set(a, i, bytes(k), ofJson(j[k])));
    return rt.mk_map(a);
  };

  const vals = (list) => {
    const a = rt.vals_new(list.length);
    list.forEach((v, i) => rt.vals_set(a, i, v));
    return a;
  };

  return { bytes, readBytes, text, toJson, ofJson, vals };
}

/**
 * RFC 3339, always UTC, sub-second digits in groups of three.
 *
 * The same rule `core/instant.mbt` follows, because the two ends of this
 * boundary have to spell an instant the same way or a field written by one
 * reads back as a different moment in the other.
 */
export function instantText(secs, nanos) {
  const ms = Number(secs) * 1000;
  const base = new Date(ms).toISOString().slice(0, 19);
  if (nanos === 0) return `${base}Z`;
  const nine = String(nanos).padStart(9, "0");
  const keep = nanos % 1_000_000 === 0 ? 3 : nanos % 1000 === 0 ? 6 : 9;
  return `${base}.${nine.slice(0, keep)}Z`;
}

/** The reverse, as the `[secs, nanos]` pair the wire carries. */
export function instantParts(textValue) {
  const m = /^(\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|z|[+-]\d{2}:\d{2})$/
    .exec(textValue);
  if (!m) throw new Error(`not an RFC 3339 timestamp: ${textValue}`);
  const [, stamp, frac, zone] = m;
  const offset = zone === "Z" || zone === "z"
    ? 0
    : (zone[0] === "-" ? -1 : 1) *
      (Number(zone.slice(1, 3)) * 3600 + Number(zone.slice(4, 6)) * 60);
  const secs = BigInt(Math.floor(Date.parse(`${stamp}Z`) / 1000)) - BigInt(offset);
  const nanos = frac ? Number(frac.padEnd(9, "0").slice(0, 9)) : 0;
  return [secs, nanos];
}
