# Optional Markdown bundle measurement

Measured on 2026-09-09 with `moon 0.1.20260904` and
`moonc v0.10.12+1634b282e (2026-09-07)`.

Command: `moon build --target wasm-gc --release demo/counter_wasm`.
Artifact: `_build/wasm-gc/release/build/demo/counter_wasm/counter_wasm.wasm`.
Sizes are raw bytes, before compression or a separate Wasm optimizer.

| Configuration | Bytes |
|---|---:|
| Baseline with Markdown linked by app construction | 661,309 |
| Optional Markdown, counter without the factory | 608,939 |
| Reduction | 52,370 (7.9%) |

Both builds use the same installed compiler and dependency cache. The baseline
comes from Git commit `307a5e05`, with only the three removed numeric-parser
calls and their import updated so it builds with this compiler. The comparison
measures the complete cleanup's effect on this counter; it is not a runtime
performance measurement or a size guarantee for other applications.
