# The example corpus, as cards

What happens if you take every example in this repo and try to run it as a
**card** — the same view file, interpreted at mount instead of compiled.

The question is worth asking precisely because the two paths read the same
file. Where a card cannot run one, the gap is either a language feature that is
missing or a design decision that says no on purpose, and it is worth knowing
which.

The numbers below come from running `__tutucard.check` over
`storybook/examples/*.html` and `playground/site/examples/*.html` — 41 files —
first whole, then split into the components they declare.

## Whole files

**13 of 41** load as a card unchanged. The other 28 are refused, and almost all
for one reason:

| Refusal | Files |
| --- | --- |
| `a card is one component, but this file declares …` | 24 |
| `a card needs at least one <template>` | 4 |

Neither is about the language. A view file is allowed to declare a module's
worth of components, and most of the corpus does — `json.html` declares eight,
`dynamic.html` seven. The four with no template are macro libraries
(`macros.html`, `todo_macros.html`), a lint fixture, and the wasm demo that
builds its views at run time.

## Components

Split into components, the picture changes: **109 components**, of which

| | count | |
| --- | --- | --- |
| **could stand alone as a card** | **60** | the whole file's behaviour fits the block language, or is already in it |
| render children | 26 | `<x render>` / `render-each` / `render-it` |
| refused because the schema names a sibling component | 23 | `state Page { greeting : Greeting }` |
| something else | 0 | |

The last two rows are the same blocker seen from two sides: a card cannot hold
a child component, so neither the view that renders one nor the schema that
declares one can load. **49 of 109 are blocked by exactly one missing feature.**

Nothing else in the corpus blocks anything. There is no example that fails
because the handler language is too small, which is worth saying plainly: the
36 components that "need handlers written" need them written in
`tutuca/script` instead of MoonBit, and every one of those handlers is
expressible today.

## What was migrated

Nine examples are in the card playground's selector now, beside the four
starters it already had — `tutucard/web/examples.js`, which
`check-examples.mjs` loads through the real loader on every build, and which I
drove in a browser one by one:

| card | from | what the migration cost |
| --- | --- | --- |
| `traffic-light` | `conditionals/TrafficLight` | `$light` indexed a MoonBit array; the card spells the same mapping as nested `if`s |
| `tabs` | `conditionals/TabbedUI` | nothing — every handler was already a generated mutator |
| `show-hide` | `state_and_updates/ShowHide` | `$label` moved from MoonBit into a `compute` |
| `attributes` | `state_and_updates/AttributeBinding` | the number input takes `valueAsInt` instead of a handler that parsed the string |
| `modifiers` | `state_and_updates/EventModifiers` | nothing — `+send` and `+cancel` are guards, and all three handlers are mutators |
| `scope` | `collections/RenderWithScope` | `@upper` became `@lower`: the reading vocabulary has `lower` and no `upper` |
| `list-enrich` | `collections/ListFilterEnrich` | `when` and `enrich` became a `pred` and an `enrich`, unchanged in substance |
| `list-iteration` | `list_iteration` | seeded by `receive init`, since a card starts at the schema's zero |
| `markdown` | `playground/site/examples/markdown` | the seed is one line: a block string literal has `\'` and `\\` and no `\n` |

Two of those rows are the only places a card could not say what the MoonBit
said — `upper`, and a multi-line string — and both are one-line additions to
the language rather than design questions.

## The rest, grouped

### Easy: nothing is missing, the handlers just have to be written

31 components. Each is a single component whose whole behaviour the block
language can express; what stands between them and the selector is someone
porting an `update` arm, which is the work the nine above show the shape of.

`basics/`: MinimumViableComponent, StaticViewComponent, TextDirective,
DangerSetInnerHtml, SetInnerMd · `communication/Status` ·
`conditionals/ListAndFilter` · `state_and_updates/ConditionalAttributes` ·
`custom_collection/Song` · `dynamic/`: SelectorEntry, Selector, Sheet ·
`dynamic_selected_edit/DseEntry` · `file_picker` ·
`filter_paginate/Person` · `graphics/`: SwatchPicker, Quadratic · `json/`:
JsonSelector, JsonNull, JsonBool, JsonString, JsonNumber ·
`personal_site/AltUrl` · `pseudo_x/`: TableRow, ItemTable, SelectOption,
ItemSelect · `render_child/`: Greeting, Entry · `styles/StylesExample` ·
`todo/Item` · site: `counter`, `text_input`, `toggle`

Worth saying about two of them: the five `json/` leaves and
`render_child/Entry` are the *children* of demos that a card cannot assemble —
each is a perfectly good card on its own, and the tree above it is not.

