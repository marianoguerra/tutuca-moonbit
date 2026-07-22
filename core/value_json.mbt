// JSON bridge for runtime payloads that cross the JS boundary: CustomEvent
// detail objects, file-input metadata (app glue) and structured vdom Data
// props (render). JS gets this for free — the event payload IS a JS value.

///|
/// Build a Value from parsed JSON. Lossless: every JSON shape has a Value.
pub fn Value::from_json(j : Json) -> Value {
  match j {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Num(n)
    String(s) => Str(s)
    Array(items) => List(items.map(i => Value::from_json(i)))
    Object(m) => {
      let out : Map[String, Value] = Map([])
      for k, item in m {
        out[k] = Value::from_json(item)
      }
      Map(out)
    }
  }
}

///|
/// Stash for lossless Obj/Fn round-trips through the ToJson/FromJson trait
/// impls: active only inside with_value_stash (typed-state encode/decode).
/// Inactive (None) keeps the plain semantics: Obj/Fn degrade to null.
let value_stash : Ref[Array[Value]?] = { val: None }

///|
/// Marker key for stashed values; NUL bytes keep it out of real data.
const STASH_KEY = "\u{0}tutuca-ref\u{0}"

///|
/// Run `f` with an active Value stash: within it, the ToJson/FromJson trait
/// impls for Value carry Obj/Fn values through Json losslessly (encoded as
/// `{STASH_KEY: index}` markers into a side array). Strictly synchronous;
/// nesting saves and restores the outer stash.
pub fn[T] with_value_stash(f : () -> T) -> T {
  let saved = value_stash.val
  value_stash.val = Some([])
  let r = f()
  value_stash.val = saved
  r
}

///|
fn stash_to_json(v : Value, stash : Array[Value]) -> Json {
  match v {
    Fn(_) | Obj(_) => {
      stash.push(v)
      let marker : Map[String, Json] = Map([])
      marker[STASH_KEY] = Json::number((stash.length() - 1).to_double())
      Json::object(marker)
    }
    List(items) => Json::array(items.map(i => stash_to_json(i, stash)))
    Map(m) => {
      let obj : Map[String, Json] = Map([])
      for k, item in m {
        obj[k] = stash_to_json(item, stash)
      }
      Json::object(obj)
    }
    _ => v.to_json()
  }
}

///|
fn stash_from_json(j : Json, stash : Array[Value]) -> Value {
  match j {
    Object(m) =>
      match m.get(STASH_KEY) {
        Some(Number(n, ..)) if n.to_int() >= 0 && n.to_int() < stash.length() =>
          stash[n.to_int()]
        _ => {
          let out : Map[String, Value] = Map([])
          for k, item in m {
            out[k] = stash_from_json(item, stash)
          }
          Map(out)
        }
      }
    Array(items) => List(items.map(i => stash_from_json(i, stash)))
    _ => Value::from_json(j)
  }
}

///|
/// Trait form of Value::to_json, stash-aware: lets `derive(ToJson)` state
/// structs hold Value fields (see with_value_stash).
pub impl ToJson for Value with fn to_json(self) {
  match value_stash.val {
    Some(stash) => stash_to_json(self, stash)
    None => self.to_json()
  }
}

///|
/// Trait form of Value::from_json, stash-aware and total (never raises).
pub impl @json.FromJson for Value with fn from_json(j, _path) {
  match value_stash.val {
    Some(stash) => stash_from_json(j, stash)
    None => Value::from_json(j)
  }
}

///|
/// Json shape of a Value. `Fn`/`Obj` have no JSON form and become null (JS
/// structured clone would throw on a function too).
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Num(n) => Json::number(n)
    Str(s) => Json::string(s)
    List(items) => Json::array(items.map(i => i.to_json()))
    Map(m) => {
      let obj : Map[String, Json] = Map([])
      for k, item in m {
        obj[k] = item.to_json()
      }
      Json::object(obj)
    }
    Fn(_) | Obj(_) => Json::null()
  }
}
