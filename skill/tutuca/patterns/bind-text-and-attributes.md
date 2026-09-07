# Bind text and attributes

**Problem:** display a field as text, bind it to an attribute, or compose a
string from several values.

```tutu
spec:
  Label:
    field str :: String
    field url :: String
    field name :: String
    field kind :: String

    property str_upper :: String

logic:
  Label:
    /// A value the state does not hold. One expression, one name, and the only
    /// place the transformation is written.
    property str_upper :: String:
      get: it.str.upper()

    /// Derived values for a SUBTREE, with no `each` in sight: a scope
    /// enricher sees the state and writes bindings.
    bind_with bind_with:
      len = it.str.length()

view:
  Label:
    div():
      comment(): " text "
      " "
      span():
        @(it.str)
      " "
      comment(): " into a host element "
      " "
      @(it.str_upper)
      " "
      comment(): " derived property; no wrapping element "
      " "
      comment(): " attributes: plain = static, :attr = dynamic "
      " "
      input(value: it.str, ~on_input: it.str := e.value)
      " "
      a(href: it.url, title: @str{Hi @(it.name)}):
        "link"
      " "
      comment(): " $'…' string template "
      " "
      button(class: @str{btn btn-@(it.kind)}):
        "x"
      " "
      comment(): " derive values for a subtree without putting them on the component "
      " "
      div(~enrich_with: bind_with):
        "Len: "
        @(len)
```

A view slot NAMES things; it does not call them. `{(len .str)}` written in an
attribute has nothing to interpolate — an expression belongs in a body, and
`str_upper()` / `@len` is how the view reaches its result.

Value slots take `it.field`, `handler()`, or `~binding` — never a path
(`it.user.name` fails; a body may walk one, a slot may not). Multi-word strings
**must** be quoted (`"flex gap-3"`) or written as a `@str{…}` template
(`@str{btn @(it.kind)}`); a bare unquoted string returns `null`. Boolean HTML
attributes (`disabled`, `checked`, …) are auto-recognized — pass a boolean
field.

A read-only property is pure by type: its getter answers a value and cannot
assign. When the answer is a yes or a no used as a contract, declare it a
`pred` instead. A derivation that takes arguments or depends on a render-only
`~binding`/`*lookup` remains a `compute` method because it is not a stable
member of the component state.

**When it stays MoonBit.** A property getter the block cannot spell — one
reaching a value no builtin produces — is implemented through the generated
component wrapper. Parameterized or render-context-dependent derivations use
the `compute` bucket; the scope enricher's bucket is
`(state) -> Map[String, Value]`. See
[the handler buckets](../core.md#the-handler-buckets).
