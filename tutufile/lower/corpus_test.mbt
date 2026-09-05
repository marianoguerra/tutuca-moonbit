// Constructs drawn from what the repo's 86 view files actually use, rather
// than from what a test author thinks of.
//
// The count beside each is how often the corpus uses it, because that is what
// decides which gap costs the most: `@loop-with` appears 28 times and had no
// test, and a two-name binder with an option — every tab strip there is — did
// not parse at all until a real file arrived carrying one.

///|
test "a macro call is an element call whose name the file declares" {
  // 3 in the corpus. Before this it printed as `<badge>`, an element nobody
  // has, which renders empty rather than refusing.
  let src =
    #|spec:
    #|  Page:
    #|    field status :: String
    #|
    #|view:
    #|  macro badge(~label: "New", ~kind: "info"):
    #|    @span(~class: @str{badge badge-@(kind)}){@(label)}
    #|
    #|  Page:
    #|    @div{
    #|      @badge()
    #|      @badge(~label: "Beta")
    #|      @badge(~label: it.status)
    #|    }
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("<template id=\"macro:badge\""))
  assert_true(out.text.contains("<x:badge></x:badge>"))
  // a literal passes as a static attribute; anything else is bound
  assert_true(out.text.contains("<x:badge label=\"Beta\"></x:badge>"))
  assert_true(out.text.contains("<x:badge :label=\".status\"></x:badge>"))
}

///|
test "the loop options the corpus leans on" {
  // `@loop-with` 28, `@when` 29, `@enrich-with` 38 — and all three on one
  // loop is the paginated, filtered, decorated list every table is.
  let src =
    #|spec:
    #|  Table:
    #|    field rows :: List.of(Any)
    #|    field query :: String
    #|
    #|logic:
    #|  Table:
    #|    pred matches(row, i): row.to_string().contains(it.query)
    #|    enrich decorate(row, i):
    #|      shown = row.to_string()
    #|
    #|view:
    #|  Table:
    #|    @tbody{
    #|      @each(row, i in it.rows, ~loop_with: page, ~when: matches,
    #|            ~enrich_with: decorate){
    #|        @tr{@td{@(shown)}}
    #|      }
    #|    }
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("@each=\".rows\""))
  assert_true(out.text.contains("@loop-with=\"page\""))
  assert_true(out.text.contains("@when=\"matches\""))
  assert_true(out.text.contains("@enrich-with=\"decorate\""))
  assert_true(out.text.contains("<x text=\"@shown\">"))
}

///|
test "the raw-content directives keep the names that warn about them" {
  // `@dangerouslysetinnerhtml` is the one construct whose value reaches the
  // DOM unparsed, and the only one whose name says so.
  let src =
    #|spec:
    #|  Post:
    #|    field body :: String
    #|    field notes :: String
    #|
    #|view:
    #|  Post:
    #|    @article{
    #|      @div(~inner_md: it.notes){}
    #|      @div(~dangerously_inner_html: it.body){}
    #|    }
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("@setinnermd=\".notes\""))
  assert_true(out.text.contains("@dangerouslysetinnerhtml=\".body\""))
}

///|
test "the domain vocabulary the corpus writes 110 times" {
  let src =
    #|spec:
    #|  Gallery:
    #|    field items :: List.of(String)
    #|    field entries :: Map.of(String, String)
    #|    field tags :: Set.of(String)
    #|    field current_index :: Int
    #|    field current_key :: String
    #|    field count :: Int
    #|    field level :: String
    #|    where it.current_index is_index_of it.items ~or_none
    #|    where it.current_key is_key_of it.entries
    #|    where it.count in_range(0, 100)
    #|    where it.level is_one_of ["debug", "info"]
    #|    where it.count >= 0
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(
    out.text.contains("where current_index is index of .items or none"),
  )
  assert_true(out.text.contains("where current_key is key of .entries"))
  assert_true(out.text.contains("where count between 0 and 100"))
  assert_true(out.text.contains("where level is one of ['debug', 'info']"))
  assert_true(out.text.contains("where count >= 0"))
}
