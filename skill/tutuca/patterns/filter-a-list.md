# Filter a list

**Problem:** render only the items that match a condition.

```html
<li @each=".items" @when="filterItem">
  <span @text="@key"></span>: <x text="@value"></x>
</li>
<!-- on <x render-each> the same directive applies: @when="filterItem" -->
```

```moonbit
when={
  // (s, key, value, iterData) -> Bool — false skips the item
  "filterItem": (s : ListState, _key, value, _iter) => match value {
    Str(item) => item.to_lower().contains(s.query.to_lower())
    _ => true
  },
},
```

`@when` names a `when` entry called per item with
`(state, key, value, iter_data)`; return `false` to skip. It filters
*after* any `@loop-with` slice, so a page can yield fewer than its window.
Filtering reads other fields straight off the typed state (`s.query`) —
there are no paths in the template. To filter *before* paging, return
`keys` from `@loop-with` instead — see
[filter-and-paginate.md](filter-and-paginate.md).
