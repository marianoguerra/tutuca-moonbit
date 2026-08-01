///| The standard components, driven on the in-memory DOM.
///
/// Cells are told apart by what they HOLD — a `Text` with a distinct string —
/// so an assertion about the order of `.tut-text` is an assertion about cell
/// identity, not about how many there are. That is the difference that matters
/// for a container: growing a grid must not shuffle what a person already put
/// in it, and a count would not notice if it did.

///|
/// A universal already holding a text saying `what`.
fn filled(std : Std, what : String) -> @tutuca.Value {
  std.build("Universal", {
    "child": std.build("Text", { "text": Str(what), "size": Str("") }),
  })
}

// --- the universal ----------------------------------------------------------

///|
test "an empty universal is a plus, and holding something replaces it" {
  let (h, std) = mount_std(s => s.cell())
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  // No badge over an empty one: there is nothing to name.
  @debug.assert_eq(h.find_all(".universal-badge").length(), 0)
  h.send_at_root("setRoot", args=[filled(std, "hello")])
  @debug.assert_eq(h.find_all(".universal-add").length(), 0)
  @debug.assert_eq(h.text(".tut-text"), "hello")
  // The badge names what is held, read off its own declared schema — which is
  // the same question asked of a guest and of a standard component.
  @debug.assert_eq(h.text(".universal-badge"), "Text")
}

///|
test "emptying a universal gives the plus back rather than deleting a cell" {
  let (h, std) = mount_std(s => filled(s, "hello"))
  ignore(std)
  h.click(".universal-remove")
  @debug.assert_eq(h.find_all(".tut-text").length(), 0)
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
}

///|
test "view mode draws the content and none of the chrome" {
  let (h, std) = mount_std(s => filled(s, "hello"))
  ignore(std)
  h.send_at_root("setMode", args=[Str("main")])
  // Same content...
  @debug.assert_eq(h.text(".tut-text"), "hello")
  // ...and nothing to click. Edit mode is a VIEW, so a component that has no
  // edit view — every guest — is simply itself in both.
  @debug.assert_eq(h.find_all(".universal-badge").length(), 0)
  @debug.assert_eq(h.find_all(".universal-remove").length(), 0)
}

// --- the stack --------------------------------------------------------------

///|
fn stack_of(std : Std, whats : Array[String]) -> @tutuca.Value {
  std.build("Stack", {
    "children": List(whats.map(w => filled(std, w))),
    "direction": Str("column"),
    "justify": Str("start"),
    "align": Str("stretch"),
    "gap": Num(8.0),
    "padding": Num(0.0),
    "wrap": Bool(false),
  })
}

///|
test "a stack's phantom buttons insert before each cell and after the last" {
  let (h, _) = mount_std(s => stack_of(s, ["a", "b"]))
  // One leading strip per child, and one trailing strip for the container.
  @debug.assert_eq(h.find_all(".cell-before").length(), 2)
  @debug.assert_eq(h.find_all(".cell-append").length(), 1)
  // Before the first: the new cell goes to the top.
  h.click(".cell-before")
  @debug.assert_eq(h.texts(".tut-text"), ["a", "b"])
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  // Between: the strip on what is now the third child (b) inserts before it.
  h.click(".cell-before", nth=2)
  @debug.assert_eq(h.find_all(".universal-add").length(), 2)
  // After the last.
  h.click(".cell-append")
  @debug.assert_eq(h.find_all(".universal-add").length(), 3)
  // Through all of it, what was already placed kept its order.
  @debug.assert_eq(h.texts(".tut-text"), ["a", "b"])
}

///|
test "a stack's phantom buttons are transparent until hovered" {
  let (h, _) = mount_std(s => stack_of(s, ["a"]))
  // Asserting the mechanism rather than the appearance: `opacity-0` with a
  // `hover:` counterpart is what keeps them from obstructing the layout, and a
  // strip that lost it would obstruct it silently.
  guard h.attr(".cell-before", "class") is Some(cls)
  assert_true(cls.contains("opacity-0"))
  assert_true(cls.contains("hover:opacity-60"))
}

