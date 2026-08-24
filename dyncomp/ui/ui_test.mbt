///| The app, driven on the in-memory DOM.
///
/// Backend-agnostic components are what make this possible, and it is the
/// reason the package is split from the wasm shell: clicking a `+`, typing in
/// the command bar, filling a form and reading the result back are all things
/// `moon test` can do, and none of them need a browser.
///
/// The invariant every test here leans on: the TREE is the truth. There is no
/// document beside it, so asserting against what is on screen is asserting
/// against the state itself.

///|
/// A guest with just enough state to be USED: one number per instance, a
/// handler that raises it, and successors that are new handles.
///
/// Most tests here only need it to answer the manifest, but a placed component
/// nobody can click proves nothing about what the app is holding after
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
    // A compound the form has no control for, so it draws a JSON box.
    "history" => Some(List([Num(self.counts.get(handle).unwrap_or(0.0))]))
    _ => None
  }
}

///|
impl @dyncomp.Guest for StubGuest with fn dispatch(
  self,
  handle,
  bucket,
  name,
  _args,
  _bindings,
) {
  match (bucket, name) {
    (Receive, "inc") =>
      {
        handled: true,
        next: Some(
          self.alloc(
            self.counts.get(handle).unwrap_or(0.0) + 1.0,
            note=self.notes.get(handle).unwrap_or(""),
          ),
        ),
        msgs: [],
      }
    // the guest's own text handler: `@on.input="jot e.value"`
    (Receive, "jot") =>
      match _args {
        [Str(text), ..] =>
          {
            handled: true,
            next: Some(
              self.alloc(self.counts.get(handle).unwrap_or(0.0), note=text),
            ),
            msgs: [],
          }
        _ => { handled: true, next: None, msgs: [] }
      }
    _ => { handled: false, next: None, msgs: [] }
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
impl @dyncomp.Guest for StubGuest with fn serve_intent(_self, name, _args) {
  Err(Str("no such service: \{name}"))
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
    api_version: 6,
    module_name: "counterlib",
    doc: "Sample counters.",
    version: "0.3.0",
    homepage: "",
    authors: [],
    capabilities: [],
    config: [],
    macros: [],
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
            html: "<div class=\"the-counter\"><span class=\"guest-count\" @text=\".count\"></span><button class=\"guest-inc\" @on.click=\"inc\">+</button><input class=\"guest-note\" :value=\".note\" @on.input=\"jot e.value\" /></div>",
          },
        ],
        types: [
          ty("ty-float"),
          ty("ty-text"),
          { kind: "ty-list", elem: Some(0), items: [], name: "", members: [] },
        ],
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
          // A COMPOUND, so the generated form has a JSON control. It is here
          // for the reconfigure path: a `json` field pre-filled with anything
          // other than JSON is refused the moment somebody presses Apply on a
          // field they never touched.
          {
            name: "history",
            ty: 2,
            doc: "Every value it has held.",
            required: false,
            constraint: None,
          },
        ],
        receives: [],
        intents: [],
        methods: [],
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

// --- mounting the app -------------------------------------------------------

///|
/// The app, mounted with a catalog: the standard components always, and the
/// stub bundle when `guest` is given.
///
/// `make` is the one thing the app cannot do for itself — building a LOADED
/// component — and here it goes through the bundle registered into the app's
/// own scope, which is what the wasm bridge does with a real one.
fn mount_app(guest? : StubGuest) -> @harness.MemHarness raise {
  let g = match guest {
    Some(x) => x
    None => StubGuest::new()
  }
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let reg = @registry.Registry::new()
  let module_ = universal_module(reg, (ref_, init, args) => {
    guard live.val is Some(bundle) else { return None }
    let made = if init == "" {
      bundle.make_instance(ref_.name, args~)
    } else {
      bundle.make_init(ref_.name, init)
    }
    match made {
      Some(obj) => Some(obj.to_value())
      None => None
    }
  })
  let h = @harness.mount(module_, "UniversalApp")
  if guest is Some(_) {
    let bundle = @dyncomp.register_bundle(h.app.scope, g, stub_manifest())
    live.val = Some(bundle)
    reg.register(bundle)
  }
  h
}

