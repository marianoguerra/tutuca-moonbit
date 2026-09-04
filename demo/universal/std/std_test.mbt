///|
/// The kit compiles, and it compiles clean.
///
/// A refusal here is not a warning: a component the compiler declined is a
/// component the palette will offer and the page cannot build.
test "the layout kit compiles with nothing refused" {
  let card = @std.compiled().unwrap()
  assert_eq(card.error, "")
  assert_true(card.wasm.length() > 1000, msg="\{card.wasm.length()} bytes")
  assert_eq(@std.module_name(), "std")
}

///|
/// What the SHELL needs to be true, asserted where a scene cannot reach.
///
/// A scene mounts `main` and reads fields; these are protocol claims, view
/// bindings and property declarations, and every one of them is a thing the
/// shell dispatches on. This is the test that would have caught the mismatch
/// hmtp shipped — a card whose script said `receive hold` where its spec said
/// `Holder::hold`, so the two halves agreed on a name the protocol never
/// mentions and the `+` did nothing from either side.
test "every component makes the claims the shell dispatches on" {
  let by_name : Map[String, @catalog.Entry] = Map([])
  for e in @std.entries() {
    by_name[e.ref_.name] = e
  }
  assert_eq(by_name.keys().to_array().length(), 7)

  // The holder, and the QUALIFIED names it answers and raises.
  let hole = by_name.get("Hole").unwrap()
  assert_true(hole.is_holder())
  assert_true(hole.messages.contains(@catalog.holder_hold))
  assert_true(hole.messages.contains(@catalog.holder_empty))
  // RAISED, not answered — the shell is the other end of it.
  assert_true(hole.expresses.contains(@catalog.holder_add_requested))
  // …and it is never offered, though it always resolves.
  assert_true(hole.hidden)

  // Every container, by the one fact a builder cannot infer.
  for name in ["Box", "Grid", "Tabs"] {
    let e = by_name.get(name).unwrap()
    assert_true(e.is_container(), msg="\{name} implements Container")
    assert_true(
      e.messages.contains(@catalog.container_append),
      msg="\{name} answers appendCell",
    )
    assert_true(
      e.messages.contains(@catalog.container_remove_at),
      msg="\{name} answers removeAt",
    )
    assert_true(
      e.messages.contains(@catalog.container_insert_at),
      msg="\{name} answers insertAt",
    )
    assert_true(
      e.properties.contains("cellField"),
      msg="\{name} says what its cells are called",
    )
  }

  // And every one of them draws its own settings, which is what lets the shell
  // have no form generator at all.
  for name in by_name.keys() {
    assert_true(
      by_name.get(name).unwrap().is_editable(),
      msg="\{name} implements Editable",
    )
  }
}

///|
/// The view role resolves to a LOCAL view, per component, and they differ.
///
/// One role and three answers is the point of a semantic role: a container's
/// editor still has to render its children or nested cells become unreachable,
/// and a leaf's is a form. A single shared view name could not say that.
test "the editor role binds a different local view per component" {
  let card = @std.compiled().unwrap()
  let bound : Array[String] = []
  guard card.manifest is Object(root) else { fail("no manifest") }
  guard root.get("components") is Some(Array(comps)) else {
    fail("no components")
  }
  for c in comps {
    guard c is Object(o) else { continue }
    let name = match o.get("name") {
      Some(String(s)) => s
      _ => ""
    }
    guard o.get("viewBindings") is Some(Array(bs)) else { continue }
    for b in bs {
      guard b is Object(bo) else { continue }
      let role = match bo.get("member") {
        Some(String(s)) => s
        _ => ""
      }
      let source = match bo.get("source") {
        Some(String(s)) => s
        _ => ""
      }
      if role == "editor" {
        bound.push("\{name}:\{source}")
      }
    }
  }
  assert_eq(bound, [
    "Hole:chrome", "Box:arrange", "Grid:arrange", "Tabs:arrange", "Text:configure",
    "Textarea:configure", "Markdown:configure",
  ])
}

///|
/// `vbox` and `hbox` are not components, and a person typing either finds one.
test "the palette offers presets as rows of their own" {
  let cat = @catalog.Catalog::new()
  cat.add(@std.entries())
  // FIRST, not only. "vbox" is also a keyword on the component the preset
  // configures, so `Box` and its sibling preset are legitimate answers — they
  // just are not the one that was asked for.
  assert_eq(cat.search("vbox")[0].label(), "vbox")
  assert_eq(cat.search("hbox")[0].label(), "hbox")
  assert_eq(cat.search("2x2")[0].label(), "2x2")
  // A preset carries the cell count the container is CONSTRUCTED with.
  let grid = cat.find("Grid").unwrap()
  assert_eq(grid.presets.map(p => "\{p.name}=\{p.cells}"), ["2x2=4", "3x3=9"])
}
