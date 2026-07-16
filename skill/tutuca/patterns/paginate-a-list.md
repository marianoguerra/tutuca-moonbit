# Paginate a list

**Problem:** show one page at a time without iterating or rendering the
off-page items.

```html
<li @each=".items" @loop-with="paginate">
  <span class="badge" @text="@key"></span> <x text="@value"></x>
</li>
```

```moonbit
fields={
  "items": @component.FieldSpec::of_default(List([])),
  "page": @component.FieldSpec::of_default(Num(0)),
  "pageSize": @component.FieldSpec::of_default(Num(5)),
},
alter={
  // runs once per render, before iteration; args = [seq, loopCtx]
  "paginate": (inst, args) => {
    let total = match args {
      [List(s), ..] => s.length()
      _ => 0
    }
    let page = match inst.get("page") {
      Num(n) => n.to_int()
      _ => 0
    }
    let size = match inst.get("pageSize") {
      Num(n) => n.to_int()
      _ => 5
    }
    let start = page * size
    Map({
      "iterData": Map({ "total": Num(total.to_double()) }),
      "start": Num(start.to_double()),
      "end": Num((start + size).to_double()),
    })
  },
},
```

`@loop-with` returns a `Map` with `iterData` / `start` / `end`, all optional.
`start`/`end` slice with JS `Array.prototype.slice` semantics (`end`
exclusive, negatives count from the end). Slicing is positional but
**preserves each item's original key** — `@key` is the index in the full
list, so events and two-way binding keep their identity across pages.
`iterData` is the shared per-loop value handed to `@when` / `@enrich-with`.
To paginate a *filtered* list, return `keys` instead of `start`/`end` — see
[filter-and-paginate.md](filter-and-paginate.md).
