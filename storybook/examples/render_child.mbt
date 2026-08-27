// Rendering a component from another
// component's field.
//
// Teaches: `<x render=".field">` renders a child component held in a field;
// `as="edit"` picks one of its named views. A rendered child gets a CLEAN
// namespace — the parent's @-bindings do not cross into it.

///|
fn greeting_comp() -> @component.Component {
  greeting_component(init={ name: "world", })
}

///|
/// MoonBit divergence from JS: the child is a DECLARED slot — the state block
/// says `greeting: greeting`, naming the sibling interface, and the name is
/// resolved through the registration scope at make() time rather than eagerly
/// built the way JS's `Greeting.make({...})` is. Same result, and it keeps the
/// component definitions order-independent. The arguments it is built with are
/// the one part no type states, so they stay here.
fn page_comp() -> @component.Component {
  page_component(slot_args={ "greeting": { "name": Str("tutorial reader") } })
}

///|
pub fn render_child_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="render-child",
    components=[page_comp(), greeting_comp()],
    examples=[
      { component: "Page", title: "Default", args: Map([]), view: None, },
    ],
  )
}

///|
/// The `Entry` building block: a card with a read-only
/// `main` view and an `edit` view whose inputs two-way-bind the same fields.
/// Reused by multiple-views and push-view.
fn entry_comp() -> @component.Component {
  // `containsText` is declared in this file's `tutuca/script` block, which is
  // what puts it in `EntryMethod` — no view of Entry calls it; the `@when` of
  // a PARENT does. Its body is compiled from the block, so there is no
  // `compute~` argument here.
  entry_component(init={
    title: "Entry Title",
    description: "Entry Description",
  })
}

///|
pub fn entry_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="entry", components=[entry_comp()], examples=[
    { component: "Entry", title: "Default", args: Map([]), view: None, },
    {
      component: "Entry",
      title: "Custom",
      args: {
        "title": Str("Hello"),
        "description": Str("A custom entry description"),
      },
      view: None,
    },
  ])
}

///|
/// Renders the SAME Entry instance twice: once through its default `main` view,
/// once through `as="edit"`. Editing the inputs updates both, because they are
/// one value.
fn multiple_views_comp() -> @component.Component {
  multiple_views_component()
}

///|
pub fn multiple_views_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="multiple-views",
    components=[multiple_views_comp(), entry_comp()],
    examples=[
      {
        component: "MultipleViews",
        title: "Default",
        args: Map([]),
        view: None,
      },
    ],
  )
}
