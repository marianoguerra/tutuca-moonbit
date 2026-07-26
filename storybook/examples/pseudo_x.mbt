// Port of docs/examples/pseudo-x.js — the @x escape hatch.
//
// The HTML parser strips a literal `<x>` element that is not a legal child of
// its parent: `<x>` inside `<table>` or `<select>` vanishes before tutuca sees
// it. The fix is to attach `@x` as the FIRST attribute of a tag the parser DOES
// accept there — `<tr @x render-each=".rows">` or `<option @x render-each=".options">`.
// The element pretends to be an `<x>` op while satisfying the parser.

///|
fn table_row_comp() -> @component.Component {
  @component.component(
    views=table_row_views(),
    name="TableRow",
    init=TableRowState::{ name: "", qty: 0, price: 0.0 },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=table_row_encode,
    decode=table_row_decode,
  )
}

///|
/// `<tr @x render-each=".rows">` — without the `@x` the parser would drop an
/// `<x>` here, since `<x>` is not valid inside `<tbody>`.
fn item_table_comp() -> @component.Component {
  @component.component(
    views=item_table_views(),
    name="ItemTable",
    init=ItemTableState::{ rows: [] },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=item_table_encode,
    decode=item_table_decode,
  )
}

///|
fn select_option_comp() -> @component.Component {
  @component.component(
    views=select_option_views(),
    name="SelectOption",
    init=SelectOptionState::{ value: "", label: "" },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=select_option_encode,
    decode=select_option_decode,
  )
}

///|
/// Same trick inside `<select>`: `<option @x render-each=".options">`.
fn item_select_comp() -> @component.Component {
  @component.component(
    views=item_select_views(),
    name="ItemSelect",
    init=ItemSelectState::{ options: [], current: "" },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=item_select_encode,
    decode=item_select_decode,
  )
}

///|
fn pseudo_x_demo_comp() -> @component.Component {
  @component.component(
    views=pseudo_x_demo_views(),
    name="PseudoXDemo",
    init=PseudoXDemoState::{  },
    specs={
      "table": @component.FieldSpec::comp("ItemTable"),
      "select": @component.FieldSpec::comp("ItemSelect"),
    },
  )
}

///|
pub fn pseudo_x_module() -> @component.ModuleDef {
  let row = table_row_comp()
  let opt = select_option_comp()
  let table = item_table_comp()
  let select = item_select_comp()
  let rows = [
    row.make({ "name": Str("Apple"), "qty": Num(3), "price": Num(1.5) }),
    row.make({ "name": Str("Bread"), "qty": Num(1), "price": Num(2.25) }),
    row.make({ "name": Str("Cheese"), "qty": Num(2), "price": Num(4.0) }),
  ]
  let options = [
    opt.make({ "value": Str("a"), "label": Str("Alpha") }),
    opt.make({ "value": Str("b"), "label": Str("Beta") }),
    opt.make({ "value": Str("c"), "label": Str("Gamma") }),
  ]
  @component.ModuleDef::new(
    name="pseudo-x",
    components=[pseudo_x_demo_comp(), table, row, select, opt],
    examples=[
      {
        component: "PseudoXDemo",
        title: "Default",
        args: {
          "table": table.make({ "rows": List(rows) }),
          "select": select.make({
            "current": Str("b"),
            "options": List(options),
          }),
        },
        view: None,
      },
      {
        component: "ItemTable",
        title: "Table with row components",
        args: { "rows": List(rows) },
        view: None,
      },
      {
        component: "ItemSelect",
        title: "Select with option components",
        args: { "current": Str("b"), "options": List(options) },
        view: None,
      },
    ],
  )
}
