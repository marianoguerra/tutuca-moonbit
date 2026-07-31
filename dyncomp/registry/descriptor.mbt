///| What a catalog entry IS: everything a chooser needs and nothing a renderer
/// does.
///
/// A `Descriptor` is built from a loaded bundle and then stands alone — it
/// holds no guest, no handle and no instance, so describing forty components
/// costs forty reads of data the host already parsed and not one call across
/// the boundary.

///|
/// Where a component lives. Two strings rather than one, because the module is
/// the unit of loading, hot-swapping and isolation, and a joined `"m/C"` would
/// have to be split again by everything that acts on it.
pub(all) struct ComponentRef {
  module_ : String
  name : String
} derive(Eq, Debug, Hash)

///|
/// `module/Component` — for a log line, a palette label, or a tool result.
///
/// A LABEL, not an identifier, and there is deliberately no way back from one:
/// a module name may contain a slash (a guest picks its own), so splitting the
/// result is guesswork. Everything that resolves a component takes the two
/// fields, which is also why they are two fields.
pub fn ComponentRef::to_id(self : ComponentRef) -> String {
  "\{self.module_}/\{self.name}"
}

///|
/// One name a component answers to, with whatever the manifest said about it.
/// The bucket is what tells a caller how to reach it — an `input` is raised by
/// a view, a `receive` is sent to it, a `bubble` comes from a child.
pub(all) struct MessageInfo {
  name : String
  /// input | receive | bubble | response | method | request
  bucket : String
  doc : String
} derive(Eq, Debug)

///|
/// A named initial state, and when to prefer it over the bare constructor.
pub(all) struct InitInfo {
  name : String
  doc : String
  args : Map[String, @tutuca.Value]
} derive(Eq, Debug)

///|
/// Everything the catalog knows about one component.
pub(all) struct Descriptor {
  ref_ : ComponentRef
  doc : String
  keywords : Array[String]
  category : String
  /// The declared shape — the same `SchemaInfo` the runtime uses, so nothing
  /// here can describe a component differently from how it behaves.
  schema : @tutuca.SchemaInfo
  /// Per-field docs and constraints, keyed by field name. Separate from
  /// `schema` because a HOST component has the schema and not these, and every
  /// generic seam has to keep working for it.
  field_docs : Map[String, @jsonschema.FieldDoc]
  messages : Array[MessageInfo]
  inits : Array[InitInfo]
  /// The bundle's own metadata. Advisory: nothing resolves against it, and a
  /// bundle's identity is the archive it arrived in.
  module_doc : String
  module_version : String
}

// No `derive(Eq, Debug)`: `SchemaInfo` has neither, and adding them to a
// published core type to make a description printable would be the tail
// wagging the dog. `to_json` is the projection that was wanted anyway — a
// test reads it, a palette reads it, and `ui_describe_component` returns it.

///|
/// The whole description as one document: what it is, what it holds, what it
/// answers, how to start it.
///
/// This is the tool result and the palette's data in one, which is the point.
/// A second projection for the agent would be a second place for the catalog
/// to describe a component differently from how the UI does.
pub fn Descriptor::to_json(self : Descriptor) -> Json {
  let messages : Array[Json] = self.messages.map(m => {
    Json::object({
      "name": Json::string(m.name),
      "bucket": Json::string(m.bucket),
      "doc": Json::string(m.doc),
    })
  })
  let inits : Array[Json] = self.inits.map(i => {
    Json::object({
      "name": Json::string(i.name),
      "doc": Json::string(i.doc),
      "args": @tutuca.Value::Map(i.args).to_json(),
    })
  })
  Json::object({
    "module": Json::string(self.ref_.module_),
    "name": Json::string(self.ref_.name),
    "doc": Json::string(self.doc),
    "summary": Json::string(self.summary()),
    "category": Json::string(self.category),
    "keywords": Json::array(self.keywords.map(k => Json::string(k))),
    "argsSchema": self.args_schema(),
    "messages": Json::array(messages),
    "inits": Json::array(inits),
    "moduleDoc": Json::string(self.module_doc),
    "moduleVersion": Json::string(self.module_version),
  })
}

///|
/// A one-line summary, which is what a search result and a palette row show.
/// Falls back through doc, then keywords, then the shape — an undocumented
/// component still says something rather than nothing.
pub fn Descriptor::summary(self : Descriptor) -> String {
  if self.doc != "" {
    return self.doc
  }
  if !self.keywords.is_empty() {
    return self.keywords.join(", ")
  }
  let fields = self.schema.fields.map(f => "\{f.name}: \{f.ty.show_wit()}")
  if fields.is_empty() {
    "no declared state"
  } else {
    fields.join(", ")
  }
}

///|
/// The JSON Schema for constructing this component — the projection both
/// layers read, built here so a caller never has to pair a schema with the
/// right docs map by hand and get it wrong.
pub fn Descriptor::args_schema(self : Descriptor) -> Json {
  @jsonschema.of_schema(
    self.schema,
    docs=self.field_docs,
    title=self.ref_.to_id(),
    description=self.doc,
  )
}

///|
/// Validate and decode constructor arguments for this component, per
/// `args_schema`. The other half of the same pairing.
pub fn Descriptor::coerce_args(
  self : Descriptor,
  j : Json,
) -> Result[Map[String, @tutuca.Value], Array[@jsonschema.SchemaError]] {
  @jsonschema.coerce(self.schema, j, docs=self.field_docs)
}

///|
/// The names in one bucket, with their docs merged in by name. The manifest
/// carries a single flat `message-docs` table on purpose, so this is where it
/// is spread back out over the six lists it describes.
fn messages_of(
  names : Array[String],
  bucket : String,
  docs : Map[String, String],
) -> Array[MessageInfo] {
  names.map(n => { name: n, bucket, doc: docs.get(n).unwrap_or("") })
}

///|
/// Build a descriptor for one component of a loaded bundle. None when the
/// bundle has no such component.
///
/// `inputs` comes off the COMPILED views rather than from the manifest, which
/// is the same asymmetry the contract has everywhere: a guest declares what it
/// answers itself, and the host reads what its views raise.
pub fn describe(bundle : @dyncomp.Bundle, component : String) -> Descriptor? {
  guard bundle.schema_of(component) is Some(schema) else { return None }
  guard bundle.def_of(component) is Some(def) else { return None }
  let manifest = bundle.manifest()
  let field_docs : Map[String, @jsonschema.FieldDoc] = Map([])
  for f in def.fields {
    field_docs[f.name] = {
      doc: f.doc,
      required: f.required,
      constraint: f.constraint,
    }
  }
  let messages : Array[MessageInfo] = []
  for m in messages_of(schema.inputs, "input", def.message_docs) {
    messages.push(m)
  }
  for
    pair in [
      (def.receives, "receive"),
      (def.bubbles, "bubble"),
      (def.responses, "response"),
      (def.methods, "method"),
      (def.requests, "request"),
    ] {
    for m in messages_of(pair.0, pair.1, def.message_docs) {
      messages.push(m)
    }
  }
  Some({
    ref_: { module_: bundle.module_name(), name: component },
    doc: def.doc,
    keywords: def.keywords,
    category: def.category,
    schema,
    field_docs,
    messages,
    inits: def.inits.map(i => {
      ({ name: i.name, doc: i.doc, args: i.args } : InitInfo)
    }),
    module_doc: manifest.doc,
    module_version: manifest.version,
  })
}
