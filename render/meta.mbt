// §{json}§ boundary metas (emission + path metaChain
// parsing). Emission and parsing share this type so they cannot drift.

///|
/// Written straight into a builder rather than assembled as a `Json` and
/// stringified. Every component render site and every `@each` iteration emits one
/// of these on EVERY pass, so a 1000-row list built and threw away 2000 Json
/// objects per render — 2.2% of the update profile in `stringify` alone, before
/// the allocation behind it. The shapes are fixed and closed, so there is nothing
/// for a generic encoder to decide.
///
/// Byte-identical to what `Json::stringify` produced, which `Meta::parse` and a
/// good number of DOM snapshots both depend on: no spaces, keys in this order,
/// `nid` present-but-null for a site without one.
pub fn Meta::to_comment_text(self : Meta) -> String {
  let sb = StringBuilder()
  sb.write_char('§')
  match self {
    Comp(nid~, cid~, vid~, base~) => {
      sb.write_string("{\"$\":\"Comp\",\"nid\":")
      match nid {
        Some(n) => sb.write_string(n.to_string())
        None => sb.write_string("null")
      }
      sb.write_string(",\"cid\":")
      sb.write_string(cid.to_string())
      sb.write_string(",\"vid\":")
      write_json_string(sb, vid)
      match base {
        Some(path) => {
          sb.write_string(",\"base\":")
          sb.write_string(render_path_text(path))
        }
        None => ()
      }
    }
    Each(nid~, key~) => {
      sb.write_string("{\"$\":\"Each\",\"nid\":")
      sb.write_string(nid.to_string())
      match key {
        KInt(i) => {
          sb.write_string(",\"si\":")
          sb.write_string(i.to_string())
        }
        KStr(s) => {
          sb.write_string(",\"sk\":")
          write_json_string(sb, s)
        }
      }
    }
    Scope(nid~) => {
      sb.write_string("{\"$\":\"Scope\",\"nid\":")
      sb.write_string(nid.to_string())
    }
  }
  sb.write_string("}§")
  sb.to_string()
}

///|
/// A JSON string literal. View names and loop keys are plain printable ASCII
/// virtually always, so that case is written directly; anything else goes
/// through `Json::stringify`, which owns the escaping rules — the point is to
/// skip an allocation, not to reimplement them.
fn write_json_string(sb : StringBuilder, s : String) -> Unit {
  for c in s {
    if c < ' ' || c > '~' || c == '"' || c == '\\' {
      sb.write_string((s.to_json() : Json).stringify())
      return
    }
  }
  sb.write_char('"')
  sb.write_string(s)
  sb.write_char('"')
}

///|
fn Meta::to_comment(self : Meta) -> @vdom.Vdom {
  @vdom.comment(self.to_comment_text())
}

///|
fn step_to_render_json(step : @tutuca.Step) -> Json? {
  let out : Map[String, Json] = Map([])
  match step {
    FieldStep(field) => out["f"] = Json::string(field)
    SeqStep(field~, key~) | EachRenderItStep(field~, key~) => {
      out["f"] = Json::string(field)
      out["k"] = key.to_json()
    }
    SeqAccessStep(seq_field~, key_field~) => {
      out["f"] = Json::string(seq_field)
      out["a"] = Json::string(key_field)
    }
    _ => return None
  }
  Some(Json::object(out))
}

///|
fn render_json_to_step(j : Json) -> @tutuca.Step? {
  guard j is Object(m) else { return None }
  guard m.get("f") is Some(String(field)) else { return None }
  match (m.get("k"), m.get("a")) {
    (Some(key), None) =>
      match @tutuca.PathKey::from_json(key) {
        Some(k) => Some(SeqStep(field~, key=k))
        None => None
      }
    (None, Some(String(key_field))) =>
      Some(SeqAccessStep(seq_field=field, key_field~))
    (None, None) => Some(FieldStep(field))
    _ => None
  }
}

///|
fn render_path_text(path : @tutuca.Path) -> String {
  let items : Array[Json] = []
  for step in path.steps {
    match step_to_render_json(step) {
      Some(j) => items.push(j)
      None => return "[]"
    }
  }
  Json::array(items).stringify()
}

///|
fn render_path_from_json(j : Json) -> @tutuca.Path? {
  guard j is Array(items) else { return None }
  let steps : Array[@tutuca.Step] = []
  for item in items {
    match render_json_to_step(item) {
      Some(step) => steps.push(step)
      None => return None
    }
  }
  Some(@tutuca.Path::new(steps~))
}

///|
fn parse_render_path_text(text : String) -> @tutuca.Path? {
  let json = @json.parse(text) catch { _ => return None }
  render_path_from_json(json)
}

///|
pub fn Meta::parse(text : String) -> Meta? {
  guard text.length() >= 2 && text[0] is '§' && text[text.length() - 1] is '§' else {
    return None
  }
  let inner = text[1:text.length() - 1]
  let j = @json.parse(inner.to_owned()) catch { _ => return None }
  match j {
    { "$": "Comp", "cid": Number(cid, ..), "vid": String(vid), .. } as obj => {
      let nid : Int? = match obj {
        { "nid": Number(n, ..), .. } => Some(n.to_int())
        _ => None
      }
      let base = match obj {
        { "base": base_json, .. } => render_path_from_json(base_json)
        _ => None
      }
      Some(Comp(nid~, cid=cid.to_int(), vid~, base~))
    }
    { "$": "Each", "nid": Number(nid, ..), .. } as obj =>
      match obj {
        { "si": Number(i, ..), .. } =>
          Some(Each(nid=nid.to_int(), key=KInt(i.to_int())))
        { "sk": String(s), .. } => Some(Each(nid=nid.to_int(), key=KStr(s)))
        _ => None
      }
    { "$": "Scope", "nid": Number(nid, ..), .. } =>
      Some(Scope(nid=nid.to_int()))
    _ => None
  }
}
