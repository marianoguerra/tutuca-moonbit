///| The standard components, as catalog entries.
///
/// This file is the whole of "there is no difference between a host-provided
/// component and a loaded one". A `Descriptor` holds no bundle and no guest —
/// it is a description — so one built here from a compiled-in
/// `@component.Component` sits in the same catalog, ranks in the same search
/// and generates a form through the same projection as one built from a
/// manifest. Nothing downstream branches on which it is.
///
/// What CANNOT be derived is what a component is FOR: its sentence, its search
/// terms, and the half of a field a type cannot state (a range, a set of
/// choices, a default worth pre-filling). A guest declares those in its
/// manifest; a standard component declares them here, beside itself, because
/// there is nowhere else for them to go.

///|
/// What the catalog calls the standard components. One name, stated once,
/// because the registry ranks it and the app branches on it.
pub let builtin_module : String = @std.module_name

///|
/// Whether a ref names a standard component rather than a loaded one.
///
/// The ONE place the difference matters: building an instance goes through the
/// std module rather than the dyncomp bridge. Everything else — searching,
/// describing, generating a form, validating arguments, placing the result —
/// is the same code for both.
pub fn is_builtin(ref_ : @registry.ComponentRef) -> Bool {
  ref_.module_ == builtin_module
}

///|
/// A descriptor over a component's own declared schema.
///
/// The schema is READ from the component rather than restated, so nothing here
/// can describe a standard component differently from how it behaves — which
/// is the same guarantee a guest gets, by the same means.
fn descriptor_of(
  comp : @component.Component,
  doc~ : String,
  keywords~ : Array[String],
  category~ : String,
  fields? : Map[String, @jsonschema.FieldDoc] = Map([]),
  inits? : Array[@registry.InitInfo] = [],
  filled? : Array[String] = [],
) -> @registry.Descriptor {
  {
    ref_: { module_: builtin_module, name: comp.name },
    doc,
    keywords,
    category,
    schema: without(comp.schema, filled),
    field_docs: fields,
    // A standard component's message names are already in its schema, and the
    // catalog reads them off the same place it reads a guest's. Left empty
    // rather than restated: a second list is a second thing to forget.
    messages: [],
    inits,
    module_doc: "The components that are always here.",
    module_version: "1",
  }
}

///|
/// The same schema minus the fields a person FILLS rather than configures.
///
/// A container's `children` and a tab strip's `tabs` hold components. The form
/// generator would draw them as JSON text boxes, because that is its honest
/// fallback for a shape it has no control for — and a text box offering to
/// type a component in is offering something that cannot work. They come out
/// of the DESCRIPTION rather than out of the component: the field is real, the
/// runtime uses it, and a `+` button is how it gets filled.
///
/// Deliberately by name rather than by type. The type says `list<any>`, which
/// is also what a list of strings would say, so there is nothing structural to
/// test — and a wrong guess here would silently hide a field somebody meant to
/// configure.
fn without(
  schema : @tutuca.SchemaInfo,
  filled : Array[String],
) -> @tutuca.SchemaInfo {
  if filled.is_empty() {
    return schema
  }
  @tutuca.SchemaInfo::new(
    name=schema.name,
    fingerprint=schema.fingerprint,
    fields=schema.fields.filter(f => !filled.contains(f.name)),
    view_handlers=schema.view_handlers,
    receives=schema.receives,
    intents=schema.intents,
    methods=schema.methods,
    ids=schema.ids,
    view_names=schema.view_names,
    init_names=schema.init_names,
  )
}

///|
/// A field doc with a constraint, spelled once instead of eight times.
fn fd(
  doc : String,
  c? : @jsonschema.Constraint = @jsonschema.Constraint::none(),
) -> @jsonschema.FieldDoc {
  { doc, required: false, constraint: Some(c) }
}

///|
/// A whole number between `lo` and `hi`, starting at `d`.
fn ranged(doc : String, lo : Int, hi : Int, d : Int) -> @jsonschema.FieldDoc {
  fd(doc, c={
    ..@jsonschema.Constraint::none(),
    min: Some(lo.to_double()),
    max: Some(hi.to_double()),
    default: Some(Num(d.to_double())),
  })
}

///|
/// One of a fixed set of words, starting at `d`. The generated form draws a
/// `<select>` for it, which is the difference between a layout somebody can
/// change and one they have to guess the spelling of.
fn choices(
  doc : String,
  of~ : Array[String],
  d~ : String,
) -> @jsonschema.FieldDoc {
  fd(doc, c={
    ..@jsonschema.Constraint::none(),
    enum_values: Some(of.map(v => (Str(v) : @tutuca.Value))),
    default: Some(Str(d)),
  })
}

