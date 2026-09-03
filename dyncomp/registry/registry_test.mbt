///| Blackbox tests over two registered bundles.
///
/// The guest here is a stub: the catalog never calls one. That is the property
/// worth stating up front — describing forty components reads data the host
/// already parsed and does not cross the boundary once, which is why a palette
/// can render the whole catalog and a search can rank it.

///|
priv struct StubGuest {}

///|
impl @dyncomp.Guest for StubGuest with fn create(_self, _component, _args) {
  0
}

///|
impl @dyncomp.Guest for StubGuest with fn get_field(_self, _handle, _name) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn handle_dispatch(
  _self,
  _handle,
  _bucket,
  _name,
  _args,
  _bindings,
) {
  { handled: false, next: None, msgs: [], }
}

///|
impl @dyncomp.Guest for StubGuest with fn render_call(
  _self,
  _handle,
  _category,
  _name,
  _args,
  _bindings,
) {
  Null
}

///|
impl @dyncomp.Guest for StubGuest with fn with_field(_self, _handle, _name, _v) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn serve_intent(_self, name, _args) {
  Err(Str("no such service: \{name}"))
}

///|
impl @dyncomp.Guest for StubGuest with fn persist(_self, _handle) {
  b""
}

///|
impl @dyncomp.Guest for StubGuest with fn restore(_self, _component, _state) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn drop_instance(_self, _handle) {

}

///|
fn ty(kind : String) -> @dyncomp.DynTyDef {
  { kind, elem: None, items: [], name: "", members: [], }
}

///|
fn plain(
  name : String,
  ty_ : @tutuca.Ty,
  doc? : String = "",
) -> @dyncomp.DynFieldDef {
  { name, ty: ty_, doc, required: false, default: None, domains: [], }
}

///|
/// A counter bundle, documented the way v3 lets a guest document itself.
fn counter_bundle() -> @dyncomp.DynManifest {
  {
    api_version: 10,
    module_name: "counterlib",
    doc: "Sample counters.",
    version: "0.3.0",
    homepage: "",
    authors: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Counter",
        doc: "A number with buttons that raise and lower it.",
        keywords: ["tally", "increment"],
        category: "input",
        message_docs: {
          "inc": "Add one.",
          "label": "The count, as a sentence.",
        },
        views: [
          {
            name: "main",
            html: "<div><button @on.click=\"inc\">+</button><span @text=\".count\"></span></div>",
          },
        ],
        types: [ty("ty-float")],
        fields: [plain("count", TyFloat, doc="The current value.")],
        properties: [],
        domains: [],
        receives: [],
        intents: [],
        express_messages: [],
        express_intents: [],
        implements: [],
        protocols: [],
        property_bindings: [],
        view_bindings: [],
        provide_bindings: [],
        lookup_bindings: [],
        methods: ["label"],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        provide: [],
        lookup: [],
        inits: [
          {
            name: "at-three",
            args: { "count": Num(3) },
            doc: "Starts at three.",
            view: "",
            tags: [],
            default_: false,
            drive_json: "",
            intents_json: "",
          },
        ],
        style: "",
      },
    ],
  }
}

///|
/// A task list, so search has something to choose BETWEEN — a ranking over one
/// component proves nothing.
fn todo_bundle() -> @dyncomp.DynManifest {
  {
    api_version: 10,
    module_name: "todolib",
    doc: "A sample task list.",
    version: "0.3.0",
    homepage: "",
    authors: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Todo",
        doc: "A task list: type a task, add it, tick it off.",
        keywords: ["task", "checklist"],
        category: "input",
        message_docs: { "add": "Add the drafted task." },
        views: [
          {
            name: "main",
            html: "<div><input @on.input=\".draft = e.value\" /><button @on.click=\"add\">Add</button></div>",
          },
        ],
        types: [ty("ty-text"), ty("ty-record")],
        fields: [
          plain("draft", TyText, doc="The task being typed."),
          plain("items", TyRecord("")),
        ],
        properties: [],
        domains: [],
        receives: [],
        intents: [],
        express_messages: [],
        express_intents: [],
        implements: [],
        protocols: [],
        property_bindings: [],
        view_bindings: [],
        provide_bindings: [],
        lookup_bindings: [],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        serves: [],
        provide: [],
        lookup: [],
        inits: [],
        style: "",
      },
    ],
  }
}

///|
fn loaded() -> Registry raise {
  let scope = @component.ComponentStack::new()
  let reg = Registry::new()
  reg.register(
    @dyncomp.register_bundle(scope, StubGuest::{ }, counter_bundle()),
  )
  reg.register(@dyncomp.register_bundle(scope, StubGuest::{ }, todo_bundle()))
  reg
}

