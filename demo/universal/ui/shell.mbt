///|
/// How far the cursor may move, clamped rather than wrapped.
///
/// Wrapping past the end of a search result list is how you select the wrong
/// thing while looking at the right one.
fn moved(cursor : Int, by : Int, len : Int) -> Int {
  if len == 0 {
    return 0
  }
  let next = cursor + by
  if next < 0 {
    0
  } else if next >= len {
    len - 1
  } else {
    next
  }
}

///|
/// The components, built ONCE.
///
/// A `Component` carries an identity, and the renderer resolves a value's views
/// by looking that identity up in the app's registry. Calling the generated
/// constructor a second time makes a second component with a second identity —
/// so rows built from it render as nothing at all, silently, because the
/// registry has never heard of them.
let picker_row : @component.Component = picker_row_component()

///|
let card_row : @component.Component = card_row_component()

///|
let note : @component.Component = note_component()

///|
let picker : @component.Component = picker_comp_new()

///|
/// The palette, with the keyboard in MoonBit.
///
/// It is here and not in the script block for one reason: a view cannot index
/// into a list. Everything else about the picker is declarative.
fn picker_comp_new() -> @component.Component {
  component_picker_component(update=(s, msg, ctx) => {
    let with_cursor = cursor => {
      let hits = s.hits.mapi((i, row) => {
        row.call_field("setSelected", [Bool(i == cursor)])
      })
      (Next({ ..s, hits, cursor, }) : @component.Update[ComponentPickerState])
    }
    match ComponentPickerMsg::from_dispatch(msg) {
      // Refused by `gen`: `Array[Any]` does not fit `Array[Instance[PickerRow]]`
      // at the declared type, and the rows arrive already built.
      Some(SetHits(hits, message)) =>
        Next({ ..s, hits, cursor: 0, emptyMessage: message, })
      Some(SetCursor(at)) => with_cursor(at)
      Some(Navigate(key)) =>
        match key {
          "ArrowDown" => with_cursor(moved(s.cursor, 1, s.hits.length()))
          "ArrowUp" => with_cursor(moved(s.cursor, -1, s.hits.length()))
          "Escape" => {
            ctx.send("dismissed", [])
            Unchanged
          }
          "Enter" => {
            guard s.cursor >= 0 && s.cursor < s.hits.length() else {
              return Unchanged
            }
            let row = s.hits[s.cursor]
            ctx.intent(
              "componentPicked",
              [row.field("module"), row.field("component"), row.field("preset")],
              @tutuca.IntentOpts::new(route=[Dyn]),
            )
            Unchanged
          }
          // Every other key is the person typing, and typing is the input's.
          _ => Unhandled
        }
      _ => Unhandled
    }
  })
}

///|
/// A note, built here because `gen` cannot: `Note` is a component and a script
/// block has no way to say "one of those".
fn note_of(text : String, tone : String) -> @tutuca.Value {
  note.make({ "text": Str(text), "tone": Str(tone) })
}