///|
/// Open the bar and pick the row whose name is `name`.
fn pick(h : @harness.MemHarness, name : String) -> Unit raise {
  h.type_into(".command-input", name)
  let names = h.texts(".row-name")
  let mut at = 0
  for i, n in names {
    if n == name {
      at = i
      break
    }
  }
  h.click(".palette-row", nth=at)
}

// --- the empty page ---------------------------------------------------------

///|
test "a new page is one empty cell, and the bar opens onto the catalog" {
  let h = mount_app()
  // The root IS a universal, so the first thing there is to do is choose what
  // the page is.
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  @debug.assert_eq(h.find_all(".command-overlay").length(), 0)
  h.click(".universal-add")
  @debug.assert_eq(h.find_all(".command-overlay").length(), 1)
  // Everything the catalog holds, with nothing loaded: an empty query is what
  // a command bar opens with.
  let names = h.texts(".row-name")
  assert_true(names.contains("Universal"))
  assert_true(names.contains("Stack"))
  assert_true(names.contains("Textarea"))
}

///|
test "picking a component places it in the cell that asked" {
  let h = mount_app()
  h.click(".universal-add")
  pick(h, "Text")
  // The bar closed, the cell filled, and the badge names what landed.
  @debug.assert_eq(h.find_all(".command-overlay").length(), 0)
  @debug.assert_eq(h.find_all(".tut-text").length(), 1)
  @debug.assert_eq(h.text(".universal-badge"), "Text")
}

///|
test "the bar filters as you type, and Escape leaves nothing behind" {
  let h = mount_app()
  h.click(".universal-add")
  h.type_into(".command-input", "grid")
  @debug.assert_eq(h.texts(".row-name"), ["Grid"])
  h.key_down(".command-input", "Escape")
  @debug.assert_eq(h.find_all(".command-overlay").length(), 0)
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
}

///|
test "the bar is keyboard navigable, and Enter places what the cursor is on" {
  let h = mount_app()
  h.click(".universal-add")
  h.type_into(".command-input", "stack")
  // The first hit starts selected, so Enter alone is the common case.
  @debug.assert_eq(h.find_all(".row-selected").length(), 1)
  h.key_down(".command-input", "Enter")
  @debug.assert_eq(h.find_all(".tut-stack").length(), 1)
}

///|
test "the cursor moves without disturbing what was typed" {
  let h = mount_app()
  h.click(".universal-add")
  h.type_into(".command-input", "t")
  let before = h.texts(".row-name")
  assert_true(before.length() > 1)
  h.key_down(".command-input", "ArrowDown")
  // The second row is selected now, and the query is untouched — moving the
  // cursor tells two rows about it rather than rebuilding the list, which is
  // what keeps the focused `<input>` the same element.
  @debug.assert_eq(h.value_of(".command-input"), "t")
  @debug.assert_eq(h.texts(".row-name"), before)
  guard! h.attr(".palette-row", "class", nth=1) is Some(cls)
  assert_true(cls.contains("row-selected"))
  // ...and it stops at the top rather than wrapping.
  h.key_down(".command-input", "ArrowUp")
  h.key_down(".command-input", "ArrowUp")
  guard! h.attr(".palette-row", "class") is Some(first)
  assert_true(first.contains("row-selected"))
}

// --- placing with arguments -------------------------------------------------

