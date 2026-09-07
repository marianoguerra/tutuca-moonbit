# Tutuca — Macros

Macros are pure template expansion — no state, no handlers of their
own. Calls inside a macro resolve against the *host* component. Read this file
when authoring `@anode.Macro` values, `macro` declarations in a `view:`
section, or slots.

A macro is a plain struct: `defaults` maps parameter names to their
default **expressions** (source text, same grammar as attribute values),
`raw_view` is the template:

```moonbit
fn badge_macro() -> @anode.Macro {
  {
    defaults: { "label": "'New'", "kind": "'info'" }, // defaults are *expressions*
    raw_view: "<span :class=\"$'badge badge-{^kind}'\" @text=\"^label\"></span>",
  }
}
```

Register macros on the `ModuleDef`:

```moonbit nocheck
// nocheck: a fragment (a match arm or an expression), not a top-level item
@component.ModuleDef::new(
  name="my-module",
  components=[...],
  macros={ "badge": badge_macro() },
)
```

A macro is called the way any other form is — its name, and its arguments
by keyword:

```tutu
badge()                      // defaults
badge(~label: "Sale")        // a literal
badge(~label: it.status)     // a field reference
```

Inside the macro body a parameter is read by its bare name. An argument is a
value like any other — see *Quoting & String Literals* in
[core.md](./core.md) for the literal-vs-template rules.

A a macro parameter is a value like any other, so it also works inside a conditional
slot's expression — this is the `macro:row` idiom:

```tutu
view:
  macro row(~value: "", ~label: ""):
    hide(value.is_empty()):
      div(class: "row"):
        span(class: "k"):
          @(label)
        " "
        b(class: "v"):
          @(value)
```

It has to expand to a single token, which is already the rule everywhere `^` is
written. A `logic:` section cannot write a macro parameter at all:
a block is parsed once for the component rather than once per call site, so
there is no frame to substitute from — pass the value in as a handler argument
or read it as a field.

Macro params are substituted as **source text**, so a handler name or a
loop binding threads straight through — the `^handler ^arg` indirection:

```moonbit
fn btn_rm_macro() -> @anode.Macro {
  {
    defaults: { "handler": "onRemove", "arg": "event" },
    raw_view: "<button class=\"btn btn-error rm\" @on.click=\"^handler ^arg\">x</button>",
  }
}
```

```tutu
btn_rm(~handler: remove_in_items_at, ~arg: key)
```

> **Pass the handler name bare.** A macro declared in a view file is expanded
> by `gen`, which refuses a decorated name in an event position:
> *"in an event position a `name(…)` and a bare name are the SAME dispatch"*. A
> bare name works in a file macro and in an `@anode.Macro` value alike, and
> there is no case where a decoration buys anything in a handler.

If registering into a scope by hand (outside `ModuleDef::build_scope`),
use `ComponentStack::register_macros(macros)` **before**
`compile_all()` — views are compiled against the scope's macros.

Registry keys are lowercased on insert because the HTML parser already
lowercases `@Tag(…)` to `@tag(…)`. `"Card"` and `"card"` both register
under `card`.

## Slots

`slot` marks where a call's children go. Content written directly in the
call's body fills it:

```tutu
view:
  macro card(~title: "Card"):
    div(class: "card"):
      h2():
        @(title)
      " "
      slot()

  Page:
    card(~title: "Hi"):
      p():
        "body"
```

## Named slots

`slot("name")` declares a second place to put children, and `fill("name")`
at the call site says which content goes there. Everything not inside a
`fill` goes to the default slot:

```tutu
view:
  macro panel():
    div():
      header():
        slot("actions")
      main():
        slot()
      footer():
        slot("footer")

  Page:
    panel():
      fill("actions"):
        button(~on_click: inc):
          "+"
      p():
        "default slot content"
      fill("footer"):
        "© 2026"
```

A `slot` may carry a body, which is what the call gets when it passes
nothing for that slot. In an `@anode.Macro` value the same two halves are
written in the markup the runtime parses — `<x:slot name="actions">` in the
body and `<x slot="actions">` at the call site — and the default slot is
`name="_"`.

## See also

- [patterns/reuse-markup-with-macros.md](./patterns/reuse-markup-with-macros.md) —
  the minimal recipe form of the badge example.
- [core.md](./core.md) — notation, quoting rules, and the component
  primer the macro body plugs into.
