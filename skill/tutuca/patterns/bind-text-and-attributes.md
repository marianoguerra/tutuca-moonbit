# Bind text and attributes

**Problem:** display a field as text, bind it to an attribute, or compose a
string from several values.

```html
<script type="tutuca/spec">
  state Label {
    str: String, url: String, name: String, kind: String
    property { strUpper: String { get } }
  }
</script>

<script type="tutuca/script" for="Label">
  /// A value the state does not hold. One expression, one name, and the only
  /// place the transformation is written.
  get strUpper { upper state.str }

  /// Derived values for a SUBTREE, with no `@each` in sight: a scope
  /// enricher sees the state and writes bindings.
  enrichScope enrichScope { @len = len .str }
</script>

<template id="Label">
  <div>
    <!-- text -->
    <span @text=".str"></span>      <!-- into a host element -->
    <x text=".strUpper"></x>        <!-- derived property; no wrapping element -->

    <!-- attributes: plain = static, :attr = dynamic -->
    <input :value=".str" @on.input=".str = e.value" />
    <a :href=".url" :title="$'Hi {.name}'">link</a>   <!-- $'…' string template -->
    <button :class="$'btn btn-{.kind}'">x</button>

    <!-- derive values for a subtree without putting them on the component -->
    <div @enrich-with="enrichScope">Len: <x text="@len"></x></div>
  </div>
</template>
```

A view slot NAMES things; it does not call them. `{(len .str)}` written in an
attribute has nothing to interpolate — an expression belongs in a body, and
`.strUpper` / `@len` is how the view reaches its result.

Value slots take `.field`, `$handler`, or `@binding` — never a path
(`.user.name` fails; a body may walk one, a slot may not). Multi-word strings
**must** be quoted (`'flex gap-3'`) or written as a `$'…'` template
(`$'btn {.kind}'`); a bare unquoted string returns `null`. Boolean HTML
attributes (`disabled`, `checked`, …) are auto-recognized — pass a boolean
field.

A read-only property is pure by type: its getter answers a value and cannot
assign. When the answer is a yes or a no used as a contract, declare it a
`pred` instead. A derivation that takes arguments or depends on a render-only
`@binding`/`*lookup` remains a `compute` method because it is not a stable
member of the component state.

**When it stays MoonBit.** A property getter the block cannot spell — one
reaching a value no builtin produces — is implemented through the generated
component wrapper. Parameterized or render-context-dependent derivations use
the `compute` bucket; the scope enricher's bucket is
`(state) -> Map[String, Value]`. See
[the handler buckets](../core.md#the-handler-buckets).
