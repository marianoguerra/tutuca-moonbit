# View pipeline performance log

One entry per measured change to `viewgen/` (and below it `anode/`), in the
order they landed. Method: `moon bench --release benchmarks` on wasm-gc and
native, back to back, before and after; for a change under ~5% the affected
bench is run 3× on each side (`-p marianoguerra/tutuca/benchmarks -f <file> -i
<n>`) and the medians compared. A change that does not move a number gets
reverted, not kept "because it should be faster".

Every entry keeps the workload's output checksums unchanged
(`viewparse_bench_test.mbt` pins them), and `cmd/dev -- gen-views` followed by
`git diff --exit-code` confirms every checked-in `*_view_gen.mbt` still
regenerates byte-identically.

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
reimplement them. Output is byte-identical, which the 797-test suite (a good
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

## Runtime numbers — 2026-07-25, after #1–#4

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

Three things fall out of this table, all still true after #4:

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

## Not yet tried

Ranked by what the profiles say is left.

In the update path (the biggest numbers on the board):

- **Why the `RenderCache` misses.** 5.6 ms of a no-op on 1000 rows says almost
  nothing is being reused. Either the transactor is not preserving the identity of
  untouched rows, or the per-slot cache key differs between passes, or `@each`
  item sites are not cache sites at all. Worth answering before optimizing
  anything below it.
- **Attribute-map equality** (`Map::contains_kv` 6.2% + much of `Eq::equal`
  9.6%). Comparing two attribute maps hashes every key; a diff does it per node
  per pass. Comparing the two entry lists directly, or an identity check first,
  would skip most of it.
- **`site_cache_key`** builds an interpolated string per render site per pass —
  and calls `view_trail()` (which allocates via `Array::rev`) twice per site once
  you count `render_site`'s own call. Same shape as #4, one layer up.
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
  passes (one parse shared between `view_surface` and `compiled_tree`, which
  currently differ deliberately in `cache_const_nodes`) or an upstream change.
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
