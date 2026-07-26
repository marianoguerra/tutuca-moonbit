// The state <-> Value bridge: the JSON round trip the runtime uses today,
// against the direct codec a schema could generate.
//
//   node benchmarks/report.mjs --file codec_bench_test.mbt
//
// Why this measurement decides something. `encode_state` / `decode_state`
// (component/instance.mbt) run once per state write, and they go through
// `Json`: S -> Json -> Value on the way in, and back on the way out, both
// inside `with_value_stash` because `Obj` and `Fn` cannot survive JSON at
// all. With a declared schema the conversion can be written field by field
// with no `Json` in between and no stash for the fields that already hold a
// `Value`.
//
// Generating that means a SECOND encoder to keep in step with the derived
// one, so it is worth having only if it is meaningfully faster. This is the
// A/B that answers it, on the shape the corpus actually has: scalars, a list
// and a dynamic field.

///|
/// A state of the shape the migrated corpus is full of.
priv struct BenchState {
  label : String
  count : Int
  ratio : Double
  active : Bool
  history : Array[Int]
  detail : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn bench_state(n : Int) -> BenchState {
  let history = []
  for i in 0..<n {
    history.push(i)
  }
  {
    label: "a label of ordinary length",
    count: 42,
    ratio: 0.5,
    active: true,
    history,
    detail: Str("dynamic"),
  }
}

///|
/// TODAY: the derived-JSON path, exactly as component/instance.mbt runs it.
fn json_encode(s : BenchState) -> Map[String, @tutuca.Value] {
  @tutuca.with_value_stash(() => {
    match ToJson::to_json(s) {
      Object(m) => {
        let out : Map[String, @tutuca.Value] = Map([])
        for k, jv in m {
          out[k] = @json.from_json(jv) catch { _ => @tutuca.Null }
        }
        out
      }
      _ => Map([])
    }
  })
}

///|
fn json_decode(fields : Map[String, @tutuca.Value]) -> BenchState? {
  @tutuca.with_value_stash(() => {
    let obj : Map[String, Json] = Map([])
    for name in ["label", "count", "ratio", "active", "history", "detail"] {
      obj[name] = ToJson::to_json(fields.get(name).unwrap_or(@tutuca.Null))
    }
    Some(@json.from_json(Json::object(obj))) catch {
      _ => None
    }
  })
}

///|
/// PROPOSED: what a schema would generate — field by field, no `Json`, and
/// no stash, because the one dynamic field never leaves the Value world.
fn direct_encode(s : BenchState) -> Map[String, @tutuca.Value] {
  let history : Array[@tutuca.Value] = []
  for x in s.history {
    history.push(@tutuca.Num(x.to_double()))
  }
  {
    "label": @tutuca.Str(s.label),
    "count": @tutuca.Num(s.count.to_double()),
    "ratio": @tutuca.Num(s.ratio),
    "active": @tutuca.Bool(s.active),
    "history": @tutuca.List(history),
    "detail": s.detail,
  }
}

///|
fn direct_decode(f : Map[String, @tutuca.Value]) -> BenchState? {
  guard f.get("label") is Some(Str(label)) else { return None }
  guard f.get("count") is Some(Num(count)) else { return None }
  guard f.get("ratio") is Some(Num(ratio)) else { return None }
  guard f.get("active") is Some(Bool(active)) else { return None }
  guard f.get("history") is Some(List(hs)) else { return None }
  let history : Array[Int] = []
  for x in hs {
    guard x is Num(n) else { return None }
    history.push(n.to_int())
  }
  Some({
    label,
    count: count.to_int(),
    ratio,
    active,
    history,
    detail: f.get("detail").unwrap_or(@tutuca.Null),
  })
}

///|
let s0 : BenchState = bench_state(0)

///|
let s16 : BenchState = bench_state(16)

///|
let s256 : BenchState = bench_state(256)

///|
let f16 : Map[String, @tutuca.Value] = json_encode(s16)

///|
let f256 : Map[String, @tutuca.Value] = json_encode(s256)

///|
test "codec/json encode 0" (b : @bench.T) {
  b.bench(() => json_encode(s0) |> ignore)
}

///|
test "codec/direct encode 0" (b : @bench.T) {
  b.bench(() => direct_encode(s0) |> ignore)
}

///|
test "codec/json encode 16" (b : @bench.T) {
  b.bench(() => json_encode(s16) |> ignore)
}

///|
test "codec/direct encode 16" (b : @bench.T) {
  b.bench(() => direct_encode(s16) |> ignore)
}

///|
test "codec/json encode 256" (b : @bench.T) {
  b.bench(() => json_encode(s256) |> ignore)
}

///|
test "codec/direct encode 256" (b : @bench.T) {
  b.bench(() => direct_encode(s256) |> ignore)
}

///|
test "codec/json decode 16" (b : @bench.T) {
  b.bench(() => json_decode(f16) |> ignore)
}

///|
test "codec/direct decode 16" (b : @bench.T) {
  b.bench(() => direct_decode(f16) |> ignore)
}

///|
test "codec/json decode 256" (b : @bench.T) {
  b.bench(() => json_decode(f256) |> ignore)
}

///|
test "codec/direct decode 256" (b : @bench.T) {
  b.bench(() => direct_decode(f256) |> ignore)
}

///|
/// The two must agree, or the comparison above measures nothing. `detail`
/// is the interesting field: it holds a plain `Str` here so the JSON path
/// can carry it at all, and the point is that the direct path never has to.
test "the two codecs agree" {
  for s in [s0, s16, s256] {
    let a = json_encode(s)
    let b = direct_encode(s)
    assert_eq(a.length(), b.length())
    for k, v in a {
      assert_eq(v.to_display_string(), b.get(k).unwrap().to_display_string())
    }
    guard json_decode(b) is Some(ja) && direct_decode(a) is Some(da)
    assert_eq(ja.label, da.label)
    assert_eq(ja.count, da.count)
    assert_eq(ja.history, da.history)
    assert_eq(ja.detail.to_display_string(), da.detail.to_display_string())
  }
}
