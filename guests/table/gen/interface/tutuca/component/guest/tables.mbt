///| Table codec for `tutuca:component` guests: `@values.Value` <-> `@tables.Table`.
///
/// CANONICAL COPY: `guests/tables.mbt`. `gen-bindings.mjs` copies it verbatim
/// into every guest's generated guest package, exactly as it does `sdk.mbt` —
/// so edit the canonical, never a copy. A copy edited by hand is overwritten on
/// the next regeneration and the drift check fails the commit that did it.
///
/// `interface tables` declares types and no functions, which is what makes the
/// shared vocabulary free at runtime. The price is that nothing generated moves
/// a table across the boundary: a table reaches a guest as a `values.value`
/// tree (arena handles) like every other field, and this is the one place that
/// knows the shape on both sides. Written once here rather than once per guest
/// for the same reason there is one SDK: five copies of a contract is five
/// chances to answer differently.
///
/// THE ONE ASYMMETRY. The WIT carries a column's missing values as a sparse
/// `nulls` index list; the wire carries them inline as `nil` inside `values`.
/// Inline is what the host's JSON form uses and what a generator writes
/// unprompted; sparse is what is cheap to hand across a boundary when — as is
/// usual — nothing is missing. Neither side is wrong, so the conversion lives
/// here and nowhere else.
///
/// The host has already checked what it hands over (`jsonschema.coerce`
/// enforces equal width, cell types and i32 range), so decode is TOLERANT
/// rather than a second validator: a cell that is not what its column claims
/// becomes missing instead of failing the whole table. A guest that wants to
/// know rejected it at the manifest, by not declaring a `ty-table` field.

///|
/// The `col-type` tag as it is spelled on the wire, matching the host's JSON
/// Schema `colType` enum. Lowercase and short because this is the string a
/// person and a model both read.
pub fn col_type_tag(t : @tables.ColType) -> String {
  match t {
    I32 => "i32"
    F64 => "f64"
    STR => "str"
    BOOL => "bool"
  }
}

///|
/// The reverse. None for anything else — an unknown tag is not a guess.
pub fn col_type_of_tag(s : String) -> @tables.ColType? {
  match s {
    "i32" => Some(I32)
    "f64" => Some(F64)
    "str" => Some(STR)
    "bool" => Some(BOOL)
    _ => None
  }
}

///|
/// How many values a column holds, whatever it holds.
pub fn col_values_len(v : @tables.ColValues) -> Int {
  match v {
    I32s(a) => a.length()
    F64s(a) => a.length()
    Strs(a) => a.length()
    Bools(a) => a.length()
  }
}

///|
/// One column's values as a wire list, with the sparse `nulls` list folded back
/// into inline `nil`s. An index in `nulls` that is out of range is ignored
/// rather than trapping: this is an encoder, and a guest that built a bad
/// column should see it in the rendering, not in a crash.
fn col_values_to_value(
  values : @tables.ColValues,
  nulls : FixedArray[UInt],
) -> @values.Value {
  let missing : Map[Int, Bool] = Map([])
  for n in nulls {
    missing[n.reinterpret_as_int()] = true
  }
  let h = @values.list_new()
  let push = (i : Int, v : @values.Value) => {
    if missing.get(i) is Some(_) {
      @values.list_push(h, Nil)
    } else {
      @values.list_push(h, v)
    }
  }
  match values {
    I32s(a) =>
      for i, x in a {
        push(i, Number(x.to_double()))
      }
    F64s(a) =>
      for i, x in a {
        push(i, Number(x))
      }
    Strs(a) =>
      for i, x in a {
        push(i, Text(x))
      }
    Bools(a) =>
      for i, x in a {
        push(i, Boolean(x))
      }
  }
  List(h)
}

///|
/// One column as `{id, label, type, values}` — the shape the host validates and
/// the JSON Schema describes. `nulls` is NOT a key: it has already been folded
/// into the values.
pub fn column_to_value(c : @tables.Column) -> @values.Value {
  let m = @values.map_new()
  @values.map_set(m, "id", Text(c.id))
  @values.map_set(m, "label", Text(c.label))
  @values.map_set(m, "type", Text(col_type_tag(col_values_type(c.values))))
  @values.map_set(m, "values", col_values_to_value(c.values, c.nulls))
  Map(m)
}

