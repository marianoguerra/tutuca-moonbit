# Tutuca — Macros

Macros are pure template expansion — no state, no handlers of their
own. Calls inside a macro resolve against the *host* component. Read this file when
authoring `@anode.Macro` values, `<x:name>` calls, or slots.

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

```html
<x:badge></x:badge>                       <!-- defaults -->
<x:badge label="Sale"></x:badge>          <!-- static string (no quotes needed) -->
<x:badge :label="'Sale'"></x:badge>       <!-- dynamic literal -->
<x:badge :label=".status"></x:badge>      <!-- field reference -->
```

Inside the macro body, `^param` reads a parameter. Static attributes
(`label="Sale"`) pass the raw string; dynamic attributes (`:label=…`)
take the same value forms as any binding — see *Quoting & String
Literals* in [core.md](./core.md) for the literal-vs-template rules.

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

```html
<!-- expands to @on.click="removeInItemsAt @key" -->
<x:btn-rm :handler="$removeInItemsAt" :arg="@key"></x:btn-rm>
```

> **The `$` prefix only survives a RUNTIME macro.** The example above is an
> `@anode.Macro` value, expanded when the view is compiled — by then the `$` has
> already been resolved away. A macro declared in a view file
> (`<template id="macro:btn-rm">`) is expanded by `gen-views` instead, which sees
> `@on.click="$removeInItemsAt"` in an event position and refuses it:
> *"drop the `$` — in an event position a `$name` and a bare name are the SAME
> dispatch"*. Pass the handler name bare (`:handler="removeInItemsAt"`) and it
> works in both kinds of macro. Prefer bare everywhere; there is no case where
> the `$` buys anything in an `@on`.

If registering into a scope by hand (outside `ModuleDef::build_scope`),
use `ComponentStack::register_macros(macros)` **before**
`compile_all()` — views are compiled against the scope's macros.

Registry keys are lowercased on insert because the HTML parser already
lowercases `<x:Tag>` to `<x:tag>`. `"Card"` and `"card"` both register
under `card`.

## Slots

```moonbit
fn card_macro() -> @anode.Macro {
  {
    defaults: { "title": "'Card'" },
    raw_view: (
      #|<div class="card">
      #|  <h2 @text="^title"></h2>
      #|  <x:slot></x:slot>
      #|</div>
    ),
  }
}
```

```html
<x:card title="Hi"><p>body</p></x:card>   <!-- default slot -->
```

## Named Slots

```moonbit
fn panel_macro() -> @anode.Macro {
  {
    defaults: {},
    raw_view: (
      #|<div>
      #|  <header><x:slot name="actions"></x:slot></header>
      #|  <main><x:slot></x:slot></main>
      #|  <footer><x:slot name="footer"></x:slot></footer>
      #|</div>
    ),
  }
}
```

(The default slot is `name="_"`.)

```html
<x:panel>
  <x slot="actions"><button @on.click="inc">+</button></x>
  <p>default slot content</p>
  <x slot="footer">© 2026</x>
</x:panel>
```

## See also

- [patterns/reuse-markup-with-macros.md](./patterns/reuse-markup-with-macros.md) —
  the minimal recipe form of the badge example.
- [core.md](./core.md) — notation, quoting rules, and the component
  primer the macro body plugs into.
