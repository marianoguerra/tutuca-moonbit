# Conditional attribute value

**Problem:** set an attribute (class, title, …) to one value or another
depending on a condition.

```html
<button
  @if.class=".isActive"
  @then="'btn btn-success'"
  @else="'btn btn-ghost'"
  @on.click="$toggleIsActive"
>
  toggle
</button>
```

`@if.<attr>` takes the condition (a `.field`, a `$compute`, or a predicate like
`equals? .tab 'x'`); `@then`/`@else` are the two values. String literals need
quotes (`'btn ok'`); a `$'…'` template works too. (`$toggleIsActive` is the
auto-generated toggler of the bool field `isActive`.) **Multiple `@if` on one
element:** every `@then`/`@else` after the first must name its attr
(`@then.title`, `@else.title`) — HTML forbids duplicate attribute names, so an
unnamed second `@then` is dropped silently.

```html
<button
  @if.class=".isActive" @then="'on'" @else="'off'"
  @if.title=".isActive" @then.title="'On'" @else.title="'Off'"
></button>
```