///|
/// A short line of text, starting at `d`.
fn text_field(doc : String, d? : String = "") -> @jsonschema.FieldDoc {
  fd(doc, c={ ..@jsonschema.Constraint::none(), default: Some(Str(d)) })
}

///|
/// Every standard component as a catalog entry.
///
/// `children` and `tabs` are deliberately given no field docs: they hold
/// components, and a form that offered to type one in would be offering
/// something that cannot work. A container is configured by its properties and
/// filled by its `+` buttons, which is the split the whole design rests on.
pub fn builtin_descriptors(
  comps : Array[@component.Component],
) -> Array[@registry.Descriptor] {
  let by_name : Map[String, @component.Component] = Map([])
  for c in comps {
    by_name[c.name] = c
  }
  let out : Array[@registry.Descriptor] = []
  let add = (
    name : String,
    doc : String,
    keywords : Array[String],
    category : String,
    fields : Map[String, @jsonschema.FieldDoc],
    inits : Array[@registry.InitInfo],
    filled : Array[String],
  ) => {
    match by_name.get(name) {
      Some(c) =>
        out.push(
          descriptor_of(c, doc~, keywords~, category~, fields~, inits~, filled~),
        )
      // Nothing to describe, so nothing is described. A name here that the std
      // module no longer declares should not invent a catalog entry for a
      // component that cannot be built.
      None => ()
    }
  }
  add(
    "Universal",
    "An empty cell. Click the + inside it to choose what goes there.",
    ["empty", "placeholder", "add", "any", "cell", "slot"],
    "layout",
    Map([]),
    [],
    ["child"],
  )
  add(
    "Stack",
    "A row or a column: everything about it is direction, spacing and alignment.",
    ["layout", "flex", "row", "column", "stack", "container", "list"],
    "layout",
    {
      "direction": choices(
        "Which way the children run.",
        of=["column", "row", "column-reverse", "row-reverse"],
        d="column",
      ),
      "justify": choices(
        "How spare room along the direction is distributed.",
        of=[
          "start", "center", "end", "space-between", "space-around", "space-evenly",
        ],
        d="start",
      ),
      "align": choices(
        "How the children sit across the direction.",
        of=["stretch", "start", "center", "end", "baseline"],
        d="stretch",
      ),
      "gap": ranged("Pixels between children.", 0, 64, 8),
      "padding": ranged("Pixels inside the edge.", 0, 64, 0),
      "wrap": fd(
        "Let the children run onto another line when they do not fit.",
        c={ ..@jsonschema.Constraint::none(), default: Some(Bool(false)) },
      ),
    },
    [
      { name: "row", doc: "Side by side.", args: { "direction": Str("row") } },
      {
        name: "column",
        doc: "One above the other.",
        args: { "direction": Str("column") },
      },
    ],
    ["children"],
  )
  add(
    "Grid",
    "A uniform grid: every cell the same size, filled left to right and top to bottom.",
    ["layout", "grid", "columns", "rows", "table", "dashboard", "tiles"],
    "layout",
    {
      "cols": ranged("How many columns.", 1, 12, 2),
      "rows": ranged("How many rows.", 1, 12, 2),
      "gap": ranged("Pixels between cells.", 0, 64, 8),
      "padding": ranged("Pixels inside the edge.", 0, 64, 0),
    },
    [],
    ["children"],
  )
  add(
    "Tabs",
    "Several pages, one at a time, with a strip of names across the top.",
    ["tabs", "pages", "notebook", "sections", "switcher"],
    "layout",
    Map([]),
    [],
    ["tabs"],
  )
  add(
    "TabPage",
    "One tab: a name on the strip, and whatever is under it.",
    ["tab", "page", "section"],
    "layout",
    { "label": text_field("What the strip calls this tab.", d="untitled") },
    [],
    ["body"],
  )
  add(
    "Text",
    "A run of text.",
    ["text", "label", "heading", "caption", "words"],
    "content",
    {
      "text": text_field("What it says."),
      "size": choices("How big.", of=["normal", "small", "large"], d="normal"),
    },
    [],
    [],
  )
  add(
    "Textarea",
    "Editable multi-line text.",
    ["text", "input", "editor", "notes", "write", "textarea"],
    "content",
    {
      "text": text_field("What is in it to start with."),
      "rows": ranged("How many lines tall.", 1, 40, 6),
      "placeholder": text_field("What it says while empty.", d="type here…"),
    },
    [],
    [],
  )
  out
}
