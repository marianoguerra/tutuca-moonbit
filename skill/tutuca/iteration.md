# Tutuca — List Iteration & Enrichment

Read this file when a view iterates a sequence (`@each`,
`render-each`), filters (`@when`), enriches items or scopes
(`@enrich-with`), or paginates (`@loop-with`).

## List Iteration

`@each` accepts: `.field`, `*dynamic`.

```html
<!-- iterate plain values -->
<li @each=".items"><span @text="@key"></span>: <x text="@value"></x></li>

<!-- filter -->
<li @each=".items" @when="filterItem">...</li>

<!-- per-item enrichment via the enrich handler (binds key X => @X in template) -->
<li @each=".items" @enrich-with="enrichItem">
  <x text="@count"></x>
</li>

<!-- shared per-loop data + slicing (computed once before iteration) -->
<li @each=".items" @loop-with="getIterData" @when="filterItem">...</li>

<!-- render a list of components -->
<x render-each=".items"></x>
<x render-each=".items" as="edit"></x>                          <!-- specific view -->
<x render-each=".items" @when="filterItem"></x>                 <!-- with filter -->
<x render-each=".items" @loop-with="getIterData" @when="filterItem"></x>
<x render-each=".items" @show=".isOpen"></x>                    <!-- wrap in show -->
```

Directives carry the `@` prefix everywhere — on `<li @each>` / `<div @each>`
host-element loops and on `<x render-each>` alike. Only `as=` is bare, because
it is an argument to the op rather than a directive. Both forms share the
handler-name resolution rules below.

`@enrich-with` is **not** supported on `<x render-each>`: the op renders
each item as a component in its own frame and drops child content, so
nothing is left to read the `@X` binds an enricher would set. Reach for a
host-element `@each` loop when you need enrichment.

Each iteration directive has its own **typed bucket** on the component,
so the handler signatures say exactly what the renderer hands them —
state first, always:

```moonbit
// @when: (s, key, value, iterData) -> Bool — true keeps the item
when={
  "filterItem": (s : ListState, _key, value, _iter) => value
  .str()
  .to_lower()
  .contains(s.query.to_lower()),
},
// @enrich-with (with @each): (s, binds, key, value, iterData) -> Unit
// binds is a MUTABLE Map seeded { key, value } — write into it,
// the return value is Unit
enrich={
  "enrichItem": (_s : ListState, binds, _key, value, _iter) => binds["count"] = Num(
    value.str().length().to_double(),
  ),
},
// @loop-with: (s, seq, loopCtx) -> LoopWith, with optional
// iter_data / start / end / keys
loop_with={
  "getIterData": (s : ListState, seq, _ctx) => {
    let start = s.page * s.pageSize
    @component.LoopWith::new(
      iter_data=Map({ "total": Num(seq.list().length().to_double()) }),
      start~,
      end=start + s.pageSize,
    )
  },
},
```

Loop keys and values arrive as `@tutuca.Value` — read them with the
coercers (`.str()`, `.int()`, `.list()`, `.field("x")`) or pattern-match
(`match value { Str(item) => ..., _ => ... }`).

### `@loop-with` return shape — `LoopWith`

A `@loop-with` handler returns a `@component.LoopWith`
(`LoopWith::new(iter_data?=…, start?=…, end?=…, keys?=…)`) — all four
fields optional:

- **`iter_data`** — the shared per-loop value handed to `@when` /
  `@enrich-with`. Defaults to `Map({ "seq": seq })` when omitted. Inside
  the loop a binding may read one **binding member** directly
  (`@value.title`) — if an enrich handler only copies members of the
  loop value, the linter hints to drop it and read the members instead.
- **`start`, `end`** (as `Int`) — a positional slice of the iteration,
  with JS `Array.prototype.slice` semantics: `end` is exclusive,
  negatives count from the end (`end=-3` drops the last 3), absent
  means the natural bound. Use this to **paginate** — skip a prefix
  and/or suffix without iterating or rendering it.
- **`keys`** (an `Array[@tutuca.Value]`) — an explicit, ordered list of
  **original keys** to visit, for **filter-then-paginate**. The handler
  filters/sorts/slices the full sequence itself and returns the current
  page's slice of original keys; the renderer visits exactly those, in
  order. Takes precedence over `start`/`end` when both are present.

