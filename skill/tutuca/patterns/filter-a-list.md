# Filter a list

**Problem:** render only the items that match a condition.

```html
<script type="tutuca/state">
  state Roster { items: Array[String], query: String }
</script>

<script type="tutuca/script" for="Roster">
  /// A row survives when the query is empty or its text contains it, folded
  /// on both sides so the filter is not a spelling test.
  pred filterItem { (empty? .query) or (contains (lower @value) (lower .query)) }
</script>

<template id="Roster">
  <ul>
    <li @each=".items" @when="filterItem">
      <span @text="@key"></span>: <x text="@value"></x>
    </li>
    <!-- on <x render-each> the same directive applies: @when="filterItem" -->
  </ul>
</template>
```

There is no `when` declaration kind, because there is nothing for one to say:
a `@when` filter and a boolean `compute` are the same construct — a name and
one expression — so an iteration filter is a **`pred`**, the same declaration
`@show`, `@hide` and `@if.<attr>` take. What differs is the SLOT, which is
where the bindings come from: inside a `pred` a loop calls, `@value` and
`@key` are the row's, and `.field` still reads the component's own state.

`@when` returns false to skip the item. It filters *after* any `@loop-with`
slice, so a page can yield fewer than its window. To filter *before* paging,
return `keys` from `@loop-with` instead — see
[filter-and-paginate.md](filter-and-paginate.md).

**When it stays MoonBit.** A row that is a child component *instance* is
filtered by reading a path into it (`@value.completed`), and `gen-views` does
not compile a path into a binding yet — it prints `stays in MoonBit` and the
name falls through to the `when` bucket, whose entries take
`(state, key, value, iter_data) -> Bool` ([the handler
buckets](../core.md#the-handler-buckets)). [todo-list.md](todo-list.md) is
that case written out. The other answer is to put the predicate on the CHILD
— `pred containsText(q)` in the item's own block — and have the parent's
`when` call it on each instance.
