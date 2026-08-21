// JSON bridge for runtime payloads that cross the language boundary: CustomEvent
// detail objects, file-input metadata (app glue) and structured vdom Data
// props (render).

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
/// Trait form of Value::to_json. `Obj` and `Fn` degrade to null: JSON has no
/// shape for either, which is why the state codec is written field by field
/// rather than routed through here.
pub impl ToJson for Value with fn to_json(self) {
  self.to_json()
}

///|
/// Trait form of Value::from_json, total (never raises).
pub impl @json.FromJson for Value with fn from_json(j, _path) {
  Value::from_json(j)
}

///|
/// Json shape of a Value.
///
/// A DESCRIBED instance projects to its declared fields, recursively — which
/// is what makes a state dump JSON rather than a debug string.
///
/// An instance that declares nothing is still null: with no schema there is
/// no field list to project, and inventing one is what the schema work
/// removed. `Fn` stays null unconditionally, so a method or an unrendered
/// handler inside a described instance projects as null rather than taking
/// the whole object with it.
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
    Obj(o) =>
      match o.obj_schema() {
        Some(schema) => {
          let obj : Map[String, Json] = Map([])
          for f in schema.fields {
            obj[f.name] = match o.obj_field(f.name) {
              Some(v) => v.to_json()
              None => Json::null()
            }
          }
          Json::object(obj)
        }
        None => Json::null()
      }
    Fn(_) => Json::null()
  }
}
