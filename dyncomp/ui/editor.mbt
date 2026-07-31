///| The universal UI: search a catalog, fill in a form, arrange what you placed.
///
/// The shape worth noticing is where the truth lives. `SurfaceEditorState.doc`
/// holds the surface DOCUMENT — the same JSON an agent reads back with
/// `ui_read` and a person exports — and every edit is a `SurfaceOp` batch
/// applied to it. `tree` is what the document renders to, rebuilt afterwards.
///
/// That ordering is the whole reason the human layer and the agent layer are
/// one system: a button here and a tool call there produce the same op against
/// the same document, so there is no shape one can reach and the other cannot.

///|
/// Builds a component instance for `make_` to hand back.
///
/// The one thing this package cannot do for itself: turning a
/// `(module, name, init, args)` into a live instance needs the dyncomp bridge,
/// which is wasm-gc-only. Taking it as a function is what keeps the editor
/// backend-agnostic and therefore testable on the in-memory DOM.
pub type MakeInstance = (
  @registry.ComponentRef,
  String,
  Map[String, @tutuca.Value],
) -> @tutuca.Value?

///|
/// The editor's components, and the two things they need from outside: the
/// catalog to search, and a way to build what was chosen.
pub struct UniversalUi {
  registry : @registry.Registry
  make : MakeInstance
  /// Filled in after every component is built, and read only at dispatch time.
  /// The editor builds palette rows and form fields, and those components are
  /// built by the same constructor that builds the editor — the `reg` pattern
  /// `inspector/` takes for the same reason.
  comps : Map[String, @component.Component]
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

// --- the document -----------------------------------------------------------

///|
/// The surface a `doc` field holds. A document that will not read back is
/// replaced by an empty surface rather than crashing the editor: the failure
/// belongs in the status line, and the only way to get one here is an import.
fn surface_of(doc : @tutuca.Value) -> @surface.Surface {
  match @surface.Surface::from_json(doc.to_json()) {
    Some(s) => s
    None => @surface.Surface::new("main")
  }
}

///|
fn doc_of(s : @surface.Surface) -> @tutuca.Value {
  @tutuca.Value::from_json(s.to_json())
}

// --- the live instances -----------------------------------------------------

///|
/// The instances a rendered editor is holding, by the slot that holds them.
///
/// Read out of the TREE rather than from a map kept beside it, because the
/// tree is where a successor lands: a click inside a placed component
/// dispatches down the render path and swaps that node's instance for its
/// successor, and anything else holding the old one is holding a dead handle
/// one drained cascade later. A copy would be right until the first time
/// somebody used what was placed, which is the worst kind of right.
///
/// Public because the shell needs the same answer for a different reason —
/// what to store — and two walks of the same tree would be two chances to
/// disagree about it.
pub fn live_slots(editor : @tutuca.Value) -> Map[String, @tutuca.Value] {
  slots_of_tree(editor.field("tree"))
}

///|
/// The same walk, from the tree itself — what the editor has in hand.
fn slots_of_tree(tree : @tutuca.Value) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  collect_slots(tree, out)
  out
}

///|
fn collect_slots(
  node : @tutuca.Value,
  into : Map[String, @tutuca.Value],
) -> Unit {
  guard node is Obj(_) else { return }
  let id = node.field("nodeId").str()
  if id != "" && node.field("slot") is Obj(_) {
    into[id] = node.field("slot")
  }
  if node.field("children") is List(children) {
    for child in children {
      collect_slots(child, into)
    }
  }
}

// --- the rendered tree ------------------------------------------------------

///|
/// A node's label: what it is and which one it is. Short, because it sits in a
/// badge on top of the thing it names.
fn node_label(n : @surface.Node) -> String {
  match n.bound {
    Some(b) => "\{b.name}"
    None => "\{n.kind.to_string()} \{n.id}"
  }
}

