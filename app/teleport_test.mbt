// Dynamic-var teleporting end-to-end (ports of test/path.test.js:642-899 and
// semantics.md §7): Workspace provides `.sheet`; a Toolbar deep in the tree
// renders `*active`; clicking inside the sheet must reconstruct a dispatch
// path that walks every intermediate component (bubbling) while the
// TRANSACTION path teleports to the producer's data.

///|
fn sheet_comp() -> @component.Component {
  @component.component(
    name="Sheet",
    view="<article><h2><x text=\".title\"></x></h2><button class=\"rename\" @on.click=\"rename 'Q2'\">r</button><button class=\"poke\" @on.click=\"poke\">p</button></article>",
    fields={ "title": @component.FieldSpec::of_default(Str("Q1")) },
    input={
      "rename": (inst, args, _ctx) => {
        match args {
          [Str(s)] => Some(inst.set("title", Str(s)))
          _ => None
        }
      },
      "poke": (_inst, _args, ctx) => {
        ctx.bubble("sheet-poked", [])
        None
      },
    },
  )
}

///|
fn seen_bubble() -> Map[String, @component.InstanceHandler] {
  { "sheet-poked": (inst, _args, _ctx) => Some(inst.set("seen", Bool(true))) }
}

///|
fn teleport_scope() -> @component.ComponentStack raise {
  let scope = @component.ComponentStack::new()
  let toolbar = @component.component(
    name="Toolbar",
    view="<div class=\"toolbar\"><x render=\"*active\"></x></div>",
    fields={ "seen": @component.FieldSpec::of_default(Bool(false)) },
    lookup={
      "active": @component.LookupSpec::{
        source: "Workspace.active",
        default: None,
      },
    },
    bubble=seen_bubble(),
  )
  let panel = @component.component(
    name="Panel",
    view="<section><x render=\".toolbar\"></x></section>",
    fields={
      "toolbar": @component.FieldSpec::comp("Toolbar"),
      "seen": @component.FieldSpec::of_default(Bool(false)),
    },
    bubble=seen_bubble(),
  )
  let workspace = @component.component(
    name="Workspace",
    view="<main><x render=\".panel\"></x></main>",
    fields={
      "sheet": @component.FieldSpec::comp("Sheet"),
      "panel": @component.FieldSpec::comp("Panel"),
      "seen": @component.FieldSpec::of_default(Bool(false)),
    },
    provide={ "active": ".sheet" },
    bubble=seen_bubble(),
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
    Some(n) => n.as_value().unwrap_or(Null)
    None => Null
  }
}

///|
fn assert_v(got : @tutuca.Value, want : @tutuca.Value) -> Unit raise {
  assert_true(got == want)
}

///|
test "dyn render: dispatch path keeps intermediates, txn path teleports" {
  let scope = teleport_scope()
  guard scope.lookup_component("Workspace") is Some(ws) else {
    fail("no Workspace")
  }
  let root = ws.make({})
  let container = mount(scope.comps, root.to_value())
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
  // one hop per crossed component, ending in the Dyn marker whose interior
  // spans consumer..producer (toolbar, panel, AND the producer's own
  // render-site step)
  assert_true(
    ed.path.items
    is [
      Plain(step=FieldStep("panel"), ..),
      Plain(step=FieldStep("toolbar"), ..),
      Dyn(steps=[FieldStep("sheet")], ..),
    ],
  )
  guard ed.path.items is [_, _, Dyn(producer~, interior~, ..)] else {
    fail("no dyn marker")
  }
  assert_eq(producer, ws.id)
  assert_eq(interior.length(), 3)
  // the transaction path collapses to the producer's data
  assert_true(ed.path.to_transaction_path().steps is [FieldStep("sheet")])
  // and dispatching the click mutates Workspace.sheet in place
  let tx = @transactor.Transactor::new(root.to_value())
  assert_true(
    @app.dispatch_dom_event(tx, rename_btn, "click", container, scope.comps),
  )
  assert_true(v_at(tx, [FieldStep("sheet"), FieldStep("title")]) == Str("Q2"))
}

