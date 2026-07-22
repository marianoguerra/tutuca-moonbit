// Ports of the "State and Updates" tutorial examples:
//
//   docs/examples/attribute-binding.js      — :attr bindings + $'templates'
//   docs/examples/conditional-attributes.js — @if.attr / @then / @else
//   docs/examples/event-modifiers.js        — @on.keydown+send / +cancel
//   docs/examples/show-hide.js              — @show / @hide
//
// Note the event modifiers tutuca actually defines (src/anode.js
// MOD_WRAPPERS_BY_EVENT): keydown takes send/cancel/ctrl/cmd/meta/alt, click
// takes ctrl/cmd/meta/alt. There is no +stop / +prevent; an unknown modifier is
// the identity (it does not gate the handler).

///|
priv struct AttributeBindingState {
  str : String
  num : Int
  bool : Bool
  notSet : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// `:attr=".field"` binds state into any attribute; `$'…{.field}…'` is a string
/// template. Typing calls the GENERATED `setStr`; the number input goes through
/// a hand-written `setRawNumber` that parses and validates first.
fn attribute_binding_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-3">
          #|  <input class="input s" :value=".str" @on.input="$setStr value" :title="$'Content is {.str}'" />
          #|  <input class="input n" type="number" :value=".num" @on.input="$setRawNumber value" />
          #|  <input class="checkbox b" type="checkbox" :checked=".bool" @on.input="$setBool value" />
          #|  <p>String: <span class="o-str" @text=".str"></span></p>
          #|  <p>Number: <span class="o-num" @text=".num"></span></p>
          #|  <p>Boolean: <span class="o-bool" @text=".bool"></span></p>
          #|</section>
        ),
      ),
    },
    name="AttributeBinding",
    init=AttributeBindingState::{
      str: "hello",
      num: 42,
      bool: true,
      notSet: Null,
    },
    mutate={
      // parse-and-validate before writing: a bad number leaves state untouched
      // (JS: `Number.isNaN(n) ? this : this.setNum(n)`)
      "setRawNumber": (s : AttributeBindingState, args) => {
        let parsed : Int? = match args {
          [Str(v)] => Some(@string.parse_int(v)) catch { _ => None }
          [Num(n)] => Some(n.to_int())
          _ => None
        }
        match parsed {
          Some(n) => { ..s, num: n }
          None => s
        }
      },
    },
  )
}

///|
pub fn attribute_binding_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="attribute-binding",
    components=[attribute_binding_comp()],
    examples=[
      {
        component: "AttributeBinding",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}

///|
priv struct ConditionalAttributesState {
  isActive : Bool
} derive(ToJson, FromJson)

///|
/// `@if.class` tests a value, `@then`/`@else` supply the attribute. With a
/// single @if the @then/@else infer the attribute name; with several, the extra
/// ones must name it (`@then.title`) — HTML forbids duplicate attribute names.
fn conditional_attributes_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <button
          #|    @if.class=".isActive" @then="'btn btn-success'" @else="'btn btn-ghost'"
          #|    @if.title=".isActive" @then.title="'Click to disable'" @else.title="'Click to enable'"
          #|    @on.click="$toggleIsActive">
          #|    <span class="on" @show=".isActive">Enabled</span>
          #|    <span class="off" @hide=".isActive">Disabled</span>
          #|  </button>
          #|</section>
        ),
      ),
    },
    name="ConditionalAttributes",
    init=ConditionalAttributesState::{ isActive: true },
  )
}

///|
pub fn conditional_attributes_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="conditional-attributes",
    components=[conditional_attributes_comp()],
    examples=[
      {
        component: "ConditionalAttributes",
        title: "Active",
        args: { "isActive": Bool(true) },
        view: None,
      },
      {
        component: "ConditionalAttributes",
        title: "Inactive",
        args: { "isActive": Bool(false) },
        view: None,
      },
    ],
  )
}

///|
priv struct EventModifiersState {
  query : String
  lastSentSearch : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// Modifiers filter events: `+send` fires only on Enter, `+cancel` only on
/// Escape. `truthy?` is a built-in unary predicate, written predicate-first.
fn event_modifiers_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-3">
          #|  <input type="search" class="input" :value=".query"
          #|    @on.input="onInput value"
          #|    @on.keydown+send="$setLastSentSearch value"
          #|    @on.keydown+cancel="$resetQuery"
          #|    placeholder="Search Query (Enter to send, Esc to clear)" />
          #|  <p class="sent" @show="truthy? .lastSentSearch">
          #|    Search: "<span class="sent-q" @text=".lastSentSearch"></span>"
          #|  </p>
          #|</section>
        ),
      ),
    },
    name="EventModifiers",
    init=EventModifiersState::{ query: "", lastSentSearch: Null },
    update=(s : EventModifiersState, msg, _ctx) => {
      match msg {
        Input("onInput", [Str(v)]) => Some({ ..s, query: v })
        _ => None
      }
    },
  )
}

///|
pub fn event_modifiers_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="event-modifiers",
    components=[event_modifiers_comp()],
    examples=[
      { component: "EventModifiers", title: "Empty", args: Map([]), view: None },
      {
        component: "EventModifiers",
        title: "With Sent Search",
        args: { "query": Str("tutuca"), "lastSentSearch": Str("tutuca") },
        view: None,
      },
    ],
  )
}

///|
priv struct ShowHideState {
  isOpen : Bool
  count : Int
} derive(ToJson, FromJson)

///|
/// `@show` keeps the host element only when the value is truthy, `@hide` only
/// when falsy. The node is REMOVED from the output entirely (render returns
/// None), not hidden with CSS — see the README "Divergences" note. Both also
/// work directly on an `<x>` render op, wrapping the produced node with no
/// extra DOM.
fn show_hide_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-2">
          #|  <button class="btn btn-primary toggle-btn" @on.click="$toggleIsOpen" @text="$label"></button>
          #|  <div class="card p-3 border details" @show=".isOpen">
          #|    <p>Details panel &mdash; only visible when <code>isOpen</code> is true.</p>
          #|    <button class="btn btn-sm bump" @on.click="$incCount">Click me</button>
          #|    <p>Clicked <x text=".count"></x> times.</p>
          #|  </div>
          #|  <p class="text-sm opacity-60 hint" @hide=".isOpen">(details are hidden)</p>
          #|  <p class="peek">Count, only when open: <x text=".count" @show=".isOpen"></x></p>
          #|</section>
        ),
      ),
    },
    name="ShowHide",
    init=ShowHideState::{ isOpen: false, count: 0 },
    compute={
      "label": (s : ShowHideState, _args) => {
        if s.isOpen {
          Str("Hide details")
        } else {
          Str("Show details")
        }
      },
    },
    mutate={
      "incCount": (s : ShowHideState, _args) => { ..s, count: s.count + 1 },
    },
  )
}

///|
pub fn show_hide_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="show-hide", components=[show_hide_comp()], examples=[
    { component: "ShowHide", title: "Closed", args: Map([]), view: None },
    {
      component: "ShowHide",
      title: "Open",
      args: { "isOpen": Bool(true) },
      view: None,
    },
  ])
}
