///|
/// The kit's module name, and where it comes from.
///
/// READ OFF THE MANIFEST, never chosen here. The compiler derives it from the
/// card, and a second spelling in MoonBit is a second answer: the catalog would
/// say one name and the host would have registered another, and every component
/// would be findable and none could be built.
pub fn module_name() -> String {
  match compiled() {
    Some(card) => card.manifest_module_name()
    None => ""
  }
}

///|
/// The compiled kit, once per process.
///
/// Compiling is not free and the answer cannot change — the source is a
/// literal — so it is done on first ask and kept. A failure is kept too: a kit
/// that does not compile is a bug in this repo, and retrying it per call would
/// turn one diagnostic into one per render.
let cache : Ref[Compiled?] = Ref(None)

///|
/// What compiling the kit produced: the module bytes, and the manifest the host
/// registers it by.
pub struct Compiled {
  wasm : Bytes
  manifest : Json
  /// Empty when it compiled. A sentence a person can act on when it did not.
  error : String
}

///|
pub fn Compiled::manifest_module_name(self : Compiled) -> String {
  match self.manifest {
    Object(o) =>
      match o.get("moduleName") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
pub fn compiled() -> Compiled? {
  if cache.val is Some(_) {
    return cache.val
  }
  let out = try {
    let c = @emit.compile(card_source(), name="std")
    ({ wasm: c.wasm, manifest: c.manifest, error: "", } : Compiled)
  } catch {
    e => { wasm: b"", manifest: Json::object({}), error: e.message(), }
  }
  cache.val = Some(out)
  cache.val
}

///|
/// The palette rows for the kit's own components.
pub fn entries() -> Array[@catalog.Entry] {
  match compiled() {
    Some(card) if card.error == "" =>
      @catalog.entries_of_manifest(card.manifest, annotations=annotations())
    _ => []
  }
}

///|
fn note(
  keywords : Array[String],
  category : String,
  presets? : Array[@catalog.Preset] = [],
  hidden? : Bool = false,
) -> @catalog.Annotation {
  { keywords, category, presets, hidden, }
}

///|
fn preset(
  name : String,
  doc : String,
  args : Map[String, Json],
  cells? : Int = 0,
) -> @catalog.Preset {
  { name, doc, args, cells, }
}

///|
/// Keywords, categories and presets: the half the manifest cannot carry.
///
/// A PRESET IS ITS OWN PALETTE ROW, which is the reason `vbox` and `hbox` are
/// not components. They are one component with two answers, and a person typing
/// "vbox" still has to find one — so the catalog lists a preset beside the
/// component it configures and ranks it on its own name first.
pub fn annotations() -> Map[String, @catalog.Annotation] {
  {
    // Out of the palette, still resolvable by name: a saved arrangement names
    // holes constantly — every cell of every container is one — and nobody
    // places one on purpose.
    "Hole": note(["hole", "cell", "empty", "slot"], "layout", hidden=true),
    "Box": note(
      [
        "box", "flex", "row", "column", "stack", "hbox", "vbox", "horizontal", "vertical",
      ],
      "layout",
      presets=[
        preset(
          "hbox",
          "A row: cells left to right.",
          {
            "direction": Json::string("row"),
            "justify": Json::string("flex-start"),
            "align": Json::string("stretch"),
            "wrap": Json::boolean(false),
            "gap": Json::number(8),
            "padding": Json::number(0),
          },
          cells=2,
        ),
        preset(
          "vbox",
          "A column: cells top to bottom.",
          {
            "direction": Json::string("column"),
            "justify": Json::string("flex-start"),
            "align": Json::string("stretch"),
            "wrap": Json::boolean(false),
            "gap": Json::number(8),
            "padding": Json::number(0),
          },
          cells=2,
        ),
      ],
    ),
    "Grid": note(
      ["grid", "table", "matrix", "cells", "rows", "columns", "2x2", "3x3"],
      "layout",
      presets=[
        preset(
          "2x2",
          "Four equal cells.",
          {
            "cols": Json::number(2),
            "rows": Json::number(2),
            "gap": Json::number(8),
            "padding": Json::number(0),
          },
          cells=4,
        ),
        preset(
          "3x3",
          "Nine equal cells.",
          {
            "cols": Json::number(3),
            "rows": Json::number(3),
            "gap": Json::number(8),
            "padding": Json::number(0),
          },
          cells=9,
        ),
      ],
    ),
    "Tabs": note(
      ["tabs", "tabbed", "pages", "notebook", "sections", "switch"],
      "layout",
      presets=[
        // The LABELS travel with the cell count, and a preset for a container
        // whose cells have anything beside them has to say so. `cells` fills
        // the one field `cellField` names and nothing else — which is right,
        // because a builder cannot know that a tab strip keeps its names in a
        // parallel array, and wrong to leave to it.
        preset("two", "Two empty pages.", {
          "labels": Json::array([Json::string("one"), Json::string("two")]),
          "active": Json::number(0),
        }, cells=2),
      ],
    ),
    "Text": note(["text", "label", "caption", "title", "heading"], "content"),
    "Textarea": note(
      ["textarea", "notepad", "note", "notes", "editor", "type", "write"],
      "content",
      presets=[
        preset("notepad", "An empty note, eight lines tall.", {
          "text": Json::string(""),
          "rows": Json::number(8),
          "placeholder": Json::string("..."),
        }),
      ],
    ),
    "Markdown": note(
      ["markdown", "md", "rich text", "formatted", "document", "prose"],
      "content",
    ),
  }
}
