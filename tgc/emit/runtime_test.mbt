///|
/// The embedded runtime source is a module a compiler accepts.
///
/// Without this the embed is a string. `rt.wax` is the authoritative copy and
/// `cmd/tgc build` compiles it directly, so a stale `rt_src_gen.mbt` would go
/// unnoticed until a page failed to mount — which is a long way from the edit
/// that caused it.
test "the runtime compiles from its embedded source" {
  let bytes = @emit.compile_runtime()
  assert_true(bytes.length() > 1000, msg="\{bytes.length()} bytes")
  // A wasm module, not a string that happens to be long: `\0asm`.
  assert_eq(bytes[0], b'\x00')
  assert_eq(bytes[1], b'\x61')
  assert_eq(bytes[2], b'\x73')
  assert_eq(bytes[3], b'\x6d')
}