### Hard: blocked on a feature

| what it needs | components | examples |
| --- | --- | --- |
| **child components** | 49 | `json` (the tree), `todo/Items`, `tree`, `composability`, `dynamic` (Panel, Workspace, EntryEditorAndSelector), `dynamic_selected_edit` (DseRoot, DseEditor), `personal_site` (Root, PsEntry), `filter_paginate` (NaivePeople, Shared, Coupled, Strategies), `pseudo_x/PseudoXDemo`, `render_child` (Page, MultipleViews), `rendering` (PushView, SeqItemAccess), `custom_collection/Playlist`, `communication` (TreeRoot, TreeItem), `styles/StylesExampleRoot`, `request` |
| ~~a record literal~~ — **`new` landed; `nested-state` is migrated** | 0 | what is left of this group is the multi-component half of `todo` and `filter_paginate`, which is the row above |
| **`@loop-with`** | 4 | `rendering/Pagination`, `svg_more/BarChart`, `collections/ListFilterEnrichWith`, `filter_paginate`'s three strategies |
| ~~macros in a card~~ — **landed; `macros` is migrated** | 0 | the loader carries `<template id="macro:…">` through to the module now |
| ~~a narrower drag argument~~ — **landed; `drag-reorder` is migrated** | 0 | `dnd` was the one example blocked on it; the design below is what shipped |
| **host-registered requests** | 1 | `request` — it loads today and shows the error path, which is honest but is not the demo |
| **nothing; a card is the wrong shape** | 2 | `visual_wasm` builds its views at run time, `lint_errors` is a fixture of deliberately broken ones |

Two small language gaps surfaced by the migration itself, and both are fixed:
`upper` joins `lower` in the reading vocabulary, and `\n` / `\t` / `\r` join
`\'` and `\\` as escapes a string literal carries — in ONE table both the slot
and the block lexer read, so the two cannot drift. (A literal could always span
lines as itself; what was missing was the one-line spelling.) The `scope` and
`markdown` cards say what they meant now rather than what they could.

## What each blocked group needs

### 1. A card that is more than one component — by far the biggest win

Blocks 49 of 109 components, including every interesting demo: the JSON tree,
the todo list, `personal_site`, `dynamic`, `filter_paginate`, `tree`.

**Design.** Two changes, and neither touches the language.

*The loader.* `@tutucard.load` refuses a file with more than one component
(`ManyComponents`). It already receives a `ViewFile` holding all of them, and
`Component::for_type` is per component — so the refusal is the only thing in
the way. `load` would build a `Deck` per component, return a `Card` carrying an
`Array[Component]` and the name of the FIRST as the root, and register them all
in one scope. A schema field typed `Greeting` resolves through that scope at
`make()` time, which is what `component/component.mbt:158-200` already does for
generated components: the slot is filled by NAME through the registration
scope, and a card's names are now in it.

*The host.* `mount_at` builds a `ModuleDef` with one component; it would take
the array. `check` needs no change beyond dropping the arity guard.

The card stays "one FILE, one component tree", which is the honest reading of
what a card is — a page of examples is one file each, and the tutorial's cards
stay single-component because that is what they teach.

Cost: moderate, and contained to `tutucard/`. No new syntax.

### 2. A record literal

Blocks appending to an `Array[Struct]` — `todo/Items` builds `Item` values,
`filter_paginate` builds `Person` rows. Today a card can read, index and write
THROUGH such an array but never grow one, which is why every list example in
the tutorial holds `Array[String]`.

**Design.** The block language has no literal for a record because it has no
type syntax at all: every type comes from the schema. That is also what makes
the feature small — the schema already names the struct and its fields, so the
literal needs no annotation:

```
on add {
  .items.push { text: (trim .draft), done: false }
}
```

The checker knows the element type of `.items` and checks the pairs against
`struct Item`'s fields — missing fields take the field's zero, an unknown field
is a finding, a wrong type is a finding. The interpreter builds a `Map`, which
is what a record already is at run time; `emit_mbt` builds `Item::{ … }`, which
it can already spell (`spread` writes one today).

Cost: small, and it is the one addition that would make cards a fair vehicle
for the list examples.

### 3. `@loop-with`

Blocks `rendering/Pagination` and `filter_paginate`'s three strategies — the
loop handler that answers a slice and the shared per-loop data.

**Design.** A `loopWith name { … }` declaration whose body answers the
`LoopWith` record: `start`, `end`, `keys?`, `iterData?`. It is the one bucket
whose return value is a STRUCTURE rather than a value, so it wants the record
literal from (2) first — which is a good reason to do them in that order.

