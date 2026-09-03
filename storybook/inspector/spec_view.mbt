// A component's DECLARATION, as something to look at.
//
// The components are in spec_view.html; this is the projection from
// `@statedef`'s values onto them. Two panels over one string:
//
//   `spec_panel`        — `Component::spec` re-parsed, rendered as what it
//                         declares: fields, messages, rules, named types.
//   `spec_source_panel` — the same block, verbatim.
//
// It exists because the block is now LOAD-BEARING at runtime rather than only
// at generation time: `testing/fuzz` derives a component's generators and its
// whole oracle from `Component::spec`, so "what does this component declare"
// stopped being a question you answer by opening the file and became one the
// gallery has to be able to answer about the story on screen.
//
// The parse is redone here rather than shared with the Fuzz tab's `Plan`: a
// plan keeps the arm it will generate from, and a reader wants every arm the
// block carries — including the child components a story renders but never
// fuzzes.

///|
/// The rule's word, and the badge it wears. A `pred` guards a write; an
/// `invariant` is a claim about every settled state, which is the one the
/// Fuzz tab can catch a component breaking — so it is the one with the colour.
fn spec_rule_kind(kind : @statedef.RuleKind) -> (String, String) {
  let (word, colour) = match kind {
    RPred => ("pred", "badge-ghost")
    RInvariant => ("invariant", "badge-info")
  }
  // The WHOLE class list, because `:class` replaces the written one rather
  // than adding to it — so the hook a test selects on has to be in here too.
  (word, "badge badge-xs rule-kind \{colour}")
}

///|
/// A field's `@attr`s on one line, or "" for the common case of none.
fn spec_attrs_of(attrs : Array[(String, @statedef.AttrValue)]) -> String {
  let out : Array[String] = []
  for a in attrs {
    let (name, v) = a
    out.push(
      match v {
        AFlag => "@\{name}"
        ANum(n) => "@\{name}=\{n}"
        AStr(s) => "@\{name}=\{@statedef.quote(s)}"
      },
    )
  }
  out.join(" ")
}

///|
/// A message's payload in parens, or "" when it carries none.
fn spec_payload_of(payload : Array[@statedef.StateTy]) -> String {
  guard !payload.is_empty() else { return "" }
  "(" + payload.map(t => t.show_source()).join(", ") + ")"
}

///|
/// A doc comment, or "" — `String?` is how the parser spells "absent", and
/// every row here takes the empty string for it because a view asks
/// `truthy? .doc` rather than matching an option.
fn spec_doc_of(doc : String?) -> String {
  doc.unwrap_or("")
}

// ---------------------------------------------------------------------------
// rows
// ---------------------------------------------------------------------------

///|
fn Inspector::spec_field_rows(
  self : Inspector,
  fields : Array[@statedef.FieldDef],
) -> Array[@tutuca.Value] {
  fields.map(f => {
    self.make_("SpecField", args={
      "name": Str(f.name),
      "typeName": Str(f.ty.show_source()),
      "attrs": Str(spec_attrs_of(f.attrs)),
      "doc": Str(spec_doc_of(f.doc)),
    })
  })
}

///|
/// `as_written` picks which of a `MsgDef`'s two names to show. A MESSAGE is
/// shown by its runtime name — that is what a dispatch is addressed to, and so
/// what a reader comparing this against a Fuzz row is looking for. An enum
/// CASE is shown as written: it is never dispatched, and its runtime name is a
/// generated spelling that appears nowhere in the file.
fn Inspector::spec_msg_rows(
  self : Inspector,
  msgs : Array[@statedef.MsgDef],
  as_written? : Bool = false,
) -> Array[@tutuca.Value] {
  msgs.map(m => {
    self.make_("SpecMsg", args={
      "name": Str(if as_written { m.source_name } else { m.name }),
      "payload": Str(spec_payload_of(m.payload)),
      "doc": Str(spec_doc_of(m.doc)),
    })
  })
}

