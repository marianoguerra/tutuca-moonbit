# Paginate a list

**Problem:** show one page at a time without iterating or rendering the
off-page items.

`paged.html`:

```tutu
spec:
  Paged:
    field items :: List.of(String)
    field page :: Int
    field page_size :: Int

view:
  Paged:
    @ul{
      @each(value, key in it.items, ~loop_with: paginate){
        @li{@span(~class: "badge"){@(key)} @(value)}
      }
    }
```

`paged.mbt` — `~loop_with` is the **one render bucket the script block has no
declaration kind for**, so this half is MoonBit by construction: a slice is
decided once per render against the whole sequence, which is not a value the
block has any way to see.


```moonbit
///|
fn paged_comp() -> @component.Component {
  paged_component(
    initial={ items: [], page: 0, page_size: 5 },
    // runs once per render, before iteration: (s, seq, loopCtx) -> LoopWith
    loop_with=l => match l {
      Paginate =>
        Some((s, seq, _ctx) => {
          let start = s.page * s.page_size
          @component.LoopWith::new(
            iter_data=Map({ "total": Num(seq.list().length().to_double()) }),
            start~,
            end=start + s.page_size,
          )
        })
    },
  )
}
```

`~loop_with` returns a `@component.LoopWith`
(`LoopWith::new(iter_data?=…, start?=…, end?=…, keys?=…)`), all fields
optional. `start`/`end` slice with JS `Array.prototype.slice` semantics
(`end` exclusive, negatives count from the end). Slicing is positional
but **preserves each item's original key** — `@key` is the index in the
full list, so events and two-way binding keep their identity across
pages. `iter_data` is the shared per-loop value handed to `~when` /
`~enrich_with`.

To paginate a *filtered* list, return `keys` instead of `start`/`end` — see
[Filter and paginate a list](filter-and-paginate.md).
