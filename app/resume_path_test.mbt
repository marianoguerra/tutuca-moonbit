// Dynamic render resumption end-to-end: Workspace provides `.sheet`; a Toolbar deep in the tree
// renders `*active`; clicking inside the sheet must reconstruct a dispatch
// path that walks every intermediate component (bubbling) while the
// active transaction frame addresses the provider's data.

///|
priv struct SheetState {
  title : String
}

///|
fn sheet_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<article><h2><x text=\".title\"></x></h2><button class=\"rename\" @on.click=\"rename 'Q2'\">r</button><button class=\"poke\" @on.click=\"poke\">p</button></article>",
      ),
    },
    name="Sheet",
    initial=SheetState::{ title: "Q1", },
    update=(_s : SheetState, msg, ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Next({ title: t, })
        Receive("poke", _) => {
          ctx.intent("sheet-poked", [], @tutuca.IntentOpts::new(route=[Dyn]))
          Unchanged
        }
        _ => Unhandled
      }
    },
  )
}

// One state type per component, because a schema describes a TYPE and these
// components hold DIFFERENT child slots. Sharing `SeenState` was only possible
// while the slots were declared out of band, in a `specs~` map beside the
// component rather than in what its state says about itself.

///|
priv struct ResumePanelState {
  seen : Bool
}

///|
priv struct ResumeWorkspaceState {
  seen : Bool
}

///|
priv struct ResumeSoloState {} derive(Default)

///|
priv struct ResumeLonelyState {} derive(Default)

///|
priv struct SeenState {
  seen : Bool
}

///|
fn seen_update() -> (SeenState, @component.Dispatch, &@tutuca.Ctx) -> @component.Update[
  SeenState,
] {
  (_s, msg, _ctx) => {
    match msg {
      Intent("sheet-poked", _) => Next({ seen: true, })
      _ => Unhandled
    }
  }
}

///|
fn resume_path_scope() -> @component.ComponentStack raise {
  let scope = @component.ComponentStack::new()
  let toolbar = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"toolbar\"><x render=\"*active\"></x></div>",
      ),
    },
    name="Toolbar",
    initial=SeenState::{ seen: false, },
    lookup=[@component.lookup_name("active")],
    update=seen_update(),
  )
  let panel = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<section><x render=\".toolbar\"></x></section>",
      ),
    },
    name="Panel",
    initial=ResumePanelState::{ seen: false, },
    update=(_s, msg, _ctx) => {
      match msg {
        Intent("sheet-poked", _) => Next({ seen: true, })
        _ => Unhandled
      }
    },
  )
  let workspace = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x render=\".panel\"></x></main>",
      ),
    },
    name="Workspace",
    initial=ResumeWorkspaceState::{ seen: false, },
    provide={ "active": ".sheet" },
    update=(_s, msg, _ctx) => {
      match msg {
        Intent("sheet-poked", _) => Next({ seen: true, })
        _ => Unhandled
      }
    },
  )
  scope.register_components([sheet_comp(), toolbar, panel, workspace])
  scope.compile_all()
  scope
}

///|
fn v_at(
  tx : @transactor.Transactor,
  steps : Array[@tutuca.Step],
) -> @tutuca.Value {
  match @tutuca.Path::new(steps~).lookup(tx.root) {
    Some(n) => n
    None => Null
  }
}

///|
fn assert_v(got : @tutuca.Value, want : @tutuca.Value) -> Unit raise {
  assert_true(got == want)
}

///|
test "dyn render: caller frame is saved and active frame addresses the value" {
  let scope = resume_path_scope()
  guard scope.lookup_component("Workspace") is Some(ws) else {
    fail("no Workspace")
  }
  let root = ws.make(Map([]))
  let container = mount(scope.comps, root)
  // `*active` really rendered the provided sheet through the lookup chain
  assert_true(container.to_html().contains("Q1"))
  guard find_el(container, "BUTTON") is Some(rename_btn) else {
    fail("no rename button")
  }
  guard @render.from_node_and_event_name(
      rename_btn,
      "click",
      container,
      scope.comps,
    )
    is Some(ed) else {
    fail("no event info")
  }
  // The visual caller remains in the first frame; the dynamic render pushes
  // the provider's concrete value path as a second frame.
  assert_true(
    ed.path.frames
    is [
      {
        base: { steps: [], },
        items: [
          Plain(step=FieldStep("panel"), ..),
          Plain(step=FieldStep("toolbar"), ..),
        ],
        ..
      },
      { base: { steps: [FieldStep("sheet")], }, items: [], .. },
    ],
  )
  // The active transaction path is the resumed provider data.
  assert_true(ed.path.to_transaction_path().steps is [FieldStep("sheet")])
  // and dispatching the click mutates Workspace.sheet in place
  let tx = @transactor.Transactor::new(root)
  assert_true(
    @app.dispatch_dom_event(tx, rename_btn, "click", container, scope.comps),
  )
  assert_true(v_at(tx, [FieldStep("sheet"), FieldStep("title")]) == Str("Q2"))
}

