///| The editor, driven on the in-memory DOM.
///
/// Backend-agnostic components are what make this possible, and it is the
/// reason the package is split from the wasm shell: clicking "+ grid", typing
/// in the palette, filling a form and reading the rendered styles back are all
/// things `moon test` can do, and none of them need a browser.
///
/// The invariant every test here leans on: the DOCUMENT is the truth. What is
/// on screen is a projection of it, so asserting against the rendered styles
/// is asserting that the projection is faithful.

///|
/// A guest with just enough state to be USED: one number per instance, a
/// handler that raises it, and successors that are new handles.
///
/// Most tests here only need it to answer the manifest, but a placed component
/// nobody can click proves nothing about what the editor is holding after
/// somebody clicks one.
priv struct StubGuest {
  counts : Map[Int, Double]
  /// A text field, so a test can drive an `input` event on a form control and
  /// not only a click on a button.
  notes : Map[Int, String]
  next : Ref[Int]
}

///|
fn StubGuest::new() -> StubGuest {
  { counts: Map([]), notes: Map([]), next: { val: 0 } }
}

///|
fn StubGuest::alloc(
  self : StubGuest,
  count : Double,
  note? : String = "",
) -> Int {
  let h = self.next.val
  self.next.val = h + 1
  self.counts[h] = count
  self.notes[h] = note
  h
}

///|
impl @dyncomp.Guest for StubGuest with fn create(self, _component, args) {
  self.alloc(
    match args.get("count") {
      Some(Num(n)) => n
      _ => 0.0
    },
  )
}

///|
impl @dyncomp.Guest for StubGuest with fn get_field(self, handle, name) {
  match name {
    "count" => Some(Num(self.counts.get(handle).unwrap_or(0.0)))
    "note" => Some(Str(self.notes.get(handle).unwrap_or("")))
    _ => None
  }
}

///|
impl @dyncomp.Guest for StubGuest with fn seq_entries(_self, _handle) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn dispatch(
  self,
  handle,
  bucket,
  name,
  _args,
) {
  match (bucket, name) {
    (Input, "inc") =>
      {
        next: Some(
          self.alloc(
            self.counts.get(handle).unwrap_or(0.0) + 1.0,
            note=self.notes.get(handle).unwrap_or(""),
          ),
        ),
        msgs: [],
      }
    // the guest's own text handler: `@on.input="jot value"`
    (Input, "jot") =>
      match _args {
        [Str(text), ..] =>
          {
            next: Some(
              self.alloc(self.counts.get(handle).unwrap_or(0.0), note=text),
            ),
            msgs: [],
          }
        _ => { next: None, msgs: [] }
      }
    _ => { next: None, msgs: [] }
  }
}

///|
impl @dyncomp.Guest for StubGuest with fn call_method(
  _self,
  _handle,
  _name,
  _args,
) {
  Null
}

///|
impl @dyncomp.Guest for StubGuest with fn with_field(self, handle, name, v) {
  match (name, v) {
    ("count", Num(n)) => Some(self.alloc(n))
    _ => {
      ignore(handle)
      None
    }
  }
}

///|
impl @dyncomp.Guest for StubGuest with fn handle_request(_self, name, _args) {
  Err(Str("no such request: \{name}"))
}

///|
/// The stub keeps no state, so it persists nothing — which is also the answer
/// most components should give.
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
  { kind, elem: None, items: [], name: "", members: [] }
}

///|
/// A catalog with one documented, constrained component — which is what makes
/// the generated form worth generating.
fn stub_manifest() -> @dyncomp.DynManifest {
  {
    api_version: 4,
    module_name: "counterlib",
    doc: "Sample counters.",
    version: "0.3.0",
    homepage: "",
    authors: [],
    capabilities: [],
    components: [
      {
        name: "Counter",
        doc: "A number with buttons that raise and lower it.",
        keywords: ["tally"],
        category: "input",
        message_docs: { "inc": "Add one." },
        views: [
          {
            name: "main",
            html: "<div class=\"the-counter\"><span class=\"guest-count\" @text=\".count\"></span><button class=\"guest-inc\" @on.click=\"inc\">+</button><input class=\"guest-note\" :value=\".note\" @on.input=\"jot value\" /></div>",
          },
        ],
        types: [ty("ty-float"), ty("ty-text")],
        fields: [
          {
            name: "count",
            ty: 0,
            doc: "The current value.",
            required: false,
            constraint: Some({
              ..@jsonschema.Constraint::none(),
              min: Some(0),
              max: Some(10),
            }),
          },
          {
            name: "label",
            ty: 1,
            doc: "What to call it.",
            required: true,
            constraint: None,
          },
        ],
        handlers: ["inc", "jot"],
        receives: [],
        bubbles: [],
        responses: [],
        methods: [],
        whens: [],
        requests: [],
        inits: [
          {
            name: "at-three",
            args: { "count": Num(3) },
            doc: "Starts at three.",
          },
        ],
        style: "",
      },
    ],
  }
}

