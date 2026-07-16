# Filter a list

**Problem:** render only the items that match a condition.

```html
<li @each=".items" @when="filterItem">
  <span @text="@key"></span>: <x text="@value"></x>
</li>
<!-- on <x render-each> the same directive applies: @when="filterItem" -->
```

```moonbit
alter={
  // args = [key, value, iterData]; return Bool — falsy skips the item
  "filterItem": (inst, args) => {
    match (inst.get("query"), args) {
      (Str(q), [_key, Str(item), ..]) =>
        Bool(item.to_lower().contains(q.to_lower()))
      _ => Bool(true)
    }
  },
},
```

`@when` names an `alter` handler called per item with
`[key, value, iterData]`; return a falsy value to skip. It filters *after* any
`@loop-with` slice, so a page can yield fewer than its window. Filtering reads
other fields off the instance directly (`inst.get("query")`) — there are no
paths in the template. To filter *before* paging, return `keys` from
`@loop-with` instead — see [filter-and-paginate.md](filter-and-paginate.md).
