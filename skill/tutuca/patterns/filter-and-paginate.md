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
alter={
  // the @when predicate: args = [key, value, iterData]
  "onlyMatches": (inst, args) => {
    match args {
      [_key, person, ..] => Bool(matches(person, query_of(inst)))
      _ => Bool(true)
    }
  },
  // scope enrich (no args): the COUNT scan — clamp the page, publish
  // the pager bindings the controls outside the loop read
  "pagerInfo": (inst, _args) => {
    let total = match_count(inst)
    let (page_count, current) = clamp(page_of(inst), total, page_size_of(inst))
    Map({
      "currentPage": Num(current.to_double()),
      "isFirst": Bool(current <= 0),
      "isLast": Bool(current >= page_count - 1),
      "pageLabel": Str("Page \{current + 1} of \{page_count} · \{total}"),
    })
  },
  // @loop-with: the COLLECT scan — args = [seq, loopCtx]
  "page": (inst, args) => {
    let seq = match args {
      [List(s), ..] => s
      _ => []
    }
    let ctx = match args {
      [_, Map(c), ..] => c
      _ => {}
    }
    let current = match ctx_lookup(ctx, "currentPage") { // reuse the enrich
      Num(n) => n.to_int()
      _ => 0
    }
    let page_size = page_size_of(inst)
    let (start, end) = (current * page_size, (current + 1) * page_size)
    let keys : Array[Int] = []
    let mut m = 0
    for i, v in seq {                       // early-exit: stops at page end
      if m >= end { break }
      if ctx_filter(ctx, i, v) {            // reuse the declared @when
        if m >= start { keys.push(i) }
        m += 1
      }
    }
    Map({ "keys": List(keys.map(k => @tutuca.Value::Num(k.to_double()))) })
  },
},
```

(`ctx_filter` / `ctx_lookup` are the two-line Fn-unwrapping helpers from
[iteration.md](../iteration.md); the input handlers `search`/`prev`/`next`
clamp and set `page`, resetting to 0 on every query change.)

Returning **`keys`** (ordered *original* keys) is what makes this work: the
renderer visits exactly those and does **not** re-apply `@when`, and because
`@key` stays the original index, deleting row `@key` on page 2 of a filtered
view hits the right item. The page controls live *outside* the loop, so they
can't read its `iterData`; instead a scope `@enrich-with` does the one counting
scan and publishes the clamped page + labels as `@`-bindings. The `@loop-with`
handler's loop context lets it avoid repeating that work: `lookup` reads the
clamped page the enrich already computed, and `filter` reuses the declared
`@when` predicate — so the collect pass scans just far enough to fill the page.

This is one of three wiring strategies (naive two-scan, shared, coupled
one-scan) — the trade-offs and the other two are in
[iteration.md](../iteration.md) *Filter-then-paginate strategies*; the
complete runnable versions of all three are `examples/filter_paginate.mbt`
(tests in `examples/filter_paginate_test.mbt`). See
[filter-a-list.md](filter-a-list.md) and
[paginate-a-list.md](paginate-a-list.md) for each half on its own.
