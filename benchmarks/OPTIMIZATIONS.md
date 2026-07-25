# View pipeline performance log

One entry per measured change to `viewgen/` (and below it `anode/`), in the
order they landed. Method: `moon bench --release benchmarks` on wasm-gc and
native, back to back, before and after. A change that does not move a number
gets reverted, not kept "because it should be faster".

Every entry keeps the workload's output checksums unchanged
(`viewparse_bench_test.mbt` pins them) unless it says otherwise.

## Baseline — 2026-07-25, `7def62d`

108 views, 58 494 chars. Mean of 10 × N runs.

| Stage     | wasm-gc  | native   |
|-----------|----------|----------|
| `split`   |  4.10 ms |  3.58 ms |
| `surface` |  8.67 ms |  8.14 ms |
| `build`   |  8.42 ms |  8.10 ms |
| `gen`     | 26.66 ms | 23.21 ms |

Where the time goes (js/V8 profile, self time — the wasmtime profile agrees on
the ranking but over-weights `moonbit.string_literal`):

```
 9.2%  JSArray::push
 9.2%  (garbage collector)
 6.7%  html::Tokenizer::new
 5.6%  html::Tokenizer::next_token
 4.3%  String::to_array
 3.4%  viewgen::split_file
 2.4%  viewgen::slice_without_styles
 2.4%  html::TreeBuilder::process_in_body_mode
 1.9%  html::TreeBuilder::parse
 1.6%  viewgen::dedent
```

Reading it: about a third of `gen` is the HTML parser, reached once per view —
and `gen` reaches it *three* times per view (`emit_module` → `view_surface`,
then `ir_supported`, then `emit_ir_module`). The rest is `split_file`'s own
slicing plus string building in the emitters.
