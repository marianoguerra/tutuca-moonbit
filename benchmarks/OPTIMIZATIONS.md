# Performance log

One entry per measured change, in the order they landed. Method:
`node benchmarks/report.mjs [--target native]` on wasm-gc and native, back to
back, before and after (`--save` / `--baseline` do the bookkeeping); for a change
under ~5% — and for ANY change whose size is comparable to this machine's
run-to-run drift — the affected bench file is run 3× on each side with the two
sides **alternating in one loop** (stash, measure, pop, measure) and the medians
compared. Non-interleaved runs have shown ±10% swings on benchmarks the change
could not touch; see #6. A
change that does not move a number gets reverted, not kept "because it should be
faster".

Every entry leaves output unchanged. For the view pipeline that means the
workload checksums (`viewparse_bench_test.mbt` pins them) plus `cmd/dev --
gen-views` followed by `git diff --exit-code`; for the runtime it means the full
test suite (890 default / 890 native / 8 js browser), a good
number of which are DOM snapshots.

# The view pipeline

## Baseline — 2026-07-25, `7def62d`

Mean of 10 × N runs, both corpora (108 small views / the same nodes as one
enormous view).

| Stage     | many-views wasm-gc | native   | one-big-view wasm-gc | native   |
|-----------|--------------------|----------|----------------------|----------|
| `split`   |  4.10 ms           |  3.58 ms |  —                   |  —       |
| `surface` |  8.67 ms           |  8.14 ms |  —                   |  —       |
| `build`   |  8.42 ms           |  8.10 ms |  —                   |  —       |
| `gen`     | 26.66 ms           | 23.21 ms |  —                   |  —       |

Where the time goes (js/V8 profile, self time — the wasmtime profile agrees on
the ranking but over-weights `moonbit.string_literal`):

```
many views                          one big view
 9.2%  JSArray::push                16.3%  JSArray::push
 9.2%  (garbage collector)          10.2%  (garbage collector)
 6.7%  html::Tokenizer::new          5.7%  String::to_array
 5.6%  html::Tokenizer::next_token   4.6%  html::Tokenizer::next_token
 4.3%  String::to_array              3.5%  viewgen::slice_without_styles
 3.4%  viewgen::split_file           3.2%  viewgen::split_file
 2.4%  viewgen::slice_without_styles 2.1%  html::TreeBuilder::parse
 2.4%  html::TreeBuilder::in_body    1.8%  anode::from_element
 1.9%  html::TreeBuilder::parse      1.6%  html::insert_character
 1.6%  viewgen::dedent               1.5%  viewgen::dedent
```

