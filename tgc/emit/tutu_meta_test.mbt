// What a component says about itself, and the fact that nothing renames it.

///|
/// `~category` and `~keywords` are SEARCH TEXT, not identifiers.
/// `compose/catalog`'s `search.mbt` lowercases the category and matches it
/// against what a person typed into a palette, so a spelling that survives the
/// printer is the whole requirement — spaces and capitals included, the way a
/// protocol id survives.
test "a .tutu card's category and keywords reach the manifest unrenamed" {
  let card =
    #|spec:
    #|  TextInput ~root:
    #|    ~category: "Form fields"
    #|    ~keywords: ["text", "input", "Single line"]
    #|    field value :: String
    #|
    #|view:
    #|  TextInput:
    #|    @output{@(it.value)}
  let out = @emit.compile(card, name="forms")
  let comp = component_in(out.manifest, "TextInput")
  // The space and the capital both survive: under identifiers this could not
  // have had a space at all.
  assert_eq(str_key(comp, "category"), "Form fields")
  assert_eq(strs_key(comp, "keywords"), ["text", "input", "Single line"])
}

///|
test "a component that says nothing says nothing, rather than guessing" {
  let card =
    #|spec:
    #|  Plain ~root:
    #|    field n :: Int
    #|
    #|view:
    #|  Plain:
    #|    @output{@(it.n)}
  let out = @emit.compile(card, name="plain")
  let comp = component_in(out.manifest, "Plain")
  assert_eq(str_key(comp, "category"), "")
  assert_eq(strs_key(comp, "keywords"), [])
}

///|
/// An `.html` card cannot set either and is not made to look as though it did.
/// For the whole migration window a host's annotation table is its only
/// channel, which is what makes the catalog's merge rule do real work from the
/// first converted card rather than being a formality.
test "an .html card carries the keys, empty" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Old { n: Int }
    #|</script>
    #|<template id="Old:main" data-root><output @text=".n"></output></template>
  let out = @emit.compile(card, name="old")
  let comp = component_in(out.manifest, "Old")
  assert_eq(str_key(comp, "category"), "")
  assert_eq(strs_key(comp, "keywords"), [])
}

///|
fn component_in(manifest : Json, name : String) -> Json {
  let missing : Json = Json::object(Map([]))
  guard manifest is Object(root) else { return missing }
  guard root.get("components") is Some(Array(comps)) else { return missing }
  for c in comps {
    if str_key(c, "name") == name {
      return c
    }
  }
  missing
}

///|
fn str_key(j : Json, key : String) -> String {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn strs_key(j : Json, key : String) -> Array[String] {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(Array(items)) => {
          let out = []
          for it in items {
            if it is String(s) {
              out.push(s)
            }
          }
          out
        }
        _ => []
      }
    _ => []
  }
}
