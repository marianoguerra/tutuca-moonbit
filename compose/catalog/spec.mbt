///|
/// The protocols a composition speaks, by id.
///
/// A SHARED VOCABULARY, and frozen as such. These strings are what a card in
/// any host declares to be placeable, holdable or configurable, so they are
/// public API in the way a type name is not: a card compiled against them is a
/// file somebody else already has. `@1` does not move. A change that would
/// break a card declaring these mints `@2` beside them and leaves these
/// answering exactly what they answer now.
///
/// They name `universal` because `demo/universal` is the reference
/// implementation and continues to be — the kit there is the worked example of
/// every one of them. The id names the vocabulary, not the directory it is
/// demonstrated in.
///
/// QUALIFIED, and that is not decoration. A protocol operation is dispatched
/// under `<protocol id>::<member>`, so a card declaring
/// `express { intent { Holder::addRequested(Bool) } }` raises THIS and not the
/// bare word — and a table keyed on the bare word matches nothing, with the
/// walk running out in silence and the `+` doing nothing at all.
pub let holder_protocol : String = "tutuca.dev/universal/Holder@1"

///|
pub let holder_hold : String = "tutuca.dev/universal/Holder@1::hold"

///|
pub let holder_empty : String = "tutuca.dev/universal/Holder@1::empty"

///|
pub let holder_add_requested : String = "tutuca.dev/universal/Holder@1::addRequested"

///|
pub let container_protocol : String = "tutuca.dev/universal/Container@1"

///|
pub let container_append : String = "tutuca.dev/universal/Container@1::appendCell"

///|
pub let container_remove_at : String = "tutuca.dev/universal/Container@1::removeAt"

///|
pub let container_insert_at : String = "tutuca.dev/universal/Container@1::insertAt"

///|
pub let container_insert_requested : String = "tutuca.dev/universal/Container@1::insertRequested"

///|
pub let container_remove_requested : String = "tutuca.dev/universal/Container@1::removeRequested"

///|
pub let editable_protocol : String = "tutuca.dev/universal/Editable@1"

///|
/// The qualified VIEW ROLE a component's settings are drawn under.
///
/// `render/components_impl.mbt` resolves this against the component's own
/// `viewBindings` and falls back to `main` for one that binds nothing — with a
/// `ProtocolViewMissing` notice rather than in silence. That fallback is what
/// makes it safe to put a whole palette of strangers into editor mode at once.
pub let editable_editor : String = "tutuca.dev/universal/Editable@1::editor"

///|
/// Which component, in which module.
pub(all) struct ComponentRef {
  module_ : String
  name : String
} derive(Eq, @debug.Debug)

///|
pub fn ComponentRef::to_id(self : ComponentRef) -> String {
  self.module_ + "/" + self.name
}

///|
/// One declared field, as much of it as a palette needs.
pub(all) struct FieldInfo {
  name : String
  ty : String
  doc : String
  required : Bool
} derive(Eq, @debug.Debug)

///|
/// A named set of construction arguments, and how many cells to open with.
///
/// `cells` is how many the container is CONSTRUCTED with — they go into the
/// `cellField` argument as a list of empty holes. Nothing sends `appendCell`
/// afterwards: an arrangement is built from the inside out and handed over
/// finished, which is the whole reason `cellField` exists.
pub(all) struct Preset {
  name : String
  doc : String
  args : Map[String, Json]
  cells : Int
} derive(Eq, @debug.Debug)

///|
/// The half a card manifest cannot carry, supplied by whoever ships the card.
///
/// WHERE A CARD IS SILENT. A `.tutu` card declares its own `~category` and
/// `~keywords` and those win; this fills in for the ones that do not, which is
/// every `.html` card — the blocks have no syntax for either and none is being
/// added. A card nobody annotated at all is still findable by its name, its
/// doc and its field names, which is the case every pasted card is in.
///
/// `presets` and `hidden` are NOT in that arrangement and never move into a
/// card. They are facts about how this host offers a component rather than
/// about what the component is: `vbox` and `hbox` are presets of `Box` here
/// and might be nothing elsewhere, and `Hole` is hidden because this shell
/// draws it, not because the card is shy.
pub(all) struct Annotation {
  keywords : Array[String]
  category : String
  presets : Array[Preset]
  /// Kept out of the palette, though still resolvable by name.
  hidden : Bool
} derive(Eq, @debug.Debug)

///|
pub fn Annotation::none() -> Annotation {
  { keywords: [], category: "", presets: [], hidden: false, }
}

///|
/// Everything known about one placeable component.
pub(all) struct Entry {
  ref_ : ComponentRef
  doc : String
  keywords : Array[String]
  category : String
  fields : Array[FieldInfo]
  /// The protocol ids this component said it implements. The ONE fact that
  /// decides whether a cell can be filled here, whether it can hold cells of
  /// its own, and whether it draws its own settings.
  implements : Array[String]
  /// Every name this component ANSWERS to.
  messages : Array[String]
  /// Every name it RAISES — the messages and intents it expresses.
  ///
  /// Separate from `messages` because they are opposite directions, and the
  /// shell cares which: a component that raises `Holder::addRequested` needs
  /// something on the other end, and one that merely answers `hold` does not.
  expresses : Array[String]
  /// The properties it lets anything outside it read.
  properties : Array[String]
  presets : Array[Preset]
  hidden : Bool
  module_doc : String
} derive(Eq, @debug.Debug)

///|
pub fn Entry::is_holder(self : Entry) -> Bool {
  self.implements.contains(holder_protocol)
}

///|
pub fn Entry::is_container(self : Entry) -> Bool {
  self.implements.contains(container_protocol)
}

///|
pub fn Entry::is_editable(self : Entry) -> Bool {
  self.implements.contains(editable_protocol)
}

///|
/// The doc's first line, which is what a row shows.
pub fn Entry::summary(self : Entry) -> String {
  match self.doc.split("\n").collect() {
    [first, ..] => first.trim().to_owned()
    _ => self.doc
  }
}
