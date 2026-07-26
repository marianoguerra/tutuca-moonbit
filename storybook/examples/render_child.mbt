// Ports of docs/examples/render-child.js, docs/examples/entry.js and
// docs/examples/multiple-views.js — rendering a component from another
// component's field.
//
// Teaches: `<x render=".field">` renders a child component held in a field;
// `as="edit"` picks one of its named views. A rendered child gets a CLEAN
// namespace — the parent's @-bindings do not cross into it.

///|
fn greeting_comp() -> @component.Component {
  @component.component(
    views=greeting_views(),
    name="Greeting",
    init=GreetingState::{ name: "world" },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=greeting_encode,
    decode=greeting_decode,
  )
}

///|
/// MoonBit divergence from JS: the child default is `FieldSpec::comp("Greeting",
/// args=...)` — a name resolved through the registration scope at make() time,
/// rather than JS's eagerly-built `Greeting.make({...})`. Same result, and it
/// keeps the component definitions order-independent.
fn page_comp() -> @component.Component {
  @component.component(views=page_views(), name="Page", init=PageState::{  }, specs={
    "greeting": @component.FieldSpec::comp("Greeting", args={
      "name": Str("tutorial reader"),
    }),
  })
}

///|
pub fn render_child_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="render-child",
    components=[page_comp(), greeting_comp()],
    examples=[
      { component: "Page", title: "Default", args: Map([]), view: None },
    ],
  )
}

///|
/// The `Entry` building block (docs/examples/entry.js): a card with a read-only
/// `main` view and an `edit` view whose inputs two-way-bind the same fields.
/// Reused by multiple-views and push-view.
fn entry_comp() -> @component.Component {
  @component.component(
    views=entry_views(),
    name="Entry",
    init=EntryState::{ title: "Entry Title", description: "Entry Description" },
    compute={
      "containsText": (s : EntryState, args) => {
        match args {
          [Str(v)] => Bool(s.title.contains(v) || s.description.contains(v))
          _ => Bool(false)
        }
      },
    },
    // The schema-generated direct codec, in place of the JSON bridge.
    encode=entry_encode,
    decode=entry_decode,
  )
}

///|
pub fn entry_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="entry", components=[entry_comp()], examples=[
    { component: "Entry", title: "Default", args: Map([]), view: None },
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
  @component.component(
    views=multiple_views_views(),
    name="MultipleViews",
    init=MultipleViewsState::{  },
    specs={ "value": @component.FieldSpec::comp("Entry") },
  )
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
