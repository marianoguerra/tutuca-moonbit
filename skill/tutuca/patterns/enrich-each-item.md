# Enrich each item

**Problem:** show a value derived from each item (a count, a formatted label)
without storing it on the data.

```html
<script type="tutuca/spec">
  state Notes { items: Array[String], picked: Set[String] }
</script>

<script type="tutuca/script" for="Notes">
  /// Per-row bindings. What an enricher writes is in scope for that row's
  /// subtree and nowhere else.
  enrich enrichItem {
    @count = len (str @value)
    @picked = has .picked @value
  }
</script>

<template id="Notes">
  <ul>
    <li @each=".items" @enrich-with="enrichItem">
      <input type="checkbox" :checked="@picked" @on.click="toggleInPicked @value">
      <x text="@value"></x> (<x text="@count"></x> characters)
    </li>
  </ul>
</template>
```

An `enrich` writes `@name` bindings; every name it assigns becomes an
`@`-prefixed binding for that item's subtree, on top of the `@key` / `@value`
the loop already bound. It writes bindings and never state — that is the whole
difference between it and a `receive`.

`@value` is a binding with no declared type, so a builtin that needs one takes
a coercer: `len (str @value)`, not `len @value`. A row's membership in a set
elsewhere on the state is what `has` answers — the same key the generated
`toggleInPicked` writes — and the answer becomes an ordinary binding the
`:checked` slot reads. Combine freely with `@when` and `@loop-with` on the same
element.

Without an `@each` on the same element, `@enrich-with` enriches the whole
scope instead — that is `bindWith`, which sees only the state (see
[bind-text-and-attributes.md](bind-text-and-attributes.md)).

`@cur` is reserved: an enricher's bindings become a view's scope, and the
`new` target is not something a component may publish.