///|
/// Build the SurfaceNode tree a document renders to.
///
/// `slots` carries the LIVE instances forward: the document holds a reference
/// and the host built the instance, so a rebuild that dropped them would reset
/// every placed component's state on every edit — which is what "the document
/// is the source of truth" would cost if the instances lived in it.
fn UniversalUi::build_tree(
  self : UniversalUi,
  s : @surface.Surface,
  slots : Map[String, @tutuca.Value],
  selected : String,
  id? : String = "",
  depth? : Int = 0,
) -> @tutuca.Value {
  let node_id = if id == "" { s.root } else { id }
  if depth > 32 {
    return Null
  }
  guard s.node(node_id) is Some(n) else { return Null }
  let children : Array[@tutuca.Value] = n.children.map(c => {
    self.build_tree(s, slots, selected, id=c, depth=depth + 1)
  })
  // Cell placement and container layout land on the same element, which is
  // what CSS wants — `grid-column-end: span 2` and `display: flex` are about
  // different relationships, not different boxes.
  let cell = n.cell_style()
  let container = n.container_style()
  let style = if cell == "" {
    container
  } else if container == "" {
    cell
  } else {
    "\{cell};\{container}"
  }
  let filled = slots.get(node_id).unwrap_or(Null)
  self.make_("SurfaceNode", {
    "nodeId": Str(node_id),
    "kind": Str(n.kind.to_string()),
    "style": Str(style),
    "label": Str(node_label(n)),
    "children": List(children),
    "slot": filled,
    "selected": Bool(node_id == selected),
    // A slot with nothing in it draws a placeholder; a container never does,
    // because an empty container is its own visible outline.
    "empty": Bool(n.kind is Slot && filled is Null),
  })
}

// --- the settings panel -----------------------------------------------------

///|
/// The panel for the selected node, or `Null` when nothing is selected —
/// which is what `<x render=".settings">` renders as nothing.
fn UniversalUi::settings_for(
  self : UniversalUi,
  s : @surface.Surface,
  selected : String,
) -> @tutuca.Value {
  guard s.node(selected) is Some(n) else { return Null }
  let p = n.props
  self.make_("NodeSettings", {
    "nodeId": Str(n.id),
    "kind": Str(n.kind.to_string()),
    "direction": Str(p.direction.to_css()),
    "justify": Str(justify_name(p.justify)),
    "align": Str(align_name(p.align)),
    "gap": Num(p.gap.to_double()),
    "padding": Num(p.padding.to_double()),
    "wrap": Bool(p.wrap),
    "columns": Str(p.columns.map(t => t.to_css()).join(" ")),
    "colSpan": Num(p.col_span.to_double()),
    "rowSpan": Num(p.row_span.to_double()),
    "isContainer": Bool(n.kind.is_container()),
    "isGrid": Bool(n.kind is Grid),
  })
}

///|
/// The document's spelling of a `justify`, which is not the CSS it renders to:
/// a panel offers `start`, the style says `flex-start`. Mirrors the serializer,
/// because the `<option value>` a person picks is what an op carries.
fn justify_name(j : @surface.Justify) -> String {
  match j {
    Start => "start"
    Center => "center"
    End => "end"
    SpaceBetween => "space-between"
    SpaceAround => "space-around"
    SpaceEvenly => "space-evenly"
  }
}

///|
fn align_name(a : @surface.Align) -> String {
  match a {
    AStart => "start"
    ACenter => "center"
    AEnd => "end"
    AStretch => "stretch"
    ABaseline => "baseline"
  }
}

// --- the palette ------------------------------------------------------------

///|
fn UniversalUi::palette_for(
  self : UniversalUi,
  query : String,
) -> @tutuca.Value {
  let hits = self.registry.search(query, limit=25)
  let rows : Array[@tutuca.Value] = hits.map(h => {
    self.make_("PaletteRow", {
      "module": Str(h.descriptor.ref_.module_),
      "name": Str(h.descriptor.ref_.name),
      "summary": Str(h.descriptor.summary()),
      "why": Str(h.why.join(" · ")),
      "category": Str(h.descriptor.category),
    })
  })
  let empty = if self.registry.modules().is_empty() {
    "no bundles loaded yet"
  } else if query == "" {
    "no components"
  } else {
    "nothing matches \"\{query}\""
  }
  self.make_("ComponentPalette", {
    "query": Str(query),
    "hits": List(rows),
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
/// boxes for one would be pretending to be it. Extending this is where the
/// next work on the form goes.
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
/// The value a field starts at: the schema's `default` when it stated one,
/// otherwise blank. NOT the type's zero — a default is a claim about what is
/// usually wanted, and a zero is only a claim about the type.
fn default_text(schema : Json, kind : String) -> String {
  match at(schema, "default") {
    Some(String(s)) => s
    Some(d) => d.stringify()
    None => if kind == "json" { "" } else { "" }
  }
}

///|
/// A form over a component's declared arguments, generated from the JSON
/// Schema the catalog projects. No per-component code: the same projection an
/// agent's tool reads is the one this draws.
fn UniversalUi::form_for(
  self : UniversalUi,
  d : @registry.Descriptor,
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
      let text = default_text(fs, kind)
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
          "text": Str(text),
          "num": Num(
            match at(fs, "default") {
              Some(Number(n, ..)) => n
              _ => 0.0
            },
          ),
          "flag": Bool(at(fs, "default") is Some(True)),
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