///|
/// Which `col-type` an arm is. The arm IS the type, which is the whole point of
/// the variant — this is just the projection back to the tag.
pub fn col_values_type(v : @tables.ColValues) -> @tables.ColType {
  match v {
    I32s(_) => I32
    F64s(_) => F64
    Strs(_) => STR
    Bools(_) => BOOL
  }
}

///|
/// A whole table as `{columns, rowCount}`.
pub fn table_to_value(t : @tables.Table) -> @values.Value {
  let cols = @values.list_new()
  for c in t.columns {
    @values.list_push(cols, column_to_value(c))
  }
  let m = @values.map_new()
  @values.map_set(m, "columns", List(cols))
  @values.map_set(m, "rowCount", Number(t.row_count.to_double()))
  Map(m)
}

///|
/// The wire list of a column's values, split into a typed array and the indices
/// that were `nil`. A value that is not what `tag` claims is treated as
/// missing — see the tolerance note at the top of this file.
fn col_values_of_value(
  tag : @tables.ColType,
  h : UInt64,
) -> (@tables.ColValues, FixedArray[UInt]) {
  let n = @values.list_len(h).reinterpret_as_int()
  let nulls : Array[UInt] = []
  // The zero of each type stands in at a missing index. It is never read —
  // `nulls` says so — but a column is a dense array and something has to be
  // there.
  let ints : Array[Int] = []
  let floats : Array[Double] = []
  let texts : Array[String] = []
  let bools : Array[Bool] = []
  for i in 0..<n {
    let v = @values.list_get(h, i.reinterpret_as_uint())
    let present = match (tag, v) {
      (I32, Number(x)) => {
        ints.push(x.to_int())
        true
      }
      (F64, Number(x)) => {
        floats.push(x)
        true
      }
      (STR, Text(s)) => {
        texts.push(s)
        true
      }
      (BOOL, Boolean(b)) => {
        bools.push(b)
        true
      }
      _ => {
        match tag {
          I32 => ints.push(0)
          F64 => floats.push(0.0)
          STR => texts.push("")
          BOOL => bools.push(false)
        }
        false
      }
    }
    if !present {
      nulls.push(i.reinterpret_as_uint())
    }
  }
  let out : @tables.ColValues = match tag {
    I32 => I32s(FixedArray::from_array(ints))
    F64 => F64s(FixedArray::from_array(floats))
    STR => Strs(texts)
    BOOL => Bools(bools)
  }
  (out, FixedArray::from_array(nulls))
}

///|
/// One column from `{id, label, type, values}`. None when the object is not a
/// column at all — a missing `type`, an unknown tag, or a `values` that is not
/// a list. Those are structural, and a structural failure is worth reporting
/// rather than smoothing over.
pub fn column_of_value(v : @values.Value) -> @tables.Column? {
  guard v is Map(m) else { return None }
  guard @values.map_get(m, "type") is Some(Text(tag)) else { return None }
  guard col_type_of_tag(tag) is Some(ty) else { return None }
  guard @values.map_get(m, "values") is Some(List(vh)) else { return None }
  let id = match @values.map_get(m, "id") {
    Some(Text(s)) => s
    _ => ""
  }
  let label = match @values.map_get(m, "label") {
    Some(Text(s)) => s
    _ => id
  }
  let (values, nulls) = col_values_of_value(ty, vh)
  Some({ id, label, values, nulls, })
}