///|
test "bubbling from a teleported leaf visits every intermediate component" {
  let scope = teleport_scope()
  guard scope.lookup_component("Workspace") is Some(ws) else {
    fail("no Workspace")
  }
  let root = ws.make({})
  let container = mount(scope.comps, root.to_value())
  guard find_el(container, "BUTTON", nth=1) is Some(poke_btn) else {
    fail("no poke button")
  }
  let tx = @transactor.Transactor::new(root.to_value())
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
test "own-provide: a component rendering its own dynamic teleports to itself" {
  let scope = @component.ComponentStack::new()
  let solo = @component.component(
    name="Solo",
    view="<main><x render=\"*active\"></x></main>",
    fields={ "sheet": @component.FieldSpec::comp("Sheet") },
    provide={ "active": ".sheet" },
  )
  scope.register_components([sheet_comp(), solo])
  scope.compile_all()
  guard scope.lookup_component("Solo") is Some(solo_c) else { fail("no Solo") }
  let root = solo_c.make({})
  let container = mount(scope.comps, root.to_value())
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(ed.path.to_transaction_path().steps is [FieldStep("sheet")])
  let tx = @transactor.Transactor::new(root.to_value())
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_true(v_at(tx, [FieldStep("sheet"), FieldStep("title")]) == Str("Q2"))
}

///|
test "iterated dynamic (@each *rows + render-it) teleports to the keyed item" {
  let scope = @component.ComponentStack::new()
  let list = @component.component(
    name="RowList",
    view="<ul><li @each=\"*rows\"><x render-it></x></li></ul>",
    lookup={
      "rows": @component.LookupSpec::{ source: "Grid.rows", default: None },
    },
  )
  let grid = @component.component(
    name="Grid",
    view="<main><x render=\".list\"></x></main>",
    fields={
      "rows": @component.FieldSpec::of_default(Map({})),
      "list": @component.FieldSpec::comp("RowList"),
    },
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
      "a": sheet_c.make({ "title": Str("row-a") }).to_value(),
      "b": sheet_c.make({ "title": Str("row-b") }).to_value(),
    }),
  })
  let container = mount(scope.comps, root.to_value())
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
  let tx = @transactor.Transactor::new(root.to_value())
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
test "seq-access dynamic (.sheets[.selId]) teleports to the live-keyed item" {
  let scope = @component.ComponentStack::new()
  let viewer = @component.component(
    name="Viewer",
    view="<div><x render=\"*sel\"></x></div>",
    lookup={
      "sel": @component.LookupSpec::{ source: "Deck.sel", default: None },
    },
  )
  let deck = @component.component(
    name="Deck",
    view="<main><x render=\".viewer\"></x></main>",
    fields={
      "sheets": @component.FieldSpec::of_default(Map({})),
      "selId": @component.FieldSpec::of_default(Str("b")),
      "viewer": @component.FieldSpec::comp("Viewer"),
    },
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
      "a": sheet_c.make({ "title": Str("first") }).to_value(),
      "b": sheet_c.make({ "title": Str("second") }).to_value(),
    }),
  })
  let container = mount(scope.comps, root.to_value())
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
  let tx = @transactor.Transactor::new(root.to_value())
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
    name="Lonely",
    view="<div><x render=\"*active\"></x></div>",
    fields={ "backup": @component.FieldSpec::comp("Sheet") },
    lookup={
      "active": @component.LookupSpec::{
        source: "Workspace.active",
        default: Some(".backup"),
      },
    },
  )
  scope.register_components([sheet_comp(), lonely])
  scope.compile_all()
  guard scope.lookup_component("Lonely") is Some(lonely_c) else {
    fail("no Lonely")
  }
  let root = lonely_c.make({})
  // no Workspace above: the default expression resolves against the consumer
  let container = mount(scope.comps, root.to_value())
  assert_true(container.to_html().contains("Q1"))
}
