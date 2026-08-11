///| Validating a table, which is the half a JSON Schema cannot do.
///
/// Every other named type reaches `coerce_ty` and is taken as it stands,
/// because the declared schema knows its name and not its fields. A table is
/// standard, so this checks it — and the check that matters is the one no draft
/// of JSON Schema can express: **every column must have the same number of
/// values**. There is no cross-item length constraint in the language. A
/// generator that writes four cities and three populations produces a document
/// that validates perfectly and is not a table.
///
/// So it is caught here, named as a width mismatch against the column that set
/// the width, and NOT repaired. Padding the short column with nulls or
/// truncating the long one would both invent data, and the caller — a person at
/// a form or a model that can write it again — is the one who knows which of
/// the two lists was wrong.

///|
/// The `col-type` tags. Same order as the schema's `colType` enum, because this
/// list is also what an error message offers.
let col_type_tags : Array[String] = ["i32", "f64", "str", "bool"]

///|
/// The keys a column object may carry. An unknown one is an error for the same
/// reason an undeclared argument is: it is a typo or a misunderstanding, and
/// silently dropping it means the value the caller wrote never arrives and
/// nothing says so.
let column_keys : Array[String] = ["id", "label", "type", "values"]

///|
/// The empty table: no columns, and therefore no rows.
fn empty_table() -> @tutuca.Value {
  Map({ "columns": List([]), "rowCount": Num(0.0) })
}

///|
/// One cell against its column's type.
///
/// `null` is legal in every column — it is a MISSING value, which is what the
/// WIT carries per column in `nulls` and what JSON spells inline. An i32 is
/// range-checked, because a number outside i32 is not an i32 and wrapping one
/// silently is how a count becomes negative three steps later.
fn coerce_cell(
  j : Json,
  tag : String,
  pointer : String,
  errors : Array[SchemaError],
) -> @tutuca.Value {
  match (tag, j) {
    (_, Null) => Null
    ("str", String(s)) => Str(s)
    ("bool", True) => Bool(true)
    ("bool", False) => Bool(false)
    ("f64", Number(n, ..)) => Num(n)
    ("i32", Number(n, ..)) => {
      if n.is_inf() ||
        n.is_nan() ||
        n < -9007199254740991.0 ||
        n > 9007199254740991.0 {
        // A JSON integer literal past 2^53 does not survive the parse — it
        // arrives already rounded, or, far enough out, as an infinity. Echoing
        // it back would print a number nobody wrote. This is the concrete shape
        // of why a column is `i32` and a big id is a `str`.
        errors.push(
          err(
            pointer, "not a safely represented integer — a value outside JSON's exact integer range belongs in a str column",
          ),
        )
      } else if n != n.trunc() {
        errors.push(err(pointer, "an i32 column holds whole numbers, got \{n}"))
      } else if n < -2147483648.0 || n > 2147483647.0 {
        errors.push(
          err(
            pointer,
            "\{n} is outside the range of an i32 (-2147483648 to 2147483647); a number this large belongs in a str column",
          ),
        )
      }
      Num(n)
    }
    _ => {
      errors.push(err(pointer, "expected \{tag} or null, got \{json_kind(j)}"))
      Null
    }
  }
}

