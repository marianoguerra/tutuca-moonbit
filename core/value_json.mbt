// JSON bridge for runtime payloads that cross the language boundary: CustomEvent
// detail objects, file-input metadata (app glue) and structured vdom Data
// props (render).

///|
/// Build a Value from parsed JSON. Total: every JSON shape has a Value.
///
/// It reads the `$`-tagged forms `to_json` writes, so the two are inverses for
/// every arm JSON has no shape of its own for — and an object whose OWN keys
/// include `$` is escaped as `{"$":"map","v":{…}}`, without which the
/// discriminator is ambiguous and a reader has to guess.
///
/// **It is not the inverse on numbers, and that is deliberate.** A plain JSON
/// number decodes to `Num`, because a JSON number IS a double and pretending
/// otherwise past 2^53 would invent precision the input never had. A producer
/// that needs an `Int` back writes the tagged form, which `to_json` always
/// does. CBOR (`tgc/value`) is the encoding without this asymmetry, which is
/// the point of having two.
///
/// One consequence worth naming, since this is also the bridge a DOM
/// `CustomEvent` detail crosses: a page that sends `{"$":"bin","v":"…"}` now
/// gets a `Bin` rather than a two-key map. That is the right answer — it is
/// what the sender wrote — and the three arms it can mint are inert data with
/// no authority of their own.
pub fn Value::from_json(j : Json) -> Value {
  match j {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Num(n)
    String(s) => Str(s)
    Array(items) => List(items.map(i => Value::from_json(i)))
    Object(m) =>
      match m.get("$") {
        Some(String(tag)) => tagged_value(tag, m)
        // A `$` that is not a string is a map that collided with the
        // discriminator and was not escaped — which means it was written by
        // something that does not implement this spelling. Read as data, since
        // a total function has nowhere to put a complaint.
        _ => plain_object(m)
      }
  }
}

///|
fn plain_object(m : Map[String, Json]) -> Value {
  let out : Map[String, Value] = Map([])
  for k, item in m {
    out[k] = Value::from_json(item)
  }
  Map(out)
}

///|
/// A `$`-tagged object. A tag nobody defines, or a payload of the wrong shape,
/// reads as the object it is — this is total, and a map is what it looks like.
fn tagged_value(tag : String, m : Map[String, Json]) -> Value {
  let payload = m.get("v").unwrap_or(Json::null())
  match (tag, payload) {
    ("int", String(text)) =>
      match (try? @string.parse_int64(text)) {
        Ok(i) => Int(i)
        Err(_) => plain_object(m)
      }
    ("int", Number(n, ..)) => Int(n.to_int64())
    ("bin", String(text)) =>
      match (try? @base64.decode(text[:])) {
        Ok(b) => Bin(b)
        Err(_) => plain_object(m)
      }
    ("instant", String(text)) =>
      match (try? instant_of_rfc3339(text)) {
        Ok((secs, nanos)) => Instant(secs~, nanos~)
        Err(_) => plain_object(m)
      }
    // The escape, read back: whatever is inside is an ordinary map, including
    // one whose own keys start with the discriminator.
    ("map", Object(inner)) => plain_object(inner)
    _ => plain_object(m)
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
    // The three arms JSON has no shape for take the format's `$`-tagged
    // spelling, which is what `tgc/value` writes and what a browser reads back.
    // A plain JSON number for an `Int` would stop being itself past 2^53, which
    // is the whole reason the arm exists.
    Int(i) => tagged_json("int", Json::string(i.to_string()))
    Bin(b) => tagged_json("bin", Json::string(base64(b)))
    Instant(secs~, nanos~) =>
      tagged_json("instant", Json::string(instant_text(secs, nanos)))
    List(items) => Json::array(items.map(i => i.to_json()))
    Map(m) => {
      let obj : Map[String, Json] = Map([])
      for k, item in m {
        obj[k] = item.to_json()
      }
      // The ESCAPE. A map that carries the discriminator as data is written
      // under the discriminator, so reading one back is never a guess.
      if obj.contains("$") {
        tagged_json("map", Json::object(obj))
      } else {
        Json::object(obj)
      }
    }
    Obj(o) =>
      match o.schema() {
        Some(schema) => {
          let obj : Map[String, Json] = Map([])
          for f in schema.fields {
            obj[f.name] = match o.field(f.name) {
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
