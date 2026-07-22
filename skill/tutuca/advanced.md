# Tutuca — Advanced Topics

Reach this file only when the task touches drag & drop, context-style
"dynamic bindings", pseudo-`x` (the `<x>`-stripping workaround inside
`<select>`/`<table>`/`<tr>`), or custom collections. For compiling
Tailwind / MargaUI classes see [margaui.md](./margaui.md); for
everything else, `core.md` is the right place.

## Drag and Drop

```html
<div
  @each=".items"
  draggable="true"
  data-dragtype="my-item"
  data-droptarget="my-item"
  @on.drop="onDrop @key dragInfo"
></div>
```

```moonbit
priv struct DndState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

// in the component spec:
update=(s : DndState, msg, _ctx) => match msg {
  // args = [@key (the TARGET row's key), dragInfo]
  Input("onDrop", [Num(target), Obj(di), ..]) =>
    // dragInfo is an Obj exposing type / value / lookupBind(name) — read
    // the SOURCE row's loop key off the drag's captured stack (Fn
    // convention: element 0 is the this-slot)
    match di.obj_field("lookupBind") {
      Some(Fn(lookup)) =>
        match lookup([Null, Str("key")]) {
          Num(source) =>
            Some({
              items: move_index_to_index(
                s.items,
                source.to_int(),
                target.to_int(),
              ),
            })
          _ => None
        }
      _ => None
    }
  _ => None
},
```

`data-dragtype` on the source and `data-droptarget` on the target pair a
draggable with where it may drop. `dragstart` captures a `DragInfo` from
the **source** render — its `value`, its `type`, and `lookupBind(name)`
over the source's `@each` binds — and every dispatch while the drag is
active sees it as the `dragInfo` handler arg, even though `drop` fires
on the target row.

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
> side from the drag **direction** instead (see `examples/dnd.mbt`).

## Dynamic Bindings

For passing values "context-style" to a deep descendant without threading
them through every component in between. **`provide`** on the producer;
**`lookup`** on consumers; resolve as `*name`.

> **Best practice:** keep state local to the component and reach for
> `provide` / `lookup` only when it is genuinely the only solution. Dynamic
> bindings couple a consumer to a producer that may not be in scope — prefer
> keeping components as self-contained as possible: let a child render the
> field it needs from its owner, and lift state only as far up the tree as it
> actually needs to live.

```moonbit
priv struct ThemeState {
  color : String
} derive(ToJson, FromJson)

fn theme_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view="<div><x render=\".child\"></x></div>"),
  },
  name="Theme",
  init=ThemeState::{ color: "blue" },
  specs={ "child": @component.FieldSpec::comp("Child") },
  provide={ "color": ".color" },
)
}

priv struct NoState {} derive(ToJson, FromJson)

fn child_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view="<p :style=\"$'color: {*color}'\">themed</p>"),
  },
  name="Child",
  init=NoState::{  },
  lookup={ "color": { source: "Theme.color", default: Some("'gray'") } },
)
}
```

A **`provide`** maps an exported name to a field expression (source
text). Every provide is evaluated and pushed onto the dynamic stack
automatically when the producer is entered during render — there is no
hook to opt in.

A **`lookup`** reads a value the `*name` way: the map key is the name
used in views (`*color`), the value is a `LookupSpec` —
`{ source: "Producer.provideName", default: Some("...") }` — where
`default` supplies a fallback expression for when no producer is in
scope (`None` → a miss resolves to `null`). (The JS spelling
`{ for: "...", default: "..." }` becomes `source` here.) A `*name` that
names the component's own `provide` resolves to the nearest provided
value (including its own).

### Dynamic vars as render targets

A `*name` dynamic var resolves to a value, so it works anywhere a value
is read — not just in `:style` / `:class`. In particular it can be a
component-render target and an iteration source:

```html
<x render="*selected"></x>           <!-- render the dynamic's component -->
<x render="*selected" as="edit"></x> <!-- a specific view of it -->
<div @each="*items"><x render-it></x></div>  <!-- iterate a dynamic seq -->
```

A `provide` value must be **addressable** — a `.field` or a `.seq[.key]`
seq-access, nothing else. (It is both read as `*name` *and* used as a
render-target / teleport path, so a `$`-handler or constant — which has no
path — is a lint error.) A `lookup` `default`, by contrast, is only a
value fallback and accepts the full value grammar, including constants
like `'gray'`. A `provide` can be a sequence/map item access:

