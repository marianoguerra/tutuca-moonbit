# Filter and paginate a list

**Problem:** show one page of the items that match a query — filtering
*before* paging, so page counts reflect the filtered total and a row's
identity survives editing or deleting across pages — without scanning the
list more than necessary.

```tutu
view:
  Card:
    @section(~enrich_with: pager_info){@comment{ COUNT pass: runs once } @input(~value: it.query, ~on_input: search(e.value)) @each(value, key in it.items, ~when: only_matches, ~loop_with: page){@li{@comment{ COLLECT pass } @span{@(key)} @render(value) @button(~on_click: remove_in_items_at(key)){✕}}} @button(~disabled: is_first, ~on_click: prev){‹} @button{@(page_label)} @button(~disabled: is_last, ~on_click: next){›}}
```

All three handlers are MoonBit, and each for its own reason: `~loop_with` has
no declaration kind in `logic:`; the count scan folds over the whole
sequence, which no expression in that language can do; and the rows are child
component *instances*, whose fields are read through a path into the loop binder that
`gen` does not compile. This is the shape the split is meant to have —
the block takes the ordinary five-sixths, and what is left is genuinely
MoonBit's.

```moonbit nocheck
// nocheck: a bucket argument, not a top-level item
// generated wrapper: each bucket is a match over a generated enum
// ("onlyMatches" -> OnlyMatches; a raw component() call would take
// string-keyed maps instead)
when=w => match w {
  // the @when predicate: (s, key, value, iterData) -> Bool
  OnlyMatches => Some((s, _key, person, _iter, _stack) => matches(person, s.query)),
},
bind_with=e => match e {
  // scope enrich (state only): the COUNT scan — clamp the page, publish
  // the pager bindings the controls outside the loop read
  PagerInfo =>
    Some(s => {
      let total = match_count(s)
      let (page_count, current) = clamp(s.page, total, s.page_size)
      {
        "currentPage": Num(current.to_double()),
        "isFirst": Bool(current <= 0),
        "isLast": Bool(current >= page_count - 1),
        "pageLabel": Str("Page \{current + 1} of \{page_count} · \{total}"),
      }
    }),
},
loop_with=l => match l {
  // the COLLECT scan: (s, seq, loopCtx) -> LoopWith
  Page =>
    Some((s, seq, ctx) => {
      let current = match (ctx.lookup)("currentPage") { // reuse the enrich
        Num(n) => n.to_int()
        _ => 0
      }
      let (start, end) = (current * s.page_size, (current + 1) * s.page_size)
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
    }),
},
```

(The `search`/`prev`/`next` events are `Receive` arms of `update`
that clamp and set `page`, resetting to 0 on every query change.)

Returning **`keys`** (ordered *original* keys) is what makes this work: the
renderer visits exactly those and does **not** re-apply `~when`, and because
`@key` stays the original index, deleting row `@key` on page 2 of a filtered
view hits the right item. The page controls live *outside* the loop, so they
can't read its `iter_data`; instead a scope `~enrich_with` (`bind_with`)
does the one counting scan and publishes the clamped page + labels as
`@`-bindings. The `LoopCtx` lets the `loop_with` handler avoid repeating
that work: `(ctx.lookup)` reads the clamped page the enrich already
computed, and `(ctx.filter)` reuses the declared `~when` predicate — so the
collect pass scans just far enough to fill the page.

This is one of three wiring strategies (naive two-scan, shared, coupled
one-scan) — the trade-offs and the other two are in
[iteration.md](../iteration.md) *Filter-then-paginate strategies*. See
[filter-a-list.md](filter-a-list.md) and
[paginate-a-list.md](paginate-a-list.md) for each half on its own.