///|
/// A whole table.
///
/// `row_count` is DERIVED from the first column rather than read from the wire,
/// even though the host puts one there. The count and the data cannot disagree
/// if only one of them is believed, and the data is the one that carries the
/// values. A column that disagrees with the first is dropped: the host already
/// refused ragged tables, so reaching here means something else built this one,
/// and a table whose columns are different lengths is not a table.
pub fn table_of_value(v : @values.Value) -> @tables.Table? {
  guard v is Map(m) else { return None }
  guard @values.map_get(m, "columns") is Some(List(h)) else { return None }
  let n = @values.list_len(h).reinterpret_as_int()
  let columns : Array[@tables.Column] = []
  let mut width = 0
  for i in 0..<n {
    let cv = @values.list_get(h, i.reinterpret_as_uint())
    guard column_of_value(cv) is Some(c) else { continue }
    let len = col_values_len(c.values)
    if columns.is_empty() {
      width = len
      columns.push(c)
    } else if len == width {
      columns.push(c)
    }
  }
  Some({ columns, row_count: width.reinterpret_as_uint(), })
}

///|
/// The empty table: no columns, no rows. What a `ty-table` field holds before
/// anything has been loaded into it.
pub fn table_empty() -> @tables.Table {
  { columns: [], row_count: 0, }
}

///|
/// One cell of one column, or `Blank` for a missing one and for any index past
/// the end. Out of range is `Blank` rather than a trap because a renderer walks
/// a table by index and a row count it computed a moment ago can be stale.
pub fn table_cell(t : @tables.Table, col : Int, row : Int) -> @tables.Cell {
  guard col >= 0 && col < t.columns.length() else { return Blank }
  let c = t.columns[col]
  for n in c.nulls {
    if n.reinterpret_as_int() == row {
      return Blank
    }
  }
  guard row >= 0 && row < col_values_len(c.values) else { return Blank }
  match c.values {
    I32s(a) => I32(a[row])
    F64s(a) => F64(a[row])
    Strs(a) => Str(a[row])
    Bools(a) => Bool(a[row])
  }
}

///|
/// A cell as the text a view puts in a `<td>`. `Blank` is the empty string
/// rather than "null": a gap in a table reads as a gap, and a component that
/// wants to say more about it can check for `Blank` itself.
pub fn cell_text(c : @tables.Cell) -> String {
  match c {
    I32(x) => x.to_string()
    F64(x) => x.to_string()
    Str(s) => s
    Bool(b) => if b { "true" } else { "false" }
    Blank => ""
  }
}

///|
/// The headers, in column order — a row's worth of identity with no data.
pub fn table_fields(t : @tables.Table) -> Array[@tables.FieldRef] {
  t.columns.map(c => {
    id: c.id,
    label: c.label,
    ty: col_values_type(c.values),
  })
}

///|
/// One row across every column, self-describing. Out-of-range rows answer with
/// all-`Blank` cells rather than None, so a caller iterating a stale count
/// renders empty instead of stopping.
pub fn table_row(t : @tables.Table, row : Int) -> @tables.Row {
  let cells : Array[@tables.Cell] = []
  for i in 0..<t.columns.length() {
    cells.push(table_cell(t, i, row))
  }
  { fields: table_fields(t), cells, index: row.reinterpret_as_uint(), }
}

// ── Commands ────────────────────────────────────────────────────────────────
//
// The `command` variant is a vocabulary, and a vocabulary nothing speaks is a
// vocabulary nobody can trust. This is the reference interpreter: total over
// every arm, pure (a command answers a NEW table), and refusing rather than
// repairing — a command that would leave columns of different lengths is an
// error, because a table that is not rectangular is not a table.

///|
/// The index of a column by id, or None. Commands address columns by id and
/// never by position, so this is the lookup every one of them starts with.
pub fn col_index(t : @tables.Table, id : String) -> Int? {
  for i, c in t.columns {
    if c.id == id {
      return Some(i)
    }
  }
  None
}

