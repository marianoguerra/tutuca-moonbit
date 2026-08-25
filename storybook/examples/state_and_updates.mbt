// The "State and Updates" tutorial examples:
//
//   :attr bindings + $'templates'           (attribute binding)
//   @if.attr / @then / @else                (conditional attributes)
//   @on.keydown+send / +cancel              (event modifiers)
//   @show / @hide
//
// Note the event modifiers tutuca actually defines. Guards: keydown takes
// send/cancel/ctrl/cmd/meta/alt, click takes ctrl/cmd/meta/alt; an unknown
// guard is the identity (it does not gate the handler). Effects: +prevent
// calls preventDefault and +stop calls stopPropagation when the handler
// runs — on any event, gated by any guards written beside them.

///|
/// `:attr=".field"` binds state into any attribute; `$'…{.field}…'` is a string
/// template. Typing calls the GENERATED `setStr`; the number input goes through
/// a hand-written `setRawNumber` that parses and validates first.
fn attribute_binding_comp() -> @component.Component {
  attribute_binding_component(
    init={ str: "hello", num: 42, bool: true, notSet: Null },
    update=(
      // Parse-and-validate before writing: a bad number leaves state untouched.
      // The payload is typed
      // `String` by the generator — every call site passes one — so the
      // untyped two-branch unpack is gone.
      s,
      msg,
      _ctx,
    ) => {
      match AttributeBindingMsg::from_dispatch(msg) {
        Some(SetRawNumber(v)) =>
          match (Some(@string.parse_int(v)) catch { _ => None }) {
            Some(n) => Next({ ..s, num: n })
            // A bad number leaves the state untouched — and `Unchanged`, not
            // `Unhandled`, because this arm claimed `setRawNumber`.
            None => Unchanged
          }
        // Served by the generated mutators for `str` and `bool`.
        Some(SetStr(_)) | Some(SetBool(_)) => Unhandled
        Some(Unknown(_, _)) | None => Unhandled
      }
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
/// `@if.class` tests a value, `@then`/`@else` supply the attribute. With a
/// single @if the @then/@else infer the attribute name; with several, the extra
/// ones must name it (`@then.title`) — HTML forbids duplicate attribute names.
fn conditional_attributes_comp() -> @component.Component {
  conditional_attributes_component(init={ isActive: true })
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
  event_modifiers_component(init={ query: "", lastSentSearch: Null }, update=(
    s,
    msg,
    _ctx,
  ) => {
    match EventModifiersMsg::from_dispatch(msg) {
      // Served by the mutators generated from the state's fields: the
      // view spells them bare now, so they arrive as Inputs, and `Unhandled`
      // falls through to them.
      Some(ResetQuery | SetLastSentSearch(_)) => Unhandled
      Some(OnInput(v)) => Next({ ..s, query: v })
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
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
/// `@show` keeps the host element only when the value is truthy, `@hide` only
/// when falsy. The node is REMOVED from the output entirely (render returns
/// None), not hidden with CSS — see the README "Divergences" note. Both also
/// work directly on an `<x>` render op, wrapping the produced node with no
/// extra DOM.
///
/// Neither button needs an arm: `toggleIsOpen` is the generated toggle for a
/// Bool field, and `incCount` is one line in the file's
/// `<script type="tutuca/script">` block. `$label` stays here because a
/// `compute` is answered by the render stack, which is not what that block
/// compiles.
fn show_hide_comp() -> @component.Component {
  show_hide_component(init={ isOpen: false, count: 0 }, compute=m => {
    match m {
      Label =>
        Some((s, _args, _stack) => {
          if s.isOpen {
            Str("Hide details")
          } else {
            Str("Show details")
          }
        })
    }
  })
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
