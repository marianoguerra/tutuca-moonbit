# Tutuca — Advanced Topics

Reach this file only when the task touches drag & drop, context-style
"dynamic bindings", or custom collections. For compiling
Tailwind / MargaUI classes see [margaui.md](./margaui.md); for
everything else, `core.md` is the right place.

## Drag and Drop

```tutu
view:
  Card:
    each(value, key in it.items):
      div(draggable: "true", data_dragtype: "my-item", data_droptarget: "my-item", ~on_drop: on_drop(key, e.dragKey))
```

```moonbit nocheck
// nocheck: a state struct plus one bucket argument, not a whole component
priv struct DndState {
  items : Array[@tutuca.Value]
}

// in the component spec:
update=(s : DndState, msg, _ctx) => match msg {
  // args = [@key (the TARGET row's key), dragKey (the SOURCE row's)]
  Receive("onDrop", [Num(target), Num(source), ..]) =>
    Some({
      items: move_index_to_index(s.items, source.to_int(), target.to_int()),
    })
  _ => Unhandled
},
```

`data-dragtype` on the source and `data-droptarget` on the target pair a
draggable with where it may drop. `dragstart` captures the drag from the
**source** render — a `Map` of `value`, `type`, and `lookupBind(name)`
over the source's `each` binds — and every dispatch while the drag is
active can ask it for something, even though `drop` fires on the target
row.

Ask for the narrow name, the way `e.valueAsInt` sits beside `e.value`:
`e.dragKey` is the source row's `@key`, `e.dragValue` the dragged value,
`e.dragType` the type it declared. Each is `Null` when no drag is in
flight, so a `Msg` case carries `@tutuca.Value` for it.

`e.dragInfo` is the whole capture beside them, for a handler that needs a
bind the three do not name — and it is a wider argument in every sense,
since reading one off it means applying a function:

```moonbit nocheck
// nocheck: one bucket argument, not a whole component
update=(s : DndState, msg, _ctx) => match msg {
  Receive("onDrop", [_, Map(di), ..]) =>
    // Fn convention: element 0 is the this-slot
    match di.get("lookupBind") {
      Some(Fn(lookup)) =>
        match lookup([Null, Str("row")]) {
          Str(row) => Some({ items: [Str(row)] })
          _ => Unhandled
        }
      _ => Unhandled
    }
  _ => Unhandled
},
```

A **card** has only the narrow three: the block language has no way to
name a MoonBit value, so it cannot apply the `Fn` that `lookupBind`
answers with. The `drag-reorder` starter card is this page's example
with its handler written in a `logic:` section.

Tutuca auto-manages two attrs during a drag — style them with CSS:

```css
[data-dragging="1"] {
  opacity: 0.5;
}
[data-draggingover="my-item"] {
  outline: 1px dashed;
}
```

Touch is wired up in the browser glue too (a touch on a `[draggable]`
becomes a drag after a small move threshold).

> Port divergence — drop geometry: the JS original also measures the
> pointer against the target's bounding box to decide above vs below.
> The value layer exposes no DOM objects, so this port derives the drop
> side from the drag **direction** instead.

## Dynamic Bindings

For passing values "context-style" to a deep descendant without threading
them through every component in between. **`provide`** on the producer;
**`lookup`** on consumers; resolve as `dyn.<name>`.

> **Best practice:** keep state local to the component and reach for
> `provide` / `lookup` only when it is genuinely the only solution. Dynamic
> bindings couple a consumer to a producer that may not be in scope — prefer
> keeping components as self-contained as possible: let a child render the
> field it needs from its owner, and lift state only as far up the tree as it
> actually needs to live.

`theme.html` — both components in one view file, so one generated module:

```tutu
spec:
  Theme:
    field color :: String
    field body :: Instance.of(Child)

  Child

view:
  Theme:
    div():
      render(it.body)

  Child:
    p(style: @str{color: @(dyn.color)}):
      "themed"
```

`theme.mbt`:

```moonbit
///|
fn theme_comp() -> @component.Component {
  theme_component(initial={ ..ThemeState::zero(), color: "blue" }, provide={
    "color": ".color",
  })
}

///|
fn child_comp() -> @component.Component {
  child_component(lookup=[@component.lookup_or("color", "'gray'")])
}
```