///|
/// A column rebuilt with its rows in `order` — a permutation given as the OLD
/// index each new row comes from. Sorting, deleting and inserting are all this
/// with a different order, so there is one place that has to get `nulls` right.
fn permute_column(c : @tables.Column, order : Array[Int]) -> @tables.Column {
  let was_null : Map[Int, Bool] = Map([])
  for n in c.nulls {
    was_null[n.reinterpret_as_int()] = true
  }
  let nulls : Array[UInt] = []
  for i, from in order {
    if was_null.get(from) is Some(_) {
      nulls.push(i.reinterpret_as_uint())
    }
  }
  let values : @tables.ColValues = match c.values {
    I32s(a) => I32s(FixedArray::from_array(order.map(i => a[i])))
    F64s(a) => F64s(FixedArray::from_array(order.map(i => a[i])))
    Strs(a) => Strs(order.map(i => a[i]))
    Bools(a) => Bools(order.map(i => a[i]))
  }
  { id: c.id, label: c.label, values, nulls: FixedArray::from_array(nulls), }
}

///|
/// Lexicographic string order, spelled out.
///
/// NOT `x < y`: MoonBit's `String::compare` orders by LENGTH first and only
/// then by content, so `<` would sort a column of cities as Lima, Oslo,
/// Athens, Berlin. That is a fine total order for a map key and a wrong one
/// for anything a person reads, and the difference is invisible until every
/// string in a column happens to be the same length.
fn str_cmp(a : String, b : String) -> Int {
  let x = a.to_array()
  let y = b.to_array()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] < y[i] {
      return -1
    }
    if x[i] > y[i] {
      return 1
    }
  }
  if x.length() < y.length() {
    -1
  } else if x.length() > y.length() {
    1
  } else {
    0
  }
}

///|
/// Order two cells of the same column. `Blank` sorts last in both directions —
/// missing is not "smallest", it is absent, and burying it is what a reader
/// wants either way. Booleans order false-then-true; anything mixed compares
/// equal, which only happens if a column was built by hand and lied.
fn cell_cmp(a : @tables.Cell, b : @tables.Cell) -> Int {
  match (a, b) {
    (Blank, Blank) => 0
    (Blank, _) => 1
    (_, Blank) => -1
    (I32(x), I32(y)) => if x < y { -1 } else if x > y { 1 } else { 0 }
    (F64(x), F64(y)) => if x < y { -1 } else if x > y { 1 } else { 0 }
    (Str(x), Str(y)) => str_cmp(x, y)
    (Bool(x), Bool(y)) => if x == y { 0 } else if y { -1 } else { 1 }
    _ => 0
  }
}

///|
/// The width every column of a well-formed table has.
pub fn table_width(t : @tables.Table) -> Int {
  if t.columns.is_empty() {
    0
  } else {
    col_values_len(t.columns[0].values)
  }
}

///|
/// A column holding `n` rows, all missing, of the given type. What a new column
/// starts as when the table already has rows — the alternative is inventing
/// zeroes, and a zero that means "nothing was supplied" is the bug this whole
/// design is trying to avoid.
fn blank_column(
  id : String,
  label : String,
  ty : @tables.ColType,
  n : Int,
) -> @tables.Column {
  let nulls : Array[UInt] = []
  for i in 0..<n {
    nulls.push(i.reinterpret_as_uint())
  }
  let values : @tables.ColValues = match ty {
    I32 => I32s(FixedArray::make(n, 0))
    F64 => F64s(FixedArray::make(n, 0.0))
    STR => Strs(Array::make(n, ""))
    BOOL => Bools(Array::make(n, false))
  }
  { id, label, values, nulls: FixedArray::from_array(nulls), }
}

///|
/// Set one cell, or answer None when the value does not match the column's
/// type. A cell of the wrong type is refused rather than coerced: the caller
/// knows what it meant and this does not.
fn set_one(c : @tables.Column, row : Int, v : @tables.Cell) -> @tables.Column? {
  guard row >= 0 && row < col_values_len(c.values) else { return None }
  let nulls : Array[UInt] = []
  for n in c.nulls {
    if n.reinterpret_as_int() != row {
      nulls.push(n)
    }
  }
  if v is Blank {
    nulls.push(row.reinterpret_as_uint())
  }
  let values : @tables.ColValues = match (c.values, v) {
    (I32s(a), I32(x)) => {
      let b = FixedArray::from_array(a.iter().to_array())
      b[row] = x
      I32s(b)
    }
    (F64s(a), F64(x)) => {
      let b = FixedArray::from_array(a.iter().to_array())
      b[row] = x
      F64s(b)
    }
    (Strs(a), Str(x)) => {
      let b = a.copy()
      b[row] = x
      Strs(b)
    }
    (Bools(a), Bool(x)) => {
      let b = a.copy()
      b[row] = x
      Bools(b)
    }
    // Blank leaves the stand-in value alone; `nulls` is what says it is absent.
    (_, Blank) => c.values
    _ => return None
  }
  Some({
    id: c.id,
    label: c.label,
    values,
    nulls: FixedArray::from_array(nulls),
  })
}