///|
test "ctrl-clicking the plus opens the form instead of placing" {
  let h = mount_app()
  h.fire(
    ".universal-add",
    @render.DomEvent::new(name="click", ctrl_or_cmd=true),
  )
  @debug.assert_eq(h.find_all(".command-hint").length(), 1)
  pick(h, "Text")
  // The form, generated from the component's declared arguments and opened on
  // their defaults.
  @debug.assert_eq(h.find_all(".command-overlay").length(), 0)
  @debug.assert_eq(h.text(".form-title"), "std/Text")
  assert_true(h.texts(".field-name").contains("text"))
  h.type_into(".field-string", "hello")
  h.click(".form-create")
  @debug.assert_eq(h.text(".tut-text"), "hello")
}

///|
test "a component that needs an argument asks instead of failing" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  // `Counter.label` is required and has no default, so there is nothing to
  // place it WITH. Opening the form is the answer: the person asked for this
  // component, and the form is how they get it.
  pick(h, "Counter")
  @debug.assert_eq(h.text(".form-title"), "counterlib/Counter")
  @debug.assert_eq(h.find_all(".the-counter").length(), 0)
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  @debug.assert_eq(h.find_all(".the-counter").length(), 1)
}

///|
test "the schema refuses bad arguments, per field, without placing anything" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  // `count` is constrained to 0..10.
  h.type_into(".field-number", "99")
  h.click(".form-create")
  @debug.assert_eq(h.find_all(".the-counter").length(), 0)
  assert_true(h.text(".field-error").length() > 0)
}

///|
test "a named fixture places without the form being filled in" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  // The guest said when to prefer it, so the form offers it beside the bare
  // constructor.
  @debug.assert_eq(h.texts(".form-init"), ["at-three — Starts at three."])
  h.click(".form-init")
  @debug.assert_eq(h.text(".guest-count"), "3")
}

///|
test "cancelling the form places nothing and leaves the cell empty" {
  let h = mount_app()
  h.fire(
    ".universal-add",
    @render.DomEvent::new(name="click", ctrl_or_cmd=true),
  )
  pick(h, "Text")
  h.click(".form-cancel")
  @debug.assert_eq(h.find_all(".schema-form").length(), 0)
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
}

// --- a loaded component is not a special case -------------------------------

///|
test "a loaded component is placed, rendered and used like a standard one" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  // It ranks in the same search as the standard components...
  h.type_into(".command-input", "counter")
  @debug.assert_eq(h.texts(".row-name"), ["Counter"])
  h.click(".palette-row")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  // ...renders its own view inside the same universal...
  @debug.assert_eq(h.text(".guest-count"), "0")
  @debug.assert_eq(h.text(".universal-badge"), "Counter")
  // ...and is USED there: a click reaches the guest and the successor lands
  // back in the cell that holds it.
  h.click(".guest-inc")
  h.click(".guest-inc")
  @debug.assert_eq(h.text(".guest-count"), "2")
}

// --- the config sidebar -----------------------------------------------------

///|
test "the badge opens the sidebar on what the cell holds" {
  let h = mount_app()
  h.click(".universal-add")
  pick(h, "Text")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
  h.click(".universal-badge")
  @debug.assert_eq(h.find_all(".config-panel").length(), 1)
  @debug.assert_eq(h.text(".config-title"), "std/Text")
  h.click(".config-close")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
}

///|
test "the sidebar opens on what is already there, and applying keeps the rest" {
  let h = mount_app()
  h.fire(
    ".universal-add",
    @render.DomEvent::new(name="click", ctrl_or_cmd=true),
  )
  pick(h, "Text")
  h.type_into(".field-string", "hello")
  h.click(".form-create")
  h.click(".universal-badge")
  // Opened on what the instance HOLDS, not on the defaults: changing one
  // property must not mean retyping the rest.
  @debug.assert_eq(h.value_of(".field-string"), "hello")
  @debug.assert_eq(h.text(".form-create"), "Apply")
  h.type_into(".field-string", "goodbye")
  h.click(".form-create")
  @debug.assert_eq(h.text(".tut-text"), "goodbye")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
}