```moonbit
priv struct RootState {
  items : Map[String, @tutuca.Value]
  selectedKey : String
} derive(ToJson, FromJson)

fn root_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=...),
  },
  name="Root",
  // omitted
    init=RootState::{ items: {}, selectedKey: "" },
  provide={
      "items": ".items",                  // the whole sequence
      "selected": ".items[.selectedKey]", // seq-access to one entry
    },
)
}
```

There is **no `*name[.key]` form** — a consumer never indexes a dynamic
var. The seq-access lives in the producer's `provide` declaration; the
consumer just reads the resolved value as `*name`.

**Teleporting.** The component rendered via `<x render="*selected">`
physically lives at the producer (e.g. `Root.items`), not under the
consumer. When an event fires inside that dynamically-rendered subtree,
the runtime expands the *render* path (consumer → … → the rendered
node) to reconstruct the handler, but the *transaction* is teleported:
the mutation skips the intermediate components and lands on the
producer's data. Editing the entry in the consumer and the same entry
in the producer's own view update in lock-step.

Worked examples: `examples/dynamic.mbt` (both the value-read side and
the teleporting render target) and `examples/dynamic_selected_edit.mbt`
(seq-access provide, "edit the selected entry"). Runtime mechanics:
[semantics.md](./semantics.md) *Dynamic-var teleporting*.

## Pseudo-`x` (`@x`)

Tutuca's special operations (`render`, `render-it`, `render-each`, `text`,
`show`, `hide`, `slot`) live on the `<x>` tag. That works almost
everywhere, but the browser's HTML parser refuses to keep `<x>` (or any
unknown tag) as a child of certain elements. Drop `<x render-each>`
inside one of those and the parser silently strips it.

The parser strips `<x>` only inside the **table family** and **`<select>`**.
Use pseudo-`@x` when the parent is one of:

`table`, `thead`, `tbody`, `tfoot`, `tr`, `colgroup`, `select`, `optgroup`.

Everywhere else `<x>` is kept and needs no workaround — including `ul`, `ol`,
`li`, `dl`, `dt`, `dd`, `details`, `summary`, `caption`, `td`, `th`. So
`<ul><x render-each=".items">…</x></ul>` is fine. (When in doubt, the rule of
thumb is: any element whose HTML content model only permits *specific* child
tags — table sections and `<select>` — strips `<x>`.)

The escape hatch: prefix the **first** attribute on a *legal* tag with
`@x`. Tutuca treats that tag as if it were `<x>` and reads the next
attribute as the special op.

```html
<!-- ❌ <x> stripped by the HTML parser inside <select> -->
<select>
  <x render-each=".items" as="option"></x>
</select>

<!-- ✅ pseudo-x: <option @x render-each=".items" as="option"> -->
<select>
  <option @x render-each=".items" as="option"></option>
</select>
```

Notes:

- `@x` must be the **first** attribute; the special op (`render-each`,
  `render`, `text`, `show`, ...) is the second.
- The host tag (here `<option>`) is otherwise ignored — only the special
  op runs. Tutuca produces the rendered children directly.
- Same trick works inside any of the stripping parents listed above
  (`<table>`/`<tr>`/`<colgroup>`/`<select>`/…).

(Worked example: `examples/pseudo_x.mbt`.)

## Custom collections

The JS `SEQ_INFO` prototype walker does not exist in this port — a
custom collection is any struct implementing the `@tutuca.Obj` trait,
chiefly `obj_seq_entries` (what `@each` iterates, keyed) and `obj_item`
(seq-access reads). Full treatment with the worked `KeyedList` example
in [iteration.md](./iteration.md) *Custom collections — the `Obj`
trait*, ported from `examples/custom_collection.mbt`.

## Not in this port

- **JS-side module loading** (`import()`-based CLI module input,
  `*.dev.js` discovery) — modules are `ModuleDef` **values** and the CLI is
  embedded in a project binary; see [cli.md](./cli.md). The storybook is
  ported (`storybook/` + `demo/storybook_wasm`), but as a compiled gallery
  of the example registry rather than scanned `*.dev.js`; `tutuca storybook`
  serves that pre-built bundle.
- **`SEQ_INFO` registration** — replaced by the `Obj` trait (above).

## Tailwind / MargaUI Class Compilation

Moved to [margaui.md](./margaui.md) — collecting the class set with
`collect_classes()`, the CDN compile step, `inject_style`, and the
assembled-class-names decoy-view pitfall.