///|
/// Append one row's worth of cells to every column. The row must be as long as
/// `columns` and match their types, cell by cell.
fn append_one(t : @tables.Table, row : Array[@tables.Cell]) -> @tables.Table? {
  guard row.length() == t.columns.length() else { return None }
  let cols : Array[@tables.Column] = []
  for i, c in t.columns {
    let n = col_values_len(c.values)
    let grown : @tables.ColValues = match (c.values, row[i]) {
      (I32s(a), I32(x)) =>
        I32s(FixedArray::from_array(a.iter().to_array() + [x]))
      (F64s(a), F64(x)) =>
        F64s(FixedArray::from_array(a.iter().to_array() + [x]))
      (Strs(a), Str(x)) => Strs(a + [x])
      (Bools(a), Bool(x)) => Bools(a + [x])
      (I32s(a), Blank) =>
        I32s(FixedArray::from_array(a.iter().to_array() + [0]))
      (F64s(a), Blank) =>
        F64s(FixedArray::from_array(a.iter().to_array() + [0.0]))
      (Strs(a), Blank) => Strs(a + [""])
      (Bools(a), Blank) => Bools(a + [false])
      _ => return None
    }
    let nulls = c.nulls.iter().to_array()
    if row[i] is Blank {
      nulls.push(n.reinterpret_as_uint())
    }
    cols.push({
      id: c.id,
      label: c.label,
      values: grown,
      nulls: FixedArray::from_array(nulls),
    })
  }
  Some({ columns: cols, row_count: (table_width(t) + 1).reinterpret_as_uint(), })
}

