# Show or hide content

**Problem:** render an element only when a condition holds.

```html
<div @show=".isOpen">Details</div>
<p @hide=".isOpen">(hidden when open)</p>

<!-- boolean predicates for one-field checks -->
<p @show="empty? .items">No results</p>
<p @show="truthy? .query">Searching…</p>
<div @show="equals? .view 'detail'">detail view</div>

<!-- on an <x> render op: wraps the produced node, no extra DOM element -->
<x text=".count" @show=".isOpen"></x>
```

The closed set of predicates is `empty?`, `truthy?`, `falsy?`, `null?`,
`equals?` (binary) — semantics in [core.md](../core.md) *Conditional Display*.
For a condition spanning multiple fields, use a no-arg `compute` entry
instead (`@show="$canSubmit"`). A hidden element is **omitted from the output**
entirely (not just visually hidden); the wrapper form (`show=` / `hide=` on
`<x>`) conditionally emits the node with no surrounding element.
