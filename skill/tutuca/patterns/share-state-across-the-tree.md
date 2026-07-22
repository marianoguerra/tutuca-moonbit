# Share state across the tree

**Problem:** a deep descendant needs a value owned by a distant ancestor, and
you don't want to thread it through every component in between.

> **Reach for this last.** Keep state local to the component and use
> `provide` / `lookup` only when it is genuinely the only solution — a value
> owned far away that a deep descendant needs and nothing in between should
> know about. Dynamic bindings couple a consumer to a producer that may not be
> in scope, so keep components as self-contained as possible: let a child
> render the field it needs from its owner, and lift state only as far up the
> tree as it needs to live.

```moonbit
priv struct ItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

// producer — exposes one of its fields under a name
fn producer_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=...),
  },
  name="EntryEditorAndSelector",
  // omitted
    init=ItemsState::{ items: [] },
  provide={ "entries": ".items" },
)
}

// consumer — forwards to the producer's binding by "Component.name"
fn consumer_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<select class="select">
      #|  <option @each="*entries" :value="@value.value" @text="@value.label"></option>
      #|</select>
    )),
  },
  name="Selector",
  init=ItemsState::{ items: [] },
  lookup={
      "entries": {
        source: "EntryEditorAndSelector.entries",
        default: Some(".items"),
      },
    },
)
}
```

`provide` publishes a field under a name; a descendant's `lookup` resolves
`*name` to the nearest matching producer, falling back to the `default`
expression when none is in scope (`None` → `null`). `*name` works wherever a
`.field` does for iteration/rendering. This is the **read** side; to edit the
producer's value through the dynamic, see the edit-through-a-dynamic-target
recipe. Runnable version: `examples/dynamic.mbt` (dynamic-bindings).
