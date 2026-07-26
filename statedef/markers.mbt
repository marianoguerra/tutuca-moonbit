// Marker type names.
//
// WIT has no user-defined generics and no open type, so four of tutuca's
// field kinds have no structural spelling. They arrive as bare names, which
// this table resolves before any structural interpretation happens.
//
// A marker is justified ONLY when WIT cannot express the concept at all:
//
//   any         an arbitrary @tutuca.Value — WIT is a closed type system
//   component   a child-component slot — a WIT interface is not a type
//   text-set    a set with open membership (`flags` covers the closed case)
//   *-omap      an ORDERED map; WIT `map` is unordered by definition
//
// Everything else uses the standard WIT spelling: `flags` for closed sets,
// `list<T>`, `record`, `variant`, `enum`, and `map<string, T>` once the
// parser carries it.
//
// The names are RESERVED: a user type that shadowed `any` would silently
// change what every `any` in the file means.

///|
/// A marker name -> the type it denotes. None when the name is not a marker.
fn marker(name : String) -> StateTy? {
  match name {
    "any" => Some(TAny)
    "component" => Some(TComp(None))
    "text-set" => Some(TSet)
    // Convenience aliases over the markers above. They exist because the
    // shapes they name are the two commonest in the corpus by a wide margin.
    "values" => Some(TList(TAny))
    "value-omap" => Some(TOMap(TAny))
    "text-omap" => Some(TOMap(TText))
    _ => None
  }
}

///|
/// True when a name may not be declared as a user type.
fn is_reserved(name : String) -> Bool {
  marker(name) is Some(_) || name == "state"
}

///|
/// The marker vocabulary, for the "did you mean" tail of an unknown-type
/// error. Sorted, so the message is stable across runs.
fn marker_names() -> Array[String] {
  ["any", "component", "text-omap", "text-set", "value-omap", "values"]
}
