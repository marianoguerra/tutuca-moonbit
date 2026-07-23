# Filter and paginate a list

**Problem:** show one page of the items that match a query — filtering
*before* paging, so page counts reflect the filtered total and a row's
identity survives editing or deleting across pages — without scanning the
list more than necessary.

```html
<section @enrich-with="pagerInfo">          <!-- COUNT pass: runs once -->
  <input :value=".query" @on.input="search value" />
  <li @each=".items" @when="onlyMatches" @loop-with="page">  <!-- COLLECT pass -->
    <span @text="@key"></span> <x render-it></x>
    <button @on.click="$removeInItemsAt @key">✕</button>
  </li>
  <button :disabled="@isFirst" @on.click="prev">‹</button>
  <button @text="@pageLabel"></button>
  <button :disabled="@isLast" @on.click="next">›</button>
</section>
```

```moonbit
when={
  // the @when predicate: (s, key, value, iterData) -> Bool
  "onlyMatches": (s : PeopleState, _key, person, _iter) => matches(
    person,
    s.query,
  ),
},
enrich_scope={
  // scope enrich (state only): the COUNT scan — clamp the page, publish
  // the pager bindings the controls outside the loop read
  "pagerInfo": (s : PeopleState) => {
    let total = match_count(s)
    let (page_count, current) = clamp(s.page, total, s.pageSize)
    {
      "currentPage": Num(current.to_double()),
      "isFirst": Bool(current <= 0),
      "isLast": Bool(current >= page_count - 1),
      "pageLabel": Str("Page \{current + 1} of \{page_count} · \{total}"),
    }
  },
},
loop_with={
  // the COLLECT scan: (s, seq, loopCtx) -> LoopWith
  "page": (s : PeopleState, seq, ctx) => {
    let current = match (ctx.lookup)("currentPage") { // reuse the enrich
      Num(n) => n.to_int()
      _ => 0
    }
    let (start, end) = (current * s.pageSize, (current + 1) * s.pageSize)
    let keys : Array[@tutuca.Value] = []
    let mut m = 0
    for i, v in seq.list() {                // early-exit: stops at page end
      if m >= end {
        break
      }
      if (ctx.filter)(Num(i.to_double()), v, Null) { // reuse the declared @when
        if m >= start {
          keys.push(Num(i.to_double()))
        }
        m += 1
      }
    }
    @component.LoopWith::new(keys~)
  },
},
```

(The `search`/`prev`/`next` events are `Input` arms of `update`
that clamp and set `page`, resetting to 0 on every query change.)

Returning **`keys`** (ordered *original* keys) is what makes this work: the
renderer visits exactly those and does **not** re-apply `@when`, and because
`@key` stays the original index, deleting row `@key` on page 2 of a filtered
view hits the right item. The page controls live *outside* the loop, so they
can't read its `iter_data`; instead a scope `@enrich-with` (`enrich_scope`)
does the one counting scan and publishes the clamped page + labels as
`@`-bindings. The `LoopCtx` lets the `loop_with` handler avoid repeating
that work: `(ctx.lookup)` reads the clamped page the enrich already
computed, and `(ctx.filter)` reuses the declared `@when` predicate — so the
collect pass scans just far enough to fill the page.

This is one of three wiring strategies (naive two-scan, shared, coupled
one-scan) — the trade-offs and the other two are in
[iteration.md](../iteration.md) *Filter-then-paginate strategies*; the
complete runnable versions of all three are `storybook/examples/filter_paginate.mbt`
(tests in `storybook/examples/filter_paginate_test.mbt`). See
[filter-a-list.md](filter-a-list.md) and
[paginate-a-list.md](paginate-a-list.md) for each half on its own.
