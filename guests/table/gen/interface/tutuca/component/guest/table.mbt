///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The table guest: the reference consumer of `tutuca:component/tables`.
///
/// It exists to show that the shared table vocabulary is usable end to end, and
/// to be the thing that FAILS if it is not. Every piece of the design is on the
/// path here: the host validates an agent's JSON against the `ty-table` schema
/// (jsonschema/coerce_table.mbt), hands it over as a `values.value` tree, this
/// decodes it with `table_of_value`, sorts and pages it through `apply_command`
/// — the `command` variant, actually spoken rather than merely declared — and
/// hands it back with `table_to_value`.
///
/// THE GET_FIELD RULE, which this component is shaped around. `get_field` runs
/// once per `.name` a rendering view reaches for, on every render, at roughly
/// 5 µs a call. So the visible page is computed in `handle` and STORED as plain
/// MoonBit data, and `get_field` only builds the arena value for what is
/// already decided. It cannot be cached any further than that: an arena handle
/// is valid only for the duration of one host->guest call, so the `values.value`
/// itself has to be rebuilt each time even though its contents do not change.

///|
/// One page's worth of already-decided text. Not a `values.value`, because a
/// handle would be stale by the time the next render asked for it.
priv struct Cells {
  labels : Array[String]
  types : Array[String]
  ids : Array[String]
  rows : Array[Array[String]]
}

///|
priv struct TableView {
  table : @tables.Table
  page : Int
  page_size : Int
  /// "" when nothing is sorted; otherwise the column id.
  sort : String
  descending : Bool
  /// Derived from everything above. Recomputed on every successor, never in
  /// `get_field`.
  view : Cells
}

///|
/// The page the table is showing, as text. The one place that walks cells.
fn project(t : @tables.Table, page : Int, page_size : Int) -> Cells {
  let labels = t.columns.map(c => c.label)
  let ids = t.columns.map(c => c.id)
  let types = t.columns.map(c => col_type_tag(col_values_type(c.values)))
  let width = table_width(t)
  let start = page * page_size
  let stop = if start + page_size < width { start + page_size } else { width }
  let rows : Array[Array[String]] = []
  for r in start..<stop {
    let row : Array[String] = []
    for ci in 0..<t.columns.length() {
      row.push(cell_text(table_cell(t, ci, r)))
    }
    rows.push(row)
  }
  { labels, types, ids, rows, }
}

///|
/// How many pages the current table and page size make. At least one, so
/// "page 1 of 1" is what an empty table says rather than "page 1 of 0".
fn page_count(t : @tables.Table, page_size : Int) -> Int {
  let width = table_width(t)
  if width == 0 || page_size <= 0 {
    1
  } else {
    (width + page_size - 1) / page_size
  }
}

///|
/// A successor with the page clamped and the projection rebuilt. Every handler
/// ends here, so no path can leave the two disagreeing.
fn TableView::retable(
  self : TableView,
  table : @tables.Table,
  page : Int,
  sort : String,
  descending : Bool,
) -> TableView {
  let pages = page_count(table, self.page_size)
  let clamped = if page < 0 {
    0
  } else if page >= pages {
    pages - 1
  } else {
    page
  }
  {
    table,
    page: clamped,
    page_size: self.page_size,
    sort,
    descending,
    view: project(table, clamped, self.page_size),
  }
}

///|
impl DynComponent for TableView with fn get_field(self, name) {
  match name {
    // The DECLARED field. The host reads it when it projects the instance to
    // JSON or shows it in the inspector — not on every render, because the
    // views below read the derived fields instead.
    "data" => Some(table_to_value(self.table))
    "labels" => Some(text_list(self.view.labels))
    "types" => Some(text_list(self.view.types))
    "ids" => Some(text_list(self.view.ids))
    "rows" => {
      let h = @values.list_new()
      for row in self.view.rows {
        @values.list_push(h, text_list(row))
      }
      Some(@values.Value::List(h))
    }
    "page" => Some(@values.Value::Number((self.page + 1).to_double()))
    "pageCount" =>
      Some(
        @values.Value::Number(
          page_count(self.table, self.page_size).to_double(),
        ),
      )
    "pageSize" => Some(@values.Value::Number(self.page_size.to_double()))
    "rowCount" =>
      Some(@values.Value::Number(table_width(self.table).to_double()))
    "colCount" =>
      Some(@values.Value::Number(self.table.columns.length().to_double()))
    "sort" => Some(@values.Value::Text(self.sort))
    "descending" => Some(@values.Value::Boolean(self.descending))
    "empty" => Some(@values.Value::Boolean(table_width(self.table) == 0))
    "summary" => {
      let n = table_width(self.table)
      let c = self.table.columns.length()
      Some(@values.Value::Text("\{n} rows × \{c} columns"))
    }
    _ => None
  }
}

