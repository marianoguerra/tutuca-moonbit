// Ports of the four smallest tutorial examples, which exist to show that
// nearly everything about a component is optional:
//
//   docs/examples/minimum-viable-component.js — component({}), no view at all
//   docs/examples/static-view-component.js    — a view, no state
//   docs/examples/text-directive.js           — @text / <x text>
//   docs/examples/danger-set-inner-html.js    — the raw-HTML escape hatch

///|
priv struct BasicsNoState {} derive(ToJson, FromJson)

///|
/// The smallest component there is: no fields, no view, no logic. It renders
/// nothing visible — the point is that it is legal.
///
/// MoonBit divergence: `views~` is a required argument, so "no view" is an
/// empty `<template>` in basics.html rather than JS's absent key.
fn minimum_viable_comp() -> @component.Component {
  @component.component(
    views=minimum_viable_component_views(),
    name="MinimumViableComponent",
    init=BasicsNoState::{  },
  )
}

///|
pub fn minimum_viable_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="minimum-viable-component",
    components=[minimum_viable_comp()],
    examples=[
      {
        component: "MinimumViableComponent",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}

///|
/// A view with no dynamic content and no state. Works, but for purely static
/// markup a macro is the better fit (see macros.mbt).
fn static_view_comp() -> @component.Component {
  @component.component(
    views=static_view_component_views(),
    name="StaticViewComponent",
    init=BasicsNoState::{  },
  )
}

///|
pub fn static_view_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="static-view-component",
    components=[static_view_comp()],
    examples=[
      {
        component: "StaticViewComponent",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}

///|
priv struct TextDirectiveState {
  str : String
  num : Int
  bool : Bool
  notSet : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// `@text` on an element PREPENDS text into it (keeping its other children);
/// `<x text=...>` is a standalone text node that adds no element. The value can
/// be a field (`.str`) or a method call (`$getStrUpper`), and every value type
/// renders: strings, numbers, booleans, null.
fn text_directive_comp() -> @component.Component {
  @component.component(
    views=text_directive_views(),
    name="TextDirective",
    init=TextDirectiveState::{ str: "hello", num: 42, bool: true, notSet: Null },
    compute={
      "getStrUpper": (s : TextDirectiveState, _args) => Str(s.str.to_upper()),
    },
  )
}

///|
pub fn text_directive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="text-directive",
    components=[text_directive_comp()],
    examples=[
      {
        component: "TextDirective",
        title: "Defaults",
        args: Map([]),
        view: None,
      },
      {
        component: "TextDirective",
        title: "Custom Values",
        args: { "str": Str("tutuca"), "num": Num(100), "bool": Bool(false) },
        view: None,
      },
    ],
  )
}

///|
priv struct DangerSetInnerHtmlState {
  content : String
} derive(ToJson, FromJson)

///|
/// The escape hatch: `@dangerouslysetinnerhtml` sets the element's innerHTML
/// from a field instead of building children.
fn danger_set_inner_html_comp() -> @component.Component {
  @component.component(
    views=danger_set_inner_html_views(),
    name="DangerSetInnerHtml",
    init=DangerSetInnerHtmlState::{
      content: "<strong><em>Raw HTML!</em></strong>",
    },
  )
}

///|
pub fn danger_set_inner_html_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="danger-set-inner-html",
    components=[danger_set_inner_html_comp()],
    examples=[
      {
        component: "DangerSetInnerHtml",
        title: "Default",
        args: Map([]),
        view: None,
      },
      {
        component: "DangerSetInnerHtml",
        title: "Custom Markup",
        args: {
          "content": Str("<h3>Title</h3><ul><li>One</li><li>Two</li></ul>"),
        },
        view: None,
      },
    ],
  )
}
