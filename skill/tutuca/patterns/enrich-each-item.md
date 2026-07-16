# Enrich each item

**Problem:** show a value derived from each item (a count, a formatted label)
without storing it on the data.

```html
<li @each=".items" @enrich-with="enrichItem">
  <x text="@value"></x> (<x text="@count"></x> characters)
</li>
```

```moonbit
alter={
  // args = [binds, key, value, iterData]; write into binds, return ignored
  "enrichItem": (_inst, args) => {
    match args {
      [Map(binds), _key, Str(item), ..] => {
        binds["count"] = Num(item.length().to_double()) // becomes @count
        Null
      }
      _ => Null
    }
  },
},
```

`@enrich-with` receives a **mutable** `binds` `Map` (seeded with `{ key,
value }`) as its first arg; every key you write becomes an `@`-prefixed
binding for that item's subtree. The return value is ignored. Combine freely
with `@when` and `@loop-with` on the same element. Without an `@each` on the
same element, `@enrich-with` enriches the whole scope instead — no args, and
the **returned** `Map` is the bindings (see the bind-text-and-attributes
recipe).
