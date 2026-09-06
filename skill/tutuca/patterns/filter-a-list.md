# Filter a list

**Problem:** render only the items that match a condition.

```tutu
spec:
  Roster:
    field items :: List.of(String)
    field query :: String

logic:
  Roster:
    /// A row survives when the query is empty or its text contains it, folded
    /// on both sides so the filter is not a spelling test.
    ///
    /// It reads the loop binder, so it stays HERE rather than in `spec:`: it is
    /// a question about one row, not a fact about the roster.
    pred filter_item(value, key): (it.query.is_empty() || (value.lower()).contains(it.query.lower()))

view:
  Roster:
    @ul{@each(value, key in it.items, ~when: filter_item){@li{@span{@(key)}@": "@(value)}} @comment{@" a loop that renders components takes the same ~when: option "}}
```

There is no `when` declaration kind, because there is nothing for one to say:
a `~when` filter and a boolean `compute` are the same construct — a name and
one expression — so an iteration filter is a **`pred`**, the same declaration
`@show`, `@hide` and a conditional attribute take. What differs is the SLOT, which is
where the bindings come from: inside a `pred` a loop calls, the loop binder and
`@key` are the row's, and `it.field` still reads the component's own state.

**Which block it goes in follows from that.** A `pred` normally lives in the
`spec:` section, beside the state it is about — that is the case
[show-or-hide-content.md](show-or-hide-content.md) shows. This one does not,
and neither does one that takes an argument: reading the loop binder makes it a
question about a ROW, and a spec-block rule is asked from no loop at all. So
the two kinds of `pred` divide by what they can see, and `spec:` refuses
a parameterised one by name rather than letting it read null.

`~when` returns false to skip the item. It filters *after* any `~loop_with`
slice, so a page can yield fewer than its window. To filter *before* paging,
return `keys` from `~loop_with` instead — see
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
