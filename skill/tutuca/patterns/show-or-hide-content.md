# Show or hide content

**Problem:** render an element only when a condition holds.

```html
<script type="tutuca/state">
  state Form { title: String, body: String, isOpen: Bool, items: Array[Any], query: String }
</script>

<script type="tutuca/script" for="Form">
  /// A condition spanning more than one field is a named `pred` — the view
  /// reads the NAME, and the rule is written once.
  pred canSubmit { ((trim .title) is not '') and ((trim .body) is not '') }
</script>

<template id="Form">
  <div>
    <div @show=".isOpen">Details</div>
    <p @hide=".isOpen">(hidden when open)</p>

    <!-- boolean predicates for one-field checks -->
    <p @show="empty? .items">No results</p>
    <p @show="truthy? .query">Searching…</p>
    <div @show="equals? .query 'detail'">detail view</div>

    <!-- a pred of your own: `$name`, because this is a value position -->
    <button @show="$canSubmit">Publish</button>

    <!-- on an <x> render op: wraps the produced node, no extra DOM element -->
    <x text=".title" @show=".isOpen"></x>
  </div>
</template>
```

The closed set of built-in predicates is `empty?`, `truthy?`, `falsy?`,
`null?`, `equals?` (binary) — semantics in [core.md](../core.md) *Conditional
Display*. Anything else is a `pred` in the script block, read as `$name`; the
`$` sigil is what a value slot spells a callable with, and a bare `canSubmit`
in a `@show` is a generation error. (Inside a body the same rule inverts: a
`pred` is called BARE there, since nothing answers `$` once the render stack is
gone.)

A hidden element is **omitted from the output** entirely (not just visually
hidden); the wrapper form (`show=` / `hide=` on `<x>`) conditionally emits the
node with no surrounding element.

The same `pred` is also what a contract attaches to — `receive publish requires
canSubmit` refuses the transition and reports it, instead of the view merely
hiding the button (see [schema.md](../schema.md#contracts-requires--ensures--invariant)).
