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

The three iteration helpers are `alter` entries — pure `MethodFn`s
(`(inst, args) => Value`) whose `args` shape depends on the directive:

```moonbit
alter={
  // @when: args = [key, value, iterData]; return Bool (truthy keeps)
  "filterItem": (inst, args) => {
    match (inst.get("query"), args) {
      (Str(q), [_key, Str(item), ..]) => Bool(item.contains(q))
      _ => Bool(true)
    }
  },
  // @enrich-with (with @each): args = [binds, key, value, iterData];
  // binds is a MUTABLE Map seeded { key, value } — write into it,
  // the return value is ignored
  "enrichItem": (_inst, args) => {
    match args {
      [Map(binds), _key, Str(item), ..] => {
        binds["count"] = Num(item.length().to_double())
        Null
      }
      _ => Null
    }
  },
  // @loop-with: args = [seq, loopCtx]; return Map with optional
  // iterData / start / end / keys
  "getIterData": (inst, args) => {
    let seq_len = match args {
      [List(s), ..] => s.length()
      _ => 0
    }
    let page = match inst.get("page") {
      Num(n) => n.to_int()
      _ => 0
    }
    let page_size = match inst.get("pageSize") {
      Num(n) => n.to_int()
      _ => 5
    }
    let start = page * page_size
    Map({
      "iterData": Map({ "total": Num(seq_len.to_double()) }),
      "start": Num(start.to_double()),
      "end": Num((start + page_size).to_double()),
    })
  },
}
```

### `@loop-with` return shape — `iterData` + slicing

A `@loop-with` handler returns a `Map` with up to four optional keys:

- **`iterData`** — the shared per-loop value handed to `@when` /
  `@enrich-with`. Defaults to `Map({ "seq": seq })` when omitted. Inside
  the loop a binding may read one **binding member** directly
  (`@value.title`) — if an enrich handler only copies members of the
  loop value, the linter hints to drop it and read the members instead.
- **`start`, `end`** (as `Num`) — a positional slice of the iteration,
  with JS `Array.prototype.slice` semantics: `end` is exclusive,
  negatives count from the end (`end: -3` drops the last 3), absent
  means the natural bound. Use this to **paginate** — skip a prefix
  and/or suffix without iterating or rendering it.
- **`keys`** (as `List`) — an explicit, ordered list of **original keys**
  to visit, for **filter-then-paginate**. The handler
  filters/sorts/slices the full sequence itself and returns the current
  page's slice of original keys; the renderer visits exactly those, in
  order. Takes precedence over `start`/`end` when both are present.

Slicing is positional but **preserves each item's original key**: a list
sliced to `start: 2` still binds `@key` to `2, 3, …`, so events, drag,
and two-way binding keep their identity. With `start`/`end`, `@when` then
filters *within* the window, so a page may yield fewer than `end - start`
items — to filter *before* paging (so the page count reflects the filtered
total), return `keys` instead. `keys` are original keys, so identity is
preserved there too: editing or deleting a row on page 2 of a filtered view
hits the right item. A `keys` return is **authoritative** — the renderer
visits exactly those keys and does **not** re-apply `@when` (the handler has
already decided what renders).

### `@loop-with` handler context — `args = [seq, loopCtx]`

The handler's second arg is the loop context — a `Map` holding two `Fn`
values (so it can grow). Both follow the port's Fn calling convention:
**element 0 of the call args is the this-slot** (pass `Null`):

- **`lookup`** — reads a scope `@`-binding, e.g. one published by an
  ancestor scope `@enrich-with`. Lets the handler **reuse a value the
  enrich already computed** instead of recomputing it. Call as
  `f([Null, Str("currentPage")])`.
- **`filter`** — wraps the declared `@when` predicate (always callable; a
  no-op that returns `Bool(true)` when there is no `@when`). Lets the
  handler apply the *declared* filter while building its `keys` slice,
  rather than re-implementing the match test. Call as
  `f([Null, key, value, iterData])`.

Small helpers keep the pattern-matching noise down (from
`examples/filter_paginate.mbt`):

```moonbit
fn ctx_filter(ctx : Map[String, @tutuca.Value], i : Int, v : @tutuca.Value) -> Bool {
  match ctx.get("filter") {
    Some(Fn(f)) => f([Null, Num(i.to_double()), v, Null]) is Bool(true)
    _ => true
  }
}

fn ctx_lookup(ctx : Map[String, @tutuca.Value], name : String) -> @tutuca.Value {
  match ctx.get("lookup") {
    Some(Fn(f)) => f([Null, Str(name)])
    _ => Null
  }
}
```

