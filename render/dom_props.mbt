// Asking the generated DOM property table a question.
//
// The table itself is `dom_props_gen.mbt` — machine-extracted from the
// specifications, never hand-edited. This is the two questions it answers, and
// the walk that answers them: a property declared on an ancestor interface is
// found by following `inherits`, because the table stores what each interface
// DECLARES rather than what it carries. Flattening would have made it several
// times larger and said nothing more.
//
// It is a TYPE ORACLE and not a permission list. Whether a step may be
// traversed at all is `render/event_paths.mbt`'s question, and the two are
// deliberately separate: this one is fetched and that one is argued.

///|
/// The interfaces, by name. Built once from the generated array, because a
/// linear scan of 115 entries per property lookup is a linear scan nobody
/// needs.
let dom_index : Map[String, DomInterface] = build_dom_index()

///|
fn build_dom_index() -> Map[String, DomInterface] {
  let out : Map[String, DomInterface] = Map([])
  for row in dom_interfaces {
    out[row.0] = row.1
  }
  out
}

///|
/// The type of `prop` on `iface`, or None when no interface in the chain
/// declares it.
///
/// None means "the specifications do not give this interface that property",
/// which is what `UNKNOWN_EVENT_PROP` reports. It does NOT mean the path is
/// refused — that is the allowlist's answer, and a path can be well-typed and
/// still refused.
pub fn dom_prop_ty(iface : String, prop : String) -> DomPropTy? {
  let seen : Set[String] = Set([])
  let mut cur = Some(iface)
  while cur is Some(name) {
    // A cycle cannot happen in an inheritance chain the specs describe, and a
    // walk with no guard would hang rather than report if one ever did.
    if seen.contains(name) {
      return None
    }
    seen.add(name)
    guard dom_index.get(name) is Some(def) else { return None }
    for pair in def.props {
      if pair.0 == prop {
        return Some(pair.1)
      }
    }
    cur = def.inherits
  }
  None
}

///|
/// Every property `iface` has, its own and its ancestors', sorted.
///
/// What `UNKNOWN_EVENT_PROP` searches for its "did you mean" — a warning that
/// names no alternative is a warning that costs more than it saves.
pub fn dom_props_of(iface : String) -> Array[String] {
  let out : Array[String] = []
  let seen : Set[String] = Set([])
  let mut cur = Some(iface)
  while cur is Some(name) {
    if seen.contains(name) {
      break
    }
    seen.add(name)
    guard dom_index.get(name) is Some(def) else { break }
    for pair in def.props {
      if !out.contains(pair.0) {
        out.push(pair.0)
      }
    }
    cur = def.inherits
  }
  out.sort()
  out
}

///|
/// Whether the table knows this interface at all.
///
/// `Window` and `Document` answer false, and that is the table's scope rather
/// than an omission — see the generated file's header.
pub fn dom_interface_known(iface : String) -> Bool {
  dom_index.contains(iface)
}