///|
test "lexical resume path renders and dispatches without a root provider" {
  let dynamic_scope = resume_path_scope()
  guard dynamic_scope.lookup_component("Toolbar") is Some(toolbar) &&
    dynamic_scope.lookup_component("Panel") is Some(panel) else {
    fail("missing fixture components")
  }
  let sheet = @component.component(
    views={
      // A fragment root forces the second button to reconstruct from the
      // repeated data-cid/data-rp attributes rather than the first Comp meta.
      "main": @anode.View::new(
        "main",
        raw_view="<h2><x text=\".title\"></x></h2><button>first</button><button class=\"rename\" @on.click=\"rename 'Q2'\">r</button>",
      ),
    },
    name="Sheet",
    initial=SheetState::{ title: "Q1", },
    update=(_s : SheetState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(title)]) => Next({ title, })
        _ => Unhandled
      }
    },
  )
  let workspace = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x render=\".panel\"></x></main>",
      ),
    },
    name="LexWorkspace",
    initial=ResumeWorkspaceState::{ seen: false, },
  )
  let scope = @component.ComponentStack::new()
  // This belongs to the lexical module/session scope. LexWorkspace itself
  // publishes nothing and exists only because it is the component we mount.
  scope.register_paths({
    "active": @tutuca.Path::new(steps=[FieldStep("sheet")]),
  })
  scope.register_components([sheet, toolbar, panel, workspace])
  scope.compile_all()
  let root = workspace.make(Map([]))
  let container = mount(scope.comps, root)
  assert_true(container.to_html().contains("Q1"))
  guard find_el(container, "BUTTON", nth=1) is Some(rename_btn) else {
    fail("no rename button")
  }
  guard @render.from_node_and_event_name(
      rename_btn,
      "click",
      container,
      scope.comps,
    )
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(ed.path.frames.length() == 2)
  assert_true(ed.path.frames[1].base.steps is [FieldStep("sheet")])
  let tx = @transactor.Transactor::new(
    root,
    names=@app.ScopeNames::new(scope.comps),
  )
  assert_true(
    @app.dispatch_dom_event(tx, rename_btn, "click", container, scope.comps),
  )
  assert_true(v_at(tx, [FieldStep("sheet"), FieldStep("title")]) == Str("Q2"))
}

///|
test "bubbling from a resumed leaf returns through the visual caller" {
  let scope = resume_path_scope()
  guard scope.lookup_component("Workspace") is Some(ws) else {
    fail("no Workspace")
  }
  let root = ws.make(Map([]))
  let container = mount(scope.comps, root)
  guard find_el(container, "BUTTON", nth=1) is Some(poke_btn) else {
    fail("no poke button")
  }
  let tx = @transactor.Transactor::new(root)
  assert_true(
    @app.dispatch_dom_event(tx, poke_btn, "click", container, scope.comps),
  )
  // the bubble walked Toolbar -> Panel -> Workspace (the dispatch path kept
  // the intermediates of the dynamic render)
  assert_v(
    v_at(tx, [FieldStep("panel"), FieldStep("toolbar"), FieldStep("seen")]),
    Bool(true),
  )
  assert_true(v_at(tx, [FieldStep("panel"), FieldStep("seen")]) == Bool(true))
  assert_true(v_at(tx, [FieldStep("seen")]) == Bool(true))
}

///|
test "own-provide: a component can resume at its own dynamic value" {
  let scope = @component.ComponentStack::new()
  let solo = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x render=\"*active\"></x></main>",
      ),
    },
    name="Solo",
    initial=ResumeSoloState::{ },
    provide={ "active": ".sheet" },
  )
  scope.register_components([sheet_comp(), solo])
  scope.compile_all()
  guard scope.lookup_component("Solo") is Some(solo_c) else { fail("no Solo") }
  let root = solo_c.make(Map([]))
  let container = mount(scope.comps, root)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(ed.path.to_transaction_path().steps is [FieldStep("sheet")])
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_true(v_at(tx, [FieldStep("sheet"), FieldStep("title")]) == Str("Q2"))
}

