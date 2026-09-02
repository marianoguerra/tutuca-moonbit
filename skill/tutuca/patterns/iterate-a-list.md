# Iterate a list

**Problem:** render one element per item in a list/map field.

```html
<script type="tutuca/spec">
  state Feed { items: Array[String] }   // or Array[Row], Map[String, Row], …
</script>

<template id="Feed">
  <ul>
    <!-- a host element per item: @key and @value are bound in the loop -->
    <li @each=".items"><span @text="@key"></span>: <x text="@value"></x></li>
    <!-- a child component per item -->
    <x render-each=".items"></x>
    <div @each=".items"><x render-it></x></div>
  </ul>
</template>
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