///|
fn Inspector::spec_rule_rows(
  self : Inspector,
  rules : Array[@statedef.RuleDecl],
) -> Array[@tutuca.Value] {
  rules.map(r => {
    let (word, klass) = spec_rule_kind(r.kind)
    self.make_("SpecRule", args={
      "kind": Str(word),
      "kindClass": Str(klass),
      "name": Str(r.name),
      "source": Str(r.source),
      "format": Str(r.format),
      "doc": Str(spec_doc_of(r.doc)),
    })
  })
}

///|
/// `rows`, with the declaration's own doc comment above them.
fn Inspector::spec_with_doc(
  self : Inspector,
  doc : String?,
  rows : Array[@tutuca.Value],
) -> Array[@tutuca.Value] {
  let text = spec_doc_of(doc)
  guard text != "" else { return rows }
  let out : Array[@tutuca.Value] = [
    self.make_("SpecDoc", args={ "text": Str(text) }),
  ]
  for r in rows {
    out.push(r)
  }
  out
}

// ---------------------------------------------------------------------------
// sections
// ---------------------------------------------------------------------------

///|
/// A labelled group, or None when the group is empty. Empty sections are
/// omitted for the reason the component inspector omits them: a declaration
/// read through ten "(0)" headers is a declaration nobody read.
fn Inspector::spec_section(
  self : Inspector,
  label : String,
  rows : Array[@tutuca.Value],
  expanded? : Bool = false,
) -> @tutuca.Value? {
  guard !rows.is_empty() else { return None }
  Some(
    self.make_("CompSection", args={
      "label": Str(label),
      "items": List(rows),
      "isExpanded": Bool(expanded),
    }),
  )
}

///|
/// The named types the block declares, one nested section each.
fn Inspector::spec_types_section(
  self : Inspector,
  types : Array[@statedef.UserTy],
) -> @tutuca.Value? {
  let rows = types.map(t => {
    // The keyword the AUTHOR wrote, not the one the parser landed on: the
    // state language has ONE sum declaration, and `enum` becomes a `UVariant`
    // the moment any case carries a payload. Labelling that "variant" would
    // name a word that appears nowhere in the file. The rows say it instead —
    // a payload-free case is a name, one with a payload is a signature.
    let (kind, items) = match t.kind {
      URecord(fs) => ("struct", self.spec_field_rows(fs))
      // `(as written, MoonBit ident)` — the first is what the author typed.
      UEnum(cases) =>
        (
          "enum",
          cases.map(c => self.make_("SpecField", args={ "name": Str(c.0) })),
        )
      UVariant(ms) => ("enum", self.spec_msg_rows(ms, as_written=true))
    }
    self.make_("CompSection", args={
      // As WRITTEN: `t.name` is the generated MoonBit type, which prefixes the
      // component name onto it — `ShipmentParcel` for a `struct Parcel` — and
      // that name is not in the file the reader has open.
      "label": Str("\{kind} \{t.source_name}"),
      "items": List(self.spec_with_doc(t.doc, items)),
    })
  })
  self.spec_section("Types", rows)
}

///|
/// One component's arm of the block.
fn Inspector::spec_def_section(
  self : Inspector,
  def : @statedef.StateDef,
  root~ : Bool,
) -> @tutuca.Value {
  let inner : Array[@tutuca.Value] = []
  fn push(section : @tutuca.Value?) -> Unit {
    match section {
      Some(s) => inner.push(s)
      None => ()
    }
  }

  // Fields start expanded — the section a reader opened this for.
  push(
    self.spec_section("Fields", self.spec_field_rows(def.fields), expanded=true),
  )
  push(self.spec_section("Receive", self.spec_msg_rows(def.receive)))
  push(self.spec_section("Intent", self.spec_msg_rows(def.intent)))
  push(
    self.spec_section(
      "Express message",
      self.spec_msg_rows(def.express_message),
    ),
  )
  push(
    self.spec_section("Express intent", self.spec_msg_rows(def.express_intent)),
  )
  // …and so do the rules: they are the half of the block the schema cannot
  // carry, and the half the Fuzz tab holds the component to.
  push(
    self.spec_section("Rules", self.spec_rule_rows(def.rules), expanded=true),
  )
  push(self.spec_types_section(def.types))
  push(
    self.spec_section(
      "Implements",
      def.implements.map(id => self.make_("CompName", args={ "name": Str(id) })),
    ),
  )
  push(
    self.spec_section(
      "Provide",
      def.provide.map(p => {
        self.make_("SpecField", args={
          "name": Str(p.name),
          "typeName": Str(p.source),
        })
      }),
    ),
  )
  push(
    self.spec_section(
      "Lookup",
      def.lookup.map(l => {
        self.make_("SpecField", args={
          "name": Str(l.name),
          "typeName": Str(l.default.unwrap_or("")),
        })
      }),
    ),
  )
  self.make_("CompSection", args={
    "label": Str(def.component),
    "items": List(self.spec_with_doc(def.doc, inner)),
    // The story's own component is the arm it was opened for; the others are
    // the children the file happens to declare beside it.
    "isExpanded": Bool(root),
  })
}