A **`provide`** maps an exported name to a field expression (source
text). Every provide is evaluated and pushed onto the dynamic stack
automatically when the producer is entered during render — there is no
hook to opt in.

A **`lookup`** names what it WANTS, not who provides it. It is a LIST:
`@component.lookup_name("color")` is the whole declaration, and
`@component.lookup_or("color", "'gray'")` adds the fallback expression used
when no producer is above the consumer (without one, a miss resolves to
`null`). The local name IS the provided name — there is no alias. A `dyn.<name>`
resolves to the nearest binding above, which includes the component's own
`provide` (pushed on entering it).

More than one component may provide the same name. The live render stack is a
normal shadowing stack, so the nearest rendered provider wins.

### Dynamic vars as render targets

A `dyn.<name>` dynamic var resolves to a value, so it works anywhere a value
is read — not just in `:style` / `:class`, and including inside a `pred` or a
`compute` body. In particular it can be a component-render target and an
iteration source:

```tutu
view:
  Card:
    render(dyn.selected)
    " "
    comment(): " render the dynamic's component "
    " "
    render(dyn.selected, ~as: "edit")
    " "
    comment(): " a specific view of it "
    " "
    each(value, key in dyn.items):
      div():
        render(value)
    " "
    comment(): " iterate a dynamic seq "
```

A `provide` value must be **addressable** — a `it.field` or a `it.seq[key]`
seq-access, nothing else. It is both read as `dyn.<name>` *and* used as a
render-target / resume path, so a `$`-handler or constant — which has no
path — cannot work. `Component::compile` **drops a bad `provide`** rather
than raising on it, and the consumer's `dyn.<name>` then resolves to its
`default`, or to `null`; `ComponentStack::check_names` reports it as
`PROVIDE_NOT_ADDRESSABLE`. If a dynamic binding reads as its fallback
everywhere, run the checks and suspect the producer's expression first.
A `lookup` `default`, by contrast, is only a
value fallback and accepts the full value grammar, including constants
like `"gray"`. A `provide` can be a sequence/map item access:

```moonbit nocheck
// nocheck: a hand-written state type; its `@component.Fields` impl is omitted for brevity
priv struct RootState {
  items : Map[String, @tutuca.Value]
  selectedKey : String
}

fn root_comp() -> @component.Component {
  @component.component(
  views={
    // ... — from the view file
  },
  name="Root",
  // omitted
    initial=RootState::{ items: {}, selectedKey: "" },
  provide={
      "items": ".items",                  // the whole sequence
      "selected": ".items[.selectedKey]", // seq-access to one entry
    },
)
}
```

There is **no `*name[.key]` form** — a consumer never indexes a dynamic
var. The seq-access lives in the producer's `provide` declaration; the
consumer just reads the resolved value as `dyn.<name>`.

**Resuming at the value's path.** The component rendered via
`render(dyn.selected)` uses the concrete app path stored beside the dynamic
value. Rendering pushes that path as a continuation frame. An event inside the
subtree therefore mutates the selected value, while bubbling pops back to the
visual caller at the top of the frame. Editing it here and in the owner's own
view updates the same state in lock-step.

The same mechanism can start from lexical scope rather than a rendered
provider. Register lowercase names as absolute paths from the app state root:

```moonbit nocheck
// nocheck: module fragment; the target values still live in the one app root
@component.ModuleDef::new(
  name="workspace",
  components=[workspace_comp(), toolbar_comp()],
  paths={
    "session": @tutuca.Path::new(steps=[FieldStep("session")]),
    "theme": @tutuca.Path::new(steps=[FieldStep("theme")]),
  },
)
```

Descendants may declare `lookup_bare("session")` / `lookup_bare("theme")` and
read or render `*session` / `*theme`. The mounted root component does not have
to publish them, and no artificial `App` component is needed solely to push
ambient values. Register on a nested `ComponentStack` to scope a path more
tightly; nearest lexical registration wins. A rendered dynamic provider still
wins first under the default `dyn lex` lookup order.

