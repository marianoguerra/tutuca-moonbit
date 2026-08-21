///| The page as a document: written out, read back, and rendered again.
///
/// The claim this file makes is the one the wasm shell's own codec could never
/// check, because it lived in a package `moon test` cannot reach: a page a
/// person built by clicking survives being saved and reopened, down to what is
/// typed in it.
///
/// It also pins the two things that codec got wrong for the same reason —
/// deciding what a field held by LOOKING at it, at a moment when an empty one
/// holds nothing to look at.

///|
/// Mount the app AND keep the `UniversalUi` behind it, which is what a restore
/// needs: rebuilding a standard component by name is only something the thing
/// holding them can do.
fn mount_restorable(
  guest? : StubGuest,
) -> (@harness.MemHarness, UniversalUi, @component.ModuleDef) raise {
  let g = match guest {
    Some(x) => x
    None => StubGuest::new()
  }
  let live : Ref[@dyncomp.Bundle?] = { val: None }
  let reg = @registry.Registry::new()
  let (module_, ui) = seeded_app(reg, (ref_, init, args) => {
    guard live.val is Some(bundle) else { return None }
    let made = if init == "" {
      bundle.make_instance(ref_.name, args~)
    } else {
      bundle.make_init(ref_.name, init)
    }
    match made {
      Some(obj) => Some(obj.to_value())
      None => None
    }
  })
  let h = @harness.mount(module_, "UniversalApp")
  if guest is Some(_) {
    let bundle = @dyncomp.register_bundle(h.app.scope, g, stub_manifest())
    live.val = Some(bundle)
    reg.register(bundle)
  }
  (h, ui, module_)
}

///|
/// The tree under the app root, which is what a session writes out.
fn tree_of(h : @harness.MemHarness) -> @tutuca.Value {
  h.drive_value().field("root")
}

///|
test "a notepad survives being written out and read back" {
  let (h, ui, module_) = mount_restorable()
  // Exactly the notepad-by-composition sequence, built by clicking.
  h.click(".universal-add")
  pick(h, "Tabs")
  h.click(".universal-add")
  pick(h, "Textarea")
  h.type_into(".tut-textarea", "buy milk")
  h.click(".tab-add")
  h.click(".universal-add")
  pick(h, "Textarea")
  h.type_into(".tut-textarea", "call mum")
  h.click(".tab-label")
  @debug.assert_eq(h.value_of(".tut-textarea"), "buy milk")

  // Save, reopen.
  let doc = tree_of(h).to_component_json()
  let restored = ui.tree_of_json(doc)

  // The document is stable: encoding what came back produces the same text.
  @debug.assert_eq(restored.to_component_json().stringify(), doc.stringify())
  // Reopened, it is the same notepad: both tabs, the one that was open still
  // open, and what was typed in each still in it.
  let reopened = @harness.mount(module_, "UniversalApp", args={
    "root": restored,
  })
  @debug.assert_eq(reopened.texts(".tab-label"), ["tab 1", "tab 2"])
  @debug.assert_eq(reopened.value_of(".tut-textarea"), "buy milk")
  reopened.click(".tab-label", nth=1)
  @debug.assert_eq(reopened.value_of(".tut-textarea"), "call mum")
  // And it holds what was typed, in the tab it was typed in.
  @debug.assert_eq(
    restored
    .field("child")
    .field("tabs")
    .item(KInt(0))
    .field("body")
    .field("child")
    .field("text"),
    Str("buy milk"),
  )
  @debug.assert_eq(
    restored
    .field("child")
    .field("tabs")
    .item(KInt(1))
    .field("body")
    .field("child")
    .field("text"),
    Str("call mum"),
  )
}

///|
test "an empty cell stays empty — the case a value-inspecting codec cannot see" {
  let (h, ui, module_) = mount_restorable()
  h.click(".universal-add")
  pick(h, "Stack")
  // A fresh Stack has one empty cell, and nothing in it to recognize.
  let doc = tree_of(h).to_component_json()
  let restored = ui.tree_of_json(doc)
  guard restored.field("child").field("children") is List(cells) else {
    fail("the stack did not come back holding a list")
  }
  @debug.assert_eq(cells.length(), 1)
  @debug.assert_eq(cells[0].field("child"), Null)
  @debug.assert_eq(restored.to_component_json().stringify(), doc.stringify())
}

///|
test "a container emptied by hand does not grow a cell back" {
  let (_h, ui, _m) = mount_restorable()
  // `Std::build` fills `children` when the key is ABSENT, so a document that
  // says the list is empty has to keep saying so.
  let doc : Json = {
    "$component": "Universal",
    "child": { "$component": "Stack", "children": [], "gap": 2 },
  }
  let restored = ui.tree_of_json(doc)
  guard restored.field("child").field("children") is List(cells) else {
    fail("the stack did not come back holding a list")
  }
  @debug.assert_eq(cells.length(), 0)
  @debug.assert_eq(restored.field("child").field("gap"), Num(2))
}

///|
test "an unresolvable component leaves the rest of the page standing" {
  let (_h, ui, _m) = mount_restorable()
  let doc : Json = {
    "$component": "Universal",
    "child": {
      "$component": "Stack",
      "children": [
        {
          "$component": "Universal",
          "child": { "$component": "Text", "text": "kept", "size": "md" },
        },
        {
          "$component": "Universal",
          "child": { "$component": "Gone", "$module": "never/loaded" },
        },
      ],
      "direction": "col",
      "gap": 0,
      "padding": 0,
      "wrap": false,
      "justify": "start",
      "align": "stretch",
    },
  }
  let restored = ui.tree_of_json(doc)
  guard restored.field("child").field("children") is List(cells) else {
    fail("the stack did not come back holding a list")
  }
  @debug.assert_eq(cells.length(), 2)
  @debug.assert_eq(cells[0].field("child").field("text"), Str("kept"))
  // The cell is still a cell; it just holds nothing, which is what draws a `+`.
  @debug.assert_eq(cells[1].field("child"), Null)
}

///|
test "a loaded component is written as its identity and restored through the bridge" {
  let guest = StubGuest::new()
  let (h, ui, _m) = mount_restorable(guest~)
  h.click(".universal-add")
  pick(h, "Counter")
  h.type_into(".field-string", "tally")
  h.click(".form-create")
  @debug.assert_eq(h.text(".guest-count"), "0")
  let doc = tree_of(h).to_component_json()
  // The host walked into it, because this stub is not opaque to the codec —
  // what a real host does instead is answer `claim~`. Either way the document
  // names the module it came from once a `$module` is written, and the
  // instance comes back through `MakeInstance`.
  let restored = ui.tree_of_json(doc)
  @debug.assert_eq(restored.field("child").schema().unwrap().name, "Counter")
}
