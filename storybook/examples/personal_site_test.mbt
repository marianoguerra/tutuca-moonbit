///|
test "personal-site: nothing until init, then the fixture loads and sorts" {
  let h = @harness.mount(personal_site_module(), "Root")
  inspect(h.find_all(".entry-row").length(), content="0")
  h.send_at_root("init")
  // 4 fixture entries; featured-first + newest-first is the default sort
  inspect(h.find_all(".entry-row").length(), content="4")
  debug_inspect(
    h.texts(".title"),
    content=(
      #|["Tutuca", "Talk on WASM", "MoonBit port", "Distributed thing"]
    ),
  )
}

///|
test "personal-site: the facets are the distinct categories and roles" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // categories, sorted and de-duped across entries
  debug_inspect(
    h.texts(".cat-btn"),
    content=(
      #|["Distributed Systems", "Programming Languages", "Web", "WebAssembly"]
    ),
  )
  debug_inspect(
    h.texts(".role-btn"),
    content=(
      #|["Author", "Maintainer", "Speaker"]
    ),
  )
  // everything starts selected -> every entry shows
  inspect(h.find_all(".entry-row").length(), content="4")
}

///|
test "personal-site: toggling a category off filters the entries" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // enrich composes the JS margaui classes + the `cat-btn on|off` hooks
  debug_inspect(
    h.attr(".cat-btn", "class", nth=0),
    content=(
      #|Some("btn btn-xs border-0 bg-indigo-700 text-white cat-btn on")
    ),
  )
  // toggle "Distributed Systems" (index 0) OFF
  h.click(".cat-btn", nth=0)
  debug_inspect(
    h.attr(".cat-btn", "class", nth=0),
    content=(
      #|Some("btn btn-xs border-0 ring-1 ring-indigo-500 text-indigo-700 dark:text-indigo-300 cat-btn off")
    ),
  )
  // the Distributed thing entry (its only category) drops out
  inspect(h.find_all(".entry-row").length(), content="3")
  inspect(h.find_all(".title").filter(_t => true).length(), content="3")
}

///|
test "personal-site: alt-click inverse-solos a selected tag, then solos it" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // categories sorted: [Distributed Systems, Programming Languages, Web, WebAssembly]
  // Everything starts selected, so alt-clicking Web (index 2, already selected)
  // INVERSE-solos: select all EXCEPT Web.
  h.fire(".cat-btn", @render.DomEvent::new(name="click", alt=true), nth=2)
  debug_inspect(
    h.attr(".cat-btn", "class", nth=2),
    content=(
      #|Some("btn btn-xs border-0 ring-1 ring-cyan-500 text-cyan-700 dark:text-cyan-300 cat-btn off")
    ),
  )
  debug_inspect(
    h.attr(".cat-btn", "class", nth=0),
    content=(
      #|Some("btn btn-xs border-0 bg-indigo-700 text-white cat-btn on")
    ),
  )
  // alt-click Web again (now NOT selected): SOLO — select only Web.
  h.fire(".cat-btn", @render.DomEvent::new(name="click", alt=true), nth=2)
  debug_inspect(
    h.attr(".cat-btn", "class", nth=2),
    content=(
      #|Some("btn btn-xs border-0 bg-cyan-700 text-white cat-btn on")
    ),
  )
  debug_inspect(
    h.attr(".cat-btn", "class", nth=0),
    content=(
      #|Some("btn btn-xs border-0 ring-1 ring-indigo-500 text-indigo-700 dark:text-indigo-300 cat-btn off")
    ),
  )
  // only entries tagged Web remain: Tutuca and Talk on WASM
  debug_inspect(
    h.texts(".title"),
    content=(
      #|["Tutuca", "Talk on WASM"]
    ),
  )
}

///|
test "personal-site: sort toggles re-order the entries" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // default: featured first, newest first -> Tutuca(2024,feat), WASM(2021,feat), ...
  inspect(h.text(".title", nth=0), content="Tutuca")
  // turn OFF featured-first: pure newest-first by start year
  h.fire(".feat-first", @render.DomEvent::new(name="change", value=Bool(false)))
  debug_inspect(
    h.texts(".title"),
    content=(
      #|["MoonBit port", "Tutuca", "Talk on WASM", "Distributed thing"]
    ),
  )
  // oldest-first flips it
  h.fire(".sort-asc", @render.DomEvent::new(name="change", value=Bool(true)))
  debug_inspect(
    h.texts(".title"),
    content=(
      #|["Distributed thing", "Talk on WASM", "Tutuca", "MoonBit port"]
    ),
  )
}

///|
test "personal-site: Clear Filters appears only when a facet is deselected" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // all selected -> @show="$hasActiveFilters" is false
  inspect(h.find_all(".clear-filters").length(), content="0")
  h.click(".cat-btn", nth=0) // deselect one
  inspect(h.find_all(".clear-filters").length(), content="1")
  h.click(".clear-filters") // $clearFilters re-selects everything
  inspect(h.find_all(".clear-filters").length(), content="0")
  inspect(h.find_all(".entry-row").length(), content="4")
}

///|
test "personal-site: an Entry renders its year, role, categories and alt-urls" {
  let h = @harness.mount(personal_site_module(), "Root")
  h.send_at_root("init")
  // the first entry (Tutuca) is featured, 2024-2026, Author, 2 categories, 1 alt-url
  inspect(h.text(".years"), content="2024-2026")
  inspect(h.text(".role"), content="Author")
  // .cat spans across ALL entries, in row order; Tutuca's are sorted first
  debug_inspect(
    h.texts(".cat"),
    content=(
      #|[
      #|  "Programming Languages",
      #|  "Web",
      #|  "Web",
      #|  "WebAssembly",
      #|  "Programming Languages",
      #|  "Distributed Systems",
      #|]
    ),
  )
  inspect(h.find_all(".alt-url").length(), content="1")
}
