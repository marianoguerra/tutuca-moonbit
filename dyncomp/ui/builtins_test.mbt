///| The standard components as catalog entries.
///
/// The claim under test is that nothing downstream can tell them apart from a
/// loaded bundle's: the same search ranks them, the same projection generates
/// their form, and the same validator refuses their bad arguments — with the
/// same JSON Pointers in the same shape.

///|
/// One key of a JSON object, or None. The editor has its own copy of this and
/// keeps it private; a blackbox test cannot see it, and duplicating four lines
/// beats widening an API for a test's convenience.
fn json_at(j : Json, key : String) -> Json? {
  if j is Object(m) {
    m.get(key)
  } else {
    None
  }
}

///|
/// A catalog with the standard components in it, and one stub bundle beside
/// them.
fn mixed_catalog() -> @registry.Registry raise {
  let reg = catalog()
  let (comps, _) = @std.std_components()
  reg.set_builtins(builtin_descriptors(comps))
  reg
}

///|
test "the standard components are in the catalog, and lead it" {
  let reg = mixed_catalog()
  let names = reg.all().map(d => d.ref_.to_id())
  // Builtins first: an empty query is what a command bar opens with, and a
  // catalog with no bundles loaded is still one you can build a page out of.
  @debug.assert_eq(names[0], "std/Universal")
  assert_true(names.contains("std/Grid"))
  assert_true(names.contains("std/Textarea"))
  // ...and the loaded bundle is still there, after them.
  assert_true(names.contains("counterlib/Counter"))
}

///|
test "a search ranks a standard component and a loaded one together" {
  let reg = mixed_catalog()
  let hits = reg.search("grid")
  @debug.assert_eq(hits[0].descriptor.ref_.to_id(), "std/Grid")
  // And it says why, exactly as it does for a guest — a ranking a person
  // cannot explain is one they stop trusting, whoever wrote the component.
  assert_true(hits[0].why.length() > 0)
}

///|
test "the standard components survive a bundle arriving and leaving" {
  let reg = mixed_catalog()
  let before = reg.all().length()
  reg.forget("counterlib")
  // The bundle's components are gone; ours are not. `forget` only touches
  // loaded modules, and a page that could lose its `+` to a dropped file is a
  // page that can be taken away.
  assert_true(reg.all().length() < before)
  assert_true(reg.describe({ module_: "std", name: "Universal", }) is Some(_))
  assert_true(reg.describe({ module_: "counterlib", name: "Counter", }) is None)
}

///|
test "a standard component projects a schema the generated form can draw" {
  let reg = mixed_catalog()
  guard! reg.describe({ module_: "std", name: "Grid", }) is Some(d)
  let schema = d.args_schema()
  guard! json_at(schema, "properties") is Some(props)
  guard! json_at(props, "cols") is Some(cols)
  // The half a TYPE cannot state, and the half a form needs: a range and a
  // starting value. `s32` says none of it.
  @debug.assert_eq(json_at(cols, "minimum"), Some(Json::number(1)))
  @debug.assert_eq(json_at(cols, "maximum"), Some(Json::number(12)))
  @debug.assert_eq(json_at(cols, "default"), Some(Json::number(2)))
  @debug.assert_eq(
    json_at(cols, "description"),
    Some(Json::string("How many columns.")),
  )
}

///|
test "a choice field projects the choices, so the form draws a select" {
  let reg = mixed_catalog()
  guard! reg.describe({ module_: "std", name: "Stack", }) is Some(d)
  guard! json_at(d.args_schema(), "properties") is Some(props)
  guard! json_at(props, "direction") is Some(dir)
  @debug.assert_eq(
    json_at(dir, "enum"),
    Some(
      Json::array([
        Json::string("column"),
        Json::string("row"),
        Json::string("column-reverse"),
        Json::string("row-reverse"),
      ]),
    ),
  )
  // Which is what the form generator reads to pick a `<select>` over a text
  // box — the same read it does for a guest's enum.
}

///|
test "a standard component's arguments are validated like any other" {
  let reg = mixed_catalog()
  guard! reg.describe({ module_: "std", name: "Grid", }) is Some(d)
  assert_true(d.coerce_args(Json::object({ "cols": Json::number(3) })) is Ok(_))
  // Refused, per field, with an RFC 6901 pointer — the same shape a guest's
  // bad argument comes back in, because it is the same validator.
  guard! d.coerce_args(Json::object({ "cols": Json::number(0) })) is Err(errors)
  @debug.assert_eq(errors[0].pointer, "/cols")
}

///|
test "a standard component offers its named fixtures like a guest does" {
  let reg = mixed_catalog()
  guard! reg.describe({ module_: "std", name: "Stack", }) is Some(d)
  @debug.assert_eq(d.inits.map(i => i.name), ["row", "column"])
  @debug.assert_eq(d.inits[0].args.get("direction"), Some(Str("row")))
}

///|
test "a container is configured by properties, never by typing in a child" {
  let reg = mixed_catalog()
  guard! reg.describe({ module_: "std", name: "Stack", }) is Some(d)
  guard! json_at(d.args_schema(), "properties") is Some(props)
  guard! props is Object(m)
  // `children` holds components, and the generated form's honest fallback for
  // a shape it has no control for is a JSON text box — which here would be
  // offering to type a component in. It is out of the DESCRIPTION and still in
  // the component: a container is FILLED by its `+` buttons.
  assert_false(m.contains("children"))
  assert_true(m.contains("gap"))
}
