///| The universal app: search a catalog, put what you chose where you clicked,
/// and configure what is there.
///
/// The shape worth noticing is where the truth lives. There is no document
/// beside the tree — what is on screen IS the state, and every edit is an
/// ordinary tutuca message to an ordinary component. A `+` asks, the app
/// answers, and the answer arrives at the exact component that asked because
/// `ctx.target_path()` said which one it was.
///
/// That is also why the app is thin. Arranging is the containers' job,
/// holding is the universal's, and rendering is everyone's. What is left here
/// is the one thing no component can do for itself: turning "the thing called
/// Counter in the module called counterlib" into a live instance.

///|
/// Builds a component instance for the app to place.
///
/// The one thing this package cannot do for itself: turning a
/// `(module, name, init, args)` into a live guest instance needs the dyncomp
/// bridge, which is wasm-gc-only. Taking it as a function is what keeps the
/// app backend-agnostic and therefore testable on the in-memory DOM.
///
/// Standard components never reach it — they are built directly, because they
/// are compiled in.
pub type MakeInstance = (
  @registry.ComponentRef,
  String,
  Map[String, @tutuca.Value],
) -> @tutuca.Value?

///|
/// The app's components, and everything they need from outside.
pub struct UniversalUi {
  /// The catalog to search: the standard components and whatever is loaded.
  registry : @registry.Registry
  /// How to build a loaded component.
  make : MakeInstance
  /// How to build a standard one.
  std : @std.Std
  /// The app's own chrome, by name. Filled in after every component is built
  /// and read only at dispatch time — the `reg` pattern `inspector/` takes for
  /// the same reason.
  comps : Map[String, @component.Component]
  /// Where the last request came from.
  ///
  /// A `DispatchPath` is not a `Value` — it carries dynamic-render markers a
  /// JSON shape would have to invent a spelling for — and what it names is
  /// transient focus that nothing persists. So it is held beside the state
  /// rather than in it, the way `demo/universal_wasm` already keeps its
  /// in-flight loads.
  asked : Ref[@tutuca.DispatchPath?]
  /// The cell whose contents the config panel is about, or None when nothing
  /// is being configured.
  ///
  /// Both panel modes set it, because both need to write back to that cell —
  /// but only `view` mode also TAKES the instance out of the tree (an instance
  /// rendered in two places has one of them holding a collected handle). Which
  /// mode is in play is read off the panel, not stored twice.
  configuring : Ref[@tutuca.DispatchPath?]
}

///|
fn UniversalUi::make_(
  self : UniversalUi,
  name : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args)
    None => Null
  }
}

