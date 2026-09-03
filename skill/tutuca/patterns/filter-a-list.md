# Filter a list

**Problem:** render only the items that match a condition.

```html
<script type="tutuca/spec">
  state Roster { items: Array[String], query: String }
</script>

<script type="tutuca/script" for="Roster">
  /// A row survives when the query is empty or its text contains it, folded
  /// on both sides so the filter is not a spelling test.
  ///
  /// It reads `@value`, so it stays HERE rather than in the spec block: it is
  /// a question about one row, not a fact about the roster.
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

**Which block it goes in follows from that.** A `pred` normally lives in the
spec block, beside the state it is about — that is the case
[show-or-hide-content.md](show-or-hide-content.md) shows. This one does not,
and neither does one that takes an argument: reading `@value` makes it a
question about a ROW, and a spec-block rule is asked from no loop at all. So
the two kinds of `pred` divide by what they can see, and the spec block refuses
a parameterised one by name rather than letting it read null.

`@when` returns false to skip the item. It filters *after* any `@loop-with`
slice, so a page can yield fewer than its window. To filter *before* paging,
return `keys` from `@loop-with` instead — see
[filter-and-paginate.md](filter-and-paginate.md).

**When it stays MoonBit.** A row that is a child component *instance* is
filtered by reading a path into it (`@value.completed`), and `gen` does
not compile a path into a binding yet — it prints `stays in MoonBit` and the
name falls through to the `when` bucket, whose entries take
`(state, key, value, iter_data) -> Bool` ([the handler
buckets](../core.md#the-handler-buckets)). [todo-list.md](todo-list.md) is
that case written out. The other answer is to put the predicate on the CHILD
— `pred containsText(q)` in the item's own SCRIPT block, since it takes an
argument — and have the parent's `when` call it on each instance.