///|
test "iterated dynamic (@each *rows + render-it) resumes at the keyed item" {
  let scope = @component.ComponentStack::new()
  let list = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<ul><li @each=\"*rows\"><x render-it></x></li></ul>",
      ),
    },
    name="RowList",
    initial=NoState::{ },
    lookup=[@component.lookup_name("rows")],
  )
  let grid = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x render=\".list\"></x></main>",
      ),
    },
    name="Grid",
    initial=RowsState::{ rows: Map([]), },
    provide={ "rows": ".rows" },
  )
  scope.register_components([sheet_comp(), list, grid])
  scope.compile_all()
  guard scope.lookup_component("Grid") is Some(grid_c) else { fail("no Grid") }
  guard scope.lookup_component("Sheet") is Some(sheet_c) else {
    fail("no Sheet")
  }
  let root = grid_c.make({
    "rows": Map({
      "a": sheet_c.make({ "title": Str("row-a") }),
      "b": sheet_c.make({ "title": Str("row-b") }),
    }),
  })
  let container = mount(scope.comps, root)
  assert_true(container.to_html().contains("row-a"))
  // second item's rename button (buttons alternate rename/poke per sheet)
  guard find_el(container, "BUTTON", nth=2) is Some(btn) else {
    fail("no second rename button")
  }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(
    ed.path.to_transaction_path().steps
    is [SeqStep(field="rows", key=KStr("b"))],
  )
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_v(
    v_at(tx, [SeqStep(field="rows", key=KStr("b")), FieldStep("title")]),
    Str("Q2"),
  )
  assert_v(
    v_at(tx, [SeqStep(field="rows", key=KStr("a")), FieldStep("title")]),
    Str("row-a"),
  )
}

///|
test "seq-access dynamic (.sheets[.selId]) resumes at the live-keyed item" {
  let scope = @component.ComponentStack::new()
  let viewer = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\"*sel\"></x></div>",
      ),
    },
    name="Viewer",
    initial=NoState::{ },
    lookup=[@component.lookup_name("sel")],
  )
  let deck = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<main><x render=\".viewer\"></x></main>",
      ),
    },
    name="Deck",
    initial=DeckState::{ sheets: Map([]), selId: "b", },
    provide={ "sel": ".sheets[.selId]" },
  )
  scope.register_components([sheet_comp(), viewer, deck])
  scope.compile_all()
  guard scope.lookup_component("Deck") is Some(deck_c) else { fail("no Deck") }
  guard scope.lookup_component("Sheet") is Some(sheet_c) else {
    fail("no Sheet")
  }
  let root = deck_c.make({
    "sheets": Map({
      "a": sheet_c.make({ "title": Str("first") }),
      "b": sheet_c.make({ "title": Str("second") }),
    }),
  })
  let container = mount(scope.comps, root)
  assert_true(container.to_html().contains("second")) // selId=b rendered
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(
    ed.path.to_transaction_path().steps
    is [SeqAccessStep(seq_field="sheets", key_field="selId")],
  )
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_v(
    v_at(tx, [SeqStep(field="sheets", key=KStr("b")), FieldStep("title")]),
    Str("Q2"),
  )
  assert_v(
    v_at(tx, [SeqStep(field="sheets", key=KStr("a")), FieldStep("title")]),
    Str("first"),
  )
}

///|
test "lookup default: a consumer without its producer falls back" {
  let scope = @component.ComponentStack::new()
  let lonely = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\"*active\"></x></div>",
      ),
    },
    name="Lonely",
    initial=ResumeLonelyState::{ },
    lookup=[@component.lookup_or("active", ".backup")],
  )
  scope.register_components([sheet_comp(), lonely])
  scope.compile_all()
  guard scope.lookup_component("Lonely") is Some(lonely_c) else {
    fail("no Lonely")
  }
  let root = lonely_c.make(Map([]))
  // no Workspace above: the default expression resolves against the consumer
  let container = mount(scope.comps, root)
  assert_true(container.to_html().contains("Q1"))
}

///|
priv struct NoState {} derive(Default)

///|
priv struct RowsState {
  rows : Map[String, @tutuca.Value]
}

///|
priv struct DeckState {
  sheets : Map[String, @tutuca.Value]
  selId : String
}

///|
impl @component.Fields for SheetState with fn encode(s) {
  { "title": Str(s.title) }
}

