// What a declared TYPE cannot state, and what a form and a JSON Schema both
// need anyway.
//
// `Ty` says a field holds a string. This says it holds an email between three
// and 254 characters, defaulting to blank. Neither half is derivable from the
// other, and a generated form that has only the first half can draw a text box
// and nothing else.
//
// It lives here rather than in `dyncomp/host` because it is part of the
// DESCRIPTION, not part of the runtime: the manifest parser produces one, and
// both consumers of the description read it. A host component can supply one
// too, and gets the same form.
//
// The bounds used to be a `Constraint` record of eight optional members —
// `min`, `max`, `min_len`, `max_len`, `pattern`, `format`, `enum_values`,
// `default` — beside `@tutuca.Domain`, which said seven of those eight things
// already and said them in a form the runtime could CHECK. Two vocabularies for
// one idea meant two gates deciding which bound applied to which type, and they
// disagreed. There is one now: a field's bounds are domains, and `default` —
// which was never a bound, only a seed — is a field of its own.

///|
/// What a manifest says about one field beyond its type. Absent from the map
/// entirely is the same as a blank one — a host component that declares no
/// docs still gets a schema, just a terser one.
pub(all) struct FieldDoc {
  doc : String
  /// Whether a constructor must be given this field. A field the type's zero
  /// covers is not required, which is why this is stated rather than inferred.
  required : Bool
  /// What a form pre-fills and a schema advertises. NOT the type's zero — the
  /// host already knows that one (`Ty::zero`), so stating it here would be a
  /// second answer to a question already answered.
  ///
  /// Not a domain, and that is the distinction the merge made visible: every
  /// domain is a statement about which values are ADMITTED, and a default
  /// admits nothing — it picks one.
  default : @tutuca.Value?
  /// The bounds on this field, conjoined. Empty is unconstrained.
  domains : Array[@tutuca.Domain]
} derive(Eq, Debug)

///|
pub fn FieldDoc::none() -> FieldDoc {
  { doc: "", required: false, default: None, domains: [], }
}