///|
test "the catalog lists every component of every loaded module" {
  let reg = loaded()
  debug_inspect(reg.modules(), content="[\"counterlib\", \"todolib\"]")
  debug_inspect(
    reg.all().map(d => d.ref_.to_id()),
    content="[\"counterlib/Counter\", \"todolib/Todo\"]",
  )
}

///|
/// The whole point of v3: a catalog entry that says something. Before it,
/// every one of these fields was empty and a chooser had only a name.
test "a descriptor carries what a chooser needs" {
  let reg = loaded()
  guard! reg.describe({ module_: "counterlib", name: "Counter", }) is Some(d)
  inspect(d.doc, content="A number with buttons that raise and lower it.")
  inspect(d.category, content="input")
  debug_inspect(d.keywords, content="[\"tally\", \"increment\"]")
  inspect(d.module_version, content="0.3.0")
  // `inputs` comes off the COMPILED views, not the manifest — the same
  // asymmetry the contract has everywhere
  debug_inspect(
    d.messages.map(m => "\{m.bucket}:\{m.name}"),
    content=(
      #|["receive:inc", "method:label"]
    ),
  )
  // the flat message-docs table spread back over the buckets it describes
  debug_inspect(
    d.messages.map(m => m.doc),
    content="[\"Add one.\", \"The count, as a sentence.\"]",
  )
  debug_inspect(
    d.inits.map(i => "\{i.name}: \{i.doc}"),
    content="[\"at-three: Starts at three.\"]",
  )
}

///|
/// An undocumented component still says something. A palette row that read
/// blank would be worse than one that reads "count: f64".
test "summary falls back through doc, keywords, then the shape" {
  let reg = loaded()
  guard! reg.describe({ module_: "counterlib", name: "Counter", }) is Some(d)
  inspect(d.summary(), content="A number with buttons that raise and lower it.")
  let bare : Descriptor = { ..d, doc: "", keywords: [], }
  inspect(bare.summary(), content="count: Double")
  let kw : Descriptor = { ..d, doc: "", }
  inspect(kw.summary(), content="tally, increment")
}

///|
/// The descriptor pairs the schema with the right docs so a caller never has
/// to, which is what keeps the form and the tool describing the same thing.
test "a descriptor projects its own args schema, and coerces against it" {
  let reg = loaded()
  guard! reg.describe({ module_: "counterlib", name: "Counter", }) is Some(d)
  let props = d.args_schema()
  inspect(
    (if props is Object(m) { m.get("properties") } else { None })
    .unwrap()
    .stringify(),
    content=(
      #|{"count":{"type":"number","description":"The current value."}}
    ),
  )
  guard! d.coerce_args(@json.parse("{\"count\": 4}")) is Ok(args)
  debug_inspect(
    args,
    content=(
      #|{ "count": RNum(4) }
    ),
  )
  // and the same descriptor rejects what its schema forbids
  guard! d.coerce_args(@json.parse("{\"count\": \"x\"}")) is Err(errors)
  debug_inspect(
    errors.map(e => "\{e.pointer}: \{e.message}"),
    content="[\"/count: expected Double, got string\"]",
  )
}

///|
/// The weights are a claim, so a score is checkable arithmetic rather than a
/// number to accept: 100 for being CALLED that, plus 8 because the module is
/// too. Nothing else in this component mentions the word.
test "an exact name match outscores every other kind" {
  let reg = loaded()
  let hits = reg.search("counter")
  debug_inspect(
    hits.map(h => "\{h.descriptor.ref_.to_id()} \{h.score}"),
    content=(
      #|["counterlib/Counter 108"]
    ),
  )
  debug_inspect(
    hits[0].why,
    content="[\"name is \\\"counter\\\"\", \"module \\\"counterlib\\\"\"]",
  )
  // ...and it outscores the best a keyword can do (30) by more than three
  // times, which is the ordering the weights exist to state
  debug_inspect(reg.search("tally").map(h => h.score), content="[30]")
}

///|
/// A search a person cannot explain is one they stop trusting, and a model
/// handed a ranked list with no reasons takes the order on faith.
test "a match says why it matched" {
  let reg = loaded()
  let hits = reg.search("task")
  debug_inspect(
    hits.map(h => h.descriptor.ref_.to_id()),
    content="[\"todolib/Todo\"]",
  )
  debug_inspect(
    hits[0].why,
    content=(
      #|[
      #|  "keyword \"task\"",
      #|  "described as containing \"task\"",
      #|  "field \"draft\"",
      #|]
    ),
  )
}

