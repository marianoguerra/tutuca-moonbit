# Show or hide content

**Problem:** render an element only when a condition holds.

```tutu
spec:
  Form:
    field title :: String
    field body :: String
    field is_open :: Bool
    field items :: List.of(Any)
    field query :: String

    /// A condition spanning more than one field is a named `pred` — the view
    /// reads the NAME, and the rule is written once. It sits HERE, beside the
    /// fields it is about: a rule has no statements, no effects and no
    /// arguments, so it is part of what the component is rather than part of
    /// what it does.
    pred can_submit: ((it.title.trim() != "") && (it.body.trim() != ""))

view:
  Form:
    div():
      show(it.is_open):
        div():
          "Details"
      " "
      hide(it.is_open):
        p():
          "(hidden when open)"
      " "
      comment(): " boolean predicates for one-field checks "
      " "
      show(it.items.is_empty()):
        p():
          "No results"
      " "
      show(it.query.is_truthy()):
        p():
          "Searching…"
      " "
      show((it.query == "detail")):
        div():
          "detail view"
      " "
      comment(): " a pred of your own: `name(…)`, because this is a value position "
      " "
      show(can_submit()):
        button():
          "Publish"
      " "
      comment(): " around a hole or a render: wraps the produced node, no extra DOM element "
      " "
      show(it.is_open):
        @(it.title)
```

A conditional slot takes the same expression language a `pred` body does:
the shape predicates `empty?`, `truthy?`, `null?`, the operators `not`, `and`,
`or`, `is`, `is not`, `<`, `<=`, `>`, `>=`, `implies`, and the reading
builtins — semantics in [core.md](../core.md) *Conditional
Display*. Anything else is a `pred` in `spec:`, read as `name(…)`; the
`$` sigil is what a value slot spells a callable with, and a bare `canSubmit`
in a `show` is a generation error. (Inside a body the same rule inverts: a
`pred` is called BARE there, since nothing answers `$` once the render stack is
gone.)

A hidden element is **omitted from the output** entirely (not just visually
hidden); the wrapper form (`show` / `hide` around a hole or a render) conditionally emits the
node with no surrounding element.

The same `pred` is also what a contract attaches to — `receive publish requires
canSubmit` in `logic:` refuses the transition and reports it, instead
of the view merely hiding the button. The rule and the clause live in different
blocks on purpose: the rule is a fact about the form, the clause says when one
handler applies (see
[schema.md](../schema.md#contracts-requires--ensures--invariant)).

A rule that reads a loop's the loop binder, or one that takes an argument, is not
about the component and stays in `logic:` —
[filter-a-list.md](filter-a-list.md) is that case.
