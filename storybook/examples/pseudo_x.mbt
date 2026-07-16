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
    name="TableRow",
    view=(
      #|<tr>
      #|  <td class="name" @text=".name"></td>
      #|  <td class="qty" @text=".qty"></td>
      #|  <td class="price" @text=".price"></td>
      #|</tr>
    ),
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "qty": @component.FieldSpec::of_default(Num(0)),
      "price": @component.FieldSpec::of_default(Num(0)),
    },
  )
}

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
    fields={ "rows": @component.FieldSpec::of_default(List([])) },
  )
}

///|
fn select_option_comp() -> @component.Component {
  @component.component(
    name="SelectOption",
    view=(
      #|<option :value=".value" @text=".label"></option>
    ),
    fields={
      "value": @component.FieldSpec::of_default(Str("")),
      "label": @component.FieldSpec::of_default(Str("")),
    },
  )
}

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
    fields={
      "options": @component.FieldSpec::of_default(List([])),
      "current": @component.FieldSpec::of_default(Str("")),
    },
  )
}

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
    fields={
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
    row
    .make({ "name": Str("Apple"), "qty": Num(3), "price": Num(1.5) })
    .to_value(),
    row
    .make({ "name": Str("Bread"), "qty": Num(1), "price": Num(2.25) })
    .to_value(),
    row
    .make({ "name": Str("Cheese"), "qty": Num(2), "price": Num(4.0) })
    .to_value(),
  ]
  let options = [
    opt.make({ "value": Str("a"), "label": Str("Alpha") }).to_value(),
    opt.make({ "value": Str("b"), "label": Str("Beta") }).to_value(),
    opt.make({ "value": Str("c"), "label": Str("Gamma") }).to_value(),
  ]
  @component.ModuleDef::new(
    name="pseudo-x",
    components=[pseudo_x_demo_comp(), table, row, select, opt],
    examples=[
      {
        component: "PseudoXDemo",
        title: "Default",
        args: {
          "table": table.make({ "rows": List(rows) }).to_value(),
          "select": select
          .make({ "current": Str("b"), "options": List(options) })
          .to_value(),
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
