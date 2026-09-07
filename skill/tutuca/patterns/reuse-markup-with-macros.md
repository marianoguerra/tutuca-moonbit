# Reuse markup with macros

**Problem:** the same markup fragment repeats across a view and you want one
definition — but it has no state of its own.

```moonbit nocheck
// nocheck: ends in a bare `ModuleDef::new(...)` expression showing registration
fn badge_macro() -> @anode.Macro {
  {
    defaults: { "label": "'New'", "kind": "'info'" }, // defaults are *expressions*
    raw_view: "<span :class=\"$'badge badge-{^kind}'\" @text=\"^label\"></span>",
  }
}

fn card_macro() -> @anode.Macro {
  {
    defaults: { "title": "'Card'" },
    raw_view: "<div class=\"card\"><h2 @text=\"^title\"></h2><x:slot></x:slot></div>",
  }
}

// register on the ModuleDef
@component.ModuleDef::new(
  name="my-module",
  components=[...],
  macros={ "badge": badge_macro(), "card": card_macro() },
)
```

Or declare the same two in the `view:` section of the file that uses them:

```tutu
view:
  macro badge(~label: "New", ~kind: "info"):
    span(class: @str{badge badge-@(kind)}):
      @(label)

  macro card(~title: "Card"):
    div(class: "card"):
      h2():
        @(title)
      " "
      slot()

  Page:
    badge()
    badge(~label: "Sale")
    badge(~label: it.status)
    card(~title: "Hi"):
      p():
        "body"
```

Register from MoonBit when the macro is built by code; declare it in the file
when it is written by hand. Either way it is expanded at build time — there is
no state for a `logic:` section to be about.

A macro is pure template expansion — no fields, no handlers. Parameters are
read by their bare names; calls inside the body (`handler`, `it.field`)
resolve against the *host* component. A parameter carries a value, so a
handler name threads through: `@btn_rm(~handler: remove_in_items_at, ~arg:
key)` dispatches `remove_in_items_at(key)` inside the loop. `slot` (or
`slot("name")` for named slots) receives the caller's children. Registry
keys are lowercased. Full semantics (named slots, quoting of parameter values)
in [macros.md](../macros.md). For repeated markup that *does* need state, use
a child component instead (see the render-a-child-component recipe).