///|
/// Build any component in the catalog.
///
/// The ONE place a standard component and a loaded one are told apart, and it
/// is about where the code is rather than about what the component is: one is
/// compiled in, the other arrived in an archive. Searching, describing,
/// forming, validating and placing are the same for both.
fn UniversalUi::build(
  self : UniversalUi,
  ref_ : @registry.ComponentRef,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value? {
  if !is_builtin(ref_) {
    // No fixture name crosses here. A named fixture is resolved to its
    // arguments by whoever asked (`place_form`), because a fixture is a
    // statement about ARGUMENTS and this seam is the only one that takes them —
    // the other thing a person does with a fixture is apply it to a component
    // that already exists, which constructs nothing at all.
    return (self.make)(ref_, "", args)
  }
  match self.std.build(ref_.name, args) {
    Null => None
    v => Some(v)
  }
}

///|
/// A component's descriptor, found from a live instance.
///
/// By declared NAME, because that is all an instance carries — `schema`
/// says what it declared and not which module it came from. Two modules
/// declaring the same name would make this ambiguous; the first match wins,
/// and the catalog's own order puts the standard components first.
fn UniversalUi::describe_instance(
  self : UniversalUi,
  inst : @tutuca.Value,
) -> @registry.Descriptor? {
  guard inst.schema() is Some(schema) else { return None }
  for d in self.registry.all() {
    if d.schema.name == schema.name {
      return Some(d)
    }
  }
  None
}

// --- the command bar --------------------------------------------------------

///|
fn UniversalUi::bar_for(
  self : UniversalUi,
  query : String,
  configure? : Bool = false,
) -> @tutuca.Value {
  let hits = self.registry.search(query, limit=25)
  let rows : Array[@tutuca.Value] = []
  for i, h in hits {
    rows.push(
      self.make_("PaletteRow", {
        "module": Str(h.descriptor.ref_.module_),
        "name": Str(h.descriptor.ref_.name),
        "summary": Str(h.descriptor.summary()),
        "why": Str(h.why.join(" · ")),
        "category": Str(h.descriptor.category),
        "selected": Bool(i == 0),
      }),
    )
  }
  let empty = if query == "" {
    "no components"
  } else {
    "nothing matches \"\{query}\""
  }
  self.make_("CommandBar", {
    "query": Str(query),
    "hits": List(rows),
    "cursor": Num(0.0),
    "configure": Bool(configure),
    "emptyMessage": Str(empty),
  })
}

// --- the generated form -----------------------------------------------------

///|
/// One key of a JSON object, or None.
fn at(j : Json, key : String) -> Json? {
  if j is Object(m) {
    m.get(key)
  } else {
    None
  }
}

///|
/// The control a field's schema calls for.
///
/// Four real controls and a JSON fallback. The fallback is honest rather than
/// lazy: a list-of-records editor is a real feature, and drawing three text
/// boxes for one would be pretending to be it.
fn control_for(schema : Json) -> String {
  if at(schema, "enum") is Some(_) {
    return "enum"
  }
  match at(schema, "type") {
    Some(String("boolean")) => "bool"
    Some(String("integer")) | Some(String("number")) => "number"
    Some(String("string")) => "string"
    _ => "json"
  }
}

///|
/// What the constraint says, for the label. The half a type cannot state, and
/// the half a person needs to see BEFORE submitting rather than in an error
/// afterwards.
fn hint_for(schema : Json, kind : String) -> String {
  let parts : Array[String] = []
  let num = (key : String) => {
    match at(schema, key) {
      Some(Number(n, ..)) => Some(n)
      _ => None
    }
  }
  match (num("minimum"), num("maximum")) {
    (Some(lo), Some(hi)) => parts.push("\{lo}…\{hi}")
    (Some(lo), None) => parts.push("≥ \{lo}")
    (None, Some(hi)) => parts.push("≤ \{hi}")
    (None, None) => ()
  }
  match (num("minLength"), num("maxLength")) {
    (Some(lo), Some(hi)) => parts.push("\{lo.to_int()}–\{hi.to_int()} chars")
    (Some(lo), None) => parts.push("≥ \{lo.to_int()} chars")
    (None, Some(hi)) => parts.push("≤ \{hi.to_int()} chars")
    (None, None) => ()
  }
  if at(schema, "format") is Some(String(f)) {
    parts.push(f)
  }
  if kind == "json" {
    parts.push("JSON")
  }
  parts.join(" · ")
}

///|
/// The choices of an enum field, as strings for the `<option>`s.
fn choices_for(schema : Json) -> Array[@tutuca.Value] {
  match at(schema, "enum") {
    Some(Array(items)) =>
      items.map(i => (Str(@tutuca.Value::from_json(i).str()) : @tutuca.Value))
    _ => []
  }
}

///|
/// The value a field starts at: what an existing instance already holds when
/// there is one, the schema's `default` when there is not, and blank
/// otherwise.
///
/// NOT the type's zero. A default is a claim about what is usually wanted; a
/// zero is only a claim about the type.
fn start_value(schema : Json, current : @tutuca.Value?) -> @tutuca.Value {
  match current {
    Some(v) if !(v is Null) => v
    _ =>
      match at(schema, "default") {
        Some(String(s)) => Str(s)
        Some(True) => Bool(true)
        Some(False) => Bool(false)
        Some(Number(n, ..)) => Num(n)
        Some(d) => @tutuca.Value::from_json(d)
        // NOT `Str("")`. "Nothing here" has to be a value no control can turn
        // into content: a blank string is what a JSON box would encode as
        // `""`, which then fails validation for a field nobody filled in.
        None => Null
      }
  }
}

///|
/// What a control STARTS with, as the text it holds.
///
/// Per KIND, not per value shape, and that distinction is the whole of it: the
/// `json` control is read back by parsing its text, so it has to be given JSON
/// — a list pre-filled with its display string (`[0]` shown as `0`) parses as
/// a number, and the schema then refuses the field a person never touched.
/// That failure is invisible: the form was pre-filled from the instance, so
/// every value in it looks like one that was already accepted.
fn control_text(v : @tutuca.Value, kind : String) -> String {
  match kind {
    "json" => if v is Null { "" } else { v.to_json().stringify() }
    "number" =>
      match v {
        Num(n) =>
          if n == n.to_int().to_double() {
            n.to_int().to_string()
          } else {
            n.to_string()
          }
        other => other.to_display_string()
      }
    _ =>
      match v {
        Str(t) => t
        Null => ""
        other => other.to_display_string()
      }
  }
}

///|
/// A form over a component's declared arguments, generated from the JSON
/// Schema the catalog projects.
///
/// No per-component code and no branch on where the component came from: the
/// same projection an agent's tool reads is the one this draws.
///
/// `values` is what an EXISTING instance holds, so reconfiguring opens on what
/// is there rather than on the defaults — the difference between changing a
/// gap and retyping every property to change one.
fn UniversalUi::form_for(
  self : UniversalUi,
  d : @registry.Descriptor,
  values? : Map[String, @tutuca.Value] = Map([]),
  submit_label? : String = "Place",
) -> @tutuca.Value {
  let schema = d.args_schema()
  let required : Array[String] = match at(schema, "required") {
    Some(Array(items)) =>
      items.filter_map(i => {
        match i {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
  let fields : Array[@tutuca.Value] = []
  if at(schema, "properties") is Some(Object(props)) {
    for name, fs in props {
      let kind = control_for(fs)
      let start = start_value(fs, values.get(name))
      fields.push(
        self.make_("SchemaField", {
          "name": Str(name),
          "kind": Str(kind),
          "hint": Str(hint_for(fs, kind)),
          "doc": Str(
            match at(fs, "description") {
              Some(String(s)) => s
              _ => ""
            },
          ),
          "required": Bool(required.contains(name)),
          "text": Str(control_text(start, kind)),
          "num": Num(start.num()),
          "flag": Bool(start.is_truthy()),
          "choices": List(choices_for(fs)),
          "error": Str(""),
        }),
      )
    }
  }
  let inits : Array[@tutuca.Value] = d.inits.map(i => {
    (
      Map({
        "name": Str(i.name),
        "label": Str(
          if i.doc == "" {
            i.name
          } else {
            "\{i.name} — \{i.doc}"
          },
        ),
      }) : @tutuca.Value)
  })
  self.make_("SchemaForm", {
    "module": Str(d.ref_.module_),
    "name": Str(d.ref_.name),
    "title": Str(d.ref_.to_id()),
    "doc": Str(d.doc),
    "fields": List(fields),
    "inits": List(inits),
    "error": Str(""),
    "submitLabel": Str(submit_label),
  })
}

///|
/// Read the filled-in form back as the JSON its schema describes.
///
/// The controls hold text, so this is where a `"3"` becomes a `3` — but only
/// as far as the control's KIND says, never by guessing. Everything else that
/// could be wrong (a range, a length, a required field) is the schema's to
/// catch, and `Descriptor::coerce_args` is what catches it.
fn form_args(fields : Array[@tutuca.Value]) -> Json {
  let out : Map[String, Json] = Map([])
  for f in fields {
    let name = f.field("name").str()
    if name == "" {
      continue
    }
    let kind = f.field("kind").str()
    out[name] = match kind {
      "bool" => Json::boolean(f.field("flag").is_truthy())
      "number" =>
        Json::number(
          @string.parse_double(f.field("text").str()) catch {
            _ => f.field("num").num()
          },
        )
      "json" => {
        let raw = f.field("text").str()
        if raw == "" {
          continue
        }
        @json.parse(raw) catch {
          _ => Json::string(raw)
        }
      }
      _ => Json::string(f.field("text").str())
    }
  }
  Json::object(out)
}

///|
/// The arguments a component is placed with when nobody filled anything in.
///
/// `coerce` does not fill defaults for absent fields — an absent optional stays
/// absent — so "place it with its defaults" has to materialize them first, out
/// of the same projection the form reads. A component whose required fields
/// have no default cannot be placed this way, which is what makes the caller
/// open the form instead.
fn defaults_of(
  d : @registry.Descriptor,
) -> Result[Map[String, @tutuca.Value], Array[@jsonschema.SchemaError]] {
  let out : Map[String, Json] = Map([])
  if at(d.args_schema(), "properties") is Some(Object(props)) {
    for name, fs in props {
      if at(fs, "default") is Some(v) {
        out[name] = v
      }
    }
  }
  d.coerce_args(Json::object(out))
}

///|
/// Build a standard component by name, with everything a container needs to be
/// usable already in it.
///
/// Public for one caller: a host putting a saved page back together. It goes
/// through the same `Std` the app places with, so a restored tree is built by
/// the same code that built it the first time.
pub fn UniversalUi::build_standard(
  self : UniversalUi,
  name : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  self.std.build(name, args)
}
