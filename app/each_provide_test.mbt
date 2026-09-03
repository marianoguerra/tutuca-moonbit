// A `provide` published from INSIDE an `@each` body. The loop moves the render
// position to the item, so everything the item publishes lives under
// `rows[key]` — and a `<x render="*psel">` below it has to resume there, not at
// the app root. The three grid shapes below differ only in how the item is
// reached; the address they publish must not.

///|
priv struct PbSlotState {} derive(Default)

///|
priv struct PbCellState {
  doc : @tutuca.Value
}

///|
priv struct PbGridState {
  rows : Array[@tutuca.Value]
}

///|
priv struct PbPlainState {
  cell : @tutuca.Value
}

///|
/// Slot consumes `*psel` and is the render target: it holds no data of its own,
/// so a mutation landing anywhere but the provider's `.doc` is visible.
fn pb_slot() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"slot\"><x render=\"*psel\"></x></div>",
      ),
    },
    name="PbSlot",
    initial=PbSlotState::{ },
    lookup=[@component.lookup_name("psel")],
  )
}

///|
fn pb_cell() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"cell\"><x render=\".slot\"></x></div>",
      ),
    },
    name="PbCell",
    initial=PbCellState::{ doc: Null, },
    provide={ "psel": ".doc" },
  )
}

///|
fn pb_scope(
  grid_view : String,
  grid_state : String,
) -> @component.ComponentStack raise {
  let scope = @component.ComponentStack::new()
  let grid = if grid_state == "rows" {
    @component.component(
      views={ "main": @anode.View::new("main", raw_view=grid_view) },
      name="PbGrid",
      initial=PbGridState::{ rows: [], },
    )
  } else {
    @component.component(
      views={ "main": @anode.View::new("main", raw_view=grid_view) },
      name="PbGrid",
      initial=PbPlainState::{ cell: Null, },
    )
  }
  scope.register_components([sheet_comp(), pb_slot(), pb_cell(), grid])
  scope.compile_all()
  scope
}

///|
fn pb_rows(scope : @component.ComponentStack) -> @tutuca.Value raise {
  guard scope.lookup_component("PbCell") is Some(cell) &&
    scope.lookup_component("Sheet") is Some(sheet) else {
    fail("missing fixture components")
  }
  List([
    cell.make({ "doc": sheet.make({ "title": Str("row-a") }) }),
    cell.make({ "doc": sheet.make({ "title": Str("row-b") }) }),
  ])
}

///|
fn pb_row_title(tx : @transactor.Transactor, i : Int) -> @tutuca.Value {
  v_at(tx, [
    SeqStep(field="rows", key=KInt(i)),
    FieldStep("doc"),
    FieldStep("title"),
  ])
}

///|
test "provide inside @each publishes the item address, not the root" {
  let scope = pb_scope(
    "<div class=\"grid\"><div @each=\".rows\"><x render-it></x></div></div>", "rows",
  )
  guard scope.lookup_component("PbGrid") is Some(grid) else {
    fail("no PbGrid")
  }
  let root = grid.make({ "rows": pb_rows(scope) })
  let container = mount(scope.comps, root)
  assert_true(container.to_html().contains("row-b"))
  guard find_el(container, "BUTTON", nth=2) is Some(btn) else {
    fail("no second rename button")
  }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  // the resumed frame is the provider's own `.doc`, under row 1
  assert_true(
    ed.path.to_transaction_path().steps
    is [SeqStep(field="rows", key=KInt(1)), FieldStep("doc")],
  )
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_v(pb_row_title(tx, 1), Str("Q2"))
  assert_v(pb_row_title(tx, 0), Str("row-a"))
}

///|
test "render-each sugar publishes the same item address" {
  let scope = pb_scope(
    "<div class=\"grid\"><x render-each=\".rows\"></x></div>", "rows",
  )
  guard scope.lookup_component("PbGrid") is Some(grid) else {
    fail("no PbGrid")
  }
  let root = grid.make({ "rows": pb_rows(scope) })
  let container = mount(scope.comps, root)
  guard find_el(container, "BUTTON", nth=2) is Some(btn) else {
    fail("no second rename button")
  }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(
    ed.path.to_transaction_path().steps
    is [SeqStep(field="rows", key=KInt(1)), FieldStep("doc")],
  )
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_v(pb_row_title(tx, 1), Str("Q2"))
  assert_v(pb_row_title(tx, 0), Str("row-a"))
}

///|
test "provide with no loop above it still addresses its own field" {
  let scope = pb_scope(
    "<div class=\"grid\"><x render=\".cell\"></x></div>", "cell",
  )
  guard scope.lookup_component("PbGrid") is Some(grid) else {
    fail("no PbGrid")
  }
  guard scope.lookup_component("PbCell") is Some(cell) &&
    scope.lookup_component("Sheet") is Some(sheet) else {
    fail("missing fixture components")
  }
  let root = grid.make({
    "cell": cell.make({ "doc": sheet.make({ "title": Str("solo") }) }),
  })
  let container = mount(scope.comps, root)
  guard find_el(container, "BUTTON") is Some(btn) else { fail("no button") }
  guard @render.from_node_and_event_name(btn, "click", container, scope.comps)
    is Some(ed) else {
    fail("no event info")
  }
  assert_true(
    ed.path.to_transaction_path().steps is [FieldStep("cell"), FieldStep("doc")],
  )
  let tx = @transactor.Transactor::new(root)
  assert_true(@app.dispatch_dom_event(tx, btn, "click", container, scope.comps))
  assert_v(
    v_at(tx, [FieldStep("cell"), FieldStep("doc"), FieldStep("title")]),
    Str("Q2"),
  )
}

///|
impl @component.Fields for PbSlotState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for PbSlotState with fn decode(_f) {
  Some(Default::default())
}

///|
impl @component.Fields for PbSlotState with fn schema() {
  @component.SchemaInfo::new(fingerprint="pb_slot_state", fields=[])
}

///|
impl @component.Fields for PbCellState with fn encode(s) {
  { "doc": s.doc }
}

///|
impl @component.Fields for PbCellState with fn decode(f) {
  guard f.get("doc") is Some(doc) else { return None }
  Some({ doc, })
}

///|
impl @component.Fields for PbCellState with fn schema() {
  @component.SchemaInfo::new(fingerprint="pb_cell_state", fields=[
    @component.FieldInfo::new("doc", TyComp(Some("Sheet"))),
    @component.FieldInfo::new("slot", TyComp(Some("PbSlot"))),
  ])
}

///|
impl @component.Fields for PbGridState with fn encode(s) {
  { "rows": (List(s.rows) : @tutuca.Value) }
}

///|
impl @component.Fields for PbGridState with fn decode(f) {
  guard f.get("rows") is Some(List(rows)) else { return None }
  Some({ rows, })
}

///|
impl @component.Fields for PbGridState with fn schema() {
  @component.SchemaInfo::new(fingerprint="pb_grid_state", fields=[
    @component.FieldInfo::new("rows", TyList(TyComp(Some("PbCell")))),
  ])
}

///|
impl @component.Fields for PbPlainState with fn encode(s) {
  { "cell": s.cell }
}

///|
impl @component.Fields for PbPlainState with fn decode(f) {
  guard f.get("cell") is Some(cell) else { return None }
  Some({ cell, })
}

///|
impl @component.Fields for PbPlainState with fn schema() {
  @component.SchemaInfo::new(fingerprint="pb_plain_state", fields=[
    @component.FieldInfo::new("cell", TyComp(Some("PbCell"))),
  ])
}