///|
test "dropping the config pill on a cell opens the sidebar for that cell" {
  let h = mount_app()
  h.click(".universal-add")
  pick(h, "Stack")
  // Two cells in the stack; fill the second so the two are told apart.
  h.click(".cell-append")
  h.click(".universal-add")
  pick(h, "Text")
  // Drag the pill onto the stack's own universal — the outer one.
  h.fire(".config-pill", @render.DomEvent::new(name="dragstart"))
  h.fire(".tut-universal", @render.DomEvent::new(name="dragover"))
  h.fire(".tut-universal", @render.DomEvent::new(name="drop"))
  h.fire(".config-pill", @render.DomEvent::new(name="dragend"))
  @debug.assert_eq(h.find_all(".config-panel").length(), 1)
  @debug.assert_eq(h.text(".config-title"), "std/Stack")
}

// --- edit mode --------------------------------------------------------------

///|
test "view mode hides every affordance and keeps the page" {
  let h = mount_app()
  h.click(".universal-add")
  pick(h, "Stack")
  h.click(".cell-append")
  assert_true(h.find_all(".cell-before").length() > 0)
  h.click(".toggle-mode")
  @debug.assert_eq(h.text(".toggle-mode"), "viewing")
  // The layout is still there; nothing to click is.
  @debug.assert_eq(h.find_all(".tut-stack").length(), 1)
  @debug.assert_eq(h.find_all(".cell-before").length(), 0)
  @debug.assert_eq(h.find_all(".universal-add").length(), 0)
  @debug.assert_eq(h.find_all(".universal-badge").length(), 0)
  h.click(".toggle-mode")
  assert_true(h.find_all(".cell-before").length() > 0)
}

// --- the acceptance test ----------------------------------------------------

///|
/// The notepad, by composition.
///
/// A notepad built out of a tabbed container and a text area by somebody
/// clicking. Nothing here was written for notepads.
test "a notepad is a tabbed container holding text areas" {
  let h = mount_app()
  // Choose what the page is.
  h.click(".universal-add")
  pick(h, "Tabs")
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1"])
  // A fresh tab opens on a `+`, so the next step is the same gesture again.
  h.click(".universal-add")
  pick(h, "Textarea")
  h.type_into(".tut-textarea", "buy milk")
  @debug.assert_eq(h.value_of(".tut-textarea"), "buy milk")
  // A second tab, with its own text area.
  h.click(".tab-add")
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2"])
  @debug.assert_eq(h.find_all(".tut-textarea").length(), 0)
  h.click(".universal-add")
  pick(h, "Textarea")
  h.type_into(".tut-textarea", "call mum")
  // Switching back: the first tab kept what was typed in it, which is the one
  // thing a tabbed notepad has to get right.
  h.click(".tab-label")
  @debug.assert_eq(h.value_of(".tut-textarea"), "buy milk")
  h.click(".tab-label", nth=1)
  @debug.assert_eq(h.value_of(".tut-textarea"), "call mum")
  // And in view mode it is a notepad rather than an editor.
  h.click(".toggle-mode")
  @debug.assert_eq(h.find_all(".tab-add").length(), 0)
  @debug.assert_eq(h.value_of(".tut-textarea"), "call mum")
}

///|
/// Applying to a LOADED component has to write through the same way it does
/// for a standard one: the sidebar is generated from the declared schema
/// either way, and a guest that could be configured only by being rebuilt
/// would lose everything it keeps privately.
test "applying the sidebar's form writes through a loaded component" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  @debug.assert_eq(h.text(".guest-count"), "0")
  h.click(".universal-badge")
  @debug.assert_eq(h.text(".config-title"), "counterlib/Counter")
  // Opened on what the instance holds.
  @debug.assert_eq(h.value_of(".field-number"), "0")
  h.type_into(".field-number", "7")
  h.click(".form-create")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
  @debug.assert_eq(h.text(".guest-count"), "7")
}

