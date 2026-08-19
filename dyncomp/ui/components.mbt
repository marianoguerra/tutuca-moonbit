///| The app's chrome, and the app that owns it.
///
/// Every leaf here is stateless in the sense that matters: a row knows only
/// its own text, a field edits one control, a form hands back what was filled
/// in. What goes WHERE, and what a choice means, is the app's — because the
/// app is the only thing that can see both the catalog and the tree.

// --- the command bar --------------------------------------------------------

///|
fn palette_row_comp() -> @component.Component {
  palette_row_component(update=(s, msg, ctx) => {
    match PaletteRowMsg::from_dispatch(msg) {
      Some(Pick(configure)) => {
        PaletteRowIntent::ComponentPicked(s.module_, s.name, configure).dispatch(
          ctx,
        )
        Next(s)
      }
      Some(Unknown(_, _)) | None =>
        match PaletteRowReceive::from_dispatch(msg) {
          Some(SetSelected(selected)) => Next({ ..s, selected, })
          // The merged `Receive` now carries this component's own VIEW names as
          // well as the schema's, so `Unknown` no longer covers everything this
          // match has nothing to say about. They are answered by the Input match
          // beside this one, and task 19 folds the two into one.
          _ => Unhandled
        }
    }
  })
}

///|
/// The cursor, moved by `by` and clamped into what exists.
///
/// Clamping rather than wrapping: a list you can fall off the end of is one
/// you have to look at to use, and the whole point of the cursor is not
/// having to.
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
fn command_bar_comp() -> @component.Component {
  command_bar_component(update=(s, msg, ctx) => {
    // The cursor moves by telling two rows about it rather than by rebuilding
    // the list. That is not a micro-optimisation: rebuilding would replace the
    // `<input>` the person is typing in, and an arrow key that costs you the
    // focus is an arrow key nobody presses twice.
    let with_cursor = (cursor : Int) => {
      let hits = s.hits.mapi((i, r) => {
        r.call_field("setSelected", [Bool(i == cursor)])
      })
      (Next({ ..s, hits, cursor }) : @component.Update[CommandBarState])
    }
    match CommandBarMsg::from_dispatch(msg) {
      // The bar does not search — it cannot, since the catalog is the app's.
      // It reports what was typed and gets new rows back.
      Some(SetQuery(q)) => {
        ctx.intent(
          "queryChanged",
          [Str(q)],
          @tutuca.IntentOpts::new(route=[Dyn]),
        )
        Next({ ..s, query: q })
      }
      Some(Nav(key)) =>
        match key {
          "ArrowDown" => with_cursor(moved(s.cursor, 1, s.hits.length()))
          "ArrowUp" => with_cursor(moved(s.cursor, -1, s.hits.length()))
          "Escape" => {
            ctx.intent("commandClose", [], @tutuca.IntentOpts::new(route=[Dyn]))
            Unchanged
          }
          "Enter" => {
            guard s.cursor >= 0 && s.cursor < s.hits.length() else {
              return Unchanged
            }
            let row = s.hits[s.cursor]
            ctx.intent(
              "componentPicked",
              [row.field("module"), row.field("name"), Bool(s.configure)],
              @tutuca.IntentOpts::new(route=[Dyn]),
            )
            Unchanged
          }
          _ => Unhandled
        }
      // A click on the backdrop. It reaches here rather than being swallowed
      // by the panel because the panel is inside it, and a click inside the
      // panel stops at whatever it hit.
      Some(Close) => {
        ctx.intent("commandClose", [], @tutuca.IntentOpts::new(route=[Dyn]))
        Unchanged
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

// --- the generated form -----------------------------------------------------

///|
/// A field writes its own control's value and says so.
///
/// Writing locally is what makes the control feel like a control (no round
/// trip through the app per keystroke); the bubble is so the form can clear a
/// stale error the moment the thing it complained about changes.
fn schema_field_comp() -> @component.Component {
  schema_field_component(update=(s, msg, ctx) => {
    match SchemaFieldMsg::from_dispatch(msg) {
      Some(Edit(v)) => {
        SchemaFieldIntent::FieldEdited(s.name, v.to_display_string()).dispatch(
          ctx,
        )
        Next(
          match (s.kind, v) {
            ("bool", _) => { ..s, flag: v.is_truthy(), error: "" }
            // A number control still hands back text, and `text` is what
            // `form_args` reads: keeping one source per field is what stops a
            // half-typed "1." from becoming a 1.
            (_, Str(text)) => { ..s, text, error: "" }
            _ => { ..s, text: v.to_display_string(), error: "" }
          },
        )
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
fn schema_form_comp() -> @component.Component {
  schema_form_component(update=(s, msg, ctx) => {
    match SchemaFormMsg::from_dispatch(msg) {
      Some(Create) => {
        // The form does not build anything: it hands the app what was filled
        // in, and the app validates it against the schema and builds.
        ctx.intent(
          "submitForm",
          [Str(s.module_), Str(s.name), Str(""), List(s.fields)],
          @tutuca.IntentOpts::new(route=[Dyn]),
        )
        return Unchanged
      }
      Some(UseInit(init)) => {
        ctx.intent(
          "submitForm",
          [Str(s.module_), Str(s.name), init, List(s.fields)],
          @tutuca.IntentOpts::new(route=[Dyn]),
        )
        return Unchanged
      }
      Some(Cancel) => {
        ctx.intent("cancelForm", [], @tutuca.IntentOpts::new(route=[Dyn]))
        return Unchanged
      }
      // The merged `Receive` now carries this component's own VIEW names as
      // well as the schema's, so `Unknown` no longer covers everything this
      // match has nothing to say about. They are answered by the Input match
      // beside this one, and task 19 folds the two into one.
      _ => ()
    }
    match SchemaFormReceive::from_dispatch(msg) {
      // Errors arrive keyed by JSON Pointer (`/email`), because that is what
      // the schema layer produces and what every other layer here already
      // speaks. Stripping the leading slash is this component's whole share of
      // knowing about pointers.
      Some(ShowErrors(errors)) => {
        let by_field = errors.map()
        let fields = s.fields.map(f => {
          let name = f.field("name").str()
          let msg = by_field.get("/\{name}").unwrap_or(Str("")).str()
          f.call_field("setError", [Str(msg)])
        })
        let general = by_field.get("").unwrap_or(Str("")).str()
        return Next({ ..s, fields, error: general })
      }
      // The merged `Receive` now carries this component's own VIEW names as
      // well as the schema's, so `Unknown` no longer covers everything this
      // match has nothing to say about. They are answered by the Input match
      // beside this one, and task 19 folds the two into one.
      _ => ()
    }
    match msg {
      Intent("fieldEdited", _) => Next({ ..s, error: "" })
      _ => Unhandled
    }
  })
}

// --- the sidebar ------------------------------------------------------------

///|
fn config_panel_comp() -> @component.Component {
  config_panel_component(update=(_s, msg, ctx) => {
    match ConfigPanelMsg::from_dispatch(msg) {
      Some(Close) => {
        ConfigPanelIntent::CloseConfig.dispatch(ctx)
        Unchanged
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}
