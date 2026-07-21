// Port of docs/examples/styles-example.js.
//
// Three style slots, each scoped differently:
//   style       — this component + THIS view   ([data-cid=N][data-vid="main"])
//   commonStyle — this component, every view   ([data-cid=N])
//   globalStyle — injected verbatim, no scoping
//
// A handy consequence of the scoping wrapper: BARE declarations with no selector
// (`padding: …`) land directly inside it, so they style the component's ROOT
// element. Rules written with a selector target descendants instead.
//
// JS spells a per-view style as `views: { two: { view, style } }`; MoonBit keeps
// the two maps separate — `views` and `view_styles`, keyed by the same name.

///|
fn styles_example_comp() -> @component.Component {
  @component.component(
    name="StylesExample",
    view=(
      #|<section>
      #|  <p>View: main</p>
      #|  <p class="mine">My Style</p>
      #|  <p class="common">Common Style</p>
      #|  <p class="styles-example-global-class">Global Style</p>
      #|</section>
    ),
    views={
      "one": (
        #|<section>
        #|  <p>View: one</p>
        #|  <p class="mine">My Style</p>
        #|  <p class="common">Common Style</p>
        #|  <p class="styles-example-global-class">Global Style</p>
        #|</section>
      ),
      "two": (
        #|<section>
        #|  <p>View: two</p>
        #|  <p class="mine">My Style</p>
        #|  <p class="common">Common Style</p>
        #|  <p class="styles-example-global-class">Global Style</p>
        #|</section>
      ),
    },
    // view "two" overrides `.mine`: red in main/one, orange+underlined here
    view_styles={
      "two": (
        #|.mine { color: orange; text-decoration: underline; }
      ),
    },
    style=(
      #|.mine { color: red; }
    ),
    common_style=(
      #|padding: 0.75rem;
      #|border: 1px solid currentColor;
      #|border-radius: 0.5rem;
      #|.common { color: yellow; }
    ),
    global_style=(
      #|.styles-example-global-class { color: green; }
    ),
  )
}

///|
fn styles_example_root_comp() -> @component.Component {
  @component.component(
    name="StylesExampleRoot",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <x render=".value"></x>
      #|  <x render=".value" as="one"></x>
      #|  <x render=".value" as="two"></x>
      #|</section>
    ),
    fields={ "value": @component.FieldSpec::comp("StylesExample") },
  )
}

///|
pub fn styles_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="styles-example",
    components=[styles_example_root_comp(), styles_example_comp()],
    examples=[
      {
        component: "StylesExampleRoot",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}
