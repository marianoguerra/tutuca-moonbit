// JSON encoding — the `$`-tagged form.
//
// JSON is the INTERCHANGE encoding: it is what an agent writes by hand, what a
// browser parses without a library, and what a person reads in a log. Five arms
// have no JSON shape, so they become one-key-plus-payload objects under a `"$"`
// discriminator.
//
// The rule that makes the discriminator safe is the ESCAPE: an ordinary map
// whose own keys include `"$"` is written tagged too. Without it, `{"$": "bin"}`
// as data and `{"$": "bin"}` as a tag are the same six bytes, and a decoder has
// to guess. With it, a `"$"` at the top of an object ALWAYS means a tag, and the
// cost is paid only by the maps that actually collide.

///|
/// The discriminator key. One character, and `$` because it is the character a
/// JSON key is least likely to start with by accident — and the one this
/// codebase already spends on `$component` / `$module` in `core`.
pub let tag_key : String = "$"

///|
/// The payload key beside it.
pub let value_key : String = "v"

///|
pub fn to_json(v : TVal) -> Json raise CodecError {
  enc_json(v, "")
}

///|
fn enc_json(v : TVal, at : String) -> Json raise CodecError {
  match v {
    TNull => Json::null()
    TBool(b) => Json::boolean(b)
    TNum(n) => Json::number(n)
    // Always tagged, and always a STRING payload. `JSON.parse` gives a double,
    // so an integer written as a JSON number stops being itself past 2^53 —
    // which is the whole reason this arm exists.
    TInt(i) => tagged("int", Json::string(i.to_string()))
    TStr(s) => Json::string(s)
    TBin(b) => tagged("bin", Json::string(@base64.encode(b[:])))
    TInstant(secs~, nanos~) =>
      tagged("instant", Json::string(instant_to_rfc3339(secs, nanos)))
    TList(items) => {
      let out = []
      for i, item in items {
        out.push(enc_json(item, "\{at}/\{i}"))
      }
      Json::array(out)
    }
    TMap(entries) => {
      let obj : Map[String, Json] = Map([])
      for e in entries {
        let (k, val) = e
        if obj.contains(k) {
          raise DuplicateKey(key=k, at~)
        }
        obj[k] = enc_json(val, "\{at}/\{escape_pointer(k)}")
      }
      // The escape. A map that carries the discriminator as data is written
      // under the discriminator, so reading one is never a guess.
      if obj.contains(tag_key) {
        tagged("map", Json::object(obj))
      } else {
        Json::object(obj)
      }
    }
    TFunc =>
      raise NotEncodable(
        kind="function",
        why="a function is code in one module's address space; " +
          "there is nothing to write down that another process could call",
        at~,
      )
    TComp(c) => {
      let inner : Map[String, Json] = Map([])
      inner["module"] = Json::string(c.module_)
      inner["component"] = Json::string(c.component)
      inner["state"] = Json::string(@base64.encode(c.state[:]))
      tagged("comp", Json::object(inner))
    }
    TExt(ext_tag~, payload~) => {
      let obj : Map[String, Json] = Map([])
      obj[tag_key] = Json::string("ext")
      obj["tag"] = Json::number(ext_tag.to_double())
      obj[value_key] = enc_json(payload, "\{at}/v")
      Json::object(obj)
    }
  }
}

///|
fn tagged(name : String, payload : Json) -> Json {
  let obj : Map[String, Json] = Map([])
  obj[tag_key] = Json::string(name)
  obj[value_key] = payload
  Json::object(obj)
}

///|
/// RFC 6901: `~` becomes `~0` and `/` becomes `~1`, so a key containing a slash
/// does not read as two steps.
fn escape_pointer(k : String) -> String {
  let out = StringBuilder()
  for c in k {
    match c {
      '~' => out.write_string("~0")
      '/' => out.write_string("~1")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}
