// Four of the smallest tutorial examples, which exist to show that
// nearly everything about a component is optional:
//
//   component({})             — no view at all
//   a static view             — a view, no state
//   @text / <x text>          — the text directive
//   set-inner-html            — the raw-HTML escape hatch

///|
/// The smallest component there is: no fields, no view, no logic. It renders
/// nothing visible — the point is that it is legal.
///
/// MoonBit divergence: `views~` is a required argument, so "no view" is an
/// empty `<template>` in basics.html rather than JS's absent key.
fn minimum_viable_comp() -> @component.Component {
  minimum_viable_component_component()
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
  static_view_component_component()
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
/// `@text` on an element PREPENDS text into it (keeping its other children);
/// `<x text=...>` is a standalone text node that adds no element. The value can
/// be a field (`.str`) or a method call (`$getStrUpper`), and every value type
/// renders: strings, numbers, booleans, null.
fn text_directive_comp() -> @component.Component {
  text_directive_component(
    initial={ str: "hello", num: 42, bool: true, notSet: Null, },
    compute=m => {
      match m {
        GetStrUpper => Some((s, _args, _stack) => Str(s.str.to_upper()))
      }
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
/// The escape hatch: `@dangerouslysetinnerhtml` sets the element's innerHTML
/// from a field instead of building children.
fn danger_set_inner_html_comp() -> @component.Component {
  danger_set_inner_html_component(initial={
    content: "<strong><em>Raw HTML!</em></strong>",
  })
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

///|
/// The safe sibling: `@setinnermd` takes markdown SOURCE and replaces the
/// element's children with the nodes it parses to. No permission to grant and
/// no escape hatch — the markdown never becomes an HTML string, and every
/// element and attribute value it produces is judged by the app's own
/// sanitizer on the way out. See docs/sanitizer.md.
fn set_inner_md_comp() -> @component.Component {
  set_inner_md_component(initial={
    source: "# Markdown\n\nWith *emphasis*, `code`, and a [link](/docs).\n\n- and\n- a list\n",
  })
}

///|
pub fn set_inner_md_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="set-inner-md",
    components=[set_inner_md_comp()],
    examples=[
      { component: "SetInnerMd", title: "Default", args: Map([]), view: None, },
      {
        component: "SetInnerMd",
        title: "GFM",
        args: {
          "source": Str(
            "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n- [x] task lists\n- [ ] and footnotes[^1]\n\n[^1]: like this\n",
          ),
        },
        view: None,
      },
      // The half worth looking at: none of this renders, and the reason is the
      // same sanitizer that judges every other node in the tree.
      {
        component: "SetInnerMd",
        title: "Sanitized",
        args: {
          "source": Str(
            "<script>alert(1)</script>\n\n<svg><script>alert(2)</script></svg>\n\n<iframe src=\"https://example.com\"></iframe>\n\n<div onclick=\"alert(3)\">handler dropped</div>\n\n[keeps its words, loses its href](javascript:alert(4))\n",
          ),
        },
        view: None,
      },
    ],
  )
}
