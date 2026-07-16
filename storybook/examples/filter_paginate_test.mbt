// All three strategies must produce the IDENTICAL visible result — they differ
// only in internal scanning. These tests assert that, and that filtering +
// paging + editing compose the way the example promises.

///|
test "filter-paginate: all three strategies render the same first page" {
  let h = @harness.mount_example(filter_paginate_module(), "Default")
  // 14 people, pageSize 5 -> first page is 5 rows, in each of the 3 sections
  inspect(h.find_all("section").length(), content="3")
  inspect(h.find_all("li").length(), content="15") // 5 per strategy
  // every pager reads the same label
  debug_inspect(
    h.texts(".pglabel"),
    content=(
      #|[
      #|  "Page 1 of 3 · 14 matches",
      #|  "Page 1 of 3 · 14 matches",
      #|  "Page 1 of 3 · 14 matches",
      #|]
    ),
  )
  // and the badges are the ORIGINAL indices 0..4, three times over
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|[
      #|  "0",
      #|  "1",
      #|  "2",
      #|  "3",
      #|  "4",
      #|  "0",
      #|  "1",
      #|  "2",
      #|  "3",
      #|  "4",
      #|  "0",
      #|  "1",
      #|  "2",
      #|  "3",
      #|  "4",
      #|]
    ),
  )
}

///|
test "filter-paginate: paging one strategy keeps ORIGINAL keys" {
  let h = @harness.mount_example(filter_paginate_module(), "Shared alone")
  inspect(h.text(".pglabel"), content="Page 1 of 3 · 14 matches")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["0", "1", "2", "3", "4"]
    ),
  )
  h.click(".next")
  inspect(h.text(".pglabel"), content="Page 2 of 3 · 14 matches")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["5", "6", "7", "8", "9"]
    ),
  )
  h.click(".next")
  inspect(h.text(".pglabel"), content="Page 3 of 3 · 14 matches")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["10", "11", "12", "13"]
    ),
  ) // short last page
  h.click(".next") // clamped
  inspect(h.text(".pglabel"), content="Page 3 of 3 · 14 matches")
}

///|
test "filter-paginate: filtering pages the MATCHES, not the raw list" {
  let h = @harness.mount_example(filter_paginate_module(), "Shared alone")
  h.type_into(".q", "nasa")
  // 2 of 14 match "nasa" (Margaret Hamilton, Katherine Johnson)
  inspect(h.text(".pglabel"), content="Page 1 of 1 · 2 matches")
  // and the badges are their ORIGINAL indices, not 0..1
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["6", "8"]
    ),
  )
}

///|
test "filter-paginate: searching resets to page 0 (never stranded)" {
  let h = @harness.mount_example(filter_paginate_module(), "Shared alone")
  h.click(".next")
  h.click(".next") // now on page 3
  inspect(h.text(".pglabel"), content="Page 3 of 3 · 14 matches")
  h.type_into(".q", "bell") // 2 matches -> 1 page; page must reset to 0
  inspect(h.text(".pglabel"), content="Page 1 of 1 · 2 matches")
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["12", "13"]
    ),
  )
}

///|
test "filter-paginate: the naive and coupled strategies agree with shared" {
  // drive all three at once via the Strategies root, then filter — the point of
  // the example is that the three internal approaches are indistinguishable
  let h = @harness.mount_example(filter_paginate_module(), "Default")
  h.type_into(".q", "nasa", nth=0) // naive
  h.type_into(".q", "nasa", nth=1) // shared
  h.type_into(".q", "nasa", nth=2) // coupled
  debug_inspect(
    h.texts(".pglabel"),
    content=(
      #|[
      #|  "Page 1 of 1 · 2 matches",
      #|  "Page 1 of 1 · 2 matches",
      #|  "Page 1 of 1 · 2 matches",
      #|]
    ),
  )
  debug_inspect(
    h.texts(".badge"),
    content=(
      #|["6", "8", "6", "8", "6", "8"]
    ),
  )
}

///|
test "filter-paginate: editing a row on a filtered page hits the right person" {
  let h = @harness.mount_example(filter_paginate_module(), "Shared alone")
  h.type_into(".q", "nasa")
  // each row is its own Person component: rename the second match (Katherine)
  h.type_into("input.name", "Katherine G. Johnson", nth=1)
  inspect(h.value_of("input.name", nth=1), content="Katherine G. Johnson")
  inspect(h.value_of("input.name", nth=0), content="Margaret Hamilton")
}
