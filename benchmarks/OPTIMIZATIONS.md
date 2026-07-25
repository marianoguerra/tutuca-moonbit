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

## Runtime baseline — 2026-07-25, after #1–#3

### Render: mount + first render + serialize

| Workload           | wasm-gc  | native   |
|--------------------|----------|----------|
| `list 10`          |  46.7 µs |  85.0 µs |
| `list 100`         | 402.6 µs | 712.6 µs |
| `list 1000`        |  7.45 ms |  7.51 ms |
| `todo 0`           |  10.7 µs |  17.7 µs |
| `todo 10`          | 156.8 µs | 210.8 µs |
| `todo 100`         |  1.73 ms |  1.94 ms |
| `todo 1000`        | 28.49 ms | 22.30 ms |
| `people 1000`      | 471.9 µs | 585.6 µs |
| `json 8x4` (deep)  |  5.05 ms |  6.75 ms |
| `all examples`     | 30.40 ms | 23.33 ms |

`todo` (a child component per row) costs ~3× `list` (plain values) at every size,
and both are linear in the row count. `people 1000` is cheap because pagination
bounds the DOM even though the pipeline still walks all 1000 items — the filter
itself is ~130 µs of that.

### Diff/patch: two round-trip passes per number

| Workload                     | wasm-gc  | native   |
|------------------------------|----------|----------|
| `counter`                    |  21.4 µs |  33.5 µs |
| `switch view`                |  61.8 µs |  87.7 µs |
| `noop todo 10`               |  97.8 µs | 151.7 µs |
| `toggle todo 10`             | 105.7 µs | 146.5 µs |
| `add+remove todo 10`         | 129.2 µs | 185.7 µs |
| `move json 8x4`              | 193.1 µs | 218.3 µs |
| `page people 1000`           | 557.3 µs | 764.4 µs |
| `refilter people 1000`       |  1.65 ms |  1.59 ms |
| `toggle todo 100`            | 718.8 µs | 932.4 µs |
| `add+remove todo 100`        |  1.16 ms |  1.48 ms |
| `noop todo 1000`             | 10.46 ms | 11.11 ms |
| `toggle todo 1000`           | 12.74 ms | 14.43 ms |
| `add+remove todo 1000`       | 22.92 ms | 28.38 ms |

Three things fall out of this table:

1. **A one-row change costs a whole-list pass.** Ticking one checkbox in a
   1000-row list is 7.2 ms (half of 14.43), against 22.3 ms to mount and render
   the entire list from nothing. The `RenderCache` exists to short-circuit
   subtrees whose value is physically unchanged, and the transactor swaps state
   with structural sharing, so in principle 999 rows should hit it.
2. **A no-op costs almost as much as a real change.** `noop todo 1000` is 11.11 ms
   against `toggle`'s 14.43: setting a field to the value it already holds does
   77% of the work of changing it. The ~2.7 ms difference is the actual DOM write;
   everything else is re-render and diff that could not have mattered.
3. **The list-shape change is superlinear.** `add+remove` goes 185.7 µs → 1.48 ms
   → 28.38 ms for 10 → 100 → 1000 rows: 8.0× then 19.2× for 10× the rows. Part of
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
- **`Meta::to_comment_text`** (1.8%): the `§Comp§`/`§Each§` meta comments are
  rebuilt as strings on every pass. tw-mb #3 and #13 were exactly this.
- **State through `Json`** (2.2% in `stringify`): typed state derives
  `ToJson`/`FromJson`, and an update appears to round-trip through it.
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
