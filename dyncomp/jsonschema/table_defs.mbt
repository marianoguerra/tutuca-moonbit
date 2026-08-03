///| The `$defs` for `tables.table` — the one named shape this projection can
/// describe in full.
///
/// Everywhere else a named type becomes `{"title": "card"}` and stops, because
/// the schema knows a record's NAME and not its fields. A table is standard:
/// the contract declares it, so the projection can state it, `coerce` can check
/// it, and a generator can be told exactly how to write one. That asymmetry is
/// the entire argument for having a standard table type at all.
///
/// Two things about the JSON spelling differ from the WIT, both deliberately
/// and both in the direction of whoever is writing the JSON:
///
///   - `type` sits BESIDE `values` here, where the WIT fuses them into one
///     variant arm. The arm makes a mismatch unrepresentable; the split makes
///     it discriminable, which is what a `oneOf` needs and what a generator
///     writes unprompted. Neither form can express the other's virtue.
///   - a missing value is inline `null`, where the WIT carries a sparse
///     `nulls` index list. A parallel index list is a second thing to keep
///     true, and asking a generator to keep it true is asking for bugs.
///
/// And one thing JSON Schema cannot say at all: that every column has the SAME
/// length. There is no cross-item length constraint in any draft. It is the
/// most likely mistake in a generated table, so it is `coerce`'s job, and it is
/// reported as a width mismatch naming both lengths rather than padded over.

///|
/// The `$defs` key a `TyTable` field points at.
pub let table_def : String = "table"

///|
/// The four types a column can hold, as JSON Schema type names paired with the
/// `col-type` tag that selects them. `i32` also carries its range, because a
/// number outside it is not an i32 and silently wrapping one is how a row
/// count becomes negative.
fn col_branches() -> Array[(String, Json)] {
  [
    (
      "i32",
      obj([
        ("type", Json::array([Json::string("integer"), Json::string("null")])),
        ("minimum", Json::number(-2147483648.0)),
        ("maximum", Json::number(2147483647.0)),
      ]),
    ),
    (
      "f64",
      obj([
        ("type", Json::array([Json::string("number"), Json::string("null")])),
      ]),
    ),
    (
      "str",
      obj([
        ("type", Json::array([Json::string("string"), Json::string("null")])),
      ]),
    ),
    (
      "bool",
      obj([
        ("type", Json::array([Json::string("boolean"), Json::string("null")])),
      ]),
    ),
  ]
}

///|
/// One `oneOf` branch: pin `type` to a tag with `const`, and constrain `values`
/// to what that tag admits. A branch says nothing about `id` or `label` — the
/// base object already required them, and repeating them in four places is four
/// places to disagree.
fn col_branch(tag : String, item : Json) -> Json {
  obj([
    (
      "properties",
      obj([
        ("type", obj([("const", Json::string(tag))])),
        ("values", obj([("type", Json::string("array")), ("items", item)])),
      ]),
    ),
  ])
}

///|
/// Install the table `$defs` — `colType`, `column` and `table` — and answer with
/// a `$ref` to the last. Idempotent like every other `Defs` filler: three
/// table-valued fields produce one set of entries.
fn Defs::table(self : Defs) -> Json {
  if !self.entries.contains(table_def) {
    let branches = col_branches()
    self.entries["colType"] = obj([
      ("enum", Json::array(branches.map(b => Json::string(b.0)))),
      (
        "description",
        Json::string(
          "What every value in the column is: a 32-bit integer, a float, a string, or a boolean.",
        ),
      ),
    ])
    self.entries["column"] = obj([
      ("title", Json::string("Column")),
      ("type", Json::string("object")),
      (
        "required",
        Json::array([
          Json::string("id"),
          Json::string("label"),
          Json::string("type"),
          Json::string("values"),
        ]),
      ),
      (
        "properties",
        obj([
          (
            "id",
            obj([
              ("type", Json::string("string")),
              ("pattern", Json::string("^[A-Za-z_][A-Za-z0-9_-]*$")),
              (
                "description",
                Json::string(
                  "Unique within the table, and stable: a column is addressed by id and never by position, so reordering does not break anything that named one.",
                ),
              ),
            ]),
          ),
          (
            "label",
            obj([
              ("type", Json::string("string")),
              (
                "description",
                Json::string(
                  "What the header shows. Free text, not an identifier.",
                ),
              ),
            ]),
          ),
          ("type", obj([("$ref", Json::string("#/$defs/colType"))])),
          (
            "values",
            obj([
              ("type", Json::string("array")),
              (
                "description",
                Json::string(
                  "This column's values, in row order, all of the declared type. Use null for a missing one. Every column in a table must have the SAME number of values.",
                ),
              ),
            ]),
          ),
        ]),
      ),
      ("oneOf", Json::array(branches.map(b => col_branch(b.0, b.1)))),
    ])
    self.entries[table_def] = obj([
      ("title", Json::string("Table")),
      (
        "description",
        Json::string(
          "Tabular data as typed columns of EQUAL length. Give each column a stable id, a human label, a type, and its values in row order; null marks a missing value. The number of rows is however many values each column has, so every column must have the same number of them.",
        ),
      ),
      ("type", Json::string("object")),
      ("required", Json::array([Json::string("columns")])),
      (
        "properties",
        obj([
          (
            "columns",
            obj([
              ("type", Json::string("array")),
              ("items", obj([("$ref", Json::string("#/$defs/column"))])),
              ("description", Json::string("The columns, left to right.")),
            ]),
          ),
        ]),
      ),
    ])
  }
  obj([("$ref", Json::string("#/$defs/\{table_def}"))])
}