///|
fn text_list(xs : Array[String]) -> @values.Value {
  let h = @values.list_new()
  for x in xs {
    @values.list_push(h, @values.Value::Text(x))
  }
  @values.Value::List(h)
}

///|
impl DynComponent for TableView with fn handle_dispatch(
  self,
  bucket,
  name,
  args,
) {
  match (bucket, name) {
    (MessageDispatch, "nextPage") =>
      Changed(
        self.retable(self.table, self.page + 1, self.sort, self.descending)
        as &DynComponent,
      )
    (MessageDispatch, "prevPage") =>
      Changed(
        self.retable(self.table, self.page - 1, self.sort, self.descending)
        as &DynComponent,
      )
    (MessageDispatch, "firstPage") =>
      Changed(
        self.retable(self.table, 0, self.sort, self.descending) as &DynComponent,
      )
    (MessageDispatch, "lastPage") =>
      Changed(
        self.retable(
          self.table,
          page_count(self.table, self.page_size) - 1,
          self.sort,
          self.descending,
        )
        as &DynComponent,
      )
    // The view passes the column id: `@on.click="sortBy @value"` over `.ids`.
    // Clicking the column already sorted reverses it, which is what every
    // table in the world does and what nobody thinks to ask for.
    (MessageDispatch, "sortBy") =>
      match args {
        [@values.Value::Text(id), ..] => {
          let descending = if self.sort == id {
            !self.descending
          } else {
            false
          }
          let cmd : @tables.Command = SortBy({ column: id, descending, })
          match apply_command(self.table, cmd) {
            Ok(sorted) =>
              Changed(self.retable(sorted, 0, id, descending) as &DynComponent)
            // A refused command is a no-op, not a crash. The id came from the
            // view, so a miss means the table changed under it.
            Err(_) => Unchanged
          }
        }
        _ => Unchanged
      }
    // Replace the data wholesale — how a parent or the host hands this
    // component a new table (`ctx.send("load", [table])`).
    (MessageDispatch, "load") =>
      match args {
        [v, ..] =>
          match table_of_value(v) {
            Some(t) => Changed(self.retable(t, 0, "", false) as &DynComponent)
            None => Unchanged
          }
        _ => Unchanged
      }
    (MessageDispatch, "clear") =>
      match apply_command(self.table, Clear) {
        Ok(t) =>
          Changed(
            self.retable(t, 0, self.sort, self.descending) as &DynComponent,
          )
        Err(_) => Unchanged
      }
    (MessageDispatch, "init") => Unchanged
    _ => Unhandled
  }
}

///|
/// The host writes through this when it sets the declared field — the generated
/// `setData` mutator, which the component gets without implementing it.
impl DynComponent for TableView with fn with_field(self, name, v) {
  match name {
    "data" =>
      match table_of_value(v) {
        Some(t) => Some(self.retable(t, 0, "", false) as &DynComponent)
        None => None
      }
    _ => None
  }
}

///|
impl DynComponent for TableView with fn render_call(self, name, args) {
  match name {
    // Is this the column the table is sorted by? Drives the header arrow.
    "sortedBy" =>
      match args {
        [@values.Value::Text(id), ..] =>
          @values.Value::Boolean(id == self.sort && self.sort != "")
        _ => @values.Value::Boolean(false)
      }
    "sortMark" =>
      @values.Value::Text(if self.descending { "▾" } else { "▴" })
    "atFirst" => @values.Value::Boolean(self.page <= 0)
    "atLast" =>
      @values.Value::Boolean(
        self.page >= page_count(self.table, self.page_size) - 1,
      )
    _ => @values.Value::Nil
  }
}

///|
fn make_table(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut table = table_empty()
  let mut page_size = 10
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("data", _) =>
        match table_of_value(v) {
          Some(t) => table = t
          // Unreachable through the host, which refuses a malformed table at
          // `coerce` before construction. Reachable from a bundle that builds
          // one itself, and an empty table is the honest answer for it.
          None => ()
        }
      ("pageSize", @values.Value::Number(n)) =>
        if n >= 1.0 {
          page_size = n.to_int()
        }
      _ => ()
    }
  }
  let base : TableView = {
    table,
    page: 0,
    page_size,
    sort: "",
    descending: false,
    view: project(table, 0, page_size),
  }
  base as &DynComponent
}

///|
fn dyn_module() -> DynModule {
  module_def([dyn_comp("Table", make_table)])
}