### 4. Macros in a card — DONE

`@viewfile.split_file` had been returning `file.macros` all along and
`@tutucard.load` dropped them, so `<x:badge>` in a card rendered as an unknown
element. The `Card` carries them now and the host hands them to
`ModuleDef::new(macros~)` — the same path a generated module's macros take,
rather than a second one for cards. Twenty lines, no language change, and the
`macros` card in the selector is the four macro demos that had to live in
MoonBit until it landed: a parameter with a default, a dynamic parameter, the
default slot, and a named one.

### 4b. A narrower drag argument — DONE

`dnd` was the last example blocked by something small. Its drop handler reads
the SOURCE row's key, and the only way to ask for it used to be:

```moonbit nocheck
// nocheck: the arm as `playground/site/examples/dnd.mbt` writes it
Some(OnDropOnItem(Num(t), Obj(di))) => {
  let source = match di.obj_field("lookupBind") {
    Some(Fn(lookup)) => match lookup([Null, Str("key")]) { … }
```

`dragInfo` is an `Obj` carrying `type`, `value`, and a `lookupBind(name)`
FUNCTION (`app/drag.mbt`), because the source's binds only exist on the stack
the drag captured. A block cannot apply a function it did not name, and it
should not learn how to: "no way to name a MoonBit value" is the sentence the
whole language rests on.

**What shipped: ask for the narrowest argument, the way every other event
already does.** `value` has `valueAsInt` and `valueAsFloat` beside it precisely
so a handler never parses a string; the same move here adds three names to the
closed table in `render/dom_event.mbt`:

| name | answers |
| --- | --- |
| `dragKey` | the source row's `@key` — `lookup_bind(stack, "key")` |
| `dragValue` | the dragged value itself (`dragInfo.value`) |
| `dragType` | the `data-dragtype` the source declared |

The card is then the view plus four statements, with no new syntax anywhere —
`drag-reorder` in the selector, which is this and a filter:

```html
<div @each=".items" draggable="true"
     data-dragtype="row" data-droptarget="row"
     @on.drop="moveRow @key dragKey"></div>
```

```
on moveRow(target, source) {
  if source is not target {
    if source < target {
      .items.insertAt (target + 1) .items[source]
      .items.deleteAt source
    } else {
      .items.insertAt target .items[source]
      .items.deleteAt (source + 1)
    }
  }
}
```

Both arms read `.items[source]` before they mutate, and the second index
accounts for the shift the first one caused — which is the whole of what the
MoonBit arm does after it has finished unwrapping the `Fn`.

Cost, as estimated and as spent: three lines in one table, and the same three
in the generated backend's argument-type inference — where all three are
`@tutuca.Value`, as `@key` is, because every one of them is `Null` when no drag
is in flight. It improves the MoonBit side too, where
`di.obj_field("lookupBind")` is nobody's idea of a readable handler; the skill's
drag recipe leads with `dragKey` now and keeps the `Fn` as the wide fallback.

`dragInfo` stays exactly as it is: a handler that needs the whole stack still
has it, and this is the narrow answer beside it — which is what the events
documentation already tells people to reach for.

### 5. Request handlers a page can register

`request.html` works today only in the sense that it shows the error path (the
card tutorial's step 7 uses exactly that). A page that wants a card to fetch
something has no way to answer it.

**Design.** `__tutucard.mount(id, source, name, requests?)` taking a map of
name → JS callback, wrapped as `RequestFn` on the `ModuleDef`. `<mb-card>`
would take them from a `<script type="application/json">` fixture beside it, or
a JS property. This is a HOST feature, not a language one.

### 6. Views built at run time

`visual_wasm.html` has no `<template>` because its views are assembled by
MoonBit. Nothing to do here: that is the case the compiler exists for, and a
card is the wrong shape for it. Same for `lint_errors.html`, which is a fixture
of deliberately broken views.

## The order I would do them in

1. **Multi-component cards** — unblocks 49 components, no new syntax.
2. **Record literals** — unblocks every list-of-records example, small.
3. **Macros** — cheap, and a card that repeats markup has no other answer.
4. **`@loop-with`** — after records, since it answers one.
5. **Registered requests** — a host feature, worth having when a card needs to
   talk to something.

## Method

Reproduce with:

```sh
node tutucard/build/check-examples.mjs          # the cards that ship
```

and, for the survey, `__tutucard.check(source, name)` over each file — the same
entry point a build step or an agent would use, which is the point of it being
a separate call from `mount`.