///|
impl @component.Fields for SheetState with fn decode(f) {
  guard f.get("title") is Some(Str(v_title)) else { return None }
  Some({ title: v_title, })
}

///|
impl @component.Fields for SeenState with fn encode(s) {
  { "seen": Bool(s.seen) }
}

///|
impl @component.Fields for SeenState with fn decode(f) {
  guard f.get("seen") is Some(Bool(v_seen)) else { return None }
  Some({ seen: v_seen, })
}

///|
impl @component.Fields for NoState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for NoState with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for RowsState with fn encode(s) {
  { "rows": (Map(s.rows) : @tutuca.Value) }
}

///|
impl @component.Fields for RowsState with fn decode(f) {
  guard f.get("rows") is Some(Map(v_rows)) else { return None }
  Some({ rows: v_rows, })
}

///|
impl @component.Fields for DeckState with fn encode(s) {
  { "sheets": (Map(s.sheets) : @tutuca.Value), "selId": Str(s.selId) }
}

///|
impl @component.Fields for DeckState with fn decode(f) {
  guard f.get("sheets") is Some(Map(v_sheets)) else { return None }
  guard f.get("selId") is Some(Str(v_selId)) else { return None }
  Some({ sheets: v_sheets, selId: v_selId, })
}

///|
impl @component.Fields for SheetState with fn schema() {
  @component.SchemaInfo::new(fingerprint="sheet_state", fields=[
    @component.FieldInfo::new("title", TyText),
  ])
}

///|
impl @component.Fields for SeenState with fn schema() {
  @component.SchemaInfo::new(fingerprint="seen_state", fields=[
    @component.FieldInfo::new("seen", TyBool),
  ])
}

///|
impl @component.Fields for ResumePanelState with fn schema() {
  @component.SchemaInfo::new(fingerprint="tele_panel_state", fields=[
    @component.FieldInfo::new("seen", TyBool),
    @component.FieldInfo::new("toolbar", TyComp(Some("Toolbar"))),
  ])
}

///|
impl @component.Fields for ResumePanelState with fn encode(s) {
  { "seen": Bool(s.seen) }
}

///|
impl @component.Fields for ResumePanelState with fn decode(f) {
  guard f.get("seen") is Some(Bool(v)) else { return None }
  Some({ seen: v, })
}

///|
impl @component.Fields for ResumeWorkspaceState with fn schema() {
  @component.SchemaInfo::new(fingerprint="tele_workspace_state", fields=[
    @component.FieldInfo::new("seen", TyBool),
    @component.FieldInfo::new("sheet", TyComp(Some("Sheet"))),
    @component.FieldInfo::new("panel", TyComp(Some("Panel"))),
  ])
}

///|
impl @component.Fields for ResumeWorkspaceState with fn encode(s) {
  { "seen": Bool(s.seen) }
}

///|
impl @component.Fields for ResumeWorkspaceState with fn decode(f) {
  guard f.get("seen") is Some(Bool(v)) else { return None }
  Some({ seen: v, })
}

///|
impl @component.Fields for ResumeSoloState with fn schema() {
  @component.SchemaInfo::new(fingerprint="tele_solo_state", fields=[
    @component.FieldInfo::new("sheet", TyComp(Some("Sheet"))),
  ])
}

///|
impl @component.Fields for ResumeSoloState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for ResumeSoloState with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for ResumeLonelyState with fn schema() {
  @component.SchemaInfo::new(fingerprint="tele_lonely_state", fields=[
    @component.FieldInfo::new("backup", TyComp(Some("Sheet"))),
  ])
}

///|
impl @component.Fields for ResumeLonelyState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for ResumeLonelyState with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for NoState with fn schema() {
  @component.SchemaInfo::new(fingerprint="no_state", fields=[])
}

///|
impl @component.Fields for RowsState with fn schema() {
  @component.SchemaInfo::new(fingerprint="rows_state", fields=[
    @component.FieldInfo::new("rows", TyOMap(TyAny)),
    @component.FieldInfo::new("list", TyComp(Some("RowList"))),
  ])
}

///|
impl @component.Fields for DeckState with fn schema() {
  @component.SchemaInfo::new(fingerprint="deck_state", fields=[
    @component.FieldInfo::new("sheets", TyOMap(TyAny)),
    @component.FieldInfo::new("selId", TyText),
    @component.FieldInfo::new("viewer", TyComp(Some("Viewer"))),
  ])
}
