# Tabbed interface

**Problem:** build tabs — a single `currentView` field decides which panel
shows, and the active tab button is highlighted.

`tabs.html`:

```html
<script type="tutuca/spec">
  state Tabs { currentView: String }
</script>

<script type="tutuca/fixtures">
{ "fresh": { "value": { "currentView": "overview" } } }
</script>

<template id="Tabs">
  <section>
    <div role="tablist" class="tabs">
      <button role="tab"
        @if.class=".currentView is 'overview'" @then="'tab tab-active'" @else="'tab'"
        @on.click=".currentView = 'overview'">Overview</button>
      <button role="tab"
        @if.class=".currentView is 'pricing'" @then="'tab tab-active'" @else="'tab'"
        @on.click=".currentView = 'pricing'">Pricing</button>
    </div>
    <div @show=".currentView is 'overview'">…overview…</div>
    <div @show=".currentView is 'pricing'">…pricing…</div>
  </section>
</template>
```

There is no script block and there are no handlers: each tab WRITES the field,
in the view, and a write needs nobody to answer it. The starting value is a
**named initial state** — a default is a value, so it goes in a block of its own
and the generator turns it into `TabsState::fresh()`.

`tabs.mbt` — all that is left is naming the fixture:

```moonbit
///|
fn tabs_comp() -> @component.Component {
  tabs_component(initial=TabsState::fresh())
}
```

One string field is the whole state machine. `.currentView is 'overview'`
drives both the panel's `@show` and the active-tab class via `@if.class` /
`@then` / `@else`. A tab click writes the field with a string literal
(`@on.click=".currentView = 'pricing'"`).

A field has ONE spelling now — the one a view reads — so the schema writes
`currentView` and so does every read of it. The name is yours to pick (`tab`,
`currentView`, …).

This toggles **sibling panels** by predicate; to swap a *component's own*
rendered view instead, see [Switch between views](switch-between-views.md). The
same shape scales up to tabs over whole sub-apps — each panel a component
rendered with `<x render=".field">`.
