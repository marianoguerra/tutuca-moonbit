# Bind text and attributes

**Problem:** display a field as text, bind it to an attribute, or compose a
string from several values.

```html
<script type="tutuca/spec">
  state Label { str: String, url: String, name: String, kind: String }
</script>

<script type="tutuca/script" for="Label">
  /// A value the state does not hold. One expression, one name, and the only
  /// place the transformation is written.
  compute getStrUpper { upper .str }

  /// Derived values for a SUBTREE, with no `@each` in sight: a scope
  /// enricher sees the state and writes bindings.
  enrichScope enrichScope { @len = len .str }
</script>

<template id="Label">
  <div>
    <!-- text -->
    <span @text=".str"></span>      <!-- into a host element -->
    <x text="$getStrUpper"></x>     <!-- $ calls a compute; no wrapping element -->

    <!-- attributes: plain = static, :attr = dynamic -->
    <input :value=".str" @on.input="setStr e.value" />
    <a :href=".url" :title="$'Hi {.name}'">link</a>   <!-- $'…' string template -->
    <button :class="$'btn btn-{.kind}'">x</button>

    <!-- derive values for a subtree without putting them on the component -->
    <div @enrich-with="enrichScope">Len: <x text="@len"></x></div>
  </div>
</template>
```

A view slot NAMES things; it does not call them. `{(len .str)}` written in an
attribute has nothing to interpolate — an expression belongs in a body, and
`$getStrUpper` / `@len` is how the view reaches its result.

Value slots take `.field`, `$handler`, or `@binding` — never a path
(`.user.name` fails; a body may walk one, a slot may not). Multi-word strings
**must** be quoted (`'flex gap-3'`) or written as a `$'…'` template
(`$'btn {.kind}'`); a bare unquoted string returns `null`. Boolean HTML
attributes (`disabled`, `checked`, …) are auto-recognized — pass a boolean
field.

A `compute` is pure by type: it answers a value, cannot assign, and so can
never be the reason a render is wrong. When the answer is a yes or a no,
declare it a `pred` instead — that is the same construct with its type stated,
and it is what a `@show` / `@if` / `@when` slot takes.

**When it stays MoonBit.** A `compute` the block cannot spell — one reaching a
value no builtin produces — falls through to the `compute` bucket, whose
entries are `(state, args) -> Value` keyed by a generated enum
(`GetStrUpper`); the scope enricher's is `(state) -> Map[String, Value]`. See
[the handler buckets](../core.md#the-handler-buckets).