///|
/// The catalog, and the bundle it came from — registered into `scope` when a
/// test needs instances the app can RENDER, and into a throwaway one when it
/// only needs the descriptors.
fn catalog_of(
  guest : StubGuest,
  scope? : @component.ComponentStack? = None,
) -> (@registry.Registry, @dyncomp.Bundle) raise {
  let reg = @registry.Registry::new()
  let bundle = @dyncomp.register_bundle(
    match scope {
      Some(s) => s
      None => @component.ComponentStack::new()
    },
    guest,
    stub_manifest(),
  )
  reg.register(bundle)
  (reg, bundle)
}

///|
/// The catalog alone, for the tests that never build an instance from it.
fn catalog() -> @registry.Registry raise {
  catalog_of(StubGuest::new()).0
}

///|
/// The state of the stand-in below. Hand-written rather than generated because
/// one component in one test does not earn a `.html` of its own.
priv struct PlacedState {
  label : String
}

///|
impl @component.Fields for PlacedState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for PlacedState with fn decode(f) {
  guard f.get("label") is Some(Str(label)) else { return None }
  Some({ label, })
}

///|
impl @component.Fields for PlacedState with fn schema() {
  @component.SchemaInfo::new(fingerprint="placed", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
/// A stand-in for the dyncomp bridge. The editor cannot build a real guest
/// instance here, and does not need to: what it needs is something that
/// renders, so that "was it placed" is answerable from the DOM.
///
/// TYPED, and that is not incidental. `Component::for_type` — the constructor
/// the dyncomp host uses for a guest's components — leaves `make_fn` returning
/// `Null`, because a guest instance is built through the bridge and never
/// through `make`. A stand-in that has to answer `make` therefore needs a
/// state type.
fn stub_make() -> (MakeInstance, @component.Component, Ref[Array[String]]) {
  let calls : Ref[Array[String]] = { val: [] }
  let placeholder = @component.component(
    name="Placed",
    views={
      "main": @anode.View::new(
        "main",
        // A button, so a test can USE what it placed — which is the one thing
        // a stand-in that only renders could never check.
        raw_view=(
          #|<div class="placed" @text=".label" @on.click="shout"></div>
        ),
      ),
    },
    init=({ label: "" } : PlacedState),
    update=(s : PlacedState, msg, _ctx) => {
      match msg {
        Input("shout", _) => Some({ label: s.label + "!" })
        _ => None
      }
    },
  )
  let make = fn(
    ref_ : @registry.ComponentRef,
    init : String,
    args : Map[String, @tutuca.Value],
  ) -> @tutuca.Value? {
    let shown = args.get("label").unwrap_or(Str("")).str()
    calls.val.push("\{ref_.to_id()} init=\{init} label=\{shown}")
    Some(placeholder.make({ "label": Str("\{ref_.name}:\{shown}") }))
  }
  (make, placeholder, calls)
}

///|
fn mounted() -> (@harness.Harness, Ref[Array[String]]) raise {
  let (make, placeholder, calls) = stub_make()
  let (module_, seed) = seeded_editor(catalog(), make)
  // The stand-in has to be IN the module. A component the app scope never
  // registered has no id the renderer can resolve, so `<x render>` would draw
  // nothing — which in the real shell is the dyncomp host's job, since it
  // registers a bundle's components as it loads them.
  let with_stub = @component.ModuleDef::new(
    name=module_.name,
    components=module_.components + [placeholder],
  )
  (@harness.mount(with_stub, "SurfaceEditor", args=seed), calls)
}

///|
/// `Harness::attr` answers `None` for an element with no such attribute, and
/// "" reads better than `Some("")` in every assertion here.
fn style_of(h : @harness.Harness, sel : String, nth~ : Int) -> String raise {
  h.attr(sel, "style", nth~).unwrap_or("")
}

///|
/// The document, read back out of the live editor. Every assertion about "what
/// did that click actually do" goes through here rather than through the DOM,
/// because the DOM is the projection and this is the thing.
fn doc_json(h : @harness.Harness) -> Json {
  h.drive_value().field("doc").to_json()
}

///|
fn node_kinds(h : @harness.Harness) -> Array[String] {
  match doc_json(h) {
    Object(m) =>
      match m.get("nodes") {
        Some(Array(ns)) =>
          ns.map(n => {
            match n {
              Object(nm) =>
                "\{nm.get("id").unwrap_or(Json::string("?")).stringify()}:\{nm.get("kind").unwrap_or(Json::string("?")).stringify()}"
              _ => "?"
            }
          })
        _ => []
      }
    _ => []
  }
}

// --- the canvas -------------------------------------------------------------

///|
test "an empty editor is one stack, and the badge names it" {
  let (h, _) = mounted()
  inspect(h.find_all(".tut-node").length(), content="1")
  inspect(h.text(".node-badge"), content="stack n0")
  inspect(h.text(".settings-kind"), content="stack")
  inspect(h.text(".editor-status"), content="pick a component to place")
}

///|
/// Every button is a `SurfaceOp` against the document — so the assertion is on
/// the document, and the canvas is checked to agree with it.
test "adding a node edits the document, and the canvas follows" {
  let (h, _) = mounted()
  h.click(".add-grid")
  debug_inspect(
    node_kinds(h),
    content="[\"\\\"n0\\\":\\\"stack\\\"\", \"\\\"n1\\\":\\\"grid\\\"\"]",
  )
  inspect(h.find_all(".tut-node").length(), content="2")
  // and the new node is SELECTED, which is the difference between "add a grid,
  // now click it, now set its columns" and "add a grid, set its columns"
  inspect(h.text(".settings-id"), content="n1")
  inspect(h.text(".editor-status"), content="added grid n1")
}

///|
/// A container takes the child; anything else passes it to its parent. The
/// alternative — refusing while a slot is selected — is infuriating, because
/// "selected" after placing a component is always the slot you just filled.
test "a new node goes inside a container and beside a leaf" {
  let (h, _) = mounted()
  h.click(".add-grid") // n1 inside the root, and selected
  h.click(".add-slot") // n2 inside n1, since a grid holds children
  inspect(h.text(".settings-id"), content="n2")
  h.click(".add-stack") // n3 BESIDE n2, since a slot holds none
  debug_inspect(
    node_kinds(h),
    content=(
      #|[
      #|  "\"n0\":\"stack\"",
      #|  "\"n1\":\"grid\"",
      #|  "\"n2\":\"slot\"",
      #|  "\"n3\":\"stack\"",
      #|]
    ),
  )
  // n3 is a sibling of n2 under n1, not a child of n2
  guard doc_json(h) is Object(m)
  guard m.get("nodes") is Some(Array(nodes))
  inspect(
    nodes[1].stringify(),
    content=(
      #|{"id":"n1","kind":"grid","children":["n2","n3"]}
    ),
  )
}

///|
test "clicking a badge selects that node and nothing above it" {
  let (h, _) = mounted()
  h.click(".add-grid")
  h.click(".add-slot")
  inspect(h.text(".settings-id"), content="n2")
  // the root's badge is the first in document order
  h.click(".node-badge")
  inspect(h.text(".settings-id"), content="n0")
  inspect(h.text(".settings-kind"), content="stack")
}

///|
/// What is selected SAYS so, and the structural classes survive saying it.
///
/// Both are one assertion because they are one mistake: a static `class`
/// beside an `@if.class` loses one of the two silently, and the version of
/// this template that did that rendered `tut-node` with no outline and a badge
/// that never lit up — invisible in a memdom, which has no styling to miss,
/// and invisible in a browser, which is where selection is the whole feedback.
test "the selected node is the one that looks selected" {
  let (h, _) = mounted()
  h.click(".add-slot")
  let selected = h.attr(".node-badge", "class", nth=1).unwrap_or("")
  let root = h.attr(".node-badge", "class", nth=0).unwrap_or("")
  assert_true(selected.contains("badge-primary"))
  assert_true(root.contains("badge-ghost"))
  // the structural half is still there, in both branches
  assert_true(selected.contains("node-badge") && root.contains("node-badge"))
  let box = h.attr(".tut-node", "class", nth=1).unwrap_or("")
  assert_true(box.contains("outline-primary") && box.contains("tut-node"))
  // and the chrome that keeps a parent's badge reachable is on every node,
  // which a memdom cannot see the effect of — only the class
  assert_true(
    h.attr(".tut-node", "class", nth=0).unwrap_or("").contains("pt-5"),
  )
}

///|
/// Removing takes the subtree, and the selection lands somewhere real rather
/// than pointing at a node that is gone.
test "removing a node takes its subtree and re-homes the selection" {
  let (h, _) = mounted()
  h.click(".add-grid")
  h.click(".add-slot")
  h.click(".add-slot")
  inspect(h.find_all(".tut-node").length(), content="4")
  // select the grid, then remove it
  h.click(".node-badge")
  inspect(h.text(".settings-id"), content="n0")
  h.click(".add-stack")
  h.click(".remove-node")
  debug_inspect(
    node_kinds(h),
    content=(
      #|[
      #|  "\"n0\":\"stack\"",
      #|  "\"n1\":\"grid\"",
      #|  "\"n2\":\"slot\"",
      #|  "\"n3\":\"slot\"",
      #|]
    ),
  )
  inspect(h.text(".editor-status"), content="removed n4")
}

///|
test "the root cannot be removed, and the refusal is shown rather than swallowed" {
  let (h, _) = mounted()
  h.click(".remove-node")
  inspect(
    h.text(".editor-status"),
    content="/nodes/n0: the root cannot be removed; empty it instead",
  )
  inspect(h.find_all(".tut-node").length(), content="1")
}

// --- the settings panel -----------------------------------------------------

///|
/// A control edits the DOCUMENT and the canvas re-renders from it. Reading the
/// style attribute back is how "the projection is faithful" is checked.
test "a settings control changes the layout through the document" {
  let (h, _) = mounted()
  inspect(
    style_of(h, ".tut-node", nth=0),
    content="display:flex;flex-direction:column;flex-wrap:nowrap;justify-content:flex-start;align-items:stretch",
  )
  h.type_into(".set-direction", "row")
  h.type_into(".set-gap", "12")
  inspect(
    style_of(h, ".tut-node", nth=0),
    content="display:flex;flex-direction:row;flex-wrap:nowrap;justify-content:flex-start;align-items:stretch;gap:12px",
  )
  // ...and the document says the same thing
  guard doc_json(h) is Object(m)
  guard m.get("nodes") is Some(Array(nodes))
  inspect(
    nodes[0].stringify(),
    content=(
      #|{"id":"n0","kind":"stack","props":{"direction":"row","gap":12}}
    ),
  )
}

///|
/// A track list is three shapes and no CSS lengths, so what can be typed is
/// what can be rendered — and what cannot is refused where a person can see it.
test "a grid's track list is typed, validated, and rendered" {
  let (h, _) = mounted()
  h.click(".add-grid")
  h.type_into(".set-columns", "1fr 240px auto")
  inspect(
    style_of(h, ".tut-node", nth=1),
    content="display:grid;grid-template-columns:1fr 240px auto;justify-items:flex-start;align-items:stretch",
  )
  h.type_into(".set-columns", "1fr minmax(10px,1fr)")
  inspect(
    h.text(".editor-status"),
    content="/nodes/n1/props/columns/1: expected a track: <n>fr | <n>px | auto, got minmax(10px,1fr)",
  )
  // the refused batch changed nothing
  inspect(
    style_of(h, ".tut-node", nth=1),
    content="display:grid;grid-template-columns:1fr 240px auto;justify-items:flex-start;align-items:stretch",
  )
}

///|
test "cell placement is written only when it says something" {
  let (h, _) = mounted()
  h.click(".add-slot")
  inspect(style_of(h, ".tut-node", nth=1), content="")
  h.type_into(".set-colspan", "2")
  inspect(style_of(h, ".tut-node", nth=1), content="grid-column-end:span 2")
}

// --- the palette ------------------------------------------------------------

///|
/// A slot says whether it is waiting for something; a container never does,
/// because an empty container is its own visible outline.
///
/// This is ONE computed field rather than two wrappers on the element
/// (`@show=".isSlot"` plus `@hide="null? .slot"`), because two wrappers read
/// as independent conditions and the placeholder needs their conjunction —
/// which is exactly the bug this test exists to hold down. It was found in a
/// browser, not here, so here is where it goes.
test "only an empty slot draws a placeholder" {
  let (h, _) = mounted()
  inspect(h.find_all(".node-empty").length(), content="0")
  h.click(".add-slot")
  inspect(h.find_all(".node-empty").length(), content="1")
  h.click(".palette-row")
  h.type_into(".field-string", "x")
  h.click(".form-create")
  // filled: the placeholder is gone and the component is there
  inspect(h.find_all(".node-empty").length(), content="0")
  inspect(h.text(".placed"), content="Counter:x")
  // a container never draws one, however empty
  h.click(".add-stack")
  inspect(h.find_all(".node-empty").length(), content="0")
}

///|
test "the palette shows the catalog and ranks a search" {
  let (h, _) = mounted()
  inspect(h.find_all(".palette-row").length(), content="1")
  inspect(h.text(".row-name"), content="Counter")
  inspect(
    h.text(".row-summary"),
    content="A number with buttons that raise and lower it.",
  )
  // the ranking's reasons travel with the hit: a search a person cannot
  // explain is one they stop trusting
  inspect(
    h.text(".row-why"),
    content=(
      #|
    ),
  )
  h.type_into(".palette-search", "wombat")
  inspect(h.find_all(".palette-row").length(), content="0")
  inspect(h.text(".palette-empty"), content="nothing matches \"wombat\"")
}

// --- the generated form -----------------------------------------------------

///|
/// No per-component code: the form is drawn from the same JSON Schema
/// projection an agent's tool reads.
test "picking a component generates a form from its declared arguments" {
  let (h, _) = mounted()
  h.click(".palette-row")
  inspect(h.text(".form-title"), content="counterlib/Counter")
  inspect(
    h.text(".form-doc"),
    content="A number with buttons that raise and lower it.",
  )
  debug_inspect(h.texts(".field-name"), content="[\"count\", \"label\"]")
  // the constraint is shown BEFORE submitting rather than in an error
  // afterwards, which is the half a type cannot state
  debug_inspect(h.texts(".field-hint"), content="[\"0…10\", \"\"]")
  debug_inspect(
    h.texts(".field-doc"),
    content="[\"The current value.\", \"What to call it.\"]",
  )
  // `label` is required and `count` is not
  inspect(
    h.find_all(".field-required").length(),
    content=(
      #|1
    ),
  )
  // a named fixture is offered beside the blank form, with the guest's own
  // reason for preferring it
  inspect(h.text(".form-init"), content="at-three — Starts at three.")
}

///|
test "a filled form places the component into a slot" {
  let (h, calls) = mounted()
  h.click(".palette-row")
  h.type_into(".field-string", "hits")
  h.type_into(".field-number", "4")
  h.click(".form-create")
  debug_inspect(calls.val, content="[\"counterlib/Counter init= label=hits\"]")
  // it rendered
  inspect(h.text(".placed"), content="Counter:hits")
  // ...and the DOCUMENT records the binding, which is what an export carries
  // and what an agent would read back
  guard doc_json(h) is Object(m)
  guard m.get("nodes") is Some(Array(nodes))
  inspect(
    nodes[1].stringify(),
    content=(
      #|{"id":"n1","kind":"slot","bound":{"module":"counterlib","name":"Counter","args":{"count":4,"label":"hits"}}}
    ),
  )
  inspect(h.text(".editor-status"), content="placed counterlib/Counter")
  // the form closed
  inspect(h.find_all(".schema-form").length(), content="0")
}

///|
/// The schema is what refuses, and the refusal lands on the FIELD — which is
/// the whole reason `coerce` returns JSON Pointers instead of a sentence.
test "the schema refuses bad arguments, per field" {
  let (h, calls) = mounted()
  h.click(".palette-row")
  h.type_into(".field-number", "42")
  h.click(".form-create")
  debug_inspect(calls.val, content="[]")
  inspect(h.text(".editor-status"), content="check the highlighted fields")
  debug_inspect(
    h.texts(".field-error"),
    content=(
      #|["must be at most 10, got 42"]
    ),
  )
  // fixing it clears the error and places it
  h.type_into(".field-number", "4")
  h.type_into(".field-string", "ok")
  h.click(".form-create")
  debug_inspect(calls.val, content="[\"counterlib/Counter init= label=ok\"]")
}

///|
/// A named fixture is the guest's own answer to "what arguments", so it wins
/// over the blank form it was offered beside — including over a required field
/// the form has not been given.
test "a named fixture places without the form being filled in" {
  let (h, calls) = mounted()
  h.click(".palette-row")
  h.click(".form-init")
  debug_inspect(
    calls.val,
    content="[\"counterlib/Counter init=at-three label=\"]",
  )
  inspect(h.text(".placed"), content="Counter:")
}

///|
test "cancelling closes the form and places nothing" {
  let (h, calls) = mounted()
  h.click(".palette-row")
  inspect(h.find_all(".schema-form").length(), content="1")
  h.click(".form-cancel")
  inspect(h.find_all(".schema-form").length(), content="0")
  debug_inspect(calls.val, content="[]")
  inspect(h.text(".editor-status"), content="cancelled")
}

// --- transfer ---------------------------------------------------------------

///|
/// One document for three jobs: what a person exports, what an agent reads
/// back, and what a session resumes from. The round trip is what makes that
/// one document rather than three.
test "a layout exports and imports as the same document" {
  let (h, _) = mounted()
  h.click(".add-grid")
  h.type_into(".set-columns", "1fr 2fr")
  h.click(".add-slot")
  h.click(".do-export")
  let exported = h.value_of(".editor-transfer")
  inspect(
    exported,
    content=(
      #|{"id":"main","root":"n0","nodes":[{"id":"n0","kind":"stack","children":["n1"]},{"id":"n1","kind":"grid","props":{"columns":["1fr","2fr"]},"children":["n2"]},{"id":"n2","kind":"slot"}],"data":{}}
    ),
  )
  // a fresh editor, given that document, is the same layout
  let (h2, _) = mounted()
  h2.type_into(".editor-transfer", exported)
  h2.click(".do-import")
  inspect(h2.find_all(".tut-node").length(), content="3")
  inspect(
    style_of(h2, ".tut-node", nth=1),
    content="display:grid;grid-template-columns:1fr 2fr;justify-items:flex-start;align-items:stretch",
  )
  inspect(
    h2.text(".editor-status"),
    content="imported 3 nodes; slots are empty until they are filled again",
  )
}

///|
test "a document that will not read back is refused, and says which way" {
  let (h, _) = mounted()
  h.type_into(".editor-transfer", "{not json")
  h.click(".do-import")
  inspect(h.text(".editor-status"), content="import: not JSON")
  h.type_into(".editor-transfer", "{\"root\": \"n9\", \"nodes\": []}")
  h.click(".do-import")
  inspect(
    h.text(".editor-status"),
    content="import: not a surface (no root, or a child that does not exist)",
  )
  // and the editor still has the layout it had
  inspect(h.find_all(".tut-node").length(), content="1")
}

///|
/// The instances do not survive a round trip, because a document holds
/// references and the host builds what they name. Saying so is the honest
/// answer; the alternative is silently showing someone else's state.
test "an imported layout keeps its slots and not their contents" {
  let (h, _) = mounted()
  h.click(".palette-row")
  h.type_into(".field-string", "before")
  h.click(".form-create")
  inspect(h.text(".placed"), content="Counter:before")
  h.click(".do-export")
  let exported = h.value_of(".editor-transfer")
  h.type_into(".editor-transfer", exported)
  h.click(".do-import")
  // the slot is back, and empty — and says so
  inspect(h.find_all(".placed").length(), content="0")
  inspect(h.find_all(".node-empty").length(), content="1")
  // ...but the document still names what belongs there
  assert_true(exported.contains("\"name\":\"Counter\""))
}

///|
/// What the editor holds after a placed component is USED, read the way a
/// shell reads it: off the app's root value.
///
/// This is the seam the universal page's session save sits on, and the one
/// that was wrong — a successor lands in the rendered tree, so anything that
/// looks somewhere else finds the instance one update behind, which after the
/// superseded sweep is a guest handle nobody can answer for.
test "a shell reading the app root sees what was just used" {
  let (h, _) = mounted()
  h.click(".add-slot")
  h.click(".palette-row")
  h.type_into(".field-string", "x")
  h.click(".form-create")
  inspect(h.text(".placed"), content="Counter:x")
  // use it
  h.click(".placed")
  inspect(h.text(".placed"), content="Counter:x!")
  // and now the reading a shell does
  let slots = live_slots(h.drive_value())
  inspect(slots.length(), content="1")
  let placed = slots.values().to_array()[0]
  inspect(placed.field("label").str(), content="Counter:x!")
}

///|
/// The shell state the test below mounts: one component-typed field, exactly
/// like the universal page's.
priv struct ShellState {
  editor : @tutuca.Value
}

///|
impl @component.Fields for ShellState with fn encode(s) {
  { "editor": s.editor }
}

///|
impl @component.Fields for ShellState with fn decode(f) {
  Some({ editor: f.get("editor").unwrap_or(Null) })
}

///|
impl @component.Fields for ShellState with fn schema() {
  @component.SchemaInfo::new(fingerprint="shell", fields=[
    @component.FieldInfo::new("editor", TyComp(Some("SurfaceEditor"))),
  ])
}

///|
/// The same reading, one level down: the editor as a SLOT of a page shell,
/// which is how the universal demo mounts it.
///
/// The hop through the shell's field is the part that was untested, and it is
/// where a shell looking for what it placed would find the wrong copy.
test "a shell one level up sees it too" {
  let (make, placeholder, _) = stub_make()
  let (editor_module, seed) = seeded_editor(catalog(), make)
  let shell = @component.component(
    name="Shell",
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="shell"><x render=".editor"></x></div>
        ),
      ),
    },
    init=({ editor: Null } : ShellState),
    slots={ "editor": "SurfaceEditor" },
    slot_args={ "editor": seed },
  )
  let module_ = @component.ModuleDef::new(
    name="shellmod",
    components=[shell, placeholder] + editor_module.components,
  )
  let h = @harness.mount(module_, "Shell")
  h.click(".add-slot")
  h.click(".palette-row")
  h.type_into(".field-string", "y")
  h.click(".form-create")
  h.click(".placed")
  inspect(h.text(".placed"), content="Counter:y!")
  // what the shell would store
  let slots = live_slots(h.drive_value().field("editor"))
  inspect(slots.length(), content="1")
  inspect(
    slots.values().to_array()[0].field("label").str(),
    content="Counter:y!",
  )
}

