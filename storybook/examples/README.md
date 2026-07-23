# storybook/examples

MoonBit ports of the JS docs examples (`docs/examples/*.js` in the tutuca
repo), one file per topic. Each exports a `<name>_module() -> ModuleDef` — the
analogue of the JS module's `getComponents` / `getMacros` /
`getRequestHandlers` / `getExamples` exports.

These modules are the story set for the storybook gallery: the parent
`storybook/` package groups them into sections and `storybook/ui` mounts the
whole registry as one live gallery app.

One `ModuleDef` value drives three things, so a passing test and a working page
are the same artifact:

- the **headless tests** here (`*_test.mbt`) — mount the module as a live app on
  the in-memory DOM, dispatch real click/input/keydown/drag events through the
  transactor, and assert the resulting DOM;
- the **storybook gallery** (`storybook/` + `storybook/ui`, hosted by
  `demo/storybook_wasm`) — grouped into sections and mounted as one app;
- the **CLI** (`cli.plan_with_module`) — `render`, `lint`, `show`.

## Running them

```sh
moon test storybook/examples           # the headless suite
# the whole gallery, compiled to wasm and served:
moon run --target native cmd/dev -- dist
./dist/cli/tutuca storybook            # or serve dist/ and open /storybook/
```

## Porting rules (how a JS example becomes a MoonBit one)

Views port **verbatim** — the generated field mutators keep their JS camelCase
names (`setX`, `toggleX`, `pushInX`, `removeInXAt`), so the template strings are
copied across unchanged. What changes is the JS *around* the view:

| JS | MoonBit |
|---|---|
| `component({name, view, fields, …})` | `@component.component(name~, views~, init~, …)` |
| `fields: { count: 0 }` | a `derive(ToJson, FromJson)` state struct passed as `init=State::{ count: 0 }` |
| `fields: { kid: Kid.make({…}) }` | `specs={ "kid": FieldSpec::comp("Kid", args={…}) }` — resolved through the registration scope at `make()` time |
| `methods: { m() {…} }` | `mutate={ "m": (s, args) => S }` (state change) or `compute={ "m": (s, args) => Value }` (value read) — both **pure** |
| `input`/`receive`/`bubble`/`response` | one `update=(s, dispatch, ctx) => S?` match — `None` = no change |
| `statics: { fromData }` | a plain `fn` — nothing in the framework calls statics, in either language |
| `@on.click="onAddItem Item"` (a component as an arg) | the handler **captures** the `Component` in its closure; the view just calls `onAddItem` |
| `ctx.at.field("x").send(n, a)` | `ctx.send_at_path(ctx.path().concat([FieldStep("x")]), n, a)` |
| `app.sendAtRoot("init")` | `app.send_at_root("init")` |
| `async` request handler | `RequestFn((args, respond) => …)` — callback-style, `respond(Ok(v))` / `respond(Err(e))` |

**Handlers that need `ctx` go in `update` (or `swap`), not `mutate`/`compute`.**
JS appends `ctx` to every dispatched handler, so a `methods.submit(ctx)` can
send messages. MoonBit keeps `mutate`/`compute` pure — they are also evaluated
in value positions like `@text="$label"`, where no event exists — and gives
`ctx` to `update` and `swap`, which are the effectful paths.

## What is ported

Every JS docs example: basics, state & updates, collections, rendering,
macros, graphics, communication, dynamics, drag & drop, styles, lint errors,
custom collections, the file picker and web-component hosts, and all three big
apps (`json`, `personal-site`, `visual-wasm`) — 51 modules across 32 files, all
covered by interaction tests. See `all_examples()` in `examples.mbt` for the
list, in tutorial order.

The big apps needed the runtime patterns the smaller examples established, at
scale: a `reg` map for the mutual recursion / lookup-table dispatch (`json`'s 8
types, `visual-wasm`'s ~75 components), self-replacement handlers, `^handler`
macro indirection, and Map-backed sets standing in for `ISet`
(`personal-site`). `visual-wasm` also drove the one remaining generated-mutator
gap — `insertInItemsAt` — into the runtime.

## Ported with divergences

- **`storybook.js`** — the JS gallery is ported, but lives in its own
  `storybook/` package (a compiled gallery of this registry) and is served by
  `tutuca storybook`, not as an example here.
- **`lint-errors.js`** — ported as `lint_errors.mbt`, minus the JS sections
  whose rules are statically impossible in MoonBit (`ASYNC_HANDLER`,
  `UNKNOWN_COMPONENT_SPEC_KEY`, …) and the input-handler rules that typed
  `update` makes unenumerable. See the file header for the full list.
- **`file-picker.js`, `web-component-custom-event.js`** — the value layer
  exposes no DOM objects, so the app glue converts what the JS handlers read
  off the event (a `File`'s metadata, a `CustomEvent`'s `detail`) into a
  `Value::Map` first.

## Not ported

- **`testing-example.js`** — its point is the JS `getTests()` harness, which has
  no MoonBit counterpart (`moon test` is the harness here).

## Divergences worth knowing

- **`@show` / `@hide` REMOVE the node.** They do not toggle visibility — both JS
  (`anode.js` `ShowNode.render` returns `null`) and this port omit the node from
  the output. The JS tutorial's prose says otherwise; the code does not.
- **A null `@text` renders nothing**, not `"null"` — JS's vdom `addChild` drops
  null children (`vdom.js:113`), and this port matches.
- **Drag geometry.** JS measures the pointer against the target's bounding box to
  drop above vs below. The value layer exposes no DOM objects, so `dnd.mbt`
  derives the side from the drag direction instead.
