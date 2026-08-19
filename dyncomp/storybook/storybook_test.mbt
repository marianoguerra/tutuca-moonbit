///| The gallery, driven on the in-memory DOM.
///
/// The point of the split between this package and `dyncomp/storybook/wasm` is
/// exactly this file: a bundle registers, the catalog changes, cards appear,
/// and every control in the bar is clickable — with no browser anywhere. What
/// the wasm half adds is fetching the archive, and nothing else.
///
/// The stub below is a two-component bundle with named `inits`, because the
/// claim under test is not "a card renders" but "the story set IS the
/// manifest": a component with three configurations gets four cards (its
/// defaults, and one each), and nobody wrote them down.

///|
/// A guest with one number and one string per instance — enough that a card
/// can be clicked and the click can be seen.
priv struct StubGuest {
  counts : Map[Int, Double]
  labels : Map[Int, String]
  next : Ref[Int]
}

///|
fn StubGuest::new() -> StubGuest {
  { counts: Map([]), labels: Map([]), next: { val: 0 } }
}

///|
fn StubGuest::alloc(self : StubGuest, count : Double, label : String) -> Int {
  let h = self.next.val
  self.next.val = h + 1
  self.counts[h] = count
  self.labels[h] = label
  h
}

///|
impl @dyncomp.Guest for StubGuest with fn create(self, _component, args) {
  self.alloc(
    match args.get("count") {
      Some(Num(n)) => n
      _ => 0.0
    },
    match args.get("label") {
      Some(Str(s)) => s
      _ => ""
    },
  )
}