### Lifecycle of `@each`

For each render of an element with `@each=".items"`:

1. **Resolve sequence** — evaluate `.items`. `List`s, `Map`s, and any
   `Obj` implementing `obj_seq_entries` are recognized (see *Custom
   collections* below).
2. **`@loop-with`** (once per render) — the handler is called with
   `[seq, loopCtx]`; its `iterData` becomes the shared per-loop value and
   its `start`/`end` slice the iteration. Skipped if no `@loop-with`;
   then `iterData` is `Map({ "seq": seq })` and the whole sequence is
   iterated. If it returns `keys`, those exact keys are visited in order
   (filter-then-paginate) and `start`/`end` are ignored.
3. For each `(key, value)` pair in the sliced sequence (or each `key` in
   `keys`):
   1. **`@when`** — called with `[key, value, iterData]`; if it returns
      a falsy value, the item is skipped. **Not applied** when the
      handler returned `keys` (those are authoritative).
   2. **`@enrich-with`** — called with `[binds, key, value, iterData]`.
      `binds` is a **mutable `Map`** seeded with `{ key, value }`;
      writing into it (`binds["count"] = …`) creates `@`-prefixed
      bindings available in the templated children. The return value is
      ignored (and `key`/`value` are restored afterwards).
   3. **Render** the element with the new bindings on the stack.

Auto-bound names inside the loop are always `@key` and `@value` (or
whatever you wrote into `binds`).

### Handler resolution

`@when` / `@enrich-with` / `@loop-with` resolve like event handler names:
bare `filterItem` → `alter` entry (idiomatic); `$filterItem` →
`methods` entry (works, not idiomatic — `alter` keeps iteration helpers
grouped).

## Scope Enrichment

Without an `@each` on the same element, `@enrich-with` becomes a scope
enricher: it is called with **no args**, and its **return value** (a
`Map`) is the bindings object whose keys become `@`-prefixed bindings
for descendants.

```moonbit
alter={
  "enrichScope": (inst, _args) => {
    match inst.get("text") {
      Str(t) => Map({ "len": Num(t.length().to_double()) })
      _ => Map({})
    }
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

Store it in a field as `Obj(KeyedList::{ ... })`. Operations must return
**new** instances so state transactions see a change. One trait-object
caveat: a handler sees the field as `&Obj` and there is no downcast back
to the concrete struct — rebuild the collection from `obj_seq_entries()`
when mutating (the port's trait-object rule). Complete worked example:
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
Simplest, nothing shared: the `@loop-with` handler walks `seq` with
`ctx_filter`, builds the full matching index list, clamps the page, and
returns that page's slice as `keys`.

**2. Shared — one count + one partial collect** (the recipe's default).
A scope `@enrich-with` on an ancestor does **one** counting scan and
publishes the clamped page + pager labels (which the page controls,
sitting outside the loop, read as `@`-bindings); the `@loop-with` handler
reads the clamped page via `ctx_lookup(ctx, "currentPage")`, reuses the
predicate via `ctx_filter`, and collects only the current page's keys —
early-exiting once the page is full.

**3. Coupled — one scan.** The enrich does *everything*, including the
page keys, and stashes them in a binding only the loop reads. Fastest,
but the two handlers are welded together — name them so it shows:

```moonbit
// the only scan: count + labels + keys, stashed under "__keys__"
alter["pagerInfo"] = (inst, _args) => Map({
  "__keys__": List(page_keys(inst)), // consumed ONLY by the loop-with below
  "isFirst": ..., "isLast": ..., "pageLabel": ...,
})
// useless without the enrich: just forwards its keys
alter["forwardKeys"] = (_inst, args) => {
  let ctx = match args {
    [_, Map(c), ..] => c
    _ => {}
  }
  Map({ "keys": ctx_lookup(ctx, "__keys__") })
}
```

Test any strategy end-to-end with the harness — mount the example, type
into the search box, click the pager, and assert the visible rows
(`h.texts(".row")`); see `examples/filter_paginate_test.mbt` and
[testing.md](./testing.md). (The JS `collectIterBindings` helper has no
MoonBit counterpart — the alter handlers are plain functions, so call
them directly for unit-level checks, or go through the mounted view.)

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
