# Named states a card can be shown at

> **Status: a design, not a description.** The block below is a proposal. What
> HAS shipped is the half it stands on: `<script type="tutuca/init">` now
> reaches a card's manifest, so `"init": "fresh"` in a `tutuca/test` scene
> resolves. Everything else in `docs/` documents shipped behaviour.

## The correction this document exists to record

An earlier draft proposed a sixth block, `tutuca/examples`, on the grounds that
`tutuca/init` held MoonBit source and a manifest wants JSON.

**That was wrong.** `tutuca/init` is JSON — `parse_init` calls `@json.parse` and
raises `NotJson`. What is MoonBit source is `InitState.fields`, a projection
`statedef` makes for the generator to write into a `make` call. The loss
happened on the way to the card compiler, not in the file.

And `tutuca/init` is already **many** named states, not one:

```html
<script type="tutuca/init">
{ "fresh": { "label": "Counter" },
  "with-history": { "label": "Demo", "count": 3, "history": [1, 2, 3] } }
</script>
```

`gen-views` emits one `State::<name>()` per fixture plus
`<v>_init_args(name)` — whose own doc-comment says "a storybook needs the
encoded form anyway". **It is already the example list.** A second block for
named starting states would have been two features sharing a job.

So: one block. What follows is what it would take to grow, not what to replace
it with.

## What shipped

`InitState` keeps `args : Map[String, Value]` beside the MoonBit source, and the
card manifest emits the fixtures into `DynComponentDef.inits` — which was parsed
and documented and always empty for a card.

That was a live defect, not a gap. A scene could say `"init": "fresh"`, the
runner read the manifest's `inits`, found nothing, and answered *"no
`tutuca/init` fixture called `fresh`; this component declares none"* — for every
card, however the block was written. The key was documented and could not work.

## What a card still cannot say

Three things, and each is a key rather than a block:

### 1. A state with CHILDREN

A fixture's value is a flat field map, so it cannot describe a list with two
rows in it. `Value::from_component_json` reads a `$component`-tagged document
into a tree, and a card now declares more than one component for such a document
to name.

That needs somewhere to put it, which means the fixture gains an envelope:

```json
{
  "fresh": { "value": { "label": "Counter" } },

  "three rows": {
    "doc": "What the list looks like once it has been used.",
    "value": { "$component": "Todos", "items": [
      { "$component": "Todo", "text": "write it", "done": true },
      { "$component": "Todo", "text": "read it",  "done": false } ] }
  }
}
```

**The envelope keys are plain.** `value`, `doc`, `drive` sit one level ABOVE the
field names — they are the format's own vocabulary, describing the fixture,
where the field names describe the component. Nothing can collide, so nothing
needs a sigil. `$component` needs its `$` for the opposite reason: it sits
INSIDE an object whose other keys are field names, and a component with a field
called `component` would otherwise be undecidable.

**And the envelope is the only form.** A bare `"fresh": { "label": "Counter" }`
would be nicer for the common case, and keeping it as a shorthand is what forces
a sigil back: two shapes in one position need telling apart, and the only ways
are a sigil or sniffing the keys against the schema. The second is decidable
today — `parse_init` already refuses a key that is not a declared field — and
its failure mode is a component that later ADDS a field called `value` and
silently changes how its existing fixtures parse. That is a bad trade for one
level of nesting.

The migration is two files: `demo/counterlib/counter.html` and
`tutucard/wasm/examples/Guarded.html`. That is the whole of what
`tutuca/init` has in this repo, which is what makes choosing the better shape
affordable rather than a breaking change to argue about.

### 2. `drive` — arrive at the state by doing

```json
{ "after three adds": { "drive": [
    { "type": "input.draft", "value": "one" }, { "click": "button.add" } ] } }
```

The steps are `tutuca/test`'s, exactly: the same eight verbs, the same selector
rule, the same `nth`. No second grammar, and adding a verb keeps adding it once.

It earns its place by being the honest form for a card that builds its own
children. `new` is how a list grows a row, so a `value` naming three `Todo`s is
a HOST placing them — a different thing from the list having grown them, and the
difference is exactly what a reader is looking at.

`value` seeds and `drive` runs after it; either may be omitted. A `drive` that
fails answers the `SceneResult` shape rather than showing a half-driven card,
because a fixture whose fourth step missed is a screenshot of something nobody
wrote.

### 3. `doc`, `view`, `intents`, `tags`

- **`doc`** — the sentence under the title. `DynInitDef` and `DynComponentDef`
  both carry one; a gallery with nothing but names is one nobody can choose
  from.
- **`view`** — which view to render it under, `ExampleDef.view`'s job. The one
  thing a document cannot say about itself: a `Todo` has a `main` and a `row`.
- **`intents`** — the answers this state needs, in a scene's shape. A component
  that asks a host for data is not an example until something answers.
- **`tags`** — what a picker filters on, `DynComponentDef.keywords` one level
  down. Optional because a card with three fixtures does not need it.

### And which one is the DEFAULT

Today nothing is: a card mounts at the schema's zero and the fixtures are named
but unreferenced. `default: true` on one, or — matching `data-root`, which
solved the same question a week earlier — **the first is the default and a
marker overrides it.** Consistency argues for the second.

## Keys deliberately NOT proposed

- **`component`.** Redundant: the document's own `$component` says it, and for
  a `drive`-only fixture the card's root is the only sensible answer.
- **Assertions.** That is `tutuca/test`. A fixture SHOWS and a scene CHECKS, and
  the link between them already exists in the direction that costs nothing — a
  scene names a fixture.
- **A sigil on any of these.** The keys are one level above the field names and
  are the format's own; `$component` earns its `$` by sitting among field names,
  and copying it here would be a device applied for looking like the other one.
- **`only` / `skip`.** State that outlives the reason for it.
- **viewport / background / theme.** A card does not own the page it is shown
  in.

## What it would take

- `statedef/init_block.mbt` reads the envelope: `value` through
  `from_component_json` rather than field-by-field, and the rest into new
  `InitState` fields. The schema check stays for an untagged value and becomes
  the resolver's job for a tagged one. Two files migrate.
- `DynInitDef` grows the same fields; `parse_inits` reads them.
- `tutucard/drive` grows `show(guest, manifest, name)` — `run_one` without the
  assertions: mount, seed, drive, answer the HTML.
- A host resolving `$component` for a card is `Bundle` as a `ComponentSource`:
  `build` is `make_instance`, `describe` is `schema_of`. Two methods, both
  already there under other names.

That last one is why this is worth writing down: `ComponentSource` was designed
for a page saving its own document, and a card's bundle satisfies it without
being asked to.