///|
/// Both are filed under `input` and match on nothing else, so they tie — and a
/// tie falls back to the catalog's own order (load, then declaration) rather
/// than to whatever the sort happened to do. Two equally good matches swapping
/// places between identical calls is the kind of thing that makes a palette
/// feel broken.
test "an equal match ties, and the catalog's order breaks it" {
  let reg = loaded()
  let hits = reg.search("input")
  debug_inspect(
    hits.map(h => "\{h.descriptor.ref_.to_id()} \{h.score}"),
    content=(
      #|["counterlib/Counter 15", "todolib/Todo 15"]
    ),
  )
  debug_inspect(
    reg.search("input").map(h => h.descriptor.ref_.to_id()),
    content="[\"counterlib/Counter\", \"todolib/Todo\"]",
  )
}

///|
/// Counted once per term however many members match. Todo's `add` matches BOTH
/// the message name and that message's doc, and contributes 4 rather than 8 —
/// a component with eight fields mentioning a word is not eight times as
/// relevant as one with a single field named exactly it.
///
/// Counter's 4 is the same rule seen from the other side: "Add one." is the
/// doc on its `inc` handler, so it is a real if faint match, and the `why` is
/// what stops that from looking like a bug.
test "member matches do not compound" {
  let reg = loaded()
  let hits = reg.search("add")
  debug_inspect(
    hits.map(h => "\{h.descriptor.ref_.to_id()} \{h.score}"),
    content=(
      #|["todolib/Todo 14", "counterlib/Counter 4"]
    ),
  )
  // 10 for the doc + 4 for the member, once
  debug_inspect(
    hits[0].why,
    content=(
      #|["described as containing \"add\"", "receive \"add\""]
    ),
  )
  debug_inspect(
    hits[1].why,
    content=(
      #|["receive \"inc\""]
    ),
  )
}

///|
test "a query that matches nothing returns nothing" {
  let reg = loaded()
  debug_inspect(reg.search("wombat").map(h => h.score), content="[]")
}

///|
/// "Show me everything" is the commonest search there is — it is what a
/// palette opens with — so an empty query is the whole catalog, not nothing.
test "an empty query is the whole catalog, and limit bounds it" {
  let reg = loaded()
  debug_inspect(
    reg.search("").map(h => h.descriptor.ref_.to_id()),
    content="[\"counterlib/Counter\", \"todolib/Todo\"]",
  )
  debug_inspect(reg.search("", limit=1).length(), content="1")
  debug_inspect(reg.search("input", limit=1).length(), content="1")
}

///|
/// Loading a module that is already registered is a hot swap everywhere else
/// in this system, and the catalog has to answer with the new components the
/// moment it happens — without the module jumping in a palette.
test "re-registering a module replaces it and keeps its place" {
  let scope = @component.ComponentStack::new()
  let reg = Registry::new()
  reg.register(
    @dyncomp.register_bundle(scope, StubGuest::{ }, counter_bundle()),
  )
  reg.register(@dyncomp.register_bundle(scope, StubGuest::{ }, todo_bundle()))
  let swapped : @dyncomp.DynManifest = {
    ..counter_bundle(),
    components: [
      { ..counter_bundle().components[0], name: "Tally", doc: "Renamed.", },
    ],
  }
  reg.register(@dyncomp.register_bundle(scope, StubGuest::{ }, swapped))
  debug_inspect(reg.modules(), content="[\"counterlib\", \"todolib\"]")
  debug_inspect(
    reg.all().map(d => d.ref_.to_id()),
    content="[\"counterlib/Tally\", \"todolib/Todo\"]",
  )
  assert_true(reg.describe({ module_: "counterlib", name: "Counter", }) is None)
}

///|
test "forgetting a module drops its components" {
  let reg = loaded()
  reg.forget("counterlib")
  debug_inspect(reg.modules(), content="[\"todolib\"]")
  debug_inspect(
    reg.all().map(d => d.ref_.to_id()),
    content="[\"todolib/Todo\"]",
  )
}

///|
/// One document for the palette row and the tool result alike. A second
/// projection for the agent would be a second place for the catalog to
/// describe a component differently from how the UI does.
test "a hit and a descriptor each have one JSON projection" {
  let reg = loaded()
  let hit = reg.search("tally")[0]
  inspect(
    hit.to_json().stringify(),
    content=(
      #|{"module":"counterlib","name":"Counter","summary":"A number with buttons that raise and lower it.","category":"input","score":30,"why":["keyword \"tally\""]}
    ),
  )
  guard! reg.describe({ module_: "todolib", name: "Todo", }) is Some(d)
  let doc = d.to_json()
  guard! doc is Object(m)
  debug_inspect(
    m.keys().collect(),
    content=(
      #|[
      #|  "module",
      #|  "name",
      #|  "doc",
      #|  "summary",
      #|  "category",
      #|  "keywords",
      #|  "argsSchema",
      #|  "messages",
      #|  "inits",
      #|  "moduleDoc",
      #|  "moduleVersion",
      #|]
    ),
  )
}
