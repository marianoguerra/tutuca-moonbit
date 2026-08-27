# Show or hide content

**Problem:** render an element only when a condition holds.

```html
<script type="tutuca/spec">
  state Form {
    title: String
    body: String
    isOpen: Bool
    items: Array[Any]
    query: String

    /// A condition spanning more than one field is a named `pred` — the view
    /// reads the NAME, and the rule is written once. It sits HERE, beside the
    /// fields it is about: a rule has no statements, no effects and no
    /// arguments, so it is part of what the component is rather than part of
    /// what it does.
    pred canSubmit { ((trim .title) is not '') and ((trim .body) is not '') }
  }
</script>

<template id="Form">
  <div>
    <div @show=".isOpen">Details</div>
    <p @hide=".isOpen">(hidden when open)</p>

    <!-- boolean predicates for one-field checks -->
    <p @show="empty? .items">No results</p>
    <p @show="truthy? .query">Searching…</p>
    <div @show=".query is 'detail'">detail view</div>

    <!-- a pred of your own: `$name`, because this is a value position -->
    <button @show="$canSubmit">Publish</button>

    <!-- on an <x> render op: wraps the produced node, no extra DOM element -->
    <x text=".title" @show=".isOpen"></x>
  </div>
</template>
```

A conditional slot takes the same expression language a `pred` body does:
the shape predicates `empty?`, `truthy?`, `null?`, the operators `not`, `and`,
`or`, `is`, `is not`, `<`, `<=`, `>`, `>=`, `implies`, and the reading
builtins — semantics in [core.md](../core.md) *Conditional
Display*. Anything else is a `pred` in the spec block, read as `$name`; the
`$` sigil is what a value slot spells a callable with, and a bare `canSubmit`
in a `@show` is a generation error. (Inside a body the same rule inverts: a
`pred` is called BARE there, since nothing answers `$` once the render stack is
gone.)

A hidden element is **omitted from the output** entirely (not just visually
hidden); the wrapper form (`show=` / `hide=` on `<x>`) conditionally emits the
node with no surrounding element.

The same `pred` is also what a contract attaches to — `receive publish requires
canSubmit` in the script block refuses the transition and reports it, instead
of the view merely hiding the button. The rule and the clause live in different
blocks on purpose: the rule is a fact about the form, the clause says when one
handler applies (see
[schema.md](../schema.md#contracts-requires--ensures--invariant)).

A rule that reads a loop's `@value`, or one that takes an argument, is not
about the component and stays in the script block —
[filter-a-list.md](filter-a-list.md) is that case.
