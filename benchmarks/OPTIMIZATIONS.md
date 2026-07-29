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

wasm-gc, release, medians of 4 interleaved rounds (stash / measure / pop /
measure). **This machine was not quiet** — a browser held 1–1.5 cores for two of
the four rounds, and single-round error bars reached ±40% there; the two
sub-5% rows below are within that and should be re-read on an idle machine. The
rows that carry the result are an order of magnitude outside it.

| Workload | before (#8's state) | after | |
|---|---|---|---|
| `patch noop todo 10` | 14.47 µs | 14.26 µs | −1.5% |
| `patch noop todo 1000` | 14.23 µs | 14.18 µs | −0.4% |
| `patch counter` | 22.75 µs | 23.03 µs | +1.2% |
| `patch toggle todo 10` | 120.64 µs | 84.44 µs | **−30.0%** |
| `patch toggle todo 100` | 1.08 ms | 557.85 µs | **−48.3%** |
| `patch toggle todo 1000` | 20.43 ms | 12.76 ms | **−37.5%** |
| `patch add+remove todo 10` | 109.48 µs | 107.06 µs | −2.2% |
| `patch add+remove todo 100` | 1.02 ms | 965.57 µs | −5.3% |
| `patch add+remove todo 1000` | 23.92 ms | 16.38 ms | **−31.5%** |
| `patch move json 8x4` | 421.56 µs | 187.29 µs | **−55.6%** |
| `patch page people 1000` | 296.09 µs | 304.57 µs | +2.9% |
| `patch refilter people 100` | 315.67 µs | 311.38 µs | −1.4% |
| `patch refilter people 1000` | 1.52 ms | 1.49 ms | −2.0% |
| `patch switch view` | 56.57 µs | 54.87 µs | −3.0% |
| `find .checkbox todo 1000` | 3.59 µs | 3.50 µs | −2.4% |
| `find .next people 1000` | 27.25 µs | 26.58 µs | −2.5% |

Read against #8's `RenderCache alone` column, which is the same cache measured
the other way round:

1. **The wins came back, most of the way.** `move json 8x4` recovers −55.6%
   against the old cache's −86.3%/+86.3% pairing — effectively the same row.
   `toggle todo 1000` recovers −37.5% where the old cache was worth −58.9%, so
   this version leaves something on the table there; the likeliest reason is
   bucket thrash between structurally equal todo rows (see below).
2. **The losses did not.** Every row where the old cache cost time is now flat
   or faster: `counter` +1.2% against −9.8%, `refilter people` −1.4/−2.0%
   against −3.3/−3.6%, and both mount-heavy `find` benches −2.4/−2.5% against
   −6.9/−9.7%. Declining is cheaper than keying and missing, which is the whole
   point of the change.
3. **Fingerprinting at creation is not visible.** The `find` and `page` benches
   are the mount-heavy ones and they did not move, which is the O(own fields)
   rule holding: a nested `Obj` mixes its own origin and never its contents, so
   a parent costs its own fields rather than its subtree.

Where the remaining headroom is: two structurally equal instances share a
bucket and evict each other every pass (`render/cache_test.mbt` pins that this
is a thrash and never a wrong subtree). Mixing the innermost loop key into the
bucket would separate them — the one piece of the old `site_cache_key` that
would then have a reason to exist. Measure before adding it; on this corpus the
todo rows have distinct titles, so it may not be what the gap on `toggle todo
1000` is.

Output unchanged: 903 default / 903 native / 8 js green, `gen-views`
drift-clean. The DOM snapshots are the proof the cache never returns stale.

## Not yet tried

Ranked by what the profiles say is left. **#8 removed the render caches, so the
`cache_const_nodes` divergence named below is gone — `viewgen`'s three parses
now produce identical trees, and sharing one is unblocked.**

In the update path (the biggest numbers on the board):

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
  view pipeline calls it once per view per pass. Fixing it means either fewer
  passes — one parse shared between `view_surface` and `compiled_tree`, which
  #8 unblocked by removing the `cache_const_nodes` divergence that made the two
  produce different trees — or an upstream change.
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

`codec_bench_test.mbt` A/B'd the JSON bridge (`S -> Json -> Value` and back,
inside a process-global stash because `Obj`/`Fn` cannot survive JSON) against a
direct field-by-field codec generated from the schema. On the shape the corpus
has — scalars, a list and a dynamic field — encode came out ~2x and decode ~5x,
decode gaining most because the JSON path rebuilt a whole `Json` object just to
hand it to `from_json`. That measurement is what justified generating a second
encoder at all.

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
