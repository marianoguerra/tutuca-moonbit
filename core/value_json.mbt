// JSON bridge for runtime payloads that cross the JS boundary: CustomEvent
// detail objects, file-input metadata (app glue) and structured vdom Data
// props (render). JS gets this for free — the event payload IS a JS value.
//
// It used to carry a second job: a process-global STASH, active inside
// `with_value_stash`, that smuggled `Obj` and `Fn` values through a JSON round
// trip as `{"\u{0}tutuca-ref\u{0}": index}` markers into a side array. That
// existed for exactly one caller — the typed-state bridge, `S -> Json -> Value`
// and back, which a component with no generated codec fell back to. Every
// component has a codec now, so the caller is gone and so is the stash, along
// with the global mutable it needed and the "strictly synchronous" caveat that
// came with it.

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
/// is what makes a state dump JSON rather than a debug string. It used to
/// flatten to null along with `Fn`, because nothing could enumerate an `Obj`;
/// the consequence was a `state_json()` that returned the `Show` rendering and
/// said so in a comment, and a dyncomp migration path that parsed a
/// `__dyncomp_state_json` pseudo-field instead.
///
/// An instance that declares nothing is still null: with no schema there is
/// no field list to project, and inventing one is what the schema work
/// removed. `Fn` stays null unconditionally (JS structured clone would throw
/// on a function too), so a method or an unrendered handler inside a described
/// instance projects as null rather than taking the whole object with it.
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