///|
/// The browser case, headless: a real GUEST instance in a slot, used, and then
/// read back the way the universal page's session save reads it.
///
/// A guest is the case that matters because its successor is a new opaque
/// handle rather than a new state struct: whatever the editor is holding
/// afterwards has to be the successor, or the shell stores an instance the
/// host has already collected.
test "a guest instance is current wherever it is read from" {
  let guest = StubGuest::new()
  let (registry, _) = catalog_of(guest)
  // Filled after the mount: a guest's components have to be registered into
  // the APP's scope for `<x render=".slot">` to resolve them, and the app does
  // not exist until the module that names its make-function is built.
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let placed : Ref[Array[String]] = { val: [] }
  let make = fn(
    ref_ : @registry.ComponentRef,
    _init : String,
    args : Map[String, @tutuca.Value],
  ) -> @tutuca.Value? {
    placed.val.push(ref_.to_id())
    guard live.val is Some(bundle) else { return None }
    match bundle.make_instance(ref_.name, args~) {
      Some(d) => Some(d.to_value())
      None => None
    }
  }
  let (editor_module, seed) = seeded_editor(registry, make)
  let shell = @component.component(
    name="Shell",
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="shell"><x render=".editor"></x></div>
        ),
      ),
    },
    init=({ editor: Null } : ShellState),
    slots={ "editor": "SurfaceEditor" },
    slot_args={ "editor": seed },
  )
  let h = @harness.mount(
    @component.ModuleDef::new(
      name="shellmod",
      components=[shell] + editor_module.components,
    ),
    "Shell",
  )
  live.val = Some(@dyncomp.register_bundle(h.app.scope, guest, stub_manifest()))
  h.click(".add-slot")
  h.click(".palette-row")
  h.type_into(".field-number", "2")
  h.click(".form-create")
  @debug.assert_eq(placed.val, ["counterlib/Counter"])
  inspect(h.text(".guest-count"), content="2")
  // use it: the guest hands back a NEW handle
  h.click(".guest-inc")
  inspect(h.text(".guest-count"), content="3")
  // and the shell, reading the app root, finds that one
  let slots = live_slots(h.drive_value().field("editor"))
  inspect(slots.length(), content="1")
  inspect(
    slots.values().to_array()[0].field("count").to_display_string(),
    content="3",
  )
  // The same, through a form control rather than a button: an `input` on a
  // text box is the shape that was losing its successor in the browser, and
  // it goes through the same dispatch as everything else.
  h.type_into(".guest-note", "written")
  let after = live_slots(h.drive_value().field("editor"))
  inspect(after.values().to_array()[0].field("note").str(), content="written")
}