### Publishing a component TYPE

An **uppercase** provide name publishes a component rather than a value, and
`"self"` is the only thing it can be:

```moonbit nocheck
// nocheck: a fragment; the surrounding component() call is omitted
provide={ "Cell": "self", "theme": ".theme" }
```

That injects the publisher as `Cell` for its whole subtree — a descendant that
builds a `Cell` gets the publisher's type rather than whatever is registered
under that name. A handler asks for one by name:

```moonbit nocheck
// nocheck: a handler fragment; `ctx` is the dispatch ctx
let cell = ctx.make("Cell", { "label": Str("x") }, @tutuca.LookupOpts::new())
```

The name goes in the consumer's `lookup` list too, so the checks can see it
(`UNKNOWN_COMPONENT_NAME` otherwise). Uppercase and lowercase names cannot
collide, which is why types and values share one binding frame.

A published type is **not** a render target: it has no path, so
`render(dyn.Cell)` stays unresolvable by construction.

### Routes: which environment answers

`ctx.lookup` and `ctx.make` take the same `route` an intent takes — the legs
in the order written, the first that resolves wins:

| leg   | environment                                                       |
|-------|-------------------------------------------------------------------|
| `dyn` | the render ancestry: what an ancestor published with `provide`     |
| `lex` | registered component types and app-root-relative value paths        |

`@tutuca.LookupOpts::new()` is `dyn lex`. `route=[Lex]` skips what was
published and reads the registration; `route=[Dyn]` refuses to fall back to it;
`route=[]` asks nothing. For lowercase names the lexical answer is the value at
the registered root path; for uppercase names it is the registered component
type. One route vocabulary therefore serves both calls.

Worked recipes:
[patterns/share-state-across-the-tree.md](./patterns/share-state-across-the-tree.md)
(the value-read side) and
[patterns/edit-through-a-dynamic-target.md](./patterns/edit-through-a-dynamic-target.md)
(seq-access provide, "edit the selected entry"). Runtime mechanics:
[semantics.md](./semantics.md) *Rendering with a resumed path*.

## A loop inside a `<select>` or a table

There is nothing to do here, and this section exists because there used to be.

The render ops compile to an `<x>` tag, and a browser's HTML parser drops an
unknown tag inside an element whose content model names its children — the
table family (`table`, `thead`, `tbody`, `tfoot`, `tr`, `colgroup`) and
`select` / `optgroup`. A loop written inside one of those was silently
stripped, and the old notation asked the author to write the workaround by
hand: an `@x` on a legal tag, which the parser keeps and tutuca reads as if it
were an `<x>`.

The printer knows the parent tag, so it writes that form itself:

```tutu
spec:
  Picker:
    field items :: List.of(Instance.of(Picker))

view:
  Picker:
    select():
      each(value, key in it.items):
        render(value, ~as: "option")
```

Everywhere else needs nothing either — `ul`, `ol`, `li`, `dl`, `dt`, `dd`,
`details`, `summary`, `caption`, `td`, `th` all keep an `<x>` as it is. The
rule of thumb, if you ever read the generated HTML: any element whose content
model only permits *specific* child tags borrows one of them.

## Custom collections

A custom collection is any struct implementing the `@tutuca.Obj` trait,
chiefly `seq_entries` (what `each` iterates, keyed) and `item`
(seq-access reads). There is nothing to register: the trait implementation IS
the registration. Full treatment with the worked `KeyedList` example
in [iteration.md](./iteration.md) *Custom collections — the `Obj`
trait*.

## There is no run-time module loading

A module is a `ModuleDef` **value** the project links, not something a CLI
discovers on disk; see [cli.md](./cli.md). The storybook ships as a library and
a gallery is compiled from those values — `tutuca new-storybook` scaffolds the
page, `tutuca storybook` serves what it builds, and the stories are a projection
of your modules' own `examples`. See [storybook.md](./storybook.md).

## Tailwind / MargaUI Class Compilation

Moved to [margaui.md](./margaui.md) — collecting the class set with
`collect_classes()`, the MoonBit compile step, `inject_style`, and the
assembled-class-names decoy-view pitfall.