///|
/// The same, several containers deep and behind a filtered `render-each`.
///
/// The sidebar addresses the cell it is configuring by the path the bubble
/// carried, so every kind of render between the app and that cell is a chance
/// for the path to be wrong. A tab is the hardest of them: only the active
/// page is rendered, so the path has to name the cell in the WHOLE list.
test "applying reaches a component nested inside tabs" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Tabs")
  // A second and a third tab, so the one being configured is not the first.
  h.click(".tab-add")
  h.click(".tab-add")
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2", "tab 3"])
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  @debug.assert_eq(h.text(".guest-count"), "0")
  // The second badge is the counter's; the first is the tabs' own cell.
  h.click(".universal-badge", nth=1)
  @debug.assert_eq(h.text(".config-title"), "counterlib/Counter")
  h.type_into(".field-number", "7")
  h.click(".form-create")
  @debug.assert_eq(h.text(".guest-count"), "7")
}

///|
/// Reconfiguring must not be refused for a field nobody touched.
///
/// A compound has no control of its own, so the form draws a JSON box — and a
/// box pre-filled with anything other than JSON parses as the wrong thing the
/// moment Apply reads it back. The failure is invisible from the outside: the
/// form was filled from the instance, so every value in it looks like one that
/// was already accepted, and pressing Apply silently changes nothing.
///
/// Found in a browser, not here, because the stub had no compound field.
test "a compound field round-trips through the form untouched" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  h.click(".universal-badge")
  // Pre-filled as JSON, which is what the box is read back as.
  @debug.assert_eq(h.value_of(".field-json"), "[0]")
  // Change something ELSE and apply: the untouched compound must not be what
  // stops it.
  h.type_into(".field-number", "5")
  h.click(".form-create")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
  @debug.assert_eq(h.text(".guest-count"), "5")
}

///|
test "an absent optional stays absent rather than becoming an empty string" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  // `history` has no value and no default, so its box is EMPTY — not `""`,
  // which is what a blank string would encode to and what would then be
  // refused as not-an-array.
  @debug.assert_eq(h.value_of(".field-json"), "")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  @debug.assert_eq(h.find_all(".the-counter").length(), 1)
}

///|
/// A fixture applied to a component that is ALREADY placed.
///
/// Placing and reconfiguring are different operations: placing CONSTRUCTS, and
/// reconfiguring WRITES THROUGH field by field so that everything the schema
/// does not name survives. A fixture is a statement about arguments, so the
/// panel has to resolve it to those arguments — handing the NAME down to a
/// constructor works only on the path where a constructor runs.
///
/// Resolving at the panel is also what keeps the write-through honest: the
/// branch below it applies the fixture's arguments field by field to the
/// instance that is already there, rather than replacing it — so a fixture that
/// names `count` and not `label` leaves `label` alone, and anything the guest
/// keeps privately is never in the conversation at all.
test "a fixture applies to a component that is already there" {
  let guest = StubGuest::new()
  let h = mount_app(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  h.type_into(".field-number", "5")
  h.click(".form-create")
  @debug.assert_eq(h.text(".guest-count"), "5")

  // The panel offers the same fixture the placing form did.
  h.click(".universal-badge")
  @debug.assert_eq(h.texts(".form-init"), ["at-three — Starts at three."])
  h.click(".form-init")
  @debug.assert_eq(h.find_all(".config-panel").length(), 0)
  @debug.assert_eq(h.text(".guest-count"), "3")

  // The instance was written to, not replaced: the cell still holds one
  // component and the badge still names it.
  @debug.assert_eq(h.find_all(".the-counter").length(), 1)
  @debug.assert_eq(h.text(".universal-badge"), "Counter")

  // and it is still the component it was: reopening the panel finds the same
  // instance, holding what the fixture put in it.
  h.click(".universal-badge")
  @debug.assert_eq(h.text(".config-title"), "counterlib/Counter")
  @debug.assert_eq(h.text(".guest-count"), "3")
}
