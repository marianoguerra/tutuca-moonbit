# `<script type="tutuca/examples">`

> **Status: a design, not a description.** Nothing below is implemented.
> Everything else in `docs/` documents shipped behaviour; this is a proposal,
> written after the two things that make it possible landed —
> `Value::from_component_json` (a `$component`-tagged document builds a TREE of
> instances through a resolver) and multi-component cards (a card has more than
> one name for such a document to resolve).

A card can be checked (`tutuca/test`) and it can be shown (`mountCompiled`).
What it cannot do is say **what it should be shown AS**. A gallery, a docs page
and a picker all want the same thing — a handful of named starting states, each
worth looking at — and today each of them either mounts the schema's zero or is
handed args by whoever embedded it.

```html
<script type="tutuca/examples">
{
  "an empty list": {
    "value": { "$component": "Todos", "draft": "", "items": [] }
  },
  "three rows, one done": {
    "doc": "What the list looks like once it has been used for a day.",
    "value": {
      "$component": "Todos",
      "draft": "",
      "items": [
        { "$component": "Todo", "text": "write the design", "done": true },
        { "$component": "Todo", "text": "read it back",     "done": false }
      ]
    }
  }
}
</script>
```

**The key is the title**, which is what the storybook already keys an example on
(`ExampleDef.title`) and what a picker shows. Not an identifier: it is a
sentence, it is allowed spaces, and two examples that would collide are two
examples that need different names anyway.

## Why this is new, and not `tutuca/init` again

`tutuca/init` names starting states too. It is not the same thing and should not
be merged with it:

| | `tutuca/init` | `tutuca/examples` |
|---|---|---|
| what a value IS | MoonBit **source**, spread over `State::zero()` | **JSON**, read by `Value::from_component_json` |
| how deep | one component's flat fields | a TREE — children, and their children |
| who consumes it | `gen-views`, at build time, writing a `make` call | a host, at run time, building instances |
| in the card manifest | **dropped** — "field values are MoonBit SOURCE and a manifest wants JSON" | carried, because it already is JSON |

That last row is the strongest argument for the shape. `DynComponentDef.inits`
exists, is parsed, is documented as "named initial states the guest declares" —
and `tutucard/wasm/manifest.mbt` emits an empty array into it with a comment
saying why. This block is JSON on both sides of that gap, so it fills the hole
rather than widening it.

`tutuca/init` stays. It is the ahead-of-time path's, and a view file that never
becomes a card still wants it.

## The optional keys

Each is proposed because something already established asks for it. Nothing here
is a knob for its own sake.

### `doc` — the sentence under the title

```json
"three rows, one done": { "doc": "…once it has been used for a day.", "value": … }
```

The title says which example; the doc says what it is FOR. `DynComponentDef` and
`DynInitDef` both carry one for exactly this reason, and a gallery with nothing
but names is a gallery nobody — person or model — can choose from.

### `view` — which view to render it under

```json
"a row on its own": { "value": { "$component": "Todo", … }, "view": "row" }
```

`ExampleDef.view` already is this, `None` meaning default resolution. It is the
one thing a document cannot say about itself: a `Todo` has a `main` and a `row`,
and which of them an example is about is a property of the EXAMPLE.

### `drive` — arrive at the state by doing

```json
"after three adds": {
  "drive": [
    { "type": "input.draft", "value": "one" }, { "click": "button.add" },
    { "type": "input.draft", "value": "two" }, { "click": "button.add" }
  ]
}
```

**The steps are `tutuca/test`'s, exactly** — the same eight verbs, the same
selector rule, the same `nth`. No new grammar, and adding a verb keeps adding it
in one place.

It earns its place by being the honest way to write most examples. "Three rows,
one done" hand-written as a document is a state a person asserts the component
can reach; driven, it is a state the component actually reached. It is also the
only way to show a state whose construction the card owns — a card builds its
children with `new`, so a `value` naming three `Todo`s is a host putting them
there, which is a different thing from the list having grown them.

`value` seeds and `drive` runs after it. Either may be omitted: no `value` means
the schema's zero, no `drive` means show what `value` says.

**A `drive` that fails must not silently show a half-driven card.** It answers
the `SceneResult` shape `tutuca/test` already returns — the failing step, both
values — because an example whose fourth step missed is a screenshot of
something nobody wrote.

### `intents` — the answers this example needs

```json
"the list, loaded": {
  "intents": { "rows": { "ok": [{ "text": "from the host" }] } },
  "drive": [{ "send": "init" }]
}
```

Same three answers, same shape, same synchronous rule as a scene's. An example
of a component that asks a host for data is not an example until something
answers, and a gallery that has to be taught each card's fixtures out of band is
a gallery that breaks when the card changes.

### `tags` — what a picker filters on

```json
"an empty list": { "tags": ["empty", "edge"], "value": … }
```

`DynComponentDef` has `keywords` and `category` for the same job one level up. A
card with twenty examples wants them; a card with three does not, which is why
it is optional and not a `category` string.

## Keys deliberately NOT proposed

- **`component`.** Redundant: `value.$component` says it, and for a `drive`-only
  example the card's root is the only sensible answer. A second place to say it
  is a second place for it to disagree.
- **`expect` / assertions.** That is `tutuca/test`. An example SHOWS and a scene
  CHECKS, and a block that did both would be two features sharing a name. The
  link goes the other way — see below.
- **`only` / `skip`.** Storybook has focus flags; they are state that outlives
  the reason for it, and a card is small enough to delete a line instead.
- **viewport / background / theme.** A card does not own the page it is shown
  in. A host that wants to frame an example can, and a card claiming a width
  would be a card with an opinion about somebody else's layout.

## What it feeds

1. **The manifest.** `DynComponentDef.inits`, which is parsed and always empty
   for a card today. Grouping is by `value.$component`, so a card declaring
   `Todos` and `Todo` gets its examples filed under the right one.
2. **The playground.** An Examples picker beside the Tests pane; choosing one
   re-mounts the preview at that state. The machinery exists — `Bundle::make_init`
   already builds a named init.
3. **`<mb-card example="three rows, one done">`.** A docs page embedding a card
   at the state the prose is about, rather than at the zero and a paragraph
   telling the reader to click twice.
4. **`tutuca/test`.** A scene gains `"example": "three rows, one done"` beside
   the `init` and `args` it already takes — so a state worth showing and a state
   worth testing are written once. This is the link between the two blocks, and
   it is one key rather than a shared grammar.

## What it would take

- `scenedef` grows `Example` beside `Scene`, and `parse_examples`. The step
  vocabulary is already there and is reused whole.
- `viewfile` recognises a sixth block: `ViewFile.examples`, `BadExamplesBlock`,
  `DuplicateExamplesBlock` — the same shape the fifth one took.
- `tutucard/wasm/manifest.mbt` emits them into `inits`, which needs
  `DynInitDef.args` to accept a tagged document rather than only flat fields —
  the one place the existing type has to widen.
- `tutucard/drive` grows `show(guest, manifest, example)`, which is `run_one`
  without the assertions: mount, seed, drive, answer the HTML.
- The host resolving `$component` for a card is `Bundle` as a
  `ComponentSource` — `build` is `make_instance`, `describe` is `schema_of`.
  Both exist; the impl is two methods.

The last one is the reason this is worth writing down now rather than later:
`ComponentSource` was designed for a page saving its own document, and a card's
bundle satisfies it without being asked to.
