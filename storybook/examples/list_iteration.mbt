// Port of docs/examples/list-iteration.js.
//
// Teaches: `@each=".items"` repeats the host element once per entry. Inside the
// loop `@key` is the index (List) or key (Map) and `@value` is the item — local
// bindings, read with the `@` prefix.

///|
priv struct ListIterationState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn list_iteration_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section>
          #|  <ul>
          #|    <li @each=".items"><span class="k" @text="@key"></span>: <x text="@value"></x></li>
          #|  </ul>
          #|</section>
        ),
      ),
    },
    name="ListIteration",
    init=ListIterationState::{ items: [] },
  )
}

///|
pub fn list_iteration_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-iteration",
    components=[list_iteration_comp()],
    examples=[
      {
        component: "ListIteration",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
      {
        component: "ListIteration",
        title: "Empty",
        args: { "items": List([]) },
        view: None,
      },
      {
        component: "ListIteration",
        title: "Custom Items",
        args: { "items": List([Str("one"), Str("two"), Str("three")]) },
        view: None,
      },
    ],
  )
}