Slicing is positional but **preserves each item's original key**: a list
sliced to `start=2` still binds `@key` to `2, 3, …`, so events, drag,
and two-way binding keep their identity. With `start`/`end`, `@when` then
filters *within* the window, so a page may yield fewer than `end - start`
items — to filter *before* paging (so the page count reflects the filtered
total), return `keys` instead. `keys` are original keys, so identity is
preserved there too: editing or deleting a row on page 2 of a filtered view
hits the right item. A `keys` return is **authoritative** — the renderer
visits exactly those keys and does **not** re-apply `@when` (the handler has
already decided what renders).

### `@loop-with` handler context — the `LoopCtx`

The handler's third parameter is the typed loop context,
`@component.LoopCtx`, a struct of two function fields (call
struct-function fields with parens):

- **`(ctx.lookup)(name) : Value`** — reads a scope `@`-binding, e.g. one
  published by an ancestor scope `@enrich-with`. Lets the handler
  **reuse a value the enrich already computed** instead of recomputing
  it: `(ctx.lookup)("currentPage")`.
- **`(ctx.filter)(key, value, iter_data) : Bool`** — wraps the declared
  `@when` predicate (always callable; returns `true` when there is no
  `@when`). Lets the handler apply the *declared* filter while building
  its `keys` slice, rather than re-implementing the match test:
  `(ctx.filter)(Num(i.to_double()), v, Null)`.

### Lifecycle of `@each`

For each render of an element with `@each=".items"`:

1. **Resolve sequence** — evaluate `.items`. `List`s, `Map`s, and any
   `Obj` implementing `obj_seq_entries` are recognized (see *Custom
   collections* below).
2. **`@loop-with`** (once per render) — the handler is called with
   `(state, seq, loop_ctx)`; its `iter_data` becomes the shared per-loop
   value and its `start`/`end` slice the iteration. Skipped if no
   `@loop-with`; then `iter_data` is `Map({ "seq": seq })` and the whole
   sequence is iterated. If it returns `keys`, those exact keys are
   visited in order (filter-then-paginate) and `start`/`end` are ignored.
3. For each `(key, value)` pair in the sliced sequence (or each `key` in
   `keys`):
   1. **`@when`** — called with `(state, key, value, iter_data)`; if it
      returns `false`, the item is skipped. **Not applied** when the
      handler returned `keys` (those are authoritative).
   2. **`@enrich-with`** — called with
      `(state, binds, key, value, iter_data)`. `binds` is a **mutable
      `Map[String, Value]`** seeded with `{ key, value }`; writing into
      it (`binds["count"] = …`) creates `@`-prefixed bindings available
      in the templated children. The return type is `Unit` (and
      `key`/`value` are restored afterwards).
   3. **Render** the element with the new bindings on the stack.

Auto-bound names inside the loop are always `@key` and `@value` (or
whatever you wrote into `binds`).

### Handler resolution

`@when` / `@enrich-with` / `@loop-with` name bare identifiers resolved
in the matching typed bucket: `@when="filterItem"` → the `when` entry,
`@enrich-with` → `enrich` (or `enrich_scope` without `@each`),
`@loop-with` → `loop_with`. When no typed-bucket entry matches, the name
falls back to a `compute`/`mutate`/generated entry (works, not
idiomatic — the typed buckets keep iteration helpers grouped and give
them the right signature).

## Scope Enrichment

Without an `@each` on the same element, `@enrich-with` resolves in the
**`enrich_scope`** bucket instead: the handler takes only the state, and
its **returned** `Map[String, Value]`'s keys become `@`-prefixed
bindings for descendants.

```moonbit
enrich_scope={
  "enrichScope": (s : TextState) => {
    "len": Num(s.text.length().to_double()),
    "upper": Str(s.text.to_upper()),
  },
}
```

```html
<div @enrich-with="enrichScope">Length: <x text="@len"></x></div>
```

## Custom collections — the `Obj` trait

To make `@each` iterate your own collection type, implement the
`@tutuca.Obj` trait — the MoonBit analogue of the JS `SEQ_INFO` walker:

