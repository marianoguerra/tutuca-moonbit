# Paginate a list

**Problem:** show one page at a time without iterating or rendering the
off-page items.

`paged.html`:

```html
<script type="tutuca/state">
  state Paged { items: Array[Any], page: Int, pageSize: Int }
</script>

<template id="Paged">
  <ul>
    <li @each=".items" @loop-with="paginate">
      <span class="badge" @text="@key"></span> <x text="@value"></x>
    </li>
  </ul>
</template>
```

`paged.mbt`:

```moonbit
///|
fn paged_comp() -> @component.Component {
  paged_component(
    init={ items: [], page: 0, pageSize: 5 },
    // runs once per render, before iteration: (s, seq, loopCtx) -> LoopWith
    loop_with=l => match l {
      Paginate =>
        Some((s, seq, _ctx) => {
          let start = s.page * s.pageSize
          @component.LoopWith::new(
            iter_data=Map({ "total": Num(seq.list().length().to_double()) }),
            start~,
            end=start + s.pageSize,
          )
        })
    },
  )
}
```

`@loop-with` returns a `@component.LoopWith`
(`LoopWith::new(iter_data?=…, start?=…, end?=…, keys?=…)`), all fields
optional. `start`/`end` slice with JS `Array.prototype.slice` semantics
(`end` exclusive, negatives count from the end). Slicing is positional
but **preserves each item's original key** — `@key` is the index in the
full list, so events and two-way binding keep their identity across
pages. `iter_data` is the shared per-loop value handed to `@when` /
`@enrich-with`.

To paginate a *filtered* list, return `keys` instead of `start`/`end` — see
[Filter and paginate a list](filter-and-paginate.md).
