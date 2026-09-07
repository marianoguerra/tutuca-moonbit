# Tabbed interface

**Problem:** build tabs — a single `current_view` field decides which panel
shows, and the active tab button is highlighted.

`tabs.html`:

```tutu
spec:
  Tabs:
    field current_view :: String

view:
  Tabs:
    section():
      div(role: "tablist", class: "tabs"):
        button(role: "tab", class: if (it.current_view == "overview") | "tab tab-active" | "tab", ~on_click: it.current_view := "overview"):
          "Overview"
        " "
        button(role: "tab", class: if (it.current_view == "pricing") | "tab tab-active" | "tab", ~on_click: it.current_view := "pricing"):
          "Pricing"
      " "
      show((it.current_view == "overview")):
        div():
          "…overview…"
      " "
      show((it.current_view == "pricing")):
        div():
          "…pricing…"

fixtures:
  "fresh":
    it.current_view = "overview"
```

There is no `logic:` section and there are no handlers: each tab WRITES the field,
in the view, and a write needs nobody to answer it. The starting value is a
**named initial state** — a default is a value, so it goes in a block of its own
and the generator turns it into `TabsState::fresh()`.

`tabs.mbt` — all that is left is naming the fixture:

```moonbit
///|
fn tabs_comp() -> @component.Component {
  tabs_component(initial=TabsState::fresh())
}
```

One string field is the whole state machine. `it.current_view == "overview"`
drives both the panel's `show` and the active-tab class through a conditional
`~class`. A tab click writes the field with a string literal
(`~on_click: it.current_view := "pricing"`).

A field has ONE spelling — the one a view reads — so the `spec:` section
writes `current_view` and so does every read of it. The name is yours to pick
(`tab`, `current_view`, …).

This toggles **sibling panels** by predicate; to swap a *component's own*
rendered view instead, see [Switch between views](switch-between-views.md). The
same shape scales up to tabs over whole sub-apps — each panel a component
rendered with `render(it.field)`.
