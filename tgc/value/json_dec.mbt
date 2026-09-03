// JSON decoding.
//
// Not the inverse of `to_json` on numbers, and the asymmetry is stated rather
// than papered over: a plain JSON number decodes to `TNum`, because a JSON
// number IS a double and pretending otherwise past 2^53 would invent precision
// the input never had. A producer that needs a `TInt` back writes the tagged
// form, which `to_json` always does.
//
// CBOR is the encoding without this asymmetry. Which is the point of having two.

///|
pub fn of_json(j : Json) -> TVal raise CodecError {
  dec_json(j, "")
}

///|
fn dec_json(j : Json, at : String) -> TVal raise CodecError {
  match j {
    Null => TNull
    True => TBool(true)
    False => TBool(false)
    Number(n, ..) => TNum(n)
    String(s) => TStr(s)
    Array(items) => {
      let out = []
      for i, item in items {
        out.push(dec_json(item, "\{at}/\{i}"))
      }
      TList(out)
    }
    Object(obj) =>
      match obj.get(tag_key) {
        None => plain_map(obj, at)
        Some(String(name)) => dec_tagged_json(name, obj, at)
        Some(other) =>
          // A `"$"` that is not a string is a map that collided with the
          // discriminator and was not escaped — which means it was written by
          // something that does not implement this format.
          raise BadTagged(
            want="a string type name under \{tag_key}, not \{shape_word(other)}; " +
              "a map carrying \{tag_key} as data is written as {\"\{tag_key}\":\"map\",\"\{value_key}\":{…}}",
            at~,
          )
      }
  }
}

///|
fn plain_map(obj : Map[String, Json], at : String) -> TVal raise CodecError {
  let entries = []
  for k, v in obj {
    entries.push((k, dec_json(v, "\{at}/\{escape_pointer(k)}")))
  }
  TMap(entries)
}

///|
fn dec_tagged_json(
  name : String,
  obj : Map[String, Json],
  at : String,
) -> TVal raise CodecError {
  let payload = () => {
    match obj.get(value_key) {
      Some(v) => v
      None => Json::null()
    }
  }
  match name {
    "int" =>
      match payload() {
        String(s) =>
          TInt(@string.parse_int64(s)) catch {
            _ =>
              raise BadTagged(
                want="a base-ten integer under \{value_key}, got \{s}",
                at~,
              )
          }
        // A number is accepted for the convenience of a hand-written document,
        // and it is exact up to 2^53 — past which the JSON parser already lost
        // the digits and there is nothing here to recover.
        Number(n, ..) => TInt(n.to_int64())
        other =>
          raise BadTagged(
            want="a string or number under \{value_key}, got \{shape_word(other)}",
            at~,
          )
      }
    "bin" =>
      match payload() {
        String(s) => TBin(decode_b64(s, at))
        other =>
          raise BadTagged(
            want="a base64 string under \{value_key}, got \{shape_word(other)}",
            at~,
          )
      }
    "instant" =>
      match payload() {
        String(s) => {
          let (secs, nanos) = instant_of_rfc3339(s)
          TInstant(secs~, nanos~)
        }
        other =>
          raise BadTagged(
            want="an RFC 3339 string under \{value_key}, got \{shape_word(other)}",
            at~,
          )
      }
    // The escape, read back. Whatever is inside is an ordinary map, including
    // one whose own keys start with the discriminator.
    "map" =>
      match payload() {
        Object(inner) => plain_map(inner, at)
        other =>
          raise BadTagged(
            want="an object under \{value_key}, got \{shape_word(other)}",
            at~,
          )
      }
    "comp" =>
      match payload() {
        Object(inner) => {
          let module_ = str_field(inner, "module", at)
          let component = str_field(inner, "component", at)
          let state = match inner.get("state") {
            Some(String(s)) => decode_b64(s, at)
            None => b""
            Some(other) =>
              raise BadTagged(
                want="a base64 `state`, got \{shape_word(other)}",
                at~,
              )
          }
          TComp({ module_, component, state, })
        }
        other =>
          raise BadTagged(
            want="{module, component, state} under \{value_key}, got \{shape_word(other)}",
            at~,
          )
      }
    "ext" => {
      let ext_tag = match obj.get("tag") {
        Some(Number(n, ..)) => n.to_int()
        _ =>
          raise BadTagged(want="a numeric `tag` beside \{tag_key}:\"ext\"", at~)
      }
      TExt(ext_tag~, payload=dec_json(payload(), "\{at}/v"))
    }
    other => raise UnknownTagged(got=other, at~)
  }
}

///|
fn str_field(
  obj : Map[String, Json],
  key : String,
  at : String,
) -> String raise CodecError {
  match obj.get(key) {
    Some(String(s)) => s
    _ => raise BadTagged(want="a string `\{key}`", at~)
  }
}

///|
fn decode_b64(s : String, at : String) -> Bytes raise CodecError {
  @base64.decode(s[:]) catch {
    InvalidChar(c) => raise BadBase64(why="the character \{c}", at~)
  }
}

///|
/// What a `Json` IS, for a message about what it should have been.
fn shape_word(j : Json) -> String {
  match j {
    Null => "null"
    True | False => "a boolean"
    Number(_, ..) => "a number"
    String(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
}
