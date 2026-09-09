///|
pub fn document_workspace_module(
  later? : (() -> Unit) -> Unit = f => f(),
) -> @component.ModuleDef {
  let editor = document_editor_component()
  let make = (id : String, title : String) => {
    editor.make({
      "id": Str(id),
      "title": Str(title),
      "source": Str("# " + title),
      "saved_source": Str("# " + title),
      "view": Str("edit"),
    })
  }
  let initial = DocumentWorkspaceState::{
    documents: {
      "welcome": make("welcome", "Welcome"),
      "notes": make("notes", "Meeting notes"),
    },
    selected: "welcome",
  }
  let workspace = document_workspace_component(initial~, update=(
    _s,
    dispatch,
    _ctx,
  ) => {
    match dispatch {
      Receive("init", _) => Unchanged
      _ => Unhandled
    }
  })
  @component.ModuleDef::new(
    name="document-workspace",
    components=[workspace, editor],
    intents=demo_intents(later~),
    examples=[
      {
        component: "DocumentWorkspace",
        title: "Document workspace",
        args: Map([]),
        view: None,
      },
    ],
  )
}
