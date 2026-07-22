# Edit through a dynamic target

**Problem:** render a value owned by a distant ancestor *and* let edits made in
the child land back on the owner — without forwarding events up by hand.

```moonbit
priv struct NoState {} derive(ToJson, FromJson)

// producer exposes a field (or a seq-access) as a dynamic
fn workspace_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=...),
  },
  name="Workspace",
  // renders .panel somewhere below
    init=NoState::{  },
  specs={
      "sheet": @component.FieldSpec::comp("Sheet"),
      "panel": @component.FieldSpec::comp("Panel"),
    },
  provide={ "active": ".sheet" },
  // or ".items[.selectedKey]",
)
}

// a distant consumer renders it as a target
fn toolbar_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view="<x render=\"*active\" as=\"edit\"></x>"),
  },
  name="Toolbar",
  init=NoState::{  },
  lookup={
      "active": { source: "Workspace.active", default: Some(".missing") },
    },
)
}
```

Because `*active` resolves to a real **path** (not a copied value), the event
fired inside the rendered child is *teleported*: the mutation skips the
intermediate components and lands on `Workspace.sheet`, so the owner and any
other view of the same value update in lock-step. A `provide` can even point at
a seq-access (`.items[.selectedKey]`) to expose "the selected item". This is
the **edit** counterpart of the share-state-across-the-tree recipe. Runnable
versions: `examples/dynamic.mbt` (dynamic-path) and
`examples/dynamic_selected_edit.mbt`.
