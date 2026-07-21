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
