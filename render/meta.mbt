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
    Comp(nid~, cid~, vid~) => {
      sb.write_string("{\"$\":\"Comp\",\"nid\":")
      match nid {
        Some(n) => sb.write_string(n.to_string())
        None => sb.write_string("null")
      }
      sb.write_string(",\"cid\":")
      sb.write_string(cid.to_string())
      sb.write_string(",\"vid\":")
      write_json_string(sb, vid)
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
      Some(Comp(nid~, cid=cid.to_int(), vid~))
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
