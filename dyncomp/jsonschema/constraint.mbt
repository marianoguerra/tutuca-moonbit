///| What a declared TYPE cannot state, and what a form and a JSON Schema both
/// need anyway.
///
/// `TyInfo` says a field holds a string. This says it holds an email between
/// three and 254 characters, defaulting to blank. Neither half is derivable
/// from the other, and a generated form that has only the first half can draw
/// a text box and nothing else.
///
/// This lives here rather than in `dyncomp/host` because it is part of the
/// DESCRIPTION, not part of the runtime: the manifest parser produces one, and
/// both consumers of the description read it. A host component can supply one
/// too, and gets the same form.

///|
/// Every member is optional by having an empty spelling — `None` for the
/// options, `""` for the strings — mirroring the WIT record it is parsed from.
/// `""` and `None` mean "not stated", which is never the same as a stated
/// zero: a `max_len` of 0 forbids everything, and an absent one forbids
/// nothing.
pub(all) struct Constraint {
  min : Double?
  max : Double?
  min_len : Int?
  max_len : Int?
  /// A regular expression the value must match. "" = unconstrained.
  pattern : String
  /// A JSON Schema `format` (email, uri, date-time, color, …). "" = none.
  format : String
  /// None = not an enumeration, which is not the same as an empty one.
  enum_values : Array[@tutuca.Value]?
  /// What a form pre-fills and a schema advertises. NOT the type's zero — the
  /// host already knows that one (`TyInfo::zero`), so stating it here would be
  /// a second answer to a question already answered.
  default : @tutuca.Value?
} derive(Eq, Debug)

///|
/// A constraint that constrains nothing. Spread it (`{ ..Constraint::none(),
/// max_len: Some(80) }`) rather than writing eight blanks.
pub fn Constraint::none() -> Constraint {
  {
    min: None,
    max: None,
    min_len: None,
    max_len: None,
    pattern: "",
    format: "",
    enum_values: None,
    default: None,
  }
}

///|
/// What a manifest says about one field beyond its type. Absent from the map
/// entirely is the same as a blank one — a host component that declares no
/// docs still gets a schema, just a terser one.
pub(all) struct FieldDoc {
  doc : String
  /// Whether a constructor must be given this field. A field the type's zero
  /// covers is not required, which is why this is stated rather than inferred.
  required : Bool
  constraint : Constraint?
} derive(Eq, Debug)

///|
pub fn FieldDoc::none() -> FieldDoc {
  { doc: "", required: false, constraint: None }
}
