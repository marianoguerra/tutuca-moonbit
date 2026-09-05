// Who wins when a card and its shipper both describe a component.
//
// The rule is: THE CARD, and the annotation only where the card said nothing.
// Not the other way round, which is the design that looks obvious — a shipper
// is closer to the palette and can annotate a card it cannot edit. It loses on
// staleness. A shipper annotates a component because the card was silent, so
// the row is stale the moment the card speaks; and across a version boundary a
// card ships new keywords while a v1 row keeps winning, with nothing anywhere
// saying the palette is describing a component that no longer exists.

///|
/// A component that describes ITSELF, as a `.tutu` card compiles to.
fn said(name : String, category : String, keywords : Array[String]) -> Json {
  Json::object({
    "name": Json::string(name),
    "doc": Json::string(""),
    "implements": Json::array([]),
    "fields": Json::array([]),
    "category": Json::string(category),
    "keywords": Json::array(keywords.map(Json::string)),
  })
}

///|
fn note(category : String, keywords : Array[String]) -> @catalog.Annotation {
  { category, keywords, presets: [], hidden: false, }
}

///|
test "the card's own words beat the shipper's" {
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [said("Box", "layout", ["flex", "row"])]),
    annotations={ "Box": note("widgets", ["legacy"]) },
  )
  assert_eq(entries[0].category, "layout")
  assert_eq(entries[0].keywords, ["flex", "row"])
}

///|
test "…and the shipper fills what the card left silent" {
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [said("Box", "", [])]),
    annotations={ "Box": note("widgets", ["legacy"]) },
  )
  assert_eq(entries[0].category, "widgets")
  assert_eq(entries[0].keywords, ["legacy"])
}

///|
test "the two fields are decided separately" {
  // A card that named a category and no keywords takes its own category and
  // the shipper's keywords. Per-field, because they are two answers.
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [said("Box", "layout", [])]),
    annotations={ "Box": note("widgets", ["legacy"]) },
  )
  assert_eq(entries[0].category, "layout")
  assert_eq(entries[0].keywords, ["legacy"])
}

///|
test "replacement, not union: a shipper's term does not survive alongside" {
  // A union would leave a shipper no way to REMOVE a term, and a word in a
  // palette that nothing explains is worse than a word that is missing.
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [said("Box", "layout", ["flex"])]),
    annotations={ "Box": note("", ["legacy"]) },
  )
  assert_eq(entries[0].keywords, ["flex"])
}

///|
test "a card that says nothing and has no annotation is still findable" {
  // The case every pasted card is in, and the reason neither channel is
  // required: name, doc and field names carry it.
  let entries = @catalog.entries_of_manifest(
    manifest("kit", [said("Box", "", [])]),
  )
  assert_eq(entries[0].category, "")
  assert_eq(entries[0].keywords, [])
  assert_eq(entries[0].ref_.name, "Box")
}