// --- the grid ---------------------------------------------------------------

///|
/// A 2×2 grid whose four cells hold "0".."3", in row-major order.
fn numbered_grid(std : Std) -> @tutuca.Value {
  std.build("Grid", {
    "children": List(["0", "1", "2", "3"].map(w => filled(std, w))),
    "cols": Num(2.0),
    "rows": Num(2.0),
    "gap": Num(8.0),
    "padding": Num(0.0),
  })
}

///|
test "a fresh grid has exactly cols times rows cells" {
  let (h, _) = mount_std(s => s.grid(cols=3, rows=2))
  @debug.assert_eq(h.find_all(".universal-add").length(), 6)
  @debug.assert_eq(h.find_all(".col-before").length(), 1)
  @debug.assert_eq(h.find_all(".row-after").length(), 1)
}

///|
test "growing a grid at the far edge leaves every cell where it was" {
  let (h, _) = mount_std(numbered_grid)
  h.click(".col-after")
  // 2×2 -> 3×2. Row-major with width 3: the new cells are at the end of each
  // row, so the old ones read 0,1 then 2,3 with a gap between.
  @debug.assert_eq(h.texts(".tut-text"), ["0", "1", "2", "3"])
  @debug.assert_eq(h.find_all(".universal-add").length(), 2)
  h.click(".row-after")
  // 3×2 -> 3×3: a whole new row of empties at the bottom.
  @debug.assert_eq(h.texts(".tut-text"), ["0", "1", "2", "3"])
  @debug.assert_eq(h.find_all(".universal-add").length(), 5)
}

///|
test "growing a grid at the near edge shifts what is there, and keeps it" {
  let (h, _) = mount_std(numbered_grid)
  h.click(".col-before")
  // 2×2 -> 3×2 with the new column FIRST. Every old cell moved one to the
  // right; none of them was rebuilt, which is what reading the same four
  // strings back proves.
  @debug.assert_eq(h.texts(".tut-text"), ["0", "1", "2", "3"])
  @debug.assert_eq(h.find_all(".universal-add").length(), 2)
  // Counting proves nothing about WHERE the new column went, so fill the first
  // empty cell and read the order back: "landed" first means the new column is
  // at the near edge and "0" moved right, which is the whole difference
  // between inserting before and appending.
  h.click(".universal-add")
  h.click(".place")
  @debug.assert_eq(h.texts(".tut-text"), ["landed", "0", "1", "2", "3"])
}

///|
test "resizing a grid keeps the cells that survive, by identity" {
  let (h, std) = mount_std(numbered_grid)
  ignore(h)
  // 2×2 -> 1×2 drops the right-hand column: "1" and "3" go, "0" and "2" stay
  // as the very same values rather than as fresh cells that happen to look
  // alike.
  let before = numbered_grid_state(std)
  let after = std.resize_grid(before, cols=1, rows=2)
  @debug.assert_eq(after.children.length(), 2)
  assert_true(physical_equal_value(after.children[0], before.children[0]))
  assert_true(physical_equal_value(after.children[1], before.children[2]))
}

///|
/// The same 2×2 as `numbered_grid`, as a `GridState` rather than an instance —
/// `resize_grid` is a function over the state, and driving it through the DOM
/// would test the settings panel that does not exist yet.
fn numbered_grid_state(std : Std) -> GridState {
  {
    ..GridState::zero(),
    children: ["0", "1", "2", "3"].map(w => filled(std, w)),
    cols: 2,
    rows: 2,
  }
}

///|
/// Two values that are the same instance. `Value` has structural `Eq`, and two
/// distinct cells holding equal text would pass that — which is exactly the
/// bug these tests are looking for.
fn physical_equal_value(a : @tutuca.Value, b : @tutuca.Value) -> Bool {
  match (a, b) {
    (Obj(x), Obj(y)) => physical_equal(x, y)
    _ => false
  }
}