///|
/// Apply one command, answering the successor table or the reason it was
/// refused. Pure: the argument is untouched, which is what lets a caller keep
/// the old one for an undo without copying anything itself.
pub fn apply_command(
  t : @tables.Table,
  c : @tables.Command,
) -> @tables.CommandResult {
  let width = table_width(t)
  match c {
    Load(next) => {
      // The one command that can be handed a malformed table, since it carries
      // one rather than deriving it.
      let w = table_width(next)
      for col in next.columns {
        if col_values_len(col.values) != w {
          return Err(
            WidthMismatch({
              expected: w.reinterpret_as_uint(),
              got: col_values_len(col.values).reinterpret_as_uint(),
            }),
          )
        }
      }
      Ok({ columns: next.columns, row_count: w.reinterpret_as_uint(), })
    }
    Clear =>
      Ok({
        columns: t.columns.map(col => {
          blank_column(col.id, col.label, col_values_type(col.values), 0)
        }),
        row_count: 0,
      })
    SortBy(s) => {
      guard col_index(t, s.column) is Some(ci) else {
        return Err(NoSuchColumn(s.column))
      }
      let order = Array::makei(width, i => i)
      // Sort the INDICES, then permute every column by the result — that is
      // what keeps a row together, and it is the whole reason a columnar table
      // sorts through one place instead of once per column.
      //
      // `descending` flips the comparison rather than reversing the array
      // afterwards. Reversing would drag the missing values to the FRONT, and
      // "sort descending" is not a statement about where the gaps go: they
      // stay last either way, which is what `cell_cmp` already says.
      order.sort_by((a, b) => {
        let ca = table_cell(t, ci, a)
        let cb = table_cell(t, ci, b)
        let cmp = cell_cmp(ca, cb)
        if s.descending && !(ca is Blank) && !(cb is Blank) {
          -cmp
        } else {
          cmp
        }
      })
      Ok({
        columns: t.columns.map(col => permute_column(col, order)),
        row_count: width.reinterpret_as_uint(),
      })
    }
    DeleteRows(rows) => {
      let drop : Map[Int, Bool] = Map([])
      for r in rows {
        let i = r.reinterpret_as_int()
        if i < 0 || i >= width {
          return Err(RowOutOfRange(r))
        }
        drop[i] = true
      }
      let order : Array[Int] = []
      for i in 0..<width {
        if drop.get(i) is None {
          order.push(i)
        }
      }
      Ok({
        columns: t.columns.map(col => permute_column(col, order)),
        row_count: order.length().reinterpret_as_uint(),
      })
    }
    SetCell(s) => {
      guard col_index(t, s.column) is Some(ci) else {
        return Err(NoSuchColumn(s.column))
      }
      let row = s.row.reinterpret_as_int()
      guard row >= 0 && row < width else { return Err(RowOutOfRange(s.row)) }
      guard set_one(t.columns[ci], row, s.value) is Some(updated) else {
        return Err(
          TypeMismatch({
            column: s.column,
            expected: col_values_type(t.columns[ci].values),
            got: cell_type(s.value),
          }),
        )
      }
      let cols = t.columns.copy()
      cols[ci] = updated
      Ok({ columns: cols, row_count: t.row_count, })
    }
    AppendRows(rows) => {
      let mut acc = t
      for row in rows {
        guard append_one(acc, row) is Some(next) else {
          return Err(
            WidthMismatch({
              expected: acc.columns.length().reinterpret_as_uint(),
              got: row.length().reinterpret_as_uint(),
            }),
          )
        }
        acc = next
      }
      Ok(acc)
    }
    InsertRows(ins) => {
      let at = ins.at.reinterpret_as_int()
      guard at >= 0 && at <= width else { return Err(RowOutOfRange(ins.at)) }
      // Appended, then rotated into place — one rectangular-preserving path
      // rather than a second one that has to get `nulls` right all over again.
      let mut acc = t
      for row in ins.rows {
        guard append_one(acc, row) is Some(next) else {
          return Err(
            WidthMismatch({
              expected: acc.columns.length().reinterpret_as_uint(),
              got: row.length().reinterpret_as_uint(),
            }),
          )
        }
        acc = next
      }
      let added = ins.rows.length()
      let order : Array[Int] = []
      for i in 0..<at {
        order.push(i)
      }
      for i in 0..<added {
        order.push(width + i)
      }
      for i in at..<width {
        order.push(i)
      }
      Ok({
        columns: acc.columns.map(col => permute_column(col, order)),
        row_count: order.length().reinterpret_as_uint(),
      })
    }
    AddColumn(a) => {
      if col_index(t, a.column.id) is Some(_) {
        return Err(DuplicateColumnId(a.column.id))
      }
      let n = col_values_len(a.column.values)
      // A new column must be as tall as the table it joins. An empty one is
      // the exception and means "all missing", which is a real intention.
      let joining = if t.columns.is_empty() || n == width {
        a.column
      } else if n == 0 {
        blank_column(
          a.column.id,
          a.column.label,
          col_values_type(a.column.values),
          width,
        )
      } else {
        return Err(
          WidthMismatch({
            expected: width.reinterpret_as_uint(),
            got: n.reinterpret_as_uint(),
          }),
        )
      }
      let at = a.at.reinterpret_as_int()
      let cols : Array[@tables.Column] = []
      for i in 0..<t.columns.length() {
        if i == at {
          cols.push(joining)
        }
        cols.push(t.columns[i])
      }
      if at >= t.columns.length() {
        cols.push(joining)
      }
      Ok({
        columns: cols,
        row_count: (if t.columns.is_empty() {
          col_values_len(joining.values)
        } else {
          width
        }).reinterpret_as_uint(),
      })
    }
    DropColumn(id) => {
      guard col_index(t, id) is Some(_) else { return Err(NoSuchColumn(id)) }
      let cols = t.columns.filter(col => col.id != id)
      Ok({
        columns: cols,
        row_count: (if cols.is_empty() { 0 } else { width }).reinterpret_as_uint(),
      })
    }
    RenameColumn(r) => {
      guard col_index(t, r.column) is Some(ci) else {
        return Err(NoSuchColumn(r.column))
      }
      let cols = t.columns.copy()
      let old = cols[ci]
      cols[ci] = {
        id: old.id,
        label: r.label,
        values: old.values,
        nulls: old.nulls,
      }
      Ok({ columns: cols, row_count: t.row_count, })
    }
    MoveColumn(m) => {
      guard col_index(t, m.column) is Some(ci) else {
        return Err(NoSuchColumn(m.column))
      }
      let to = m.to.reinterpret_as_int()
      guard to >= 0 && to < t.columns.length() else {
        return Err(NoSuchColumn(m.column))
      }
      let rest = t.columns.filter(col => col.id != m.column)
      let cols : Array[@tables.Column] = []
      for i in 0..<rest.length() {
        if i == to {
          cols.push(t.columns[ci])
        }
        cols.push(rest[i])
      }
      if to >= rest.length() {
        cols.push(t.columns[ci])
      }
      Ok({ columns: cols, row_count: t.row_count, })
    }
    RetypeColumn(r) => {
      guard col_index(t, r.column) is Some(ci) else {
        return Err(NoSuchColumn(r.column))
      }
      let old = t.columns[ci]
      // Values that do not convert become MISSING rather than wrong — the one
      // decision this command makes, and the reason it cannot fail.
      let nulls : Array[UInt] = []
      let ints : Array[Int] = []
      let floats : Array[Double] = []
      let texts : Array[String] = []
      let bools : Array[Bool] = []
      for i in 0..<width {
        let cell = table_cell(t, ci, i)
        let kept = match (r.ty, cell) {
          (I32, I32(x)) => {
            ints.push(x)
            true
          }
          (I32, F64(x)) =>
            if x == x.trunc() && x >= -2147483648.0 && x <= 2147483647.0 {
              ints.push(x.to_int())
              true
            } else {
              ints.push(0)
              false
            }
          (I32, Bool(b)) => {
            ints.push(if b { 1 } else { 0 })
            true
          }
          (F64, F64(x)) => {
            floats.push(x)
            true
          }
          (F64, I32(x)) => {
            floats.push(x.to_double())
            true
          }
          (STR, _) =>
            if cell is Blank {
              texts.push("")
              false
            } else {
              texts.push(cell_text(cell))
              true
            }
          (BOOL, Bool(b)) => {
            bools.push(b)
            true
          }
          (BOOL, I32(x)) => {
            bools.push(x != 0)
            true
          }
          _ => {
            match r.ty {
              I32 => ints.push(0)
              F64 => floats.push(0.0)
              STR => texts.push("")
              BOOL => bools.push(false)
            }
            false
          }
        }
        if !kept {
          nulls.push(i.reinterpret_as_uint())
        }
      }
      let values : @tables.ColValues = match r.ty {
        I32 => I32s(FixedArray::from_array(ints))
        F64 => F64s(FixedArray::from_array(floats))
        STR => Strs(texts)
        BOOL => Bools(bools)
      }
      let cols = t.columns.copy()
      cols[ci] = {
        id: old.id,
        label: old.label,
        values,
        nulls: FixedArray::from_array(nulls),
      }
      Ok({ columns: cols, row_count: t.row_count, })
    }
  }
}

///|
/// Which `col-type` a cell carries. `Blank` answers `STR`, which is a
/// convention and not a fact — it is only used to name the "got" half of a
/// type mismatch, and a blank never causes one.
pub fn cell_type(c : @tables.Cell) -> @tables.ColType {
  match c {
    I32(_) => I32
    F64(_) => F64
    Str(_) => STR
    Bool(_) => BOOL
    Blank => STR
  }
}