///|
/// The same, with the text edit FIRST: no click before it, so nothing has
/// replaced the instance the DOM was rendered from.
test "a guest's first edit is applied too" {
  let guest = StubGuest::new()
  let (registry, _) = catalog_of(guest)
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let make = fn(
    ref_ : @registry.ComponentRef,
    _init : String,
    args : Map[String, @tutuca.Value],
  ) -> @tutuca.Value? {
    guard live.val is Some(bundle) else { return None }
    match bundle.make_instance(ref_.name, args~) {
      Some(d) => Some(d.to_value())
      None => None
    }
  }
  let (editor_module, seed) = seeded_editor(registry, make)
  let h = @harness.mount(editor_module, "SurfaceEditor", args=seed)
  live.val = Some(@dyncomp.register_bundle(h.app.scope, guest, stub_manifest()))
  h.click(".add-slot")
  h.click(".palette-row")
  h.type_into(".field-number", "0")
  h.click(".form-create")
  h.type_into(".guest-note", "first")
  let slots = live_slots(h.drive_value())
  inspect(slots.values().to_array()[0].field("note").str(), content="first")
}

///|
/// The same guest, the same text edit, with NO editor in the picture: a shell
/// whose one field holds the instance.
///
/// This is the control for the two tests above — it says whether a guest's
/// `@on.input` successor survives at all, or only survives outside the editor.
test "a guest's text edit survives in a plain shell" {
  let guest = StubGuest::new()
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let shell = @component.component(
    name="PlainShell",
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="shell"><x render=".editor"></x></div>
        ),
      ),
    },
    init=({ editor: Null } : ShellState),
  )
  let h = @harness.mount(
    @component.ModuleDef::new(name="plain", components=[shell]),
    "PlainShell",
  )
  live.val = Some(@dyncomp.register_bundle(h.app.scope, guest, stub_manifest()))
  guard live.val is Some(bundle)
  guard bundle.make_instance("Counter") is Some(inst)
  // seed it into the shell's field the way a host does
  h.app.transactor.push_input(@tutuca.DispatchPath::new(), "setEditor", [
    inst.to_value(),
  ])
  |> ignore
  h.app.transactor.settle() |> ignore
  inspect(h.find_all(".the-counter").length(), content="1")
  // a click changes a DECLARED field, so the successor was never in doubt
  h.click(".guest-inc")
  inspect(
    h.drive_value().field("editor").field("count").to_display_string(),
    content="1",
  )
  // and a text edit changes only what the schema does NOT name — the case a
  // structural compare called "no change" and threw away
  h.type_into(".guest-note", "plain")
  inspect(h.drive_value().field("editor").field("note").str(), content="plain")
}
