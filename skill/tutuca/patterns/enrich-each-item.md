# Enrich each item

**Problem:** show a value derived from each item (a count, a formatted label)
without storing it on the data.

```html
<li @each=".items" @enrich-with="enrichItem">
  <x text="@value"></x> (<x text="@count"></x> characters)
</li>
```

```moonbit
enrich={
  // (s, binds, key, value, iterData) -> Unit; write into binds
  "enrichItem": (_s : ListState, binds, _key, value, _iter) => match value {
    Str(item) => binds["count"] = Num(item.length().to_double()) // becomes @count
    _ => ()
  },
},
```

An `enrich` handler receives a **mutable** `binds` `Map` (seeded with
`{ key, value }`); every key you write becomes an `@`-prefixed binding for
that item's subtree. The return type is `Unit`. Combine freely with
`@when` and `@loop-with` on the same element. Without an `@each` on the
same element, `@enrich-with` enriches the whole scope instead — that is
the `enrich_scope` bucket: the handler takes only the state and the
**returned** `Map` is the bindings (see the bind-text-and-attributes
recipe).
