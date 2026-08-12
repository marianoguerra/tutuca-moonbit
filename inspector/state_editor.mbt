// A form over any component's state, generated from its schema.
//
// No per-component code: the editor is handed an instance, asks it what fields
// it has (`obj_schema`), picks a control per declared kind, and writes an edit
// back through the mutator every field already gets (`setTitle`, `setCount`,
// …) — reached by name through the Obj trait, because there is no downcast to
// the concrete state type and none is needed.
//
// That is the whole feature, and none of it was expressible before: a `Value`
// could answer a NAMED field and nothing else, so a form over an unknown
// component had nothing to enumerate and nothing to type its controls with.
//
// What it does NOT do is write back into a running app's tree. The editor owns
// the instance it edits, which is what a storybook knob or a fixture builder
// wants; writing through to a mounted app needs the path the instance sits at,
// and that is the transactor's business rather than a form's.

///|
/// The control a declared kind gets. Three are editable and the rest render as
/// text — a list, a map or a child component is a tree, and a tree is the
/// inspector's job rather than a form's.
fn control_for(kind : @component.FieldKind) -> String {
  match kind {
    FBool => "bool"
    FInt | FFloat => "num"
    FText => "text"
    FList | FMap | FAny | FComp(..) | FSet | FOMap => "readonly"
  }
}

///|
/// `title` -> `setTitle`: the generated per-field mutator, by name.
///
/// The instance surfaces it through `obj_field` as a self-pre-bound `Fn`, so
/// calling it needs no downcast and no registry — just the field name the
/// schema already gave us.
fn setter_name(field : String) -> String {
  @tutuca.mutator_name("set", field)
}

///|
/// One row per declared field of `target`.
///
/// Empty when the instance declares nothing — a guest instance, an ad-hoc
/// `Obj` — which is the honest answer: there is no form to draw for fields
/// nobody named.
pub fn Inspector::editor_rows(
  self : Inspector,
  target : @tutuca.Value,
) -> Array[@tutuca.Value] {
  guard target.schema() is Some(schema) else { return [] }
  let rows : Array[@tutuca.Value] = []
  for f in schema.fields {
    let v = target.field(f.name)
    let kind = control_for(f.kind())
    rows.push(
      self.make_("StateEditorRow", args={
        "name": Str(f.name),
        // the WIT spelling, so the row says `list<card>` and not `list`
        "type": Str(f.ty.show_source()),
        "kind": Str(kind),
        "text": Str(v.str()),
        "num": Num(v.num()),
        "flag": Bool(v.bool()),
        "readonly": Str(v.to_json().stringify()),
        "editable": Bool(kind != "readonly"),
      }),
    )
  }
  rows
}

///|
/// A form over `target`, ready to render.
pub fn Inspector::edit_instance(
  self : Inspector,
  target : @tutuca.Value,
) -> @tutuca.Value {
  let name = match target.schema() {
    Some(s) => s.name
    None => ""
  }
  self.make_("StateEditor", args={
    "target": target,
    "rows": List(self.editor_rows(target)),
    "name": Str(name),
  })
}

///|
/// Coerce an edited control value to what the field DECLARES.
///
/// A number input hands back a `Num` and a checkbox a `Bool`, which already
/// match; the reason this exists is the text control, whose `String` is the
/// right answer for `FText` and the wrong one for everything else. The write
/// itself is coerced again against the component's declared field, so this is
/// about sending the right shape rather than about safety.
fn coerce_edit(kind : @component.FieldKind, v : @tutuca.Value) -> @tutuca.Value {
  match (kind, v) {
    (FInt, Str(s)) =>
      Num(@string.parse_double(s).to_int().to_double()) catch {
        _ => v
      }
    (FFloat, Str(s)) => Num(@string.parse_double(s)) catch { _ => v }
    (FInt, Num(n)) => Num(n.to_int().to_double())
    _ => v
  }
}

///|
fn state_editor_row_comp() -> @component.Component {
  state_editor_row_component(
    // A row holds no state of its own — it renders what it was given and
    // raises the edit at the editor that owns the instance. The bubble is not
    // declared in the state block because a two-payload variant case is not
    // WIT; `schema_viewer` takes the same escape for the same reason.
    update=(s, msg, ctx) => {
      match msg {
        Input("edit", [v]) => {
          ctx.bubble("onEdit", [Str(s.name), v])
          Unhandled
        }
        _ => Unhandled
      }
    },
  )
}

///|
/// Takes the registry rather than building one: `Inspector::new` is what
/// builds THIS component, so constructing an Inspector here would recurse.
/// The map is filled in after every component is built, and the handler below
/// only reads it at dispatch time — the `reg` pattern examples/json.mbt uses
/// for the same reason.
fn state_editor_comp(insp : Inspector) -> @component.Component {
  state_editor_component(update=(s, msg, _ctx) => {
    match msg {
      Bubble("onEdit", [Str(field), v]) => {
        // The declared kind decides what shape to send...
        guard s.target.field_info(field) is Some(info) else { return Unchanged }
        let next = s.target.call_field(setter_name(field), [
          coerce_edit(info.kind(), v),
        ])
        // ...and the mutator answers with the successor instance. A write
        // the component refused (a wrong shape, an unknown field) hands back
        // something that is not an instance, and nothing changes — `Unchanged`
        // rather than `Unhandled`, because this arm DID claim `onEdit`.
        guard next is Obj(_) else { return Unchanged }
        Next({ ..s, target: next, rows: insp.editor_rows(next) })
      }
      _ => Unhandled
    }
  })
}