// --- the tabs ---------------------------------------------------------------

///|
test "tabs show one page at a time and remember what is on the others" {
  let (h, std) = mount_std(s => s.tabs(count=1))
  // One tab, holding an empty universal: a fresh tab opens on a `+`, which is
  // what makes a tabbed thing composable rather than something to write.
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1"])
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  // Put something in it.
  h.send_at_root("setRoot", args=[
    std.build("Tabs", {
      "tabs": List([
        std.build("TabPage", {
          "label": Str("tab 1"),
          "body": filled(std, "first"),
        }),
        std.build("TabPage", { "label": Str("tab 2"), "body": std.cell() }),
      ]),
      "active": Num(0.0),
    }),
  ])
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2"])
  // Only the active page is on screen — one page, not two hidden behind CSS.
  @debug.assert_eq(h.texts(".tut-text"), ["first"])
  @debug.assert_eq(h.find_all(".tut-tabpage").length(), 1)
  h.click(".tab-label", nth=1)
  @debug.assert_eq(h.texts(".tut-text"), [])
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  // Back again: the first tab kept what was in it.
  h.click(".tab-label")
  @debug.assert_eq(h.texts(".tut-text"), ["first"])
}

///|
test "the active tab is the one that looks active" {
  let (h, _) = mount_std(s => s.tabs(count=2))
  guard h.attr(".tab-label", "class") is Some(first)
  guard h.attr(".tab-label", "class", nth=1) is Some(second)
  assert_true(first.contains("tab-active"))
  assert_false(second.contains("tab-active"))
  h.click(".tab-label", nth=1)
  guard h.attr(".tab-label", "class", nth=1) is Some(second_now)
  assert_true(second_now.contains("tab-active"))
}

///|
test "adding a tab opens it, and closing one falls back to its neighbour" {
  let (h, _) = mount_std(s => s.tabs(count=1))
  h.click(".tab-add")
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2"])
  // The new one is the one you are looking at — adding a tab you then have to
  // click is a step nobody wanted.
  guard h.attr(".tab-label", "class", nth=1) is Some(cls)
  assert_true(cls.contains("tab-active"))
  h.click(".tab-close")
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1"])
  // Closing the last one leaves no tabs and no page; the `+` is how you get
  // one back, which is why it is not hidden with the rest of the strip.
  h.click(".tab-close")
  @debug.assert_eq(h.texts(".tab-label"), [])
  @debug.assert_eq(h.find_all(".tut-tabpage").length(), 0)
  @debug.assert_eq(h.find_all(".tab-add").length(), 1)
}

// --- the leaves -------------------------------------------------------------

///|
test "a textarea edits through the mutator its declared field implies" {
  let (h, std) = mount_std(s => {
    s.build("Universal", {
      "child": s.build("Textarea", {
        "text": Str(""),
        "rows": Num(4.0),
        "placeholder": Str("type here…"),
      }),
    })
  })
  ignore(std)
  @debug.assert_eq(h.value_of(".tut-textarea"), "")
  h.type_into(".tut-textarea", "notes to self")
  @debug.assert_eq(h.value_of(".tut-textarea"), "notes to self")
  // No `update` arm answers `setText`: it is the mutator `text: string`
  // implies, and the framework serves it. The test is here because that is
  // easy to break by adding an `update` that swallows the name.
  @debug.assert_eq(h.attr(".tut-textarea", "rows"), Some("4"))
}

// --- edit mode reaches everywhere -------------------------------------------