// ---------------------------------------------------------------------------
// panels
// ---------------------------------------------------------------------------

///|
/// Why there is no declaration to show — "" when there is one.
///
/// Three different absences, said in three different ways, because they are
/// three different things to do about it: register the component, generate the
/// views, or fix the block.
fn spec_absent_hint(comp : @component.Component?) -> String {
  guard comp is Some(c) else {
    return "This story's instance does not resolve to a registered component, so there is no declaration to read."
  }
  guard c.spec == "" else { return "" }
  "\{c.name} carries no <script type=\"tutuca/spec\"> block — it was written by hand rather than compiled by gen — so there is nothing declared to show. The Fuzz tab has nothing to generate from either."
}

///|
/// What a reader of a shipped block should know about it before they trust
/// what is missing from it.
///
/// `gen` strips the prose on its way into the binary — a block is
/// carried so `@statedef.parse_state` can read it back, and no parser reads a
/// `///`. So a declaration whose author documented every field shows none of
/// it here, and that is worth saying rather than leaving as a puzzle. Empty
/// for a block nobody stripped: one parsed at run time, from a dyncomp guest
/// or the playground, reaches its component whole.
pub let spec_docs_note : String = "gen ships this block without its doc comments — a block is carried to be re-parsed, and no parser reads prose. The full text is in the .html file."

///|
/// A note about the block, or "" when it needs none.
///
/// Decided by looking: a block that still carries a `///` reached the runtime
/// whole, so there is nothing missing to warn about. One that carries none was
/// either stripped on the way in or written without prose, and the note is
/// what tells those two apart for a reader who knows the file says more.
fn spec_note_of(comp : @component.Component?) -> String {
  guard comp is Some(c) && c.spec != "" else { return "" }
  for line in c.spec.split("\n") {
    if line.to_owned().trim(chars=" \t").has_prefix("///") {
      return ""
    }
  }
  spec_docs_note
}

///|
/// The block, parsed and rendered as what it declares.
pub fn Inspector::spec_panel(
  self : Inspector,
  comp? : @component.Component,
) -> @tutuca.Value {
  let sections : Array[@tutuca.Value] = []
  let mut hint = spec_absent_hint(comp)
  if comp is Some(c) && c.spec != "" {
    // `name=` for the reason `@fuzz.Plan` passes it: a bare `state { … }`
    // belongs to the file's single unnamed component, and only the caller
    // knows what that component is called.
    let defs : Array[@statedef.StateDef] = @statedef.parse_state(
      c.spec,
      name=c.schema.name,
    ) catch {
      // A block that no longer parses is a `gen` failure that has already
      // been reported where the author will see it. Said plainly here rather
      // than swallowed, because the alternative is an empty pane that looks
      // like the gallery is broken.
      e => {
        hint = "This block no longer parses: \{e.message()}"
        []
      }
    }
    // By NAME, because the block is the FILE's: a file declaring three
    // components carries all three arms in every one of its wrappers.
    for d in defs {
      sections.push(self.spec_def_section(d, root=d.component == c.schema.name))
    }
  }
  self.make_("SpecViewer", args={
    "compName": Str(
      match comp {
        Some(c) => c.name
        None => ""
      },
    ),
    "sections": List(sections),
    "hasSpec": Bool(!sections.is_empty()),
    "hint": Str(hint),
    "note": Str(spec_note_of(comp)),
  })
}

