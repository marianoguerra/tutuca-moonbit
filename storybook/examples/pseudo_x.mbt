// Port of docs/examples/pseudo-x.js — the @x escape hatch.
//
// The HTML parser strips a literal `<x>` element that is not a legal child of
// its parent: `<x>` inside `<table>` or `<select>` vanishes before tutuca sees
// it. The fix is to attach `@x` as the FIRST attribute of a tag the parser DOES
// accept there — `<tr @x render-each=".rows">` or `<option @x render-each=".options">`.
// The element pretends to be an `<x>` op while satisfying the parser.

///|
priv struct TableRowState {
  name : String
  qty : Int
  price : Double
} derive(ToJson, FromJson)

///|
fn table_row_comp() -> @component.Component {
  @component.component(
    name="TableRow",
    view=(
      #|<tr>
      #|  <td class="name" @text=".name"></td>
      #|  <td class="qty" @text=".qty"></td>
      #|  <td class="price" @text=".price"></td>
      #|</tr>
    ),
    init=TableRowState::{ name: "", qty: 0, price: 0.0 },
  )
}

///|
priv struct ItemTableState {
  rows : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
/// `<tr @x render-each=".rows">` — without the `@x` the parser would drop an
/// `<x>` here, since `<x>` is not valid inside `<tbody>`.
fn item_table_comp() -> @component.Component {
  @component.component(
    name="ItemTable",
    view=(
      #|<table class="table">
      #|  <thead><tr><th>Name</th><th>Qty</th><th>Price</th></tr></thead>
      #|  <tbody>
      #|    <tr @x render-each=".rows"></tr>
      #|  </tbody>
      #|</table>
    ),
    init=ItemTableState::{ rows: [] },
  )
}

///|
priv struct SelectOptionState {
  value : String
  label : String
} derive(ToJson, FromJson)

///|
fn select_option_comp() -> @component.Component {
  @component.component(
    name="SelectOption",
    view=(
      #|<option :value=".value" @text=".label"></option>
    ),
    init=SelectOptionState::{ value: "", label: "" },
  )
}

///|
priv struct ItemSelectState {
  options : Array[@tutuca.Value]
  current : String
} derive(ToJson, FromJson)

///|
/// Same trick inside `<select>`: `<option @x render-each=".options">`.
fn item_select_comp() -> @component.Component {
  @component.component(
    name="ItemSelect",
    view=(
      #|<select class="select" :value=".current" @on.input="$setCurrent value">
      #|  <option @x render-each=".options"></option>
      #|</select>
    ),
    init=ItemSelectState::{ options: [], current: "" },
  )
}

///|
priv struct PseudoXNoState {} derive(ToJson, FromJson)

///|
fn pseudo_x_demo_comp() -> @component.Component {
  @component.component(
    name="PseudoXDemo",
    view=(
      #|<div>
      #|  <x render=".table"></x>
      #|  <x render=".select"></x>
      #|</div>
    ),
    init=PseudoXNoState::{  },
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
