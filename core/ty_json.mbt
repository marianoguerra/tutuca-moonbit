// A declared type on the wire.
//
// One codec, in `core`, because both ends are here: the card compiler writes
// this into a manifest and the dynamic-component host reads it, and a format
// written twice is a format that disagrees with itself the first time either
// end grows a case.
//
// It replaces a FLAT TABLE of interned entries, each referring to others by
// index, with the tree the type already is. The table was not an optimization
// that went wrong — it was a shape that could not say what it meant: a
// `ty-list` entry had an `elem` field and the writer never filled it, so every
// list, option and map in every manifest crossed as "a list of anything". The
// tree has nowhere to leave the element out.

///|
/// This type as JSON. `k` is the case; the rest of the object is that case's
/// payload, which is nothing for most of them.
pub fn Ty::to_json(self : Ty) -> Json {
  let k = (name : String) => Json::object({ "k": Json::string(name) })
  let named = (name : String, n : String) => {
    Json::object({ "k": Json::string(name), "name": Json::string(n) })
  }
  let wrapping = (name : String, inner : Ty) => {
    Json::object({ "k": Json::string(name), "of": inner.to_json() })
  }
  match self {
    TyBool => k("bool")
    TyInt(width~, signed~) =>
      Json::object({
        "k": Json::string("int"),
        "width": Json::number(width.to_double()),
        "signed": Json::boolean(signed),
      })
    TyFloat => k("float")
    TyText => k("text")
    TySet => k("set")
    TyTable => k("table")
    TyAny => k("any")
    TyList(e) => wrapping("list", e)
    TyOption(e) => wrapping("option", e)
    TyOMap(v) => wrapping("omap", v)
    TyTuple(ts) =>
      Json::object({
        "k": Json::string("tuple"),
        "items": Json::array(ts.map(t => t.to_json())),
      })
    TyRecord(n) => named("record", n)
    TyEnum(n) => named("enum", n)
    TyVariant(n) => named("variant", n)
    TyFlags(n, ms) =>
      Json::object({
        "k": Json::string("flags"),
        "name": Json::string(n),
        "members": Json::array(ms.map(Json::string)),
      })
    // "" is the bare `component` marker: a slot whose component the guest did
    // not name.
    TyComp(c) => named("comp", c.unwrap_or(""))
    TyCompProtocols(ids) =>
      Json::object({
        "k": Json::string("compProtocols"),
        "members": Json::array(ids.map(Json::string)),
      })
  }
}

///|
/// A declared type read back, or `TyAny` for anything this cannot make sense
/// of.
///
/// `TyAny` rather than a failure, and the same answer the flat table gave for
/// an unknown kind: a manifest crossed a trust boundary, and the honest reading
/// of a type a host does not recognize is "cannot say" — which is exactly what
/// `any` means everywhere else here.
pub fn Ty::of_json(j : Json) -> Ty {
  guard j is Object(m) else { return TyAny }
  guard m.get("k") is Some(String(kind)) else { return TyAny }
  let name = match m.get("name") {
    Some(String(s)) => s
    _ => ""
  }
  let inner = () => {
    match m.get("of") {
      Some(of) => Ty::of_json(of)
      None => TyAny
    }
  }
  let members = () => {
    let out : Array[String] = []
    if m.get("members") is Some(Array(items)) {
      for item in items {
        if item is String(s) {
          out.push(s)
        }
      }
    }
    out
  }
  match kind {
    "bool" => TyBool
    "int" => {
      let width = match m.get("width") {
        Some(Number(n, ..)) => n.to_int()
        _ => 32
      }
      TyInt(width~, signed=!(m.get("signed") is Some(False)))
    }
    "float" => TyFloat
    "text" => TyText
    "set" => TySet
    "table" => TyTable
    "list" => TyList(inner())
    "option" => TyOption(inner())
    "omap" => TyOMap(inner())
    "tuple" => {
      let out : Array[Ty] = []
      if m.get("items") is Some(Array(items)) {
        for item in items {
          out.push(Ty::of_json(item))
        }
      }
      TyTuple(out)
    }
    "record" => TyRecord(name)
    "enum" => TyEnum(name)
    "variant" => TyVariant(name)
    "flags" => TyFlags(name, members())
    "comp" => TyComp(if name == "" { None } else { Some(name) })
    "compProtocols" => TyCompProtocols(members())
    _ => TyAny
  }
}