///|
/// The block, verbatim.
pub fn Inspector::spec_source_panel(
  self : Inspector,
  comp? : @component.Component,
) -> @tutuca.Value {
  let source = match comp {
    Some(c) => c.spec
    None => ""
  }
  self.make_("SpecSource", args={
    "source": Str(source),
    "hasSource": Bool(source != ""),
    "hint": Str(spec_absent_hint(comp)),
    "note": Str(spec_note_of(comp)),
  })
}

// ---------------------------------------------------------------------------
// a block with everything in it
// ---------------------------------------------------------------------------

///|
/// A declaration exercising every row this panel can draw.
///
/// Written out rather than taken from a compiled component, because the
/// interesting half of a block is the half `gen` does not ship: prose
/// goes on the way into a binary, and no example in this package declares a
/// rule or a named type. This is what a block looks like when it reaches the
/// runtime WHOLE — a dyncomp guest's, the playground's — and it is the only
/// fixture in which the doc rows and the rule rows have anything to show.
pub let spec_sample_source : String =
  #|  /// One box.
  #|  struct Parcel {
  #|    id : String
  #|    weightKg : Double
  #|  }
  #|
  #|  /// Where it is in its life.
  #|  enum Status {
  #|    Booked
  #|    InTransit
  #|    Delivered
  #|  }
  #|
  #|  /// A shipment, and the two things that must stay true of one.
  #|  state Shipment {
  #|    /// Where it is going. Never empty once it has been booked.
  #|    to : String
  #|    weightKg : Double
  #|    parcels : Array[Parcel]
  #|    status : Status
  #|
  #|    /// Nothing weightless ships.
  #|    pred loadable
  #|      format 'weight must be above zero' { .weightKg > 0 }
  #|
  #|    /// A booked shipment names a destination.
  #|    invariant addressed
  #|      format 'a booked shipment must name a destination' { not (.to is '') }
  #|  }
  #|
  #|  handle Shipment {
  #|    message {
  #|    /// Add a parcel, by id and weight.
  #|    addParcel(String, Double)
  #|    reweigh(Double)
  #|
  #|    }
  #|  }

///|
/// A component that is nothing but that declaration: no views, no state codec,
/// nothing to render. It exists to be READ, the way `rich_sample_comp` exists
/// to be introspected.
pub fn spec_sample_component() -> @component.Component {
  @component.Component::for_type(
    name="Shipment",
    views={},
    schema=@component.SchemaInfo::new(
      name="Shipment",
      fingerprint="spec-sample",
    ),
    spec=spec_sample_source,
  )
}

// ---------------------------------------------------------------------------
// components
// ---------------------------------------------------------------------------

///|
fn spec_field_comp() -> @component.Component {
  spec_field_component()
}

///|
fn spec_msg_comp() -> @component.Component {
  spec_msg_component()
}

///|
fn spec_rule_comp() -> @component.Component {
  spec_rule_component()
}

///|
fn spec_doc_comp() -> @component.Component {
  spec_doc_component()
}

///|
fn spec_source_comp() -> @component.Component {
  spec_source_component()
}

///|
/// The wrapper, which exists to answer one thing: a ctrl-click on any section
/// opens or closes them all. Nested sections (a named type's) are left alone,
/// the same way the component inspector leaves them alone.
fn spec_viewer_comp() -> @component.Component {
  spec_viewer_component(update=(s, msg, _ctx) => {
    match SpecViewerIntent::from_dispatch(msg) {
      Some(ToggleAllSections(on)) =>
        Next({
          ..s,
          sections: s.sections.map(sec => sec.with_field("isExpanded", Bool(on))),
        })
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}
