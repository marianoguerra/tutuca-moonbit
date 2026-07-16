// Ports of the four smallest tutorial examples, which exist to show that
// nearly everything about a component is optional:
//
//   docs/examples/minimum-viable-component.js — component({}), no view at all
//   docs/examples/static-view-component.js    — a view, no state
//   docs/examples/text-directive.js           — @text / <x text>
//   docs/examples/danger-set-inner-html.js    — the raw-HTML escape hatch

///|
/// The smallest component there is: no fields, no view, no logic. It renders
/// nothing visible — the point is that it is legal.
///
/// MoonBit divergence: `view~` is a required argument, so "no view" is spelled
/// as the empty string rather than JS's absent key.
fn minimum_viable_comp() -> @component.Component {
  @component.component(name="MinimumViableComponent", view="")
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
        args: {},
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
    name="StaticViewComponent",
    view=(
      #|<p>Hello, world!</p>
    ),
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
        args: {},
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
  @component.component(
    name="TextDirective",
    view=(
      #|<div class="grid grid-cols-[auto_auto] gap-x-4 gap-y-2 items-center">
      #|  <span>String:</span> <span class="v-str" @text=".str"></span>
      #|  <span>Number:</span> <span class="v-num" @text=".num"> &lt;- text directive is prepended</span>
      #|  <span>Boolean:</span> <x text=".bool"></x>
      #|  <span>notSet:</span> <span class="v-notset" @text=".notSet"></span>
      #|  <span>Method Call:</span> <span class="v-method" @text="$getStrUpper"></span>
      #|</div>
    ),
    fields={
      "str": @component.FieldSpec::of_default(Str("hello")),
      "num": @component.FieldSpec::of_default(Num(42)),
      "bool": @component.FieldSpec::of_default(Bool(true)),
      "notSet": @component.FieldSpec::of_default(Null),
    },
    methods={
      "getStrUpper": (inst, _args) => {
        match inst.get("str") {
          Str(s) => Str(s.to_upper())
          _ => Null
        }
      },
    },
  )
}

///|
pub fn text_directive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="text-directive",
    components=[text_directive_comp()],
    examples=[
      { component: "TextDirective", title: "Defaults", args: {}, view: None },
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
  @component.component(
    name="DangerSetInnerHtml",
    view=(
      #|<section>
      #|  <div class="raw" @dangerouslysetinnerhtml=".content"></div>
      #|</section>
    ),
    fields={
      "content": @component.FieldSpec::of_default(
        Str("<strong><em>Raw HTML!</em></strong>"),
      ),
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
        args: {},
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
