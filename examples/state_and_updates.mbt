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
/// `:attr=".field"` binds state into any attribute; `$'…{.field}…'` is a string
/// template. Typing calls the GENERATED `setStr`; the number input goes through
/// a hand-written `setRawNumber` that parses and validates first.
fn attribute_binding_comp() -> @component.Component {
  @component.component(
    name="AttributeBinding",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input class="input s" :value=".str" @on.input="$setStr value" :title="$'Content is {.str}'" />
      #|  <input class="input n" type="number" :value=".num" @on.input="$setRawNumber value" />
      #|  <input class="checkbox b" type="checkbox" :checked=".bool" @on.input="$setBool value" />
      #|  <p>String: <span class="o-str" @text=".str"></span></p>
      #|  <p>Number: <span class="o-num" @text=".num"></span></p>
      #|  <p>Boolean: <span class="o-bool" @text=".bool"></span></p>
      #|</section>
    ),
    fields={
      "str": @component.FieldSpec::of_default(Str("hello")),
      "num": @component.FieldSpec::of_default(Num(42)),
      "bool": @component.FieldSpec::of_default(Bool(true)),
      "notSet": @component.FieldSpec::of_default(Null),
    },
    methods={
      // parse-and-validate before writing: a bad number leaves state untouched
      // (JS: `Number.isNaN(n) ? this : this.setNum(n)`)
      "setRawNumber": (inst, args) => {
        let parsed : Int? = match args {
          [Str(s)] => Some(@string.parse_int(s)) catch { _ => None }
          [Num(n)] => Some(n.to_int())
          _ => None
        }
        match parsed {
          Some(n) => inst.set("num", Num(n.to_double())).to_value()
          None => inst.to_value()
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
      { component: "AttributeBinding", title: "Default", args: {}, view: None },
    ],
  )
}

///|
/// `@if.class` tests a value, `@then`/`@else` supply the attribute. With a
/// single @if the @then/@else infer the attribute name; with several, the extra
/// ones must name it (`@then.title`) — HTML forbids duplicate attribute names.
fn conditional_attributes_comp() -> @component.Component {
  @component.component(
    name="ConditionalAttributes",
    view=(
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
    fields={ "isActive": @component.FieldSpec::of_default(Bool(true)) },
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
/// Modifiers filter events: `+send` fires only on Enter, `+cancel` only on
/// Escape. `truthy?` is a built-in unary predicate, written predicate-first.
fn event_modifiers_comp() -> @component.Component {
  @component.component(
    name="EventModifiers",
    view=(
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
    fields={
      "query": @component.FieldSpec::of_default(Str("")),
      "lastSentSearch": @component.FieldSpec::of_default(Null),
    },
    input={
      "onInput": (inst, args, _ctx) => {
        match args {
          [Str(v)] => Some(inst.set("query", Str(v)))
          _ => None
        }
      },
    },
  )
}

///|
pub fn event_modifiers_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="event-modifiers",
    components=[event_modifiers_comp()],
    examples=[
      { component: "EventModifiers", title: "Empty", args: {}, view: None },
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
/// `@show` hides the host element when the value is falsy, `@hide` when truthy.
/// The element stays in the DOM — only visibility toggles. Both also work
/// directly on an `<x>` render op, wrapping the produced node with no extra DOM.
fn show_hide_comp() -> @component.Component {
  @component.component(
    name="ShowHide",
    view=(
      #|<section class="flex flex-col gap-2">
      #|  <button class="btn btn-primary toggle" @on.click="$toggleIsOpen" @text="$label"></button>
      #|  <div class="card p-3 border details" @show=".isOpen">
      #|    <p>Details panel &mdash; only visible when <code>isOpen</code> is true.</p>
      #|    <button class="btn btn-sm bump" @on.click="$incCount">Click me</button>
      #|    <p>Clicked <x text=".count"></x> times.</p>
      #|  </div>
      #|  <p class="text-sm opacity-60 hint" @hide=".isOpen">(details are hidden)</p>
      #|  <p class="peek">Count, only when open: <x text=".count" @show=".isOpen"></x></p>
      #|</section>
    ),
    fields={
      "isOpen": @component.FieldSpec::of_default(Bool(false)),
      "count": @component.FieldSpec::of_default(Num(0)),
    },
    methods={
      "label": (inst, _args) => {
        match inst.get("isOpen") {
          Bool(true) => Str("Hide details")
          _ => Str("Show details")
        }
      },
      "incCount": (inst, _args) => {
        match inst.get("count") {
          Num(n) => inst.set("count", Num(n + 1)).to_value()
          _ => inst.to_value()
        }
      },
    },
  )
}

///|
pub fn show_hide_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="show-hide", components=[show_hide_comp()], examples=[
    { component: "ShowHide", title: "Closed", args: {}, view: None },
    {
      component: "ShowHide",
      title: "Open",
      args: { "isOpen": Bool(true) },
      view: None,
    },
  ])
}