///|
/// The page.
///
/// Four arms carry the whole interaction, and the split between them is the
/// split in what each side knows. The SHELL OUTSIDE knows where the `+` was —
/// it holds the dispatch path — and this knows what a component is, because
/// building one needs the registry. Neither tells the other; they hold the two
/// halves and meet at `placeBuilt`.
pub fn shell_comp() -> @component.Component {
  shell_component(initial={ ..ShellState::zero(), picker: picker_node(), }, update=(
    s,
    msg,
    ctx,
  ) => {
    match msg {
      // --- the picker, relayed down ---
      Receive("openPicker", _) => {
        ctx.at().field("picker").send("opened", [])
        Unchanged
      }
      Receive("pickerHits", args) => {
        ctx
        .at()
        .field("picker")
        .send("setHits", [
          args.get(0).unwrap_or(Null),
          args.get(1).unwrap_or(Str("")),
        ])
        Unchanged
      }

      // --- a `+` was clicked ---
      //
      // The cell that asked is remembered HERE, from the dispatch that is
      // carrying the question, because that is the only moment its path is in
      // hand. Answered immediately — the picker opens and the palette is asked
      // for — rather than leaving the card waiting on somebody choosing from a
      // list, which is a wait with no bound on it.
      Intent(name, _) if name == @catalog.holder_add_requested => {
        ctx.stop_propagation()
        remember_cell(ctx.target_path())
        ctx.at().field("picker").send("opened", [])
        Next({ ..s, pending: "search", argument: "", })
      }

      // --- what the picker asks, answered by the pump ---
      Intent("queryChanged", args) => {
        ctx.stop_propagation()
        Next({
          ..s,
          pending: "search",
          argument: match args.get(0) {
            Some(Str(q)) => q
            _ => ""
          },
        })
      }
      Intent("componentPicked", args) => {
        ctx.stop_propagation()
        let str_at = i => {
          match args.get(i) {
            Some(Str(x)) => x
            _ => ""
          }
        }
        // Closed FIRST and unconditionally. A pick that cannot be built must
        // not leave the list open over a page the person can no longer reach.
        ctx.at().field("picker").send("closed", [])
        Next({
          ..s,
          pending: "place",
          argument: pick_argument(str_at(0), str_at(1), str_at(2)),
        })
      }
      Intent("pickerClosed", _) => {
        ctx.stop_propagation()
        forget_cell()
        Unchanged
      }

      // --- the library ---
      Intent("loadOne", args) => {
        ctx.stop_propagation()
        // Marked from the row's OWN path, which is the same mechanism a `+`
        // uses to be filled: the intent carries where it came from, and the
        // answer goes back there. Compiling a card takes long enough to be
        // worth saying so, and it pins the path round trip where a test can
        // see it.
        ctx.send_at_path(ctx.target_path(), "setLoaded", [Bool(true)])
        Next({
          ..s,
          pending: "load",
          argument: match args.get(0) {
            Some(Str(p)) => p
            _ => ""
          },
        })
      }
      Intent("toggleChosen", args) => {
        ctx.stop_propagation()
        let path = match args.get(0) {
          Some(Str(p)) => p
          _ => ""
        }
        let on = match args.get(1) {
          Some(Bool(b)) => b
          _ => false
        }
        let library = s.library.map(row => {
          if row.field("path") is Str(p) && p == path {
            row.with_field("chosen", Bool(on))
          } else {
            row
          }
        })
        Next({ ..s, library, })
      }

      // --- what a container's own chrome asks ---
      //
      // The card raises rather than doing it, because a view cannot name a
      // qualified handler — so this is the other end, and it answers by
      // sending the protocol message back at the container that asked.
      Intent(name, args) if name == @catalog.container_insert_requested => {
        ctx.stop_propagation()
        let at = ctx.target_path()
        let i = match args.get(0) {
          Some(Num(n)) => n.to_int()
          _ => -1
        }
        if i < 0 {
          ctx.send_at_path(at, @catalog.container_append, [])
        } else {
          ctx.send_at_path(at, @catalog.container_insert_at, [
            Num(i.to_double()),
          ])
        }
        Unchanged
      }
      Intent(name, args) if name == @catalog.container_remove_requested => {
        ctx.stop_propagation()
        let at = ctx.target_path()
        ctx.send_at_path(at, @catalog.container_remove_at, [
          args.get(0).unwrap_or(Num(0)),
        ])
        Unchanged
      }

      // --- the answer coming back ---
      Receive("placeBuilt", args) => {
        let built = args.get(0).unwrap_or(Null)
        // No cell waiting means this is the whole arrangement — a restore, or
        // the first hole at boot — and the canvas is where it goes.
        guard take_cell() is Some(at) else {
          return Next({ ..s, canvas: built, status: "placed on the canvas", })
        }
        ctx.send_at_path(at, @catalog.holder_hold, [built])
        // `init`, if it declares one, and this is not optional politeness.
        //
        // A card may put its starting state in a `receive init` rather than in
        // its field defaults — `tutucard/examples/Counter.html` sets `step` to
        // 1 there — and a host that does not send it gets a component built
        // from the schema's ZEROS. That counter renders perfectly and adds zero
        // per click, which reads exactly like a dispatch that never arrived.
        // It cost an afternoon of looking for one.
        if args.get(2) is Some(Bool(true)) {
          ctx.send_at_path(at.concat([FieldStep("child")]), "init", [])
        }
        // Told AFTER it is holding, and told the hole rather than the thing in
        // it: `markEditable` is the holder's own message.
        if args.get(1) is Some(Bool(true)) {
          ctx.send_at_path(at, "markEditable", [Bool(true)])
        }
        Next({ ..s, status: "placed in the cell you clicked", })
      }
      Receive("addNote", args) => {
        let text = match args.get(0) {
          Some(Str(t)) => t
          _ => ""
        }
        let tone = match args.get(1) {
          Some(Str(t)) => t
          _ => ""
        }
        let notes = s.notes.copy()
        notes.push(note_of(text, tone))
        Next({ ..s, notes, })
      }
      Receive("clearNotes", _) => Next({ ..s, notes: [], })
      Receive("setLibrary", args) => {
        let rows = match args.get(0) {
          Some(List(items)) => items
          _ => []
        }
        Next({ ..s, library: rows, })
      }
      _ => Unhandled
    }
  })
}

///|
/// The picker, closed.
///
/// Built once and handed to the shell as its initial `picker`, because a
/// component made when it is first needed cannot animate in — and because
/// whether it is open, and what has been typed into it, are the PERSON's and
/// must survive anything the runtime pushes at the page.
pub fn picker_node() -> @tutuca.Value {
  picker.make({
    "query": Str(""),
    "hits": List([]),
    "cursor": Num(0),
    "open": Bool(false),
    "emptyMessage": Str(""),
  })
}

///|
/// The shell, built once, for the same reason the rows are.
let shell : @component.Component = shell_comp()

///|
/// Every component this page draws.
pub fn components() -> Array[@component.Component] {
  [shell, picker, picker_row, card_row, note]
}

///|
/// The page's root, as a value.
///
/// A value rather than a component name, because the app has to be built with
/// `App::new` over a scope the page ALSO registers loaded modules into. Going
/// through `from_module` would build a registry of its own, and a canvas
/// holding a component from a module that registry never heard of renders as
/// nothing at all — silently, because a view it cannot resolve is not an error.
pub fn root_value() -> @tutuca.Value {
  shell.make({ "picker": picker_node() })
}

///|
/// Every component this page draws, in one module.
///
/// For the headless tests, which mount through `@harness` and have no loaded
/// modules to share a scope with.
pub fn module_def() -> @component.ModuleDef {
  @component.ModuleDef::new(name="universal", components=components())
}
