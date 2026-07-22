# Bind text and attributes

**Problem:** display a field as text, bind it to an attribute, or compose a
string from several values.

```html
<!-- text -->
<span @text=".str"></span>      <!-- into a host element -->
<x text="$getStrUpper"></x>     <!-- $ calls a compute; no wrapping element -->

<!-- attributes: plain = static, :attr = dynamic -->
<input :value=".str" @on.input="$setStr value" />
<a :href=".url" :title="$'Hi {.name}'">link</a>   <!-- $'…' string template -->
<button :class="$'btn btn-{.kind}'">x</button>

<!-- derive values for a subtree without putting them on the component -->
<div @enrich-with="enrichScope">Len: <x text="@len"></x></div>
```

```moonbit
compute={
  "getStrUpper": (s : TextState, _args) => Str(s.str.to_upper()),
},
enrich_scope={
  // scope enrich: takes only the state; returned Map keys become @len, …
  "enrichScope": (s : TextState) => {
    "len": Num(s.text.length().to_double()),
  },
},
```

Value slots take `.field`, `$handler`, or `@binding` — never a path
(`.user.name` fails). Multi-word strings **must** be quoted (`'flex gap-3'`) or
written as a `$'…'` template (`$'btn {.kind}'`); a bare unquoted string returns
`null`. Boolean HTML attributes (`disabled`, `checked`, …) are auto-recognized
— pass a boolean field. Scope `@enrich-with` (no `@each` on the element) is the
path-free way to expose derived values to a subtree.
