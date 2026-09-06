# Enrich each item

**Problem:** show a value derived from each item (a count, a formatted label)
without storing it on the data.

```tutu
spec:
  Notes:
    field items :: List.of(String)
    field picked :: Set.of(String)

logic:
  Notes:
    /// Per-row bindings. What an enricher writes is in scope for that row's
    /// subtree and nowhere else.
    enrich enrich_item(value, key):
      count = (value.to_string()).length()
      picked = it.picked.has(value)

view:
  Notes:
    @ul{
      @each(value, key in it.items, ~enrich_with: enrich_item){
        @li{@input(~type: "checkbox", ~checked: picked, ~on_click: it.picked.toggle(value)) @(value)@" ("@(count)@" characters) "}
      }
    }
```

An `enrich` writes `@name` bindings; every name it assigns becomes an
`@`-prefixed binding for that item's subtree, on top of the `@key` / `@value`
the loop already bound. It writes bindings and never state — that is the whole
difference between it and a `receive`.

`@value` is a binding with no declared type, so a builtin that needs one takes
a coercer: `len (str @value)`, not `len @value`. A row's membership in a set
elsewhere on the state is what `has` answers — the same key the generated
`toggleInPicked` writes — and the answer becomes an ordinary binding the
`:checked` slot reads. Combine freely with `~when` and `~loop_with` on the same
element.

Without an `@each` on the same element, `~enrich_with` enriches the whole
scope instead — that is `bindWith`, which sees only the state (see
[bind-text-and-attributes.md](bind-text-and-attributes.md)).

`cur` is reserved: an enricher's bindings become a view's scope, and the
`new` target is not something a component may publish.