///|
/// One column. Answers the decoded column and how many values it holds, so the
/// caller can compare that count across columns.
fn coerce_column(
  j : Json,
  pointer : String,
  seen : Map[String, Int],
  index : Int,
  errors : Array[SchemaError],
) -> (@tutuca.Value, Int) {
  guard j is Object(fields) else {
    errors.push(err(pointer, "expected a column object, got \{json_kind(j)}"))
    return (Map({}), 0)
  }
  for k, _ in fields {
    if !column_keys.contains(k) {
      errors.push(
        err(
          join(pointer, k),
          "no such column field (expected one of \{column_keys.join(", ")})",
        ),
      )
    }
  }

  // id: the one field other things NAME, so a duplicate is worse than a typo —
  // it makes every reference ambiguous.
  let id = match fields.get("id") {
    Some(String(s)) => {
      if s == "" {
        errors.push(err(join(pointer, "id"), "a column id cannot be empty"))
      } else if seen.get(s) is Some(first) {
        errors.push(
          err(
            join(pointer, "id"),
            "duplicate column id \{s}, already used by column \{first}",
          ),
        )
      } else {
        seen[s] = index
      }
      s
    }
    Some(other) => {
      errors.push(
        err(join(pointer, "id"), "expected a string, got \{json_kind(other)}"),
      )
      ""
    }
    None => {
      errors.push(err(join(pointer, "id"), "required"))
      ""
    }
  }
  let label = match fields.get("label") {
    Some(String(s)) => s
    Some(other) => {
      errors.push(
        err(
          join(pointer, "label"),
          "expected a string, got \{json_kind(other)}",
        ),
      )
      ""
    }
    None => {
      errors.push(err(join(pointer, "label"), "required"))
      ""
    }
  }
  let tag = match fields.get("type") {
    Some(String(s)) =>
      if col_type_tags.contains(s) {
        s
      } else {
        errors.push(
          err(
            join(pointer, "type"),
            "expected one of \{col_type_tags.join(", ")}, got \{s}",
          ),
        )
        ""
      }
    Some(other) => {
      errors.push(
        err(join(pointer, "type"), "expected a string, got \{json_kind(other)}"),
      )
      ""
    }
    None => {
      errors.push(err(join(pointer, "type"), "required"))
      ""
    }
  }

  // The values are still checked when the type was bad — one unusable `type`
  // should not hide a second mistake in the same column — but with no tag there
  // is nothing to check them against, so they are taken as they stand.
  let values : Array[@tutuca.Value] = []
  let vptr = join(pointer, "values")
  match fields.get("values") {
    Some(Array(items)) =>
      for i, item in items {
        if tag == "" {
          values.push(@tutuca.Value::from_json(item))
        } else {
          values.push(coerce_cell(item, tag, join(vptr, i.to_string()), errors))
        }
      }
    Some(other) =>
      errors.push(err(vptr, "expected an array, got \{json_kind(other)}"))
    None => errors.push(err(vptr, "required"))
  }
  let out : Map[String, @tutuca.Value] = Map([])
  out["id"] = Str(id)
  out["label"] = Str(label)
  out["type"] = Str(tag)
  out["values"] = List(values)
  (Map(out), values.length())
}

///|
/// A whole table.
///
/// Normalizes on the way through: the answer always carries `rowCount`, which
/// the JSON form deliberately does not ask for. A generator would get a count
/// wrong, and a count that disagrees with the data is worse than no count — so
/// it is derived here, once, from data that has just been checked. If the input
/// stated one anyway it is verified rather than ignored.
fn coerce_table(
  j : Json,
  pointer : String,
  errors : Array[SchemaError],
) -> @tutuca.Value {
  guard j is Object(fields) else {
    errors.push(
      err(
        pointer,
        "expected a table object with a \"columns\" array, got \{json_kind(j)}",
      ),
    )
    return empty_table()
  }
  for k, _ in fields {
    if k != "columns" && k != "rowCount" {
      errors.push(err(join(pointer, k), "no such field"))
    }
  }
  let cptr = join(pointer, "columns")
  let raw = match fields.get("columns") {
    Some(Array(items)) => items
    Some(other) => {
      errors.push(err(cptr, "expected an array, got \{json_kind(other)}"))
      return empty_table()
    }
    None => {
      errors.push(err(cptr, "required"))
      return empty_table()
    }
  }
  let seen : Map[String, Int] = Map([])
  let cols : Array[@tutuca.Value] = []
  // The first column sets the width and every later one is measured against it,
  // so the error names a concrete disagreement — "3 here, 5 there" — rather
  // than asserting a number nobody wrote down.
  let mut width = 0
  let mut width_from = ""
  for i, rc in raw {
    let cptr_i = join(cptr, i.to_string())
    let (col, n) = coerce_column(rc, cptr_i, seen, i, errors)
    if i == 0 {
      width = n
      width_from = match col {
        Map(m) =>
          match m.get("id") {
            Some(Str(s)) => s
            _ => "0"
          }
        _ => "0"
      }
    } else if n != width {
      errors.push(
        err(
          join(cptr_i, "values"),
          "\{n} values, but column \{width_from} has \{width} — every column in a table must have the same number",
        ),
      )
    }
    cols.push(col)
  }
  if fields.get("rowCount") is Some(stated) {
    match stated {
      Number(n, ..) =>
        if n != width.to_double() {
          errors.push(
            err(
              join(pointer, "rowCount"),
              "says \{n}, but the columns hold \{width}; leave it out and it is counted for you",
            ),
          )
        }
      other =>
        errors.push(
          err(
            join(pointer, "rowCount"),
            "expected a number, got \{json_kind(other)}",
          ),
        )
    }
  }
  let out : Map[String, @tutuca.Value] = Map([])
  out["columns"] = List(cols)
  out["rowCount"] = Num(width.to_double())
  Map(out)
}