Reading it: about a third of `gen` is the HTML parser, reached once per view —
and `gen` reached it *three* times per view. The rest is `split_file`'s own
slicing plus string building in the emitters. One big view shifts the cost from
per-view setup (`Tokenizer::new` drops out of the top ten) into array growth and
slicing, and is mildly superlinear in its own size (see #2).

## 1. Emit the IR module without asking first — `gen` −16% / −18%

`cli/gen_views.mbt` ran `if ir_supported(file) { emit_ir_module(...) }`. Both
halves compile every view through `compiled_tree`, so the question cost as much
as the answer: together with `emit_module` → `view_surface`, every view was
parsed and compiled **three times** per job.

`emit_ir_module_opt` does both in one pass — emitting IS the check, and the
failure it catches is the same one that made `ir_supported` answer false. Output
is all-or-nothing: the builder is discarded with the error. `ir_supported`
stays for callers that only want to know.

| Stage       | wasm-gc              | native               |
|-------------|----------------------|----------------------|
| `gen`       | 26.66 → 22.35 ms −16.2% | 23.21 → 18.91 ms −18.5% |

Other stages untouched — they never called the pair.

## 2. `slice_without_styles` copies runs, not chars — `split` −6%

(tw-mb technique #6.) Recovering a view's source walked the span one char at a
time and, for *every* char, scanned the whole style-region array looking for one
that starts there:

```moonbit
while i < end_ {
  for s in styles { if s.start == i { i = s.end_; ... } }
  sb.write_char(chars[i]); i = i + 1
}
```

That is `chars × regions` per view, so `file_chars × file_regions` overall — and
both factors grow with a view file, which is the superlinearity the scaling
probe showed (`scaling_bench_test.mbt`: 4× one view's size cost 4.8× the time).
Regions are in source order and never overlap, so one pass over them copies the
runs between them with `String::from_array(chars[a:b])` — at most one more run
than there are regions in the span.

| Stage                  | native (median of 3)      |
|------------------------|---------------------------|
| `split` many-views     | 3.71 → 3.48 ms  −6.2%     |
| `split` one-big-view   | 3.26 → 3.19 ms  −2.1%     |
| `gen` many-views       | 18.91 → 18.55 ms −1.9%    |

Neutral on wasm-gc (within run-to-run noise there). Kept for the native win and
for dropping the quadratic term: `scaling` 4× went from 4.77× to 4.36× the 1×
time.

## Current — after #1 and #2

| Stage     | many-views wasm-gc | native   | one-big-view wasm-gc | native   |
|-----------|--------------------|----------|----------------------|----------|
| `split`   |  3.99 ms           |  3.42 ms |  3.59 ms             |  3.06 ms |
| `surface` |  8.63 ms           |  8.00 ms |  9.48 ms             |  8.51 ms |
| `build`   |  8.37 ms           |  7.87 ms |  9.44 ms             |  8.48 ms |
| `gen`     | 22.91 ms           | 18.93 ms | 22.75 ms             | 18.10 ms |

Scaling probe (`build` on one view holding 1×/2×/4× every view body):

| Multiple | wasm-gc  | native   | vs linear (native) |
|----------|----------|----------|--------------------|
| 1×       |  9.49 ms |  8.57 ms | —                  |
| 2×       | 21.43 ms | 17.76 ms | 2.07×              |
| 4×       | 45.19 ms | 37.33 ms | 4.36×              |

# The runtime

## 3. `Harness::find` stops at the match it wants — patches −30% to −78%

Found by profiling the update suite, not by reading the code: `harness::matches`
and `find_all`'s walk were ~4% of the whole update profile. Every dispatched
event resolves its selector first, and `find(sel, nth=0)` was calling `find_all`
— collecting every match in the DOM, then indexing element 0. On a 1000-row list
that is a full-tree walk to answer a question the first row settles.

Early exit, same semantics (a miss still visits everything, so the count in the
failure message stays honest). This is measurement infrastructure rather than
framework code, but it is also what every `testing/harness` test does dozens of
times.

| Workload (native)          | before   | after    |          |
|----------------------------|----------|----------|----------|
| `patch noop todo 1000`     | 20.62 ms | 11.11 ms | −46.1%   |
| `patch toggle todo 1000`   | 23.25 ms | 14.43 ms | −37.9%   |
| `patch add+remove todo 1000` | 40.02 ms | 28.38 ms | −29.1% |
| `patch move json 8x4`      | 986.94 µs | 218.26 µs | −77.9%  |
| `patch page people 1000`   | 833.20 µs | 764.44 µs | −8.3%   |

What is left of the harness in these numbers is now benchmarked directly:
`find .checkbox todo 1000` is 5.5 µs and `find .next people 1000` is 37.8 µs (that
selector sits after the list, so its walk is unavoidable without caching nodes,
which would silently measure nothing the moment a patch replaced one).

## 4. Meta comments written, not stringified — renders −21%, updates −31%

(tw-mb techniques #3 and #13.) Every component render site and every `@each`
iteration emits a `§{…}§` boundary comment, and `Meta::to_comment_text` built a
`Json` object and called `stringify()` to produce it. A 1000-row list therefore
allocated and threw away ~2000 `Json` objects **per render pass** — and an update
is a render pass. It showed as 2.2% self time in `Json::stringify` with a
matching share of the 11.4% in the collector and 4.4% in array allocation.

The three shapes are fixed and closed, so there is nothing for a generic encoder
to decide: write them straight into a `StringBuilder`. String fields keep a
fallback to `Json::stringify` for anything outside printable ASCII, so the
escaping rules stay in one place — the point is to skip an allocation, not to
reimplement them. Output is byte-identical, which the full test suite (a good
number of them DOM snapshots carrying these comments) checks thoroughly.

| Workload                     | wasm-gc | native  |
|------------------------------|---------|---------|
| `render list 100`            |         | −21.5%  |
| `render list 1000`           |         | −21.0%  |
| `render todo 100`            |         | −16.9%  |
| `render todo 1000`           |         | −15.8%  |
| `patch noop todo 10`         | −21.0%  | −34.3%  |
| `patch noop todo 1000`       | −18.8%  | −27.8%  |
| `patch toggle todo 100`      | −25.1%  | −30.4%  |
| `patch toggle todo 1000`     | −13.2%  | −22.6%  |
| `patch add+remove todo 100`  | −27.1%  | −30.6%  |
| `patch add+remove todo 1000` | −12.9%  | −16.2%  |
| `patch switch view`          |  −7.1%  | −11.0%  |
| `patch counter`              |  −5.1%  | −11.2%  |

Nothing regressed outside the two known-noisy benches.

## 5. `site_cache_key` written, not interpolated — big updates −4%

**Retired by #8** — the render cache this keyed is gone, and so is the function.
Kept for the record.

Same shape as #4, one layer up: the render cache's per-slot key was an
interpolated string built once per render site per pass, and it called
`view_trail()` — which materializes a reversed copy of the trail — then joined
it, on top of `render_site`'s own call. Three throwaway allocations per row per
render.

Built into a `StringBuilder` instead, walking `view_names` backwards rather than
reversing it. Same key, so the cache behaves identically.

| Workload (native)            |          |
|------------------------------|----------|
| `patch add+remove todo 1000` | −3.7%    |
| `patch toggle todo 1000`     | −3.1%    |
| `patch page people 1000`     | −3.7%    |
| `patch switch view`          | −3.3%    |

Small workloads are flat — at 10 rows this is a handful of allocations against a
fixed per-pass cost, and the difference is inside their run-to-run spread. Kept
because five independent benches moved the same way; a single reading at this
size would not have been enough (`patch noop todo 10` alone swings ±18% between
runs, which is how this nearly got reverted).

## Runtime numbers — 2026-07-25, after #1–#5

### Render: mount + first render + serialize

| Workload           | wasm-gc  | native   |
|--------------------|----------|----------|
| `list 10`          |  38.5 µs |  70.7 µs |
| `list 100`         | 337.0 µs | 572.0 µs |
| `list 1000`        |  6.64 ms |  6.16 ms |
| `todo 0`           |  10.0 µs |  16.3 µs |
| `todo 10`          | 139.5 µs | 184.8 µs |
| `todo 100`         |  1.58 ms |  1.67 ms |
| `todo 1000`        | 26.81 ms | 19.32 ms |
| `people 1000`      | 468.3 µs | 604.0 µs |
| `json 8x4` (deep)  |  5.18 ms |  7.25 ms |
| `all examples`     | 31.57 ms | 21.20 ms |

`todo` (a child component per row) costs ~3× `list` (plain values) at every size,
and both are linear in the row count. `people 1000` is cheap because pagination
bounds the DOM even though the pipeline still walks all 1000 items — the filter
itself is ~130 µs of that.

### Diff/patch: two round-trip passes per number

| Workload                     | wasm-gc  | native   |
|------------------------------|----------|----------|
| `counter`                    |  20.2 µs |  30.0 µs |
| `switch view`                |  59.0 µs |  79.7 µs |
| `noop todo 10`               |  78.6 µs |  98.6 µs |
| `toggle todo 10`             |  87.8 µs | 110.7 µs |
| `add+remove todo 10`         | 105.1 µs | 136.6 µs |
| `move json 8x4`              | 177.3 µs | 190.4 µs |
| `page people 1000`           | 547.2 µs | 748.4 µs |
| `refilter people 1000`       |  1.73 ms |  1.61 ms |
| `toggle todo 100`            | 550.7 µs | 681.1 µs |
| `add+remove todo 100`        | 874.9 µs |  1.09 ms |
| `noop todo 1000`             |  8.77 ms |  8.77 ms |
| `toggle todo 1000`           | 11.50 ms | 12.10 ms |
| `add+remove todo 1000`       | 21.04 ms | 25.53 ms |

Three things fell out of this table (measured after #4; #5 moves the 1000-row
rows down another ~4%). #6 has since answered the second one — the numbers
below are the state of things that prompted it:

1. **A one-row change costs a whole-list pass.** Ticking one checkbox in a
   1000-row list is 6.1 ms (half of 12.10), against 19.3 ms to mount and render
   the entire list from nothing. The `RenderCache` exists to short-circuit
   subtrees whose value is physically unchanged, and the transactor swaps state
   with structural sharing — but a cache hit only skips the *child component's*
   view. The parent's `@each` still evaluates every item, builds every row
   wrapper, and hands the differ 1000 rows to walk.
2. **A no-op costs almost as much as a real change.** `noop todo 1000` is 8.77 ms
   against `toggle`'s 12.10: setting a field to the value it already holds does
   72% of the work of changing it. The difference is the actual DOM write;
   everything else is re-render and diff that could not have mattered.
   *(Fixed in #6: a no-op is now 19.5 µs, because it no longer re-renders at
   all. `toggle` is unchanged — that work is not avoidable, only the work for a
   change that isn't one was.)*
3. **The list-shape change is superlinear.** `add+remove` goes 136.6 µs → 1.09 ms
   → 25.53 ms for 10 → 100 → 1000 rows: 8.0× then 23× for 10× the rows. Part of
   that is `memdom`'s array-backed children (both `detach`'s index scan and the
   splice are O(children), where a real DOM is O(1)); part is an unkeyed differ
   walking every row after the insert.

Where the update time goes (js/V8 profile of the update workloads, self time):

```
11.4%  (garbage collector)
 9.6%  Eq::equal
 6.9%  vdom::morph_children
 6.2%  Map::contains_kv[String, AttrValue]
 4.4%  $make_array_len_and_init
 3.4%  Iter::next over map pairs
 2.5%  vdom::normalize_childs
 2.2%  json::Json::stringify        <- state round-tripping through Json
 2.1%  render::RenderCache::get
 1.8%  render::Meta::to_comment_text  <- meta comments rebuilt as strings
```

## 6. A no-op update is a no-op — `patch noop` −83% / −99.8%

This answers the "why the `RenderCache` misses" question that headed the list
below, and the answer was upstream of the cache: **the state never kept its
identity long enough to be recognised**.

Three things were throwing identity away on every single update:

1. `TypedInstance::to_value()` returned a fresh `Obj(self)` each call. That cast
   allocates, so one instance presented a different `Value` every time it
   crossed the value seam — and the cache keys on `physical_equal` of exactly
   that object. Memoized into the instance now: one instance, one `Value`.
2. `with_state` re-encoded the state struct through `Json`, which rebuilds
   every container even when nothing about it changed. Each freshly encoded
   field is now compared with the one it replaces and the OLD object kept when
   they are equal, so a field the handler didn't touch keeps the exact object
   the last render cached.
3. Nothing short-circuited a write of an equal value. `TypedInstance::set`
   returns `self`, `Value::with_field`/`with_item` return the untouched
   container, and `Path::update` / the transactor compare through the
   `&PathNode` boxing (`@tutuca.same_node`) instead of `physical_equal`, which
   a trait-object cast defeats. So the whole copy-on-write spine collapses and
   the transactor sees the root it already had.

Together: an interaction that writes a field the value it already holds no
longer swaps the root, so `on_change` never fires, `app.dirty` is never set and
`App::render_now` is never reached. `patch noop todo 1000` stops being "a full
render + diff that could not have mattered" and becomes event routing plus the
harness's selector walk.

The comparison in (2) is **fuel-bounded** (`REUSE_FUEL`, component/instance.mbt).
Fuel is spent only where the two sides do not already share structure, so a list
of child components — which the value stash restores by reference — costs one
unit and is fully preserved, while a 1000-item list of plain maps gives up after
a handful of deep compares and keeps the new object. That is what holds `page`
and `refilter` (the two workloads whose state is a 1000-item plain-data list) at
+4.7% / +4.6% instead of +6.1% / +5.4%: preserving identity is worth paying for
only where it is nearly free.

| Workload (native, median of 3 interleaved rounds) | before | after | |
|---|---|---|---|
| `patch noop todo 1000`   |  8.33 ms  | 19.5 µs | **−99.8%** |
| `patch noop todo 10`     | 116.5 µs  | 19.6 µs | **−83.2%** |
| `patch toggle todo 1000` | 11.97 ms  | 12.00 ms | +0.3% |
| `patch toggle todo 100`  | 665.8 µs  | 689.9 µs | +3.6% |
| `patch add+remove todo 1000` | 24.15 ms | 24.51 ms | +1.5% |
| `patch page people 1000` | 723.8 µs  | 758.0 µs | +4.7% |
| `patch refilter people 1000` | 1.51 ms | 1.58 ms | +4.6% |
| `patch move json 8x4`    | 190.6 µs  | 189.8 µs | −0.4% |
| `patch counter`          |  29.9 µs  |  29.4 µs | −1.6% |

Render (mount + first render) and the whole view pipeline are unchanged within
noise on both backends: `render todo 1000` +1.1%, `render list 1000` +0.8%,
`render all examples` −1.1% (native, median of 2 interleaved full-suite rounds).
wasm-gc agrees, including the headline: `patch noop todo 1000` 7.96 ms → 15 µs.

Method note: this is the first entry where run-to-run drift mattered more than
the change. A non-interleaved before/after showed +50% on benchmarks the change
cannot touch (the view pipeline has no state in it at all), so every number here
comes from before and after runs **alternating in one loop**, medians of three.
`page people 1000` was the one bench that survived that treatment as a real
regression, which is what prompted the fuel bound.

The two remaining costs are real and worth naming: an update still re-encodes
the whole state struct through `Json` (the comparison is on top of that, not
instead of it), and the transactor still walks the copy-on-write spine before
discovering nothing changed.

`patch_test.mbt` asserts the no-op round trip does not move `render_count`, and
`component/identity_test.mbt` pins the identity rules directly, so a regression
here fails a test rather than only showing up as a slower number.

## 7. Constant attributes evaluated once — updates −5.6% to −17.6%

**Retired by #8** — the memo and its `attrs_id` key are gone; every element
rebuilds its attribute map again. Kept for the record, and because the
`@vdom.h`-adopts-rather-than-copies half of it survives.

`eval_attrs` walked `ConstAttrs(m)` and built a fresh
`Map[String, AttrValue]` per element per render; `@vdom.h` then copied it into
a second map. For a constant attribute list both maps hold the same entries on
every pass.

Two halves:

- `DomData` gains an `attrs_id`, minted by `optimize_node` for a `ConstAttrs`
  element — the same contract a `RenderOnce` id has (a process-global int the
  renderer keys a per-app cache on, minted at load time). `RenderCtx` carries
  the memo beside `render_once`, and the `App` holds it for its life.
- `@vdom.h` adopts the attribute map instead of copying it when it holds no
  `key` / `namespace` entry to strip — two lookups against a copy of every
  entry, and, more to the point, the identity survives.

The allocations are the smaller half. The identity is the point: with the same
map on both sides, `diff_props`'s `physical_equal` fast path answers in O(1)
where it used to hash every key in both directions. That is the
"attribute-map equality" item this file ranked first below.

`RenderOnce` does not subsume it. That needs the WHOLE subtree constant, so
`<div class="row"><x text=".name"></x></div>` — the shape of every list row —
never qualified.

Native, release, `patch_bench_test.mbt`, against a saved baseline:

| Workload                     | before   | after    |         |
|------------------------------|----------|----------|---------|
| `patch counter`              |  28.30 µs|  23.46 µs| −17.1%  |
| `patch toggle todo 10`       | 107.24 µs|  95.53 µs| −10.9%  |
| `patch toggle todo 100`      | 633.13 µs| 560.72 µs| −11.4%  |
| `patch toggle todo 1000`     |  10.54 ms|   9.95 ms|  −5.6%  |
| `patch add+remove todo 10`   | 133.83 µs| 110.23 µs| −17.6%  |
| `patch add+remove todo 100`  |   1.02 ms| 863.32 µs| −15.4%  |
| `patch add+remove todo 1000` |  23.81 ms|  20.33 ms| −14.6%  |
| `patch move json 8x4`        | 186.36 µs| 175.61 µs|  −5.8%  |
| `patch page people 1000`     | 375.42 µs| 330.81 µs| −11.9%  |
| `patch refilter people 100`  | 325.66 µs| 286.85 µs| −11.9%  |
| `patch refilter people 1000` |   1.16 ms|   1.08 ms|  −6.9%  |
| `patch switch view`          |  77.46 µs|  67.10 µs| −13.4%  |

`patch noop todo 1000` (+4.0%) and `find .checkbox todo 1000` (+5.4%) are the
two that moved the wrong way; neither re-renders (the no-op short-circuit of #6
and a harness search), so both are this machine's drift. Output unchanged: the
full suite is green on all three targets and no `*_view_gen.mbt` moved.

**Not measured on wasm-gc, and not measured on the render suite.** The machine
running this ran out of memory on the second bench file, so the numbers above
are one saved-baseline A/B rather than the interleaved 3× this file asks for on
a change under 5%. Every kept number is well over that; re-measure both suites
on wasm-gc before treating the entry as complete.

## 8. All render caching removed — updates +23% to +150%, deliberately

This entry runs the other way: a change that **costs** time and was kept anyway.
Rendering memoized three ways — the component render-site cache keyed on value
identity (`render/cache.mbt`), the `RenderOnce` constant-subtree memo, and the
constant-attribute memo of #7 — and all three are gone. #5 and #7 are retired
with them; #6 is NOT (see below).

The reason is not performance. The three caches reached into the AST (a
`RenderOnce` variant every tree walker had to see through, a `mut attrs_id` on
`DomData`), into the view pipeline (`cache_const_nodes`, which made `viewgen`
parse each view two different ways — the divergence this file's "Not yet tried"
names as the blocker for sharing one parse), and into `RenderCtx`, which was a
four-field bag of memos with a "hand the SAME map across passes" lifetime
contract. That is a lot of structure to hold still while the core design is
still moving. They can come back, keyed on whatever the design settles on.

Measured before deleting anything, by flipping the caches off at their existing
switches (`cache_const_nodes`, and `RenderCtx.render_cache`'s `None` default),
so each half could be attributed separately. The landed numbers reproduce column
A to within noise.

wasm-gc, release, `patch_bench_test.mbt`, ±1–5%:

| Workload | before | after | | RenderCache alone | RenderOnce+attrs alone |
|---|---|---|---|---|---|
| `patch noop todo 10` | 14.45 µs | 14.27 µs | −1.2% | −2.1% | −1.0% |
| `patch noop todo 1000` | 15.37 µs | 14.09 µs | −8.3% | −8.6% | −6.8% |
| `patch counter` | 17.62 µs | 21.61 µs | +22.6% | −9.8% | +24.5% |
| `patch toggle todo 10` | 74.06 µs | 116.50 µs | +57.3% | +30.1% | +19.7% |
| `patch toggle todo 100` | 450.94 µs | 973.09 µs | +115.8% | +67.8% | +29.3% |
| `patch toggle todo 1000` | 9.27 ms | 19.50 ms | +110.4% | +58.9% | +41.0% |
| `patch add+remove todo 10` | 80.56 µs | 108.90 µs | +35.2% | +10.2% | +20.9% |
| `patch add+remove todo 100` | 623.95 µs | 971.07 µs | +55.6% | +11.7% | +29.9% |
| `patch add+remove todo 1000` | 15.22 ms | 22.99 ms | +51.1% | +9.3% | +39.2% |
| `patch move json 8x4` | 162.63 µs | 406.58 µs | +150.0% | +86.3% | +9.1% |
| `patch page people 1000` | 262.82 µs | 281.92 µs | +7.3% | +4.1% | +9.8% |
| `patch refilter people 100` | 285.17 µs | 294.59 µs | +3.3% | −3.3% | +5.8% |
| `patch refilter people 1000` | 1.39 ms | 1.40 ms | +0.7% | −3.6% | 0.0% |
| `patch switch view` | 48.74 µs | 54.58 µs | +12.0% | −2.1% | +16.1% |
| `find .checkbox todo 1000` | 3.61 µs | 3.51 µs | −2.8% | −6.9% | −0.3% |
| `find .next people 1000` | 27.64 µs | 25.47 µs | −7.9% | −9.7% | −1.4% |

Four things the split says, worth keeping for whoever reintroduces caching:

1. **The two halves are nearly independent** — A ≈ B + C throughout, so neither
   was masking the other.
2. **`RenderOnce` + const-attrs is never a net cost.** Positive on every
   workload it touches, flat where it does not apply. It is also the half that
   carried nearly all the structural complexity, which is the awkward part of
   this entry.
3. **The render-site cache is a net LOSS where it does not hit**: `counter`
   −9.8%, `refilter people` −3.3/−3.6%, both mount-heavy `find` benches
   −6.9/−9.7%. Building `site_cache_key` and missing is pure overhead, and
   holding two generations of ~1000 entries costs GC on passes that never
   render — which is why `noop todo 1000` is 8.6% *faster* without it. A
   reintroduced cache should be able to decline.
4. **#6 is untouched.** Both `noop` rows are flat-to-faster in every column: the
   no-op win comes from the transactor's root-identity check, not from any
   render cache. Everything that feeds it — `TypedInstance`'s memoized box,
   `REUSE_FUEL`/`reuse_equal`, `with_field`/`with_item` returning the untouched
   container — stays, and `component/identity_test.mbt` still pins it.

Output unchanged: 890 default / 890 native / 8 js green, `gen-views` drift-clean
(the markers were minted at load time and never reached a `*_view_gen.mbt`).

## 9. The render-site cache back, keyed on a fingerprint — updates −30% to −56%

#8 removed the render caches and left two instructions for whoever brought one
back: **the render-site cache is a net loss where it misses**, because building
`site_cache_key` costs a `StringBuilder` per site per pass whether or not it
hits; and **a reintroduced cache should be able to decline.** This does both, by
changing what the key IS.

An instance now carries a `@tutuca.ObjId` — a structural fingerprint fixed at
creation plus a revision each successor bumps. The cache keys a
`Map[UInt64, CacheEntry]` on the origin. Nothing is built at lookup time, and a
value with no `ObjId` (a plain `Map` render site, a component-less `ViewMap`
embedding) is declined before anything is spent on it.

The fingerprint is a **bucket, not an identity**, and deliberately not unique —
which is what lets it be minted with no process-global counter, so a component
loaded at runtime brings everything it needs to make its own. A collision costs
a miss: the entry stores the source value and a hit still requires
`physical_equal` on it, plus the revision, the `node_id`, the `(cid, vid)` and
the dyn-binds chain. That list is exactly what a render site reads. It is not
longer because a component boundary is a bind barrier (`render_site` enters with
`is_frame=true` and empty binds, and `lookup_bind_chain` stops at a frame), so
the enclosing `@each` binds cannot reach inside; and because position is never
baked into a subtree — `events.mbt` reconstructs the dispatch path from
`data-eid` stamps and the metas. Both are why the innermost loop key the old
`site_cache_key` carried is gone: sibling list items are different instances,
so they are already different buckets.

`RenderOnce` and the constant-attribute memo did NOT come back. They were the
half that put a variant in `ANode` and a `mut attrs_id` on `DomData` and made
`viewgen` parse each view two ways — and #8 unblocked sharing one parse by
removing them.

wasm-gc, release, medians of **5 interleaved rounds** on an idle machine, the
two sides alternating in one loop. The `before` side is the previous commit
(the fingerprint, no cache) checked out in a `git worktree`, so alternating
costs a `cd` rather than a stash — and neither side is ever the one that just
rebuilt.

| Workload | before (#8's state) | after | |
|---|---|---|---|
| `patch noop todo 10` | 15.98 µs | 15.98 µs | +0.0% |
| `patch noop todo 1000` | 13.88 µs | 13.77 µs | −0.8% |
| `patch counter` | 21.34 µs | 21.98 µs | **+3.0%** |
| `patch toggle todo 10` | 113.26 µs | 82.60 µs | **−27.1%** |
| `patch toggle todo 100` | 943.16 µs | 530.72 µs | **−43.7%** |
| `patch toggle todo 1000` | 19.93 ms | 12.57 ms | **−36.9%** |
| `patch add+remove todo 10` | 106.99 µs | 106.05 µs | −0.9% |
| `patch add+remove todo 100` | 956.66 µs | 938.46 µs | −1.9% |
| `patch add+remove todo 1000` | 23.18 ms | 14.96 ms | **−35.5%** |
| `patch move json 8x4` | 395.11 µs | 169.87 µs | **−57.0%** |
| `patch page people 1000` | 290.05 µs | 288.14 µs | −0.7% |
| `patch refilter people 100` | 297.95 µs | 294.11 µs | −1.3% |
| `patch refilter people 1000` | 1.42 ms | 1.40 ms | −1.4% |
| `patch switch view` | 54.71 µs | 54.40 µs | −0.6% |
| `find .checkbox todo 1000` | 3.56 µs | 3.46 µs | −2.8% |
| `find .next people 1000` | 25.87 µs | 25.74 µs | −0.5% |

Read against #8's `RenderCache alone` column, which is the same cache measured
the other way round:

1. **The wins came back, most of the way.** `move json 8x4` recovers −57.0%
   against the old cache's −86.3% — effectively the same row. `toggle todo
   1000` recovers −36.9% where the old cache was worth −58.9%, so this version
   leaves something on the table there; the likeliest reason is bucket thrash
   between structurally equal rows (see below).
2. **`counter` still costs, but a third as much: +3.0% against −9.8%.** This
   one is real and not noise — five rounds put `before` in 21.0–21.9 µs and
   `after` in 21.8–22.4 µs, distributions that barely touch. `counter` is one
   component whose state changes on every click, so every pass is a guaranteed
   miss and the lookup plus store buys nothing. That is the irreducible floor
   of having a cache at all; what the fingerprint removed is the *other* two
   thirds, which was `site_cache_key` building a string to miss with.
3. **The rest of the losses went away.** `refilter people` −1.3/−1.4% against
   the old −3.3/−3.6%, and both mount-heavy `find` benches −2.8/−0.5% against
   −6.9/−9.7%. Those sites render plain values, so the cache declines and pays
   nothing at all, which is the whole point of being able to.
4. **Fingerprinting at creation is not visible.** The mount-heavy `find` and
   `page` benches did not move, which is the O(own fields) rule holding: a
   nested `Obj` mixes its own origin and never its contents, so a parent costs
   its own fields rather than its subtree.

`patch noop todo 10` is bimodal on BOTH sides (13.7–16.9 µs before, 14.4–16.4
after, n=5 each) and its median lands on +0.0%. It is a ~14 µs bench; do not
read a single round of it as a signal.

Where the remaining headroom is:

- **Bucket thrash.** Two structurally equal instances share a bucket and evict
  each other every pass (`render/cache_test.mbt` pins that this is a thrash and
  never a wrong subtree). Mixing the innermost loop key into the bucket would
  separate them — the one piece of the old `site_cache_key` that would then have
  a reason to exist. Measure first: on this corpus the todo rows have distinct
  titles, so it may not be what the gap on `toggle todo 1000` is.
- **Letting a guaranteed-miss site opt out**, which would take `counter`'s +3.0%
  back. The cache can already decline for a value with no fingerprint; declining
  for a site whose recent history is all misses is the same idea with a
  different signal, and the `hit`/`miss` counters are already there.

Output unchanged: 903 default / 903 native / 8 js green, `gen-views`
drift-clean. The DOM snapshots are the proof the cache never returns stale.

# The view pipeline, revisited

## 10. Compile each view once per generated pair — `gen` −26% / −28%

The types emitter needed a compiled tree to collect the component surface and
check state reads; the IR emitter independently compiled the same source again
to serialize that tree. `CompiledFile` now owns each view's expanded tree,
events and collected surface, and both emitters consume that artifact.
`emit_modules` is the high-level operation used by the CLI, playground and
benchmark; the individual emitters remain compatibility wrappers.

Native release, 10 × N runs. This after-run shared the machine with interactive
work, so treat sub-5% movement in the unrelated stages as noise rather than a
result:

| Stage                    | before   | after    | change |
|--------------------------|----------|----------|--------|
| `many-views split`       | 3.39 ms  | 3.50 ms  | +3.2%  |
| `many-views surface`     | 7.78 ms  | 7.95 ms  | +2.2%  |
| `many-views build`       | 7.78 ms  | 7.63 ms  | −1.9%  |
| `many-views gen`         | 18.20 ms | 13.46 ms | **−26.0%** |
| `one-big-view split`     | 3.02 ms  | 3.01 ms  | −0.3%  |
| `one-big-view surface`   | 8.63 ms  | 8.22 ms  | −4.8%  |
| `one-big-view build`     | 8.35 ms  | 8.27 ms  | −1.0%  |
| `one-big-view gen`       | 17.77 ms | 12.82 ms | **−27.9%** |

The generation-only drop is much larger than both the confidence intervals
(±1.6% / ±4.7% after) and the movement in stages the change cannot affect.
Output stayed byte-identical: the compatibility test compares both emitted
modules, their pinned benchmark checksums pass, and `gen-views` is drift-clean.

# The runtime, revisited

## 11. The sanitizing filter runs at element construction — updates −15% to −38%

Context: the render-time sanitizer (`vdom/filter`, `docs/sanitizer.md`) became
installed BY DEFAULT on every `App`, so what had been an opt-in cost became
everyone's. It was applied to the FINISHED tree in `App::render_now`, and that
is the wrong complexity next to #9: the render-site cache hands back the same
`Vdom` object for an unchanged site and morph short-circuits it by physical
identity, so the filter did O(whole tree) work on every render while the rest of
the pipeline did O(changed). On a 1000-row list, morph touches one row and the
filter touched a thousand.

`RenderCtx` carries the filter now, and `render` applies it in the one place it
constructs an element (the `Dom(d)` arm). Exactly-once by construction, no
traversal, and a subtree the cache returns was never rebuilt so is never
filtered again.

The intermediate design — walk each rebuilt body, stopping at nested `§Comp§`
boundaries — does NOT work and is worth recording so nobody tries it twice:
`@vdom.fragment` flattens nested fragments (`normalize_childs`), so a nested
component's `[meta, body]` is spliced inline into its parent's child list and
there is no boundary left to stop at. A test counting filtered elements caught
it (9 where 6 was expected).

Two consequences: installing a filter clears the render cache (`App::set_filter`
then; `set_sanitizer` / `add_filter` now), since a cached
subtree carries the verdict of whichever filter built it; and a filter that
replaces children owns checking what it built, because nothing runs after it on
nodes it created.

Medians of 3 interleaved runs per side (stash-free: two worktrees, alternating
in one loop), `patch_bench_test.mbt`, release. "spread" is the worse of the two
sides' own max-min across its 3 runs:

| Workload                     | wasm-gc  | native   | spread |
|------------------------------|----------|----------|--------|
| `patch move json 8x4`        | **−34.8%** | **−37.9%** | 6%   |
| `patch toggle todo 1000`     | **−28.6%** | **−20.4%** | 11%  |
| `patch add+remove todo 1000` | **−24.7%** | **−17.4%** | 11%  |
| `patch toggle todo 100`      | **−22.9%** | **−24.2%** | 12%  |
| `patch toggle todo 10`       | **−15.6%** | **−16.5%** | 7%   |
| `patch noop todo 1000`       | −7.0%    | −1.1%    | 5%    |
| `patch add+remove todo 10`   | −3.4%    | −4.4%    | 7%    |
| `patch add+remove todo 100`  | −2.4%    | −3.5%    | 6%    |
| `patch page people 1000`     | −3.4%    | −0.7%    | 9%    |
| `patch refilter people 1000` | −2.0%    |  0.0%    | 5%    |
| `patch switch view`          | +3.6%    | −2.4%    | 5%    |

Native absolutes for the movers: `move json 8x4` 281.4 → 174.8 µs,
`toggle todo 1000` 16.62 → 13.23 ms, `add+remove todo 1000` 20.53 → 16.95 ms,
`toggle todo 100` 960.9 → 728.2 µs.

The pattern is the claim: **the win scales with how much a render REUSES.**
`toggle` changes one row of many and gains the most; `add+remove todo 10/100`
rebuilds nearly everything it renders, so there is little reuse to exploit and
it moves inside its own spread. The two `find` benchmarks disagree in sign
between targets (−5.8% / +11.1%) and neither re-renders, so both are drift.

Output unchanged: full suite green (1127).

### What the filter still costs

Worth stating, because it is not zero and cannot be. Interleaved 3× on wasm-gc,
HEAD against HEAD with `set_filter(None)`:

| Workload                     | filter on | off      | cost   |
|------------------------------|-----------|----------|--------|
| `patch add+remove todo 100`  |  1.27 ms  | 957.6 µs | +32.6% |
| `patch add+remove todo 10`   | 135.6 µs  | 109.9 µs | +23.4% |
| `patch toggle todo 100`      | 637.5 µs  | 549.8 µs | +15.9% |
| `patch switch view`          |  66.3 µs  |  57.9 µs | +14.5% |
| `patch toggle todo 10`       |  97.2 µs  |  85.1 µs | +14.1% |
| `patch add+remove todo 1000` | 17.38 ms  | 16.46 ms |  +5.6% |
| `patch toggle todo 1000`     | 14.15 ms  | 13.60 ms |  +4.0% |
| `patch noop todo 1000`       |  13.7 µs  |  14.0 µs |  −2.3% |

Inspecting every attribute of every element that is BUILT is the irreducible
part — the ones that rebuild most pay most, and `patch noop` pays nothing
because it rebuilds nothing. Anything further has to come from not inspecting,
which is the skip set in "Not yet tried" below.

## 12. The filter's no-op path stops allocating — updates −2% to −3.5%

Small, kept because it moved consistently and in one direction on exactly the
benchmarks that construct the most elements.

`url_attrs.contains(name.to_lower())` ran for every attribute of every element,
allocating a String before discovering the name is not a URL attribute at all —
which is what almost every name is. `is_url_attr` probes the set with the name
as it stands and only falls back to `to_lower` for a name that actually contains
an uppercase letter; anode lowercases every attribute name it reads, so mixed
case only arrives from a hand-built vnode or vdom's IDL spellings, none of which
are URL attributes. Both filters also allocated a `doomed` array per element to
hold names they almost never collect; allocated lazily now.

Medians of 3 interleaved runs, wasm-gc, `e07d702` against `56ae747` (both with
the filter over the finished tree, so this isolates the allocations):

| Workload                     | before    | after     |        |
|------------------------------|-----------|-----------|--------|
| `patch move json 8x4`        | 256.02 µs | 247.17 µs | −3.5%  |
| `patch toggle todo 10`       | 104.01 µs | 100.79 µs | −3.1%  |
| `patch add+remove todo 100`  |   1.15 ms |   1.12 ms | −2.6%  |
| `patch add+remove todo 10`   | 123.77 µs | 120.79 µs | −2.4%  |
| `patch toggle todo 100`      | 736.80 µs | 727.44 µs | −1.3%  |

Everything else moved under 1.2% either way, inside a 1–4% per-benchmark spread.
Four of the five above exceed their own spread, all five are negative, and no
benchmark got measurably worse — which is the whole case for keeping a change
this size. Not measured on native: the effect is smaller than that machine's
drift on several of these, and the wasm-gc direction is consistent enough to
decide on.

## 13. The filter is told what it could possibly find — updates −5% to −26%

The biggest single number the filter had left, and it comes from not looking
rather than from looking faster.

Every rule in `vdom/filter` asks two questions of an attribute: does its NAME
concern me, and is this render's VALUE allowed? The second is the reason the
filter exists — a value is a `Val` expression until state produces it. The first
is not like that at all: **every attribute name in a view is a literal**
(`AttrItem` carries `name : String` in every variant), so which rules an element
could ever concern is the same answer on every render, and almost always
"none of them".

`@sinks.SinkHints` is that answer — four bits, `url` / `handler` / `css` /
`markup` — computed by `render` off the anode attributes with `vdom/filter`'s
own predicates, memoized on `DomData`, and handed to `filter_elem_hinted`. A
rule whose bit is clear returns without touching the attribute map. A `<div>`
with a `class` and an `id` now pays a field read where it used to pay a walk of
its attribute map and, for the CSS rule, a probe of an 818-name property set per
attribute.

wasm-gc, release, A/B on the same build with only the call site swapped
(`filter_elem_hinted` against `filter_elem`, which also skips computing the
hints at all):

| Workload                     | hints off | hints on  | saving |
|------------------------------|-----------|-----------|--------|
| `patch add+remove todo 100`  |   1.33 ms | 983.46 µs | −26.0% |
| `patch add+remove todo 10`   | 142.75 µs | 108.51 µs | −24.0% |
| `patch counter`              |  27.74 µs |  22.84 µs | −17.7% |
| `patch toggle todo 100`      | 658.44 µs | 542.53 µs | −17.6% |
| `patch toggle todo 10`       |  98.53 µs |  84.80 µs | −13.9% |
| `patch switch view`          |  68.34 µs |  59.56 µs | −12.8% |
| `patch refilter people 100`  | 322.34 µs | 282.44 µs | −12.4% |
| `patch toggle todo 1000`     |  14.14 ms |  12.43 ms | −12.1% |
| `patch add+remove todo 1000` |  16.47 ms |  15.24 ms |  −7.5% |
| `patch move json 8x4`        | 180.53 µs | 167.61 µs |  −7.1% |
| `patch page people 1000`     | 317.57 µs | 298.37 µs |  −6.0% |

A second A/B pair, run before this one, gives the same ordering with the top
rows 2–6 points smaller (`add+remove todo 100` −24.4%, `add+remove todo 10`
−20.1%, `toggle todo 100` −14.6%); per-benchmark spreads were ±1–5% in both.
`patch noop` moves +2% — it rebuilds nothing, so it has no elements to skip and
this is drift.

**What is left of the filter is now inside the noise.** The same build measured
against an app with no filter at all — `set_filter(None)`, which still existed
when this was measured and has since been removed with the rest of the opt-out,
and which is what §"What the filter still costs" measured at +4% to +33% before
this — comes out within ±5% on every
workload, in both directions, over two runs whose own spreads reached ±10% and
±28% on the rows that moved most. That is not a claim of zero; it is a claim
that the cost is no longer separable from the machine, which is as far as this
harness can go.

Three things worth writing down about how it is built:

- **The name tables did not move, and neither package imports the other.**
  `anode` holds the memo and `vdom/filter` reads it, but `vdom/filter` is "over
  `vdom` and nothing else" (importing `anode` would put a template compiler
  behind every render — `handler.mbt` duplicates a two-line prefix test rather
  than pay it), and `anode` is imported by everything, so it must not link a CSS
  tokenizer to hold a field. The type therefore lives alone in `sinks/`, with no
  imports at all, and `render` — which already has both — is where the question
  is asked.
- **It is a memo rather than a parse result** for that same reason: computing it
  at parse would be tidier, but the tables that decide it are behind a
  tokenizer and an HTML parser that no consumer of a view tree should link. One
  `Option` test per element per render buys the same steady state, since a
  `DomData` is shared by every render of that element.
- **Failing generous is free and failing narrow is a hole**, so everything
  defaults generous: `SinkHints::all()` where nothing looked, the trait method
  defaults to ignoring its hints (a host's own rule sees every element, because
  no bit here describes what it looks for), and the fold only ever sets bits.
  `vdom/filter/hints_test.mbt` holds every rule to "`all()` does what
  `filter_elem` does", and `render/sink_hints_wbtest.mbt` holds the memo's one
  invariant — that the `data-*` names `set_data_attr` stamps afterwards concern
  no rule.

## Not yet tried

Ranked by what the profiles say is left.

In the update path (the biggest numbers on the board):

- **The sanitizer's skip set, VALUE half.** The name half is #13 and took the
  measurable part of this with it, so what is left here is smaller than the
  bullet this replaces and needs something the name half did not.

  Pass 1 distinguishes a `Const` from a `Val` expression, so a view whose
  sink-set attributes are ALL constant has nothing left for the filter to decide
  — but only if something CHECKED those constants, and `Policy::check_view` has
  one call site (`dyncomp/host/bundle.mbt`). A plain app has no static pass, so
  for it "constant" means "unvalidated", and skipping constants would put a
  literal `href="javascript:…"` back on the page. So this one is not a pure
  optimization the way #13 was: it needs either a compile-time pass that checks
  constants for a plain app too, or a host that can promise the policy which
  checked them is the policy filtering now. Both are in `docs/sanitizer.md`.

  A per-VIEW bit keyed by `data-vid` — what this bullet used to propose — is
  also the wrong granularity now: #13 is per-element, and one dynamic `:style`
  would deoptimize a whole view under the coarser scheme.
- **Attribute-map equality** (`Map::contains_kv` 6.2% + much of `Eq::equal`
  9.6%). Comparing two attribute maps hashes every key; a diff does it per node
  per pass. #7 took the CONSTANT half of this, and #8 gave it back — EVERY
  element rebuilds its map now, so this is the whole cost again and the biggest
  single number on the board. Comparing the two entry lists directly, rather
  than hashing both ways, is the version of this that does not need a cache.
  Reprofile first.
- **State through `Json`**: typed state derives `ToJson`/`FromJson`; worth
  confirming an update does not round-trip through it. (Part of what the 2.2% in
  `stringify` was is now gone with #4 — reprofile before chasing this.)
- **`memdom` children as an array**: makes move-heavy patches quadratic. A
  doubly-linked sibling list would match a real DOM, at the cost of touching
  every `childs` user.

In the view pipeline:

- **`Tokenizer::new` per view** (6.7% self on the many-views corpus). It is
  `input.to_array()` plus setup in the vendored `moonbit-community/html`; the
  compile-once pipeline now calls it once per view. Further improvement needs
  an upstream tokenizer change or compiling several template bodies in one
  tokenizer pass.
- **`split_file`'s second `Array[Char]`** (`String::to_array`, 4.3–5.7%). The
  file is copied to an array twice: once here for slicing, once inside
  `Tokenizer::new`. Sharing one would need the tokenizer to expose its own, or
  offsets in code units rather than code points.
- **`dedent`** (1.5%): allocates a line array, a `to_array()` per line, a second
  line array, and a join, per view. A two-pass scan over the source with no
  intermediate arrays would do.
- **`JSArray::push` / GC** (9–16% + 9–10%). Mostly `StringBuilder` and tree
  children growth; the tw-mb log's biggest wins were all allocation removal, so
  this is where the headroom is.

## The state <-> Value codec, retired

A now-retired `codec_bench_test.mbt` A/B'd the JSON bridge (`S -> Json -> Value` and back,
inside a process-global stash because `Obj`/`Fn` cannot survive JSON) against a
direct field-by-field codec generated from the schema. On the shape the corpus
has — scalars, a list and a dynamic field — encode came out ~2x and decode ~5x,
decode gaining most because the JSON path rebuilt a whole `Json` object just to
hand it to `from_json`. That measurement is what justified generating a second
encoder at all.

The benchmark is gone because its other arm is: with no JSON bridge left there
is nothing to A/B against, and a benchmark timing only the surviving path
measures nothing anyone can act on. The numbers above are the record, and this
paragraph is why they cannot be re-run as written.

The bench is gone because its comparison is: `component()` requires a codec
now, the bridge and the stash are deleted, and there is no second path to
measure against. The numbers stay recorded here — they are why the codec
exists, and re-deriving them would mean rebuilding the thing they argued
against.

## Rejected: building only the mutators something names

`gen_mutators` builds every per-field mutator — `setX`, `updateX`, `resetX`,
`toggleX`, `pushInXAt`, … — for every field at every `component()` call, into a
string-keyed map, whether a view mentions them or not. Across the corpus that
is ~3490 closures for 349 state fields, against 167 names that any view or
schema mentions at all (most of which are `update` arms, not mutators). Well
over 90% are built and never called, so gating each one on being named looked
like free boot-time savings.

Measured as an upper bound — building NONE at all, which is the most the gate
could ever save:

| | all mutators | none built | |
|---|---|---|---|
| `render all examples` | 20.29 ms ± 18.0% | 18.99 ms ± 8.6% | −6.4% |
| `render todo 1000` | 25.98 ms ± 8.3% | 25.77 ms ± 8.6% | −0.8% |

Both are inside this machine's run-to-run drift, and the only one that moves at
all is the benchmark that mounts fifty modules — construction cost, which a
real app pays once. The render-heavy case moves 0.8%, which is nothing.

Not kept. The gate is also not free to write correctly: a component whose views
are built at run time (visual_wasm's factories, the macro examples) has no
`inputs` in its schema, because the generator never saw those views — so the
gate would have to read the handler names back off the compiled view trees,
which is a second implementation of `viewgen/surface.mbt`'s walker living in
the runtime. Paying that for a number this size is the trade this file exists
to refuse.

## `View.parse` instead of `View.ir` — the AOT wasm bundle −44.9%

`View::compile` branched on an `ir : Bool`: an ahead-of-time view only needed
its component id stamped, a source view had to be parsed. Both arms were in
one function, so every program that compiled a view NAMED `ANode::parse` —
and through it the whole parse subtree, the vendored WHATWG HTML tokenizer
included — whether it could ever reach that branch or not. A linker cannot
prune a runtime `if`.

The flag is a function slot now. `View::new` installs the parse step;
`View::from_ir` leaves it `None`; `compile` calls it or stamps the id. Only
`View::new` names the parser, so a program that never builds a view from
source does not link one.

Measured on `demo/counter_wasm`, which is entirely ahead-of-time
(`moon build --target wasm-gc --release`):

| | bytes |
|---|---|
| before | 438,803 |
| after  | 241,941 |
| | **−196,862 (−44.9%)** |

No call site changed — `View::new` and `View::from_ir` keep their signatures.
The bracketing measurement that found this: deleting the parse branch outright
gave 243,514 bytes, so the slot recovers essentially all of it.

This is the one claim in this file that the timing benchmarks cannot show, and
the reason to check it separately. An earlier, shallower probe — stubbing the
body of `ANode::parse` — moved only 1.7 KB and nearly led to the opposite
conclusion: the rest of the branch (`ParseContext::compile`, the attribute and
x-op parsers) kept the subtree alive on its own. Stub the entry point, not the
leaf.

# Dispatch

## 14. Baseline — the v2 walk, 2026-08-19

Not an optimization: v2 made two performance claims and neither was measured.
`benchmarks/intent.mbt` + `intent_bench_test.mbt` measure them, and
`intent_test.mbt` pins the shape of each workload so a timing cannot quietly
start measuring something else.

```
node benchmarks/report.mjs --file intent_bench_test.mbt [--target native]
```

| Workload                 | wasm-gc  | native   |
|--------------------------|----------|----------|
| `dispatch answered`      |  8.43 µs | 11.02 µs |
| `dispatch unanswered`    |  0.24 µs |  0.34 µs |
| `intent lex declines 0`  |  9.44 µs | 13.82 µs |
| `intent lex declines 4`  |  9.44 µs | 14.06 µs |
| `intent lex declines 16` | 10.18 µs | 14.80 µs |
| `intent lex declines 48` | 11.36 µs | 16.55 µs |
| `intent dyn depth 1`     |  1.73 ms |  3.10 ms |
| `intent dyn depth 4`     |  2.07 ms |  3.15 ms |
| `intent dyn depth 16`    |  1.97 ms |  2.39 ms |
| `intent dyn depth 64`    |  2.98 ms |  3.25 ms |
| `intent dyn find 64`     |  1.16 µs |  1.75 µs |

**Claim 1 — a name nothing answers costs one lookup.** It holds, with room to
spare: an unanswered dispatch is **2.8% of an answered one** on wasm-gc and
**3.1%** on native — 35× and 32× cheaper. Both go through the same
`send_at_root`; the difference is the transition and the render the answered one
does and the unanswered one does not. Stop-by-default is not paying for itself
with a hidden scan, which is what made it worth having.

**Claim 2 — a default-route intent walks every hop, one queued transaction
each.** True, and cheap. The `lex` rows are the ones to read it off, because
their DOM is fixed and only the number of DECLINING handlers changes: 48
declines add **1.92 µs on wasm-gc and 2.73 µs on native**, which is **40 ns and
57 ns per hop**. A `Pass` costs one call and one frame, exactly as
`try_lex`'s continuation-passing shape implies.

The `dyn` rows do not resolve a per-hop cost and should not be read as if they
did. A deeper chain is a deeper DOM, so the click's render grows with the same
parameter as the walk — and the render dominates by three orders of magnitude.
The noise says so outright (±58% at depth 1 on native, where depth 16 measures
*faster* than depth 1). What they do establish is the shape of the worst case: a
64-level tree whose every ancestor observes the intent and none of them replies
costs about 3 ms per click on both targets, and 64× the hops is well under 2×
the time.

**One render per walk, at any depth.** The fact that makes the above readable,
and the one worth guarding: every hop is its own queued transaction, so the
obvious worry is 64 repaints. There is exactly one, on both legs and at every
size — the transactor drains the cascade and the app reports a single change,
as a fanned-out `send` already did. `intent_test.mbt` asserts it, because a
regression here would show up in the `dyn` rows as a slope somebody would
reasonably read as the cost of walking.

**`INTENT_DEPTH` is a budget for the WALK, not for either leg.** Found by
writing the benchmark: a `lex` chain of 64 declines plus the handler that
answers is 65 hops, and the walk is cut short — so the last `lex` row is 48 and
not 64. A `dyn` chain of exactly 64 walks; 65 does not. Worth knowing because
the natural reading ("64 ancestors, and separately 64 handlers") is not what
the transactor implements: a default `dyn lex` intent raised deep in a tree has
already spent part of the budget its scope chain would need.

When the bound is hit the sender hears `<name>Unhandled` — the same message an
honest exhaustion sends. That is deliberate (`transactor/walk.mbt`: "a sender
that asked for an answer learns something rather than waiting forever"), and
the refusal channel is where the two are told apart: a cut-short walk also
raises `RefusalCode::IntentDepth` and a plain exhaustion does not.

**The house rule, applied.** This file's gate is that a design which does not
move a number gets reverted rather than kept because it should be faster; the
plan's own risk note extended it to this one — if the default route is too slow
to be the default, change the default. At 40–57 ns per hop and one render per
walk, it is not. `dyn lex` stays.
