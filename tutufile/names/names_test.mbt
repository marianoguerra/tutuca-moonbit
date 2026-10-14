///|
test "a camelCase name becomes snake_case" {
  inspect(@names.snake_of("loadRowsOk"), content="load_rows_ok")
  inspect(@names.snake_of("pokeAll"), content="poke_all")
  inspect(@names.snake_of("canSubmit"), content="can_submit")
  inspect(@names.snake_of("setAt"), content="set_at")
}

///|
test "a name already in the new spelling is its own answer" {
  inspect(@names.snake_of("count"), content="count")
  inspect(@names.snake_of("load_rows_ok"), content="load_rows_ok")
  inspect(
    @names.snake_of(@names.snake_of("loadRowsOk")),
    content="load_rows_ok",
  )
}

///|
/// A run of capitals breaks before the one that starts a word, not on every
/// letter — otherwise an acronym becomes one underscore per character.
test "a run of capitals breaks once" {
  inspect(@names.snake_of("parseHTMLDoc"), content="parse_html_doc")
  inspect(@names.snake_of("toJSON"), content="to_json")
  inspect(@names.snake_of("rowID"), content="row_id")
}

///|
test "a digit is a word boundary too" {
  inspect(@names.snake_of("row2Col"), content="row2_col")
}

///|
/// The one thing the rename must not touch.
test "a protocol member keeps the spelling the wire froze" {
  inspect(
    @names.rename_member("Container::appendCell"),
    content="Container::appendCell",
  )
  inspect(
    @names.rename_member("Container::cellField"),
    content="Container::cellField",
  )
  inspect(@names.rename_member("pokeAll"), content="poke_all")
}

///|
/// The two spellings of one operation answer the one the migration keeps.
test "a collection mutator has one spelling in the new notation" {
  inspect(@names.mutator_of("removeAt"), content="delete_at")
  inspect(@names.mutator_of("deleteAt"), content="delete_at")
  inspect(@names.mutator_of("remove_at"), content="delete_at")
  inspect(@names.mutator_of("insertAt"), content="insert_at")
  inspect(@names.mutator_of("push"), content="push")
  inspect(@names.mutator_of("toggle"), content="toggle")
}
