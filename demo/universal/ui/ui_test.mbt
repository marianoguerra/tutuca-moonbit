///| The two halves of a pick, driven with no page, no wasm and no catalog.
///
/// The kit is a loaded module and cannot be here, so the canvas in these tests
/// holds ordinary host components standing in for one. That is the right
/// substitution: everything under test is the SHELL's — where the click came
/// from, what the picker does with the keyboard, what the pump carries — and
/// none of it can tell what kind of thing is in the canvas, which is the
/// property the whole demo is built on.

///|
fn shell() -> @harness.Harness[@memdom.MemNode] raise {
  @harness.mount(@ui.module_def(), "Shell")
}

///|
test "the picker opens closed and shows what it was handed" {
  let h = shell()
  assert_eq(h.find_all("div.picker").length(), 0)
  h.send_at_root("openPicker")
  h.send_at_root("pickerHits", args=[
    List(
      @ui.picker_rows([
        {
          component: "Box",
          module_: "std",
          preset: "",
          summary: "A row.",
          why: "name",
        },
        {
          component: "Box",
          module_: "std",
          preset: "vbox",
          summary: "A column.",
          why: "name",
        },
      ]),
    ),
    Str(""),
  ])
  assert_eq(h.texts("span.row-name"), ["Box", "vbox"])
  assert_eq(h.texts("span.row-module"), ["std", "std"])
  // The reasons ride on the row. A ranking nobody can account for is one people
  // stop trusting.
  assert_eq(h.texts("span.row-why"), ["name", "name"])
}

///|
test "an empty result says which kind of empty it is" {
  // Four states, four sentences: a page with nothing loaded and a page where
  // nothing matched are different problems with different fixes.
  assert_eq(
    @ui.empty_message("", total=0),
    "nothing is loaded yet — load a card from the library below",
  )
  assert_eq(@ui.empty_message("", total=3), "nothing to place")
  assert_eq(@ui.empty_message("zzz", total=3), "nothing matches \"zzz\"")
  assert_eq(
    @ui.empty_message("zzz", total=3, offered=false),
    "this page cannot place components",
  )
}

///|
test "the cursor moves, clamps, and never wraps" {
  let h = shell()
  h.send_at_root("openPicker")
  let hits = @ui.picker_rows([
    { component: "A", module_: "m", preset: "", summary: "", why: "", },
    { component: "B", module_: "m", preset: "", summary: "", why: "", },
    { component: "C", module_: "m", preset: "", summary: "", why: "", },
  ])
  h.send_at_root("pickerHits", args=[List(hits), Str("")])
  // Which row the cursor is on, read off the state: the class is on the row and
  // the name is on a child, and a harness selector is one compound selector
  // with no descendant combinator.
  let selected = () => {
    match h.drive_value().field("picker").field("hits") {
      List(rows) =>
        rows
        .filter(r => r.field("selected") == Bool(true))
        .map(r => r.field("component"))
      _ => []
    }
  }
  assert_eq(selected(), [Str("A")])
  h.key_down("input.picker-query", "ArrowDown")
  assert_eq(selected(), [Str("B")])
  h.key_down("input.picker-query", "ArrowDown")
  h.key_down("input.picker-query", "ArrowDown")
  // Clamped: past the end is the end, not the beginning. Wrapping is how you
  // select the wrong thing while looking at the right one.
  assert_eq(selected(), [Str("C")])
  h.key_down("input.picker-query", "ArrowUp")
  h.key_down("input.picker-query", "ArrowUp")
  h.key_down("input.picker-query", "ArrowUp")
  assert_eq(selected(), [Str("A")])
}

///|
test "typing asks, and the pump carries the question out" {
  let h = shell()
  h.send_at_root("openPicker")
  h.type_into("input.picker-query", "grid")
  let root = h.drive_value()
  assert_eq(root.field("pending"), Str("search"))
  assert_eq(root.field("argument"), Str("grid"))
}

///|
test "picking closes the list first, then asks for it to be built" {
  let h = shell()
  h.send_at_root("openPicker")
  h.send_at_root("pickerHits", args=[
    List(
      @ui.picker_rows([
        {
          component: "Grid",
          module_: "std",
          preset: "2x2",
          summary: "",
          why: "",
        },
      ]),
    ),
    Str(""),
  ])
  h.click("div.picker-row")
  // CLOSED, unconditionally and before anything is built: a pick that cannot
  // be built must not leave the list open over a page nobody can reach.
  assert_eq(h.find_all("div.picker").length(), 0)
  let root = h.drive_value()
  assert_eq(root.field("pending"), Str("place"))
  assert_eq(root.field("argument"), Str("std Grid 2x2"))
}

///|
test "the three names of a pick survive one channel" {
  // Encoder and decoder are in one file for the only reason that matters.
  let (m, c, p) = @ui.pick_parts(@ui.pick_argument("std", "Box", "hbox"))
  assert_eq((m, c, p), ("std", "Box", "hbox"))
  let (m2, c2, p2) = @ui.pick_parts(@ui.pick_argument("std", "Text", ""))
  assert_eq((m2, c2, p2), ("std", "Text", ""))
}

