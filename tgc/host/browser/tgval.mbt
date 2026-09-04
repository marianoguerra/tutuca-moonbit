///| `core.Value` <-> `tg_val`, directly.
///
/// The JSON codec this replaces is still correct and still shipped — it is what
/// a JS host needs, and `tgc/SPEC.md` §8 describes it. What it is not is the
/// shortest path between a MoonBit host and a `tg_val`, and three of its costs
/// were paid on every render: base64 for a byte string, an RFC-3339 spelling
/// for an instant that two implementations had to agree on character for
/// character, and a `{"$":"map"}` escape for a map whose key happens to be `$`.
/// None of those exist here, because none of them are about VALUES — they are
/// about JSON not having a shape for one.

///|
/// The tags, as `tgc/SPEC.md` §3 numbers them.
const TAG_NULL = 0

///|
const TAG_BOOL = 1

///|
const TAG_NUM = 2

///|
const TAG_INT = 3

///|
const TAG_STR = 4

///|
const TAG_BIN = 5

///|
const TAG_INSTANT = 6

///|
const TAG_LIST = 7

///|
const TAG_MAP = 8

///|
const TAG_FUNC = 9

///|
const TAG_COMP = 10

///|
const TAG_EXT = 11

///|
/// A value the host could not read, said once rather than swallowed.
///
/// `tg_func` and `tg_ext` are in the frozen rec group and the runtime exports
/// no accessor for either — no `as_func`, no `ext_kind`. The JSON codec turned
/// both into the null VALUE, which SPEC §9 is emphatic is a different thing
/// from "no answer": one says the field holds nothing, the other says nobody
/// answered. Turning "I cannot read this" into "it is null" is the quieter of
/// the two lies and the worse one.
let unread : Ref[Array[String]] = Ref([])

///|
/// Whatever this codec could not read since it was last asked.
pub fn take_unread() -> Array[String] {
  let out = unread.val
  unread.val = []
  out
}

///|
fn cannot_read(what : String) -> Unit {
  unread.val.push(
    "a " +
    what +
    " crossed the host boundary; `tgc/rt/rt.wax` exports no accessor for one — add one there before a host can read it",
  )
}

///|
/// A decimal `i64`, parsed. `0` for text that is not one, which the runtime
/// cannot produce — `String(BigInt)` is always decimal.
fn i64_of_text(s : String) -> Int64 {
  @string.parse_int64(s) catch {
    _ => 0L
  }
}

///|
/// A `tg_val` as a `core.Value`.
///
/// `None` is `ref.null` — NO ANSWER — and `Some(Null)` is the null value. The
/// two are different and the format says so loudly; this is the one place a
/// host could quietly merge them.
pub fn value_of(
  rt : @core.Any,
  v : @core.Any,
  own : (@core.Any) -> @tutuca.Value?,
) -> @tutuca.Value? {
  if is_absent(v) {
    return None
  }
  match as_int(rt1(rt, "kind_of", v)) {
    TAG_NULL => Some(Null)
    TAG_BOOL => Some(Bool(as_int(rt1(rt, "as_bool", v)) != 0))
    TAG_NUM => Some(Num(as_double(rt1(rt, "as_num", v))))
    TAG_INT => Some(Int(i64_of_text(i64_text(rt1(rt, "as_int", v)))))
    TAG_STR => Some(Str(text_of(rt, rt1(rt, "as_str", v))))
    TAG_BIN => Some(Bin(blob_of(rt, rt1(rt, "as_bin", v))))
    TAG_INSTANT => {
      let secs = i64_of_text(i64_text(rt1(rt, "instant_secs", v)))
      Some(Instant(secs~, nanos=as_int(rt1(rt, "instant_nanos", v))))
    }
    TAG_LIST => {
      let n = as_int(rt1(rt, "list_len", v))
      let out : Array[@tutuca.Value] = []
      for i in 0..<n {
        out.push(
          value_of(rt, rt2(rt, "list_at", v, of_int(i)), own).unwrap_or(Null),
        )
      }
      Some(List(out))
    }
    TAG_MAP => {
      let n = as_int(rt1(rt, "map_len", v))
      let out : Map[String, @tutuca.Value] = Map([])
      for i in 0..<n {
        let key = text_of(rt, rt2(rt, "map_key", v, of_int(i)))
        out[key] = value_of(rt, rt2(rt, "map_val", v, of_int(i)), own).unwrap_or(
          Null,
        )
      }
      Some(Map(out))
    }
    // The arm this package exists for. `own` is the host's — it knows which
    // MODULE made this instance and therefore which schema and which views to
    // wrap it with, and getting that wrong is how a note comes back wearing a
    // hole's clothes.
    TAG_COMP => own(rt1(rt, "as_inst", v))
    TAG_FUNC => {
      cannot_read("tg_func")
      None
    }
    TAG_EXT => {
      cannot_read("tg_ext")
      None
    }
    other => {
      cannot_read("tg_val of kind \{other}")
      None
    }
  }
}

///|
/// A `core.Value` as a `tg_val`.
///
/// `hand` turns a host-held instance back into the `tg_inst` it came from, and
/// answers `None` for an `Obj` that is not one — a host component, which no
/// guest could have handed over and none can be handed.
pub fn val_of(
  rt : @core.Any,
  v : @tutuca.Value,
  hand : (@tutuca.Value) -> @core.Any?,
) -> @core.Any {
  match v {
    Null => rt0(rt, "mk_null")
    Bool(b) => rt1(rt, "mk_bool", of_int(if b { 1 } else { 0 }))
    Num(n) => rt1(rt, "mk_num", of_double(n))
    Int(n) => of_i64_text(rt, "mk_int", n.to_string())
    Str(s) => rt1(rt, "mk_str", bytes_of_text(rt, s))
    Bin(b) => rt1(rt, "mk_bin", bytes_of_blob(rt, b))
    Instant(secs~, nanos~) => mk_instant(rt, secs.to_string(), nanos)
    List(items) => {
      let a = rt1(rt, "vals_new", of_int(items.length()))
      for i, item in items {
        rt3(rt, "vals_set", a, of_int(i), val_of(rt, item, hand)) |> ignore
      }
      rt1(rt, "mk_list", a)
    }
    Map(entries) => {
      let keys = entries.keys().to_array()
      let a = rt1(rt, "entries_new", of_int(keys.length()))
      for i, k in keys {
        rt4(
          rt,
          "entries_set",
          a,
          of_int(i),
          bytes_of_text(rt, k),
          val_of(rt, entries.get(k).unwrap(), hand),
        )
        |> ignore
      }
      rt1(rt, "mk_map", a)
    }
    Obj(_) =>
      match hand(v) {
        Some(inst) => rt1(rt, "mk_comp", inst)
        // A host component. There is nothing to hand over — it has no `tg_val`
        // form at all — so it crosses as nothing, and `slot_owner` is what
        // makes sure it never has to.
        None => rt0(rt, "mk_null")
      }
    // A closure. The runtime has no constructor for one and a card cannot
    // receive one, so this is unreachable rather than unsupported.
    Fn(_) => rt0(rt, "mk_null")
  }
}

///|
/// `args`, as the `tg_vals` a call takes.
pub fn vals_of(
  rt : @core.Any,
  args : Array[@tutuca.Value],
  hand : (@tutuca.Value) -> @core.Any?,
) -> @core.Any {
  let a = rt1(rt, "vals_new", of_int(args.length()))
  for i, v in args {
    rt3(rt, "vals_set", a, of_int(i), val_of(rt, v, hand)) |> ignore
  }
  a
}
