///|
/// A manifest of the shape `tgc/emit` writes, small enough to read.
fn manifest(module_ : String, comps : Array[Json]) -> Json {
  Json::object({
    "moduleName": Json::string(module_),
    "doc": Json::string(""),
    "components": Json::array(comps),
  })
}

///|
fn comp(
  name : String,
  doc? : String = "",
  module_? : String = "",
  implements? : Array[String] = [],
  fields? : Array[String] = [],
) -> Json {
  let out : Map[String, Json] = {
    "name": Json::string(name),
    "doc": Json::string(doc),
    "implements": Json::array(implements.map(Json::string)),
    "fields": Json::array(
      fields.map(f => {
        Json::object({
          "name": Json::string(f),
          "ty": Json::object({ "k": Json::string("text") }),
        })
      }),
    ),
  }
  if module_ != "" {
    out["module"] = Json::string(module_)
  }
  Json::object(out)
}

///|
test "a manifest becomes palette rows, and a component says which module" {
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [
      comp("Box", doc="A row or a column.", module_="kit", implements=[
        @catalog.container_protocol,
      ]),
      // No `module` key: a manifest from before it existed falls back to the
      // one the manifest itself names, not to whoever happened to be reading.
      comp("Older"),
    ]),
  )
  assert_eq(entries.map(e => e.ref_.to_id()), ["kit/Box", "kit/Older"])
  assert_eq(entries[0].summary(), "A row or a column.")
  assert_true(entries[0].is_container())
  assert_true(!entries[1].is_container())
}

///|
test "a component's own module wins over the manifest around it" {
  // What a card holding another card's component produces: one manifest,
  // components from two places. Reading the module off the manifest alone is
  // how a foreign component gets filed under the wrong name.
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [comp("Note", module_="notes"), comp("Box")]),
  )
  assert_eq(entries.map(e => e.ref_.to_id()), ["notes/Note", "kit/Box"])
}

///|
test "a manifest it cannot read costs the rows it cannot read" {
  let entries = @catalog.entries_of_manifest(
    Json::object({
      "moduleName": Json::string("odd"),
      "components": Json::array([
        Json::string("this is not a component"),
        comp("Fine"),
      ]),
    }),
  )
  assert_eq(entries.map(e => e.ref_.name), ["Fine"])
}

///|
fn stocked() -> @catalog.Catalog {
  let cat = @catalog.Catalog::new()
  cat.add(
    @catalog.entries_of_manifest(
      manifest("kit", [
        comp("Hole", doc="A cell.", implements=[@catalog.holder_protocol]),
        comp("Box", doc="A row or a column.", fields=["direction"]),
        comp("Grid", doc="A uniform grid."),
      ]),
      annotations={
        "Hole": {
          keywords: ["cell"],
          category: "layout",
          presets: [],
          hidden: true,
        },
        "Box": {
          keywords: ["flex", "stack"],
          category: "layout",
          presets: [
            { name: "hbox", doc: "A row.", args: Map([]), cells: 2, },
            { name: "vbox", doc: "A column.", args: Map([]), cells: 2, },
          ],
          hidden: false,
        },
        "Grid": {
          keywords: ["matrix"],
          category: "layout",
          presets: [
            { name: "2x2", doc: "Four cells.", args: Map([]), cells: 4, },
          ],
          hidden: false,
        },
      },
    ),
  )
  cat
}

///|
test "an empty query is the palette opening: everything offerable, in order" {
  let hits = stocked().search("")
  // `Hole` is hidden and every preset is its own row.
  assert_eq(hits.map(h => h.label()), ["Box", "hbox", "vbox", "Grid", "2x2"])
}

///|
test "a preset ranks on its own name, and its component does not steal it" {
  let hits = stocked().search("vbox")
  assert_eq(hits.map(h => h.label()), ["vbox"])
  assert_eq(hits[0].entry.ref_.name, "Box")
  assert_eq(hits[0].summary(), "A column.")
  // …and the component's name finds every row it configures.
  assert_eq(stocked().search("box").map(h => h.label()), ["Box", "hbox", "vbox"])
}

///|
test "every hit can account for itself" {
  let hits = stocked().search("flex")
  // Three rows, because a keyword belongs to the COMPONENT and every preset is
  // a row of the component it configures.
  assert_eq(hits.map(h => h.label()), ["Box", "hbox", "vbox"])
  for hit in hits {
    assert_eq(hit.why, ["keyword \"flex\""])
  }
}

///|
test "every term has to land, or the row is not what was asked for" {
  // `Box` matches "box" and nothing matches "matrix" on it; `Grid` is the
  // reverse. Neither answers both, so neither is offered.
  assert_eq(stocked().search("box matrix").length(), 0)
}

///|
test "a hidden entry is not offered and is still resolvable" {
  let cat = stocked()
  assert_true(cat.search("hole").is_empty())
  assert_true(cat.find("Hole") is Some(_))
}

///|
test "adding a module again replaces its rows rather than doubling them" {
  let cat = stocked()
  let before = cat.all().length()
  cat.add(@catalog.entries_of_manifest(manifest("kit", [comp("Box")])))
  assert_eq(cat.all().map(e => e.ref_.name), ["Box"])
  assert_true(before > 1)
}

///|
test "registration order decides who owns a name" {
  let cat = stocked()
  cat.add(@catalog.entries_of_manifest(manifest("later", [comp("Box")])))
  // The kit registered first, so a saved arrangement naming `Box` still means
  // the kit's — which is the only reason restoring by name is safe at all.
  assert_eq(cat.find("Box").unwrap().ref_.module_, "kit")
  assert_eq(cat.find("Box", module_="later").unwrap().ref_.module_, "later")
}
