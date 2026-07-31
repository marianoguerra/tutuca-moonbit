///| The seven components, and the editor that owns the document.
///
/// Every leaf here is stateless in the sense that matters: a node renders what
/// it was given and raises what was clicked, a settings control edits nothing
/// and bubbles the property, a palette row knows only its own text. The
/// document is the editor's, and so is every decision about it.

///|
fn surface_node_comp() -> @component.Component {
  surface_node_component(update=(s, msg, ctx) => {
    match SurfaceNodeMsg::from_dispatch(msg) {
      // The badge is what selects, not the box: clicking a container to select
      // it would mean never being able to click through to a child.
      Some(Pick) => {
        SurfaceNodeBubble::NodePicked(s.nodeId).bubble(ctx)
        Some(s)
      }
      Some(Unknown(_, _)) | None => None
    }
  })
}

///|
fn node_settings_comp() -> @component.Component {
  node_settings_component(update=(_s, msg, ctx) => {
    // One bubble for fourteen controls. The editor decodes the pair against
    // the layout vocabulary, which is the only place that knows it — a panel
    // that parsed `1fr 2fr` itself would be a second answer to a question
    // `dyncomp/surface` has already answered.
    let changed = (prop : String, v : String) => {
      NodeSettingsBubble::PropChanged(prop, v).bubble(ctx)
      (None : NodeSettingsState?)
    }
    match NodeSettingsMsg::from_dispatch(msg) {
      Some(SetDirection(v)) => changed("direction", v)
      Some(SetJustify(v)) => changed("justify", v)
      Some(SetAlign(v)) => changed("align", v)
      Some(SetColumns(v)) => changed("columns", v)
      Some(SetGap(v)) => changed("gap", v)
      Some(SetPadding(v)) => changed("padding", v)
      Some(SetColSpan(v)) => changed("colSpan", v)
      Some(SetRowSpan(v)) => changed("rowSpan", v)
      Some(SetWrap(b)) => changed("wrap", if b { "true" } else { "false" })
      Some(Unknown(_, _)) | None => None
    }
  })
}

///|
fn palette_row_comp() -> @component.Component {
  palette_row_component(update=(s, msg, ctx) => {
    match PaletteRowMsg::from_dispatch(msg) {
      Some(Pick) => {
        PaletteRowBubble::ComponentPicked(s.module_, s.name).bubble(ctx)
        Some(s)
      }
      Some(Unknown(_, _)) | None => None
    }
  })
}

///|
fn component_palette_comp() -> @component.Component {
  component_palette_component(update=(s, msg, ctx) => {
    match ComponentPaletteMsg::from_dispatch(msg) {
      // The palette does not search — it cannot, since the catalog is the
      // editor's. It reports what was typed and gets new rows back.
      Some(SetQuery(q)) => {
        ctx.bubble("queryChanged", [Str(q)])
        Some({ ..s, query: q })
      }
      Some(Unknown(_, _)) | None => None
    }
  })
}

///|
/// A field writes its own control's value and says so.
///
/// Writing locally is what makes the control feel like a control (no round
/// trip through the editor per keystroke); the bubble is so the form can clear
/// a stale error the moment the thing it complained about changes.
fn schema_field_comp() -> @component.Component {
  schema_field_component(update=(s, msg, ctx) => {
    match SchemaFieldMsg::from_dispatch(msg) {
      Some(Edit(v)) => {
        SchemaFieldBubble::FieldEdited(s.name, v.to_display_string()).bubble(
          ctx,
        )
        Some(
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
      Some(Unknown(_, _)) | None => None
    }
  })
}

///|
fn schema_form_comp() -> @component.Component {
  schema_form_component(update=(s, msg, ctx) => {
    match SchemaFormMsg::from_dispatch(msg) {
      Some(Create) => {
        // The form does not build anything: it hands the editor what was
        // filled in, and the editor validates it against the schema and asks
        // the host for the instance.
        ctx.bubble("submitForm", [
          Str(s.module_),
          Str(s.name),
          Str(""),
          List(s.fields),
        ])
        return None
      }
      Some(UseInit(init)) => {
        ctx.bubble("submitForm", [
          Str(s.module_),
          Str(s.name),
          init,
          List(s.fields),
        ])
        return None
      }
      Some(Cancel) => {
        ctx.bubble("cancelForm", [])
        return None
      }
      Some(Unknown(_, _)) | None => ()
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
        return Some({ ..s, fields, error: general })
      }
      Some(Unknown(_, _)) | None => ()
    }
    match msg {
      Bubble("fieldEdited", _) => Some({ ..s, error: "" })
      _ => None
    }
  })
}