///|
impl @dyncomp.Guest for StubGuest with fn get_field(self, handle, name) {
  match name {
    "count" => Some(Num(self.counts.get(handle).unwrap_or(0.0)))
    "label" => Some(Str(self.labels.get(handle).unwrap_or("")))
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
) {
  match (bucket, name) {
    (Input, "inc") =>
      {
        handled: true,
        next: Some(
          self.alloc(
            self.counts.get(handle).unwrap_or(0.0) + 1.0,
            self.labels.get(handle).unwrap_or(""),
          ),
        ),
        msgs: [],
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
impl @dyncomp.Guest for StubGuest with fn with_field(_self, _h, _name, _v) {
  None
}

///|
impl @dyncomp.Guest for StubGuest with fn handle_request(_self, name, _args) {
  Err(Str("no such request: \{name}"))
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
  { kind, elem: None, items: [], name: "", members: [] }
}

///|
/// Two components, with three named configurations between them.
fn stub_manifest() -> @dyncomp.DynManifest {
  {
    api_version: 6,
    module_name: "chatlib",
    doc: "A stand-in bundle.",
    version: "0.1.0",
    homepage: "",
    authors: [],
    capabilities: [],
    config: [],
    macros: [],
    components: [
      {
        name: "Tally",
        doc: "A number with a button that raises it.",
        keywords: ["count"],
        category: "input",
        message_docs: { "inc": "Add one." },
        views: [
          {
            name: "main",
            html: "<div class=\"the-tally\"><span class=\"tally-count\" @text=\".count\"></span><button class=\"tally-inc\" @on.click=\"inc\">+</button></div>",
          },
        ],
        types: [ty("ty-float"), ty("ty-text")],
        fields: [
          {
            name: "count",
            ty: 0,
            doc: "The current value.",
            required: false,
            constraint: None,
          },
          {
            name: "label",
            ty: 1,
            doc: "What to call it.",
            required: false,
            constraint: None,
          },
        ],
        receives: [],
        intents: [],
        bubbles: [],
        responses: [],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        requests: [],
        inits: [
          {
            name: "at-three",
            args: { "count": Num(3) },
            doc: "Starts at three.",
          },
          {
            name: "named",
            args: { "count": Num(7), "label": Str("sevens") },
            doc: "Starts at seven, with a name.",
          },
        ],
        style: "",
      },
      {
        name: "Banner",
        doc: "A line of text.",
        keywords: ["text"],
        category: "display",
        message_docs: {},
        views: [
          {
            name: "main",
            html: "<p class=\"the-banner\" @text=\".label\"></p>",
          },
        ],
        types: [ty("ty-text")],
        fields: [
          {
            name: "label",
            ty: 0,
            doc: "What it says.",
            required: false,
            constraint: None,
          },
        ],
        receives: [],
        intents: [],
        bubbles: [],
        responses: [],
        methods: [],
        whens: [],
        enriches: [],
        enrich_scopes: [],
        requests: [],
        inits: [
          {
            name: "greeting",
            args: { "label": Str("hello") },
            doc: "Says hello.",
          },
        ],
        style: "",
      },
    ],
  }
}

// --- mounting ---------------------------------------------------------------

///|
/// The gallery, mounted empty. `load()` is what a bundle arriving looks like:
/// register it into the app's own scope, then tell the root the catalog
/// changed — the same two steps the wasm bridge takes.
fn mount_gallery() -> (@harness.Harness, () -> Unit raise) raise {
  let guest = StubGuest::new()
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let reg = @registry.Registry::new()
  let (module_, _) = gallery_module(reg, (ref_, init, args) => {
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
  let h = @harness.mount(module_, "DyncompStorybook")
  let load = fn() raise {
    let bundle = @dyncomp.register_bundle(h.app.scope, guest, stub_manifest())
    live.val = Some(bundle)
    reg.register(bundle)
    h.send_at_root("catalogChanged", args=[Str("chatlib")]) |> ignore
  }
  (h, load)
}

// --- the empty page ---------------------------------------------------------

///|
test "with nothing loaded the gallery says so rather than showing nothing" {
  let (h, _) = mount_gallery()
  @debug.assert_eq(h.find_all(".story-card").length(), 0)
  @debug.assert_eq(h.find_all(".story-nav").length(), 0)
  @debug.assert_eq(h.find_all(".sb-nav-empty").length(), 1)
  assert_true(h.text(".sb-empty").contains("No bundles loaded"))
}

// --- the story set ----------------------------------------------------------

///|
test "the story set is the manifest: one card per configuration, plus defaults" {
  let (h, load) = mount_gallery()
  load()
  // Tally has two inits and Banner one, so four configurations — and three
  // defaults cards nobody declared, because every component has defaults.
  @debug.assert_eq(h.find_all(".story-card").length(), 5)
  @debug.assert_eq(h.texts(".card-name"), [
    "Tally", "Tally · at-three", "Tally · named", "Banner", "Banner · greeting",
  ])
  // The defaults card carries no init badge; the others name theirs.
  @debug.assert_eq(h.texts(".card-init"), ["at-three", "named", "greeting"])
  // and every card names where its component came from
  @debug.assert_eq(h.texts(".card-ref"), [
    "chatlib/Tally", "chatlib/Tally", "chatlib/Tally", "chatlib/Banner", "chatlib/Banner",
  ])
}

///|
test "each card holds the component actually running, built from its init" {
  let (h, load) = mount_gallery()
  load()
  // The configurations are live instances, not pictures: the numbers on the
  // cards are the ones the guest is holding.
  @debug.assert_eq(h.texts(".tally-count"), ["0", "3", "7"])
  @debug.assert_eq(h.texts(".the-banner"), ["", "hello"])
}

///|
test "the sidebar counts what is under it" {
  let (h, load) = mount_gallery()
  load()
  @debug.assert_eq(h.texts(".nav-name"), ["Tally", "Banner"])
  @debug.assert_eq(h.texts(".nav-count"), ["3", "2"])
  @debug.assert_eq(h.texts(".nav-module"), ["chatlib", "chatlib"])
}

// --- the controls in the bar ------------------------------------------------

///|
test "the filter narrows without rebuilding: a component keeps what it was doing" {
  let (h, load) = mount_gallery()
  load()
  // Drive the middle card, so there is state that a rebuild would lose.
  h.click(".tally-inc", nth=1)
  @debug.assert_eq(h.texts(".tally-count"), ["0", "4", "7"])
  h.type_into(".sb-search", "named")
  @debug.assert_eq(h.texts(".card-name"), ["Tally · named"])
  // and back — the card that was mid-interaction still holds its four
  h.type_into(".sb-search", "")
  @debug.assert_eq(h.texts(".tally-count"), ["0", "4", "7"])
}

///|
test "a query nothing matches says which query" {
  let (h, load) = mount_gallery()
  load()
  h.type_into(".sb-search", "zzz")
  @debug.assert_eq(h.find_all(".story-card").length(), 0)
  @debug.assert_eq(h.text(".sb-empty"), "Nothing matches \"zzz\".")
}

///|
test "picking in the sidebar filters to one component, and `all` restores it" {
  let (h, load) = mount_gallery()
  load()
  h.click(".story-nav", nth=1) // Banner
  @debug.assert_eq(h.texts(".card-name"), ["Banner", "Banner · greeting"])
  // the row says it is the one selected
  @debug.assert_eq(h.find_all(".nav-selected").length(), 1)
  // the two filters compose rather than replace each other
  h.type_into(".sb-search", "greeting")
  @debug.assert_eq(h.texts(".card-name"), ["Banner · greeting"])
  h.click(".sb-all")
  @debug.assert_eq(h.find_all(".nav-selected").length(), 0)
  // the query survives `all`, which only clears the sidebar's half
  @debug.assert_eq(h.texts(".card-name"), ["Banner · greeting"])
  h.type_into(".sb-search", "")
  @debug.assert_eq(h.find_all(".story-card").length(), 5)
}

///|
test "the details switch pushes a view down; no card had to opt in" {
  let (h, load) = mount_gallery()
  load()
  @debug.assert_eq(h.find_all(".card-detail").length(), 0)
  h.click(".sb-details")
  @debug.assert_eq(h.find_all(".card-detail").length(), 5)
  // the documentation is the init's own sentence where there is one
  @debug.assert_eq(h.texts(".card-doc"), [
    "A number with a button that raises it.", "Starts at three.", "Starts at seven, with a name.",
    "A line of text.", "Says hello.",
  ])
  // and the arguments are the JSON the manifest carried, so a card can be
  // copied back into a bundle
  // only the configurations that carried arguments show a block, so the
  // defaults cards contribute none
  @debug.assert_eq(h.texts(".card-args").length(), 3)
  assert_true(h.texts(".card-args")[0].contains("\"count\": 3"))
  h.click(".sb-details")
  @debug.assert_eq(h.find_all(".card-detail").length(), 0)
}

///|
test "layout and theme are gallery-wide configurations" {
  let (h, load) = mount_gallery()
  load()
  @debug.assert_eq(h.text(".sb-layout"), "grid")
  assert_true(
    h.attr(".sb-cards", "class").unwrap_or("").contains("grid-cols-1"),
  )
  h.click(".sb-layout")
  @debug.assert_eq(h.text(".sb-layout"), "one per row")
  assert_true(h.attr(".sb-cards", "class").unwrap_or("").contains("flex-col"))
  // the theme rides on the gallery's own root, so it does not fight the page
  @debug.assert_eq(h.attr(".dyncomp-storybook", "data-theme"), Some("light"))
  h.type_into(".sb-theme", "dracula")
  @debug.assert_eq(h.attr(".dyncomp-storybook", "data-theme"), Some("dracula"))
}

// --- resetting one card -----------------------------------------------------

///|
test "reset rebuilds ONE card and leaves the others where they were" {
  let (h, load) = mount_gallery()
  load()
  h.click(".tally-inc", nth=0)
  h.click(".tally-inc", nth=1)
  @debug.assert_eq(h.texts(".tally-count"), ["1", "4", "7"])
  h.click(".card-rebuild", nth=1)
  // the one that was reset is back at its init; the one beside it is not
  @debug.assert_eq(h.texts(".tally-count"), ["1", "3", "7"])
}

// --- a bundle arriving twice ------------------------------------------------

///|
test "a catalog change rebuilds the whole set, and says what arrived" {
  let (h, load) = mount_gallery()
  load()
  h.click(".tally-inc", nth=0)
  @debug.assert_eq(h.texts(".tally-count"), ["1", "3", "7"])
  @debug.assert_eq(h.text(".sb-status"), "loaded chatlib")
  // A bundle loaded again is a hot swap: the components it declares may not be
  // the ones that were there, so every card is rebuilt rather than kept.
  h.send_at_root("catalogChanged", args=[Str("chatlib")]) |> ignore
  @debug.assert_eq(h.texts(".tally-count"), ["0", "3", "7"])
}

// --- the model, without a DOM -----------------------------------------------

///|
test "stories_of and nav_of agree about how many stories there are" {
  let reg = @registry.Registry::new()
  reg.register(
    @dyncomp.register_bundle(
      @component.ComponentStack::new(),
      StubGuest::new(),
      stub_manifest(),
    ),
  )
  let stories = stories_of(reg)
  @debug.assert_eq(stories.length(), 5)
  @debug.assert_eq(stories.map(s => s.init), [
    "", "at-three", "named", "", "greeting",
  ])
  let nav = nav_of(stories)
  @debug.assert_eq(nav.map(e => e.ref_.name), ["Tally", "Banner"])
  @debug.assert_eq(nav.map(e => e.count), [3, 2])
  // the counts are the cards, by construction
  let mut total = 0
  for e in nav {
    total = total + e.count
  }
  @debug.assert_eq(total, stories.length())
}

///|
test "a configuration's arguments come out as JSON somebody can paste back" {
  @debug.assert_eq(args_json(Map([])), "")
  inspect(
    args_json({ "count": Num(3), "label": Str("sevens") }),
    content=(
      #|{
      #|  "count": 3,
      #|  "label": "sevens"
      #|}
    ),
  )
}