- **`obj_seq_entries(self) -> Array[(PathKey, Value)]?`** — the entries
  `@each` visits, in order, each keyed (`KStr` / `KInt`) so event paths
  resolve back to entries (`@key` in handlers).
- **`obj_item(self, key : PathKey) -> Value?`** — resolves the same keys
  for seq-access reads (`.songs[.currentKey]`).

```moonbit
priv struct KeyedList {
  order : Array[String]
  items : Map[String, @tutuca.Value]
}

impl @tutuca.Obj for KeyedList with fn obj_seq_entries(self) {
  Some(self.order.map(k => (KStr(k), self.items.get(k).unwrap_or(Null))))
}

impl @tutuca.Obj for KeyedList with fn obj_item(self, key) {
  match key {
    KStr(s) => self.items.get(s)
    _ => None
  }
}
```

Store it in a `@tutuca.Value` state field as `Obj(KeyedList::{ ... })`.
Operations must return **new** instances so state transactions see a
change. One trait-object caveat: a handler sees the field as `&Obj` and
there is no downcast back to the concrete struct — rebuild the
collection from `obj_seq_entries()` when mutating (the port's
trait-object rule). Complete worked example:
`examples/custom_collection.mbt` (a keyed playlist whose `@key`s resolve
in remove handlers).

## Filter-then-paginate strategies

The recipe form is in
[patterns/filter-and-paginate.md](./patterns/filter-and-paginate.md).
There are three ways to wire it, trading simplicity for scans-per-render
(all return `keys`, so all keep identity). The complete worked MoonBit
version of all three is `examples/filter_paginate.mbt`:

**1. Naive — two independent scans.** The loop scans + slices the whole
list itself; a separate `@enrich-with` scans again for the pager labels.
Simplest, nothing shared: the `loop_with` handler walks `seq.list()`
with `(ctx.filter)(...)`, builds the full matching index list, clamps
the page, and returns that page's slice as `keys`.

**2. Shared — one count + one partial collect** (the recipe's default).
A scope `@enrich-with` (`enrich_scope`) on an ancestor does **one**
counting scan and publishes the clamped page + pager labels (which the
page controls, sitting outside the loop, read as `@`-bindings); the
`loop_with` handler reads the clamped page via
`(ctx.lookup)("currentPage")`, reuses the predicate via `(ctx.filter)`,
and collects only the current page's keys — early-exiting once the page
is full.

**3. Coupled — one scan.** The enrich does *everything*, including the
page keys, and stashes them in a binding only the loop reads. Fastest,
but the two handlers are welded together — name them so it shows:

```moonbit
// the only scan: count + labels + keys, stashed under "__keys__"
enrich_scope={
  "pagerInfo": (s : PeopleState) => {
    "__keys__": List(page_keys(s)), // consumed ONLY by the loop-with below
    "isFirst": Bool(...), "isLast": Bool(...), "pageLabel": Str(...),
  },
},
// useless without the enrich: just forwards its keys
loop_with={
  "forwardKeys": (_s : PeopleState, _seq, ctx) => match
    (ctx.lookup)("__keys__") {
    List(keys) => @component.LoopWith::new(keys~)
    _ => @component.LoopWith::new(keys=[])
  },
},
```

Test any strategy end-to-end with the harness — mount the example, type
into the search box, click the pager, and assert the visible rows
(`h.texts(".row")`); see `examples/filter_paginate_test.mbt` and
[testing.md](./testing.md). (The JS `collectIterBindings` helper has no
MoonBit counterpart — the bucket handlers are plain typed functions, so
call them directly for unit-level checks, or go through the mounted
view.)

## See also

- [patterns/iterate-a-list.md](./patterns/iterate-a-list.md),
  [patterns/filter-a-list.md](./patterns/filter-a-list.md),
  [patterns/paginate-a-list.md](./patterns/paginate-a-list.md),
  [patterns/enrich-each-item.md](./patterns/enrich-each-item.md) — minimal
  recipes for each half.
- [core.md](./core.md) — the component primer, notation, and the
  frame/scope stack model these directives build on.
- [advanced.md](./advanced.md) — dynamic bindings as iteration sources
  (`@each="*items"`).
