// §{json}§ boundary metas (JS Renderer._renderMetadata + path.js metaChain
// parsing). Emission and parsing share this type so they cannot drift.

///|
fn nid_json(nid : Int?) -> Json {
  match nid {
    Some(n) => n.to_json()
    None => Json::null()
  }
}

///|
pub fn Meta::to_comment_text(self : Meta) -> String {
  let j : Json = match self {
    Comp(nid~, cid~, vid~) =>
      {
        "$": "Comp",
        "nid": nid_json(nid),
        "cid": cid.to_json(),
        "vid": vid.to_json(),
      }
    Each(nid~, key~) =>
      match key {
        KInt(i) => { "$": "Each", "nid": nid.to_json(), "si": i.to_json() }
        KStr(s) => { "$": "Each", "nid": nid.to_json(), "sk": s.to_json() }
      }
    Scope(nid~) => { "$": "Scope", "nid": nid.to_json() }
  }
  "§\{j.stringify()}§"
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