///|
test "dismissing releases the cell; picking leaves it waiting" {
  let h = shell()
  // A cell is waiting.
  @ui.remember_cell({ frames: [], })
  assert_true(@ui.peek_cell() is Some(_))
  h.send_at_root("openPicker")
  h.key_down("input.picker-query", "Escape")
  // Escape is not a pick. One receive for both cost exactly the bug you would
  // expect: a pick closed the picker, closing it forgot the cell, and the built
  // component arrived with nowhere to go.
  assert_true(@ui.peek_cell() is None)
}

///|
test "a cell is filled once" {
  @ui.remember_cell({ frames: [], })
  assert_true(@ui.take_cell() is Some(_))
  // A path left behind after a place puts the NEXT pick in the same hole.
  assert_true(@ui.take_cell() is None)
  @ui.forget_cell()
}

///|
test "a path captured in a render is rewritten into a path into the state" {
  // THE ONE THAT MATTERS, and the one whose absence fails silently.
  //
  // A `+` inside a container is drawn by `render-each`, so the path the intent
  // carries describes WHERE THIS ITEM WAS DRAWN. Sending to that reaches
  // nothing — no error, no refusal, the component simply never hears it. The
  // two steps carry identical payloads, so the rewrite is exact.
  let drawn : @tutuca.DispatchPath = {
    frames: [
      {
        base: @tutuca.Path::new(),
        items: [
          Plain(
            step=EachRenderItStep(field="children", key=KInt(2)),
            origin=None,
          ),
        ],
        binds: [],
      },
    ],
  }
  @ui.remember_cell(drawn)
  let kept = @ui.take_cell().unwrap()
  let steps = kept.frames[0].items.map(i => {
    match i {
      Plain(step~, ..) => step
    }
  })
  assert_eq(steps, [SeqStep(field="children", key=KInt(2))])
}

///|
test "the whole page can be switched into editor mode and back" {
  let h = shell()
  assert_eq(h.drive_value().field("editView"), Str(""))
  assert_eq(h.text("button.act-edit"), "edit")
  h.click("button.act-edit")
  // The QUALIFIED role. A bare `editor` would resolve as a plain view name and
  // reach only components that happen to have called theirs that.
  assert_eq(
    h.drive_value().field("editView"),
    Str("tutuca.dev/universal/Editable@1::editor"),
  )
  assert_eq(h.text("button.act-edit"), "done")
  h.click("button.act-edit")
  assert_eq(h.drive_value().field("editView"), Str(""))
}

///|
test "the library offers rather than loads, and remembers what was ticked" {
  let h = shell()
  h.send_at_root("setLibrary", args=[
    List(
      @ui.library_rows([
        ("Counter.html", "cards/Counter.html"),
        ("Todos.html", "cards/Todos.html"),
      ]),
    ),
  ])
  assert_eq(h.texts("span.row-name"), ["Counter.html", "Todos.html"])
  // Nothing is loaded until somebody says so — the whole point of the section.
  assert_eq(h.find_all("span.row-loaded").length(), 0)
  h.check("input.row-chosen", true)
  let rows = match h.drive_value().field("library") {
    List(items) => items.map(r => r.field("chosen"))
    _ => []
  }
  assert_eq(rows, [Bool(true), Bool(false)])
  h.click("button.row-load")
  let root = h.drive_value()
  assert_eq(root.field("pending"), Str("load"))
  assert_eq(root.field("argument"), Str("cards/Counter.html"))
}

///|
test "a note is shown, and an error note is shown differently" {
  let h = shell()
  h.send_at_root("addNote", args=[Str("could not compile"), Str("error")])
  h.send_at_root("addNote", args=[Str("loaded std"), Str("")])
  assert_eq(h.texts("li.note"), ["could not compile", "loaded std"])
  assert_true(h.html().contains("bg-error/10"))
}

///|
/// The path round trip, which everything about placing rests on.
///
/// An intent carries WHERE IT CAME FROM, and the answer goes back there —
/// `ctx.target_path()` at the handler, `ctx.send_at_path` to reply. It is the
/// mechanism a `+` is filled by, and it fails SILENTLY when it is wrong: no
/// error, no refusal, the component simply never hears it. This is a row rather
/// than a hole because a hole is a loaded guest and this package has none —
/// but the mechanism is the same one, which is the point.
test "an answer finds its way back to the component that asked" {
  let h = shell()
  h.send_at_root("setLibrary", args=[
    List(
      @ui.library_rows([("A.html", "cards/A.html"), ("B.html", "cards/B.html")]),
    ),
  ])
  assert_eq(h.find_all("span.row-loaded").length(), 0)
  h.click("button.row-load", nth=1)
  // The SECOND row, and only it. A path that reached the first would be a path
  // that had lost which row asked.
  let loaded = match h.drive_value().field("library") {
    List(rows) => rows.map(r => r.field("loaded"))
    _ => []
  }
  assert_eq(loaded, [Bool(false), Bool(true)])
}