///|
/// `@push-view` has to reach the BOTTOM of the tree, through every kind of
/// render on the way: a plain `<x render>`, a `render-each`, and a
/// `render-each` filtered by a `@when`. A mode that stops partway is worse
/// than no mode at all — the affordances it leaves behind are the ones a
/// person is trying to get away from.
test "view mode reaches a universal nested under a plain render" {
  let (h, std) = mount_std(s => {
    s.build("TabPage", { "label": Str("one"), "body": filled(s, "deep") })
  })
  ignore(std)
  @debug.assert_eq(h.find_all(".universal-badge").length(), 1)
  h.send_at_root("setMode", args=[Str("main")])
  @debug.assert_eq(h.find_all(".universal-badge").length(), 0)
}

///|
test "view mode reaches a universal nested under a filtered render-each" {
  let (h, std) = mount_std(s => {
    s.build("Tabs", {
      "tabs": List([std_page(s, "one", "deep")]),
      "active": Num(0.0),
    })
  })
  ignore(std)
  @debug.assert_eq(h.find_all(".universal-badge").length(), 1)
  h.send_at_root("setMode", args=[Str("main")])
  @debug.assert_eq(h.find_all(".universal-badge").length(), 0)
}

///|
/// A tab holding something, for the tests above.
fn std_page(std : Std, label : String, what : String) -> @tutuca.Value {
  std.build("TabPage", { "label": Str(label), "body": filled(std, what) })
}

///|
/// Ctrl/cmd-clicking a tab renames it in place.
///
/// The modifier means "configure this" everywhere else in the app, and a tab's
/// only configuration is its name — so it is the same gesture rather than a
/// second one to learn.
test "ctrl-clicking a tab renames it, and typing shows on the strip" {
  let (h, _) = mount_std(s => s.tabs(count=2))
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2"])
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  // A plain click just selects.
  h.click(".tab-label", nth=1)
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  // With the modifier it selects AND opens the box, on that tab only.
  h.fire(".tab-label", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  @debug.assert_eq(h.find_all(".tab-rename").length(), 1)
  @debug.assert_eq(h.texts(".tab-label"), ["tab 2"])
  @debug.assert_eq(h.value_of(".tab-rename"), "tab 1")
  // Typing writes straight through, so the strip renames as you type rather
  // than at the end.
  h.type_into(".tab-rename", "notes")
  @debug.assert_eq(h.value_of(".tab-rename"), "notes")
  h.key_down(".tab-rename", "Enter")
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  @debug.assert_eq(h.texts(".tab-label"), ["notes", "tab 2"])
}

///|
test "Escape puts the old tab name back" {
  let (h, _) = mount_std(s => s.tabs(count=1))
  h.fire(".tab-label", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  h.type_into(".tab-rename", "half-typed")
  h.key_down(".tab-rename", "Escape")
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1"])
}

///|
test "renaming ends when the box loses focus, and when the tabs change" {
  let (h, _) = mount_std(s => s.tabs(count=1))
  h.fire(".tab-label", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  h.type_into(".tab-rename", "kept")
  h.fire(".tab-rename", @render.DomEvent::new(name="focusout"))
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  // Clicking away commits rather than reverts: what is on screen is what you
  // typed, and throwing it away because you looked elsewhere would be a
  // surprise.
  @debug.assert_eq(h.texts(".tab-label"), ["kept"])
  // Adding a tab while renaming closes the box too — the new tab is the one
  // now open, so an editor still pointing at the old one has nothing to edit.
  h.fire(".tab-label", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  h.click(".tab-add")
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  @debug.assert_eq(h.texts(".tab-label"), ["kept", "tab 2"])
}

///|
test "the view mode strip cannot be renamed at all" {
  let (h, _) = mount_std(s => s.tabs(count=2))
  h.send_at_root("setMode", args=[Str("main")])
  // No box, and no modifier gesture to open one: renaming is an EDIT-mode
  // affordance, and `main` is what the finished page looks like.
  h.fire(".tab-label", @render.DomEvent::new(name="click", ctrl_or_cmd=true))
  @debug.assert_eq(h.find_all(".tab-rename").length(), 0)
  @debug.assert_eq(h.texts(".tab-label"), ["tab 1", "tab 2"])
}
