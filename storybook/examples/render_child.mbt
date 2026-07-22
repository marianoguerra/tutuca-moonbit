// Ports of docs/examples/render-child.js, docs/examples/entry.js and
// docs/examples/multiple-views.js — rendering a component from another
// component's field.
//
// Teaches: `<x render=".field">` renders a child component held in a field;
// `as="edit"` picks one of its named views. A rendered child gets a CLEAN
// namespace — the parent's @-bindings do not cross into it.

///|
priv struct GreetingState {
  name : String
} derive(ToJson, FromJson)

///|
fn greeting_comp() -> @component.Component {
  @component.component(
    name="Greeting",
    view=(
      #|<p class="p-2 border rounded">
      #|  Hello, <strong @text=".name"></strong>!
      #|</p>
    ),
    init=GreetingState::{ name: "world" },
  )
}

///|
priv struct RenderChildNoState {} derive(ToJson, FromJson)

///|
/// MoonBit divergence from JS: the child default is `FieldSpec::comp("Greeting",
/// args=...)` — a name resolved through the registration scope at make() time,
/// rather than JS's eagerly-built `Greeting.make({...})`. Same result, and it
/// keeps the component definitions order-independent.
fn page_comp() -> @component.Component {
  @component.component(
    name="Page",
    view=(
      #|<section class="flex flex-col gap-2">
      #|  <h2 class="text-lg">Page header</h2>
      #|  <x render=".greeting"></x>
      #|  <p class="opacity-60">&mdash; end of page &mdash;</p>
      #|</section>
    ),
    init=RenderChildNoState::{  },
    specs={
      "greeting": @component.FieldSpec::comp("Greeting", args={
        "name": Str("tutorial reader"),
      }),
    },
  )
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
priv struct EntryState {
  title : String
  description : String
} derive(ToJson, FromJson)

///|
/// The `Entry` building block (docs/examples/entry.js): a card with a read-only
/// `main` view and an `edit` view whose inputs two-way-bind the same fields.
/// Reused by multiple-views and push-view.
fn entry_comp() -> @component.Component {
  @component.component(
    name="Entry",
    view=(
      #|<div class="card bg-base-100 shadow-sm">
      #|  <div class="card-body">
      #|    <h2 class="card-title" @text=".title"></h2>
      #|    <p @text=".description"></p>
      #|  </div>
      #|</div>
    ),
    views={
      "edit": (
        #|<div class="card bg-base-100 shadow-sm gap-3">
        #|  <div class="card-body">
        #|    <input class="input title" :value=".title" @on.input="$setTitle value" />
        #|    <input class="input desc" :value=".description" @on.input="$setDescription value" />
        #|  </div>
        #|</div>
      ),
    },
    init=EntryState::{ title: "Entry Title", description: "Entry Description" },
    compute={
      "containsText": (s : EntryState, args) => {
        match args {
          [Str(v)] => Bool(s.title.contains(v) || s.description.contains(v))
          _ => Bool(false)
        }
      },
    },
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
    name="MultipleViews",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <x render=".value"></x>
      #|  <x render=".value" as="edit"></x>
      #|</section>
    ),
    init=RenderChildNoState::{  },
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
