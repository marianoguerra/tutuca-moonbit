# table — a `tutuca:component` guest

A typed data table as a WebAssembly component, and the reference consumer of
`tutuca:component/tables` — the shared table vocabulary the contract declares.
It holds one field of the standard `ty-table` type, sorts and pages it, and is
the thing that fails if that vocabulary does not work.

It carries more weight than a sample. `tables` declares types and **no
functions**, which is what makes the shared vocabulary free at runtime; the
price is that nothing generated moves a table across the boundary, so
[`../tables.mbt`](../tables.mbt) does it by hand. That codec's arena calls
cannot run outside a real guest, so this bundle plus
[`../../dyncomp/test/table-harness.test.mjs`](../../dyncomp/test/table-harness.test.mjs)
is the **only** runtime test it has.

What the harness pins down, because each one is a way the design could have been
quietly wrong:

- **the null asymmetry round-trips** — a missing value is inline `null` on the
  wire and a sparse `nulls` index list in the WIT, and a gap has to come back
  out where it went in;
- **`apply_command` is actually spoken** — sorting goes through the `command`
  variant, so the CQRS types are exercised rather than merely declared;
- **sorting moves whole rows** — a columnar table sorted one column at a time is
  the classic way to shred a dataset, so the check is that the other columns
  followed, nulls included.

Everything structural — layout, build, binding regeneration, the WIT source, the
toolchain pins and the Component Model gotchas — is identical to the counter
guest and documented once, in [`../counter/README.md`](../counter/README.md).
Only the component source differs:

- `gen/interface/tutuca/component/guest/table.mbt` — `TableView` behavior and factory
- `manifest.json` + `views/` — its schema/catalog declaration and template

```sh
node guests/build-guest.mjs table       # dist/table.component.wasm + dist/js/
node --test dyncomp/test/table-harness.test.mjs
```

## Two things this guest is shaped around

**`get_field` runs a lot** — once per `.name` a rendering view reaches for, on
every render. So the visible page is computed in `handle` and stored as plain
MoonBit data, and `get_field` only builds the arena value for what is already
decided. It cannot be cached further than that: an arena handle is valid only
for the duration of one host->guest call, so the `values.value` is rebuilt each
time even though its contents did not change.

**One `TY_TABLE` field is the whole point.** Because the type is standard, the
host projects a real JSON Schema for `data` — the column shape, the four cell
types, their ranges — instead of the titled-but-empty `$defs` stub every
`ty-record` gets, and `jsonschema/coerce_table.mbt` checks an agent's JSON
before this guest ever sees it, including the equal-width rule that no JSON
Schema can express.

## One surprise worth carrying elsewhere

MoonBit's `String::compare` orders by **length first**, then content. Sorting a
column of cities with `<` gives `Lima, Oslo, Athens, Berlin`. That is a fine
total order for a map key and a wrong one for anything a person reads, and it is
invisible until the strings in a column stop being the same length — so
`tables.mbt` spells lexicographic order out by hand in `str_cmp`.
