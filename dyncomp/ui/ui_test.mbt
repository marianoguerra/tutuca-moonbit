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
impl @dyncomp.Guest for StubGuest with fn seq_entries(_self, _handle) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn dispatch(
  _self,
  _handle,
  _bucket,
  _name,
  _args,
) {
  { next: None, msgs: [] }
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
impl @dyncomp.Guest for StubGuest with fn with_field(_self, _handle, _name, _v) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn handle_request(_self, name, _args) {
  Err(Str("no such request: \{name}"))
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
fn catalog() -> @registry.Registry raise {
  let manifest : @dyncomp.DynManifest = {
    api_version: 3,
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
            html: "<div class=\"the-counter\"><button @on.click=\"inc\">+</button></div>",
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
        handlers: ["inc"],
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
  let reg = @registry.Registry::new()
  reg.register(
    @dyncomp.register_bundle(
      @component.ComponentStack::new(),
      StubGuest::{  },
      manifest,
    ),
  )
  reg
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
        raw_view="<div class=\"placed\" @text=\".label\"></div>",
      ),
    },
    init=({ label: "" } : PlacedState),
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
