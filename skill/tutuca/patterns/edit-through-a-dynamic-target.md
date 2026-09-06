# Edit through a dynamic target

**Problem:** render a value owned by a distant ancestor *and* let edits made in
the child land back on the owner — without forwarding events up by hand.

`workspace.html` — one view file, so one generated module for all three:

```tutu
spec:
  Workspace:
    field sheet :: Instance.of(Sheet)
    field bar :: Instance.of(Toolbar)

  Sheet:
    field text :: String

  Toolbar

view:
  Workspace:
    @div{@render(it.bar)}

  Sheet:
    @p{@(it.text)}

  Sheet.edit:
    @input(~class: "input", ~value: it.text, ~on_input: it.text := e.value)

  Toolbar:
    @render(dyn.active, ~as: "edit")
```

`workspace.mbt`:

```moonbit
///|
/// The producer exposes one of its fields as a dynamic. `provide` values must be
/// addressable, so a seq-access works too: `".items[.selectedKey]"`.
fn workspace_comp() -> @component.Component {
  workspace_component(provide={ "active": ".sheet" })
}

///|
/// A distant consumer names what it wants; the nearest rendered provider wins.
fn toolbar_comp() -> @component.Component {
  toolbar_component(lookup=[@component.lookup_name("active")])
}
```

Both calls are wiring — where a value comes from, not what a component does —
so they are `component()` arguments and no script block states them.

Because `*active` resolves to a value together with its real **path** (not a
copied value), rendering pushes that path as a continuation. The write the
input makes lands on `Workspace.sheet`; when bubbling reaches the top of
the resumed frame it returns directly to `Toolbar`, the visual caller. The
owner and any other view of the same value update in lock-step. A `provide` can
point at a seq-access (`.items[.selectedKey]`) to expose "the selected item".

Every component needs a `main` view even when you only ever render it `as="edit"`
— `gen` refuses a component without one. This is the **edit** counterpart
of [Share state across the tree](share-state-across-the-tree.md); the full
`provide`/`lookup` reference is in [advanced.md](../advanced.md#dynamic-bindings).
