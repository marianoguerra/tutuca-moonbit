# Reuse markup with macros

**Problem:** the same markup fragment repeats across a view and you want one
definition — but it has no state of its own.

```moonbit
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

```html
<x:badge></x:badge>                  <!-- defaults -->
<x:badge label="Sale"></x:badge>     <!-- static string (no quotes needed) -->
<x:badge :label=".status"></x:badge> <!-- bind a field -->
<x:card title="Hi"><p>body</p></x:card>  <!-- children fill <x:slot> -->
```

A macro is pure template expansion — no fields, no handlers. Parameters are
read as `^name`; calls inside the body (`$handler`, `.field`) resolve against
the *host* component. Params substitute as source text, so a handler name
threads through: `<x:btn-rm :handler="$removeInItemsAt" :arg="@key">` (see
`storybook/examples/todo_macros.mbt`). `<x:slot>` (or `<x:slot name="…">` for named
slots) receives the caller's children. Registry keys are lowercased
(`<x:Card>` → `card`). Full semantics (named slots, quoting of parameter
values) in [macros.md](../macros.md). For repeated markup that *does* need
state, use a child component instead (see the render-a-child-component
recipe).
