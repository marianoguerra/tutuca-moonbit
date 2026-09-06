# Iterate a list

**Problem:** render one element per item in a list/map field.

```tutu
spec:
  Feed:
    field items :: List.of(String)

view:
  Feed:
    @ul{@comment{@" a host element per item: @key and @value are bound in the loop "} @each(value, key in it.items){@li{@span{@(key)}@": "@(value)}} @comment{ a child component per item } @each(value, key in it.items){@render(value)} @each(value, key in it.items){@div{@render(value)}}}
```

There is no MoonBit half: the field is declared in the schema block and the
loop is a directive, so nothing is left for a handler to do.

`@each` accepts a `.field` or a `*dynamic` (not a `$handler` — a computed
result has no addressable path for event dispatch). `@key`/`@value` are
auto-bound on host-element loops; under `render-each` / `render-it` each
item is rendered as its own component (no `@value`). Use `render-each` for
lists of components (instance `Value`s built with `comp.make({...})`),
`@each` for plain values. `List` iterates by index, `Map` by key in insertion order; a custom
`Obj` iterates its `seq_entries` (see [iteration.md](../iteration.md)).
