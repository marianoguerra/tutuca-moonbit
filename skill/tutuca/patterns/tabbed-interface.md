# Tabbed interface

**Problem:** build tabs — a single `currentView` field decides which panel
shows, and the active tab button is highlighted.

```html
<div role="tablist" class="tabs">
  <button
    role="tab"
    @if.class="equals? .currentView 'overview'"
    @then="'tab tab-active'"
    @else="'tab'"
    @on.click="$setCurrentView 'overview'"
  >Overview</button>
  <button
    role="tab"
    @if.class="equals? .currentView 'pricing'"
    @then="'tab tab-active'"
    @else="'tab'"
    @on.click="$setCurrentView 'pricing'"
  >Pricing</button>
</div>

<div @show="equals? .currentView 'overview'">…overview…</div>
<div @show="equals? .currentView 'pricing'">…pricing…</div>
```

```moonbit
priv struct TabsState {
  currentView : String // $setCurrentView is auto-generated
} derive(ToJson, FromJson)

// in the component spec:
init=TabsState::{ currentView: "overview" },
```

One string field is the whole state machine. `equals? .currentView 'overview'`
drives both the panel's `@show` and the active-tab class via `@if.class` /
`@then` / `@else`. Tab clicks call the auto-generated setter with a
string-literal arg (`@on.click="$setCurrentView 'pricing'"`). This toggles
**sibling panels** by predicate; to swap a *component's own* rendered view
instead, see the switch-between-views recipe. The field name is yours to pick
(`tab`, `currentView`, …). A large runnable version (tabs over whole
sub-apps): `examples/composability.mbt`.
