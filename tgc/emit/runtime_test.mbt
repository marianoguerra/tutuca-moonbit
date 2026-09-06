///|
/// The embedded runtime is a module, and the one a page gets.
///
/// A page that hosts `tgc` components fetches `tutuca-rt.wasm` and cannot reach
/// this repository's `_build`, so `rt_src_gen.mbt` travels in the library and
/// this is what says it still compiles.
test "the embedded runtime compiles" {
  let bytes = @emit.compile_runtime()
  assert_true(bytes.length() > 1000)
  assert_eq(bytes[0], b'\x00')
  assert_eq(bytes[1], b'a')
  assert_eq(bytes[2], b's')
  assert_eq(bytes[3], b'm')
}

///|
/// Every name a generated card imports is a name the runtime exports.
///
/// This is the check `tgc/1` did not have. The vocabulary lived in `tgc/emit` as
/// eighty signature STRINGS spliced into generated Wax, `rt.wap` exported
/// whatever it happened to export, and nothing compared them — so a rename on
/// one side surfaced as a browser refusing to instantiate a module, at the far
/// end of a build, with `LinkError` for a message.
///
/// It checks NAMES rather than signatures. A signature mismatch is caught by
/// the engine at link time and says so; a missing name is caught here, where the
/// two lists are in the same room.
///
/// The `tut` namespace has TWO suppliers — `tgc/rt` for the pure functions, the
/// host for the ten effects — and writing the test made that explicit, because
/// the first version asked the runtime for `eff_send` and was right to fail.
test "the runtime exports the whole vocabulary" {
  let bytes = @emit.compile_runtime()
  let exported = exports_of(bytes)
  let missing : Array[String] = []
  let overreach : Array[String] = []
  for f in @abi.vocab() {
    let there = exported.contains(f.import_name)
    match f.supplier {
      Runtime => if !there { missing.push(f.import_name) }
      // The other half, and the more interesting one: an effect is the HOST's,
      // so a runtime that exported one would be a runtime that could perform
      // it. `tut` is assembled from two sources on purpose.
      Host => if there { overreach.push(f.import_name) }
    }
  }
  assert_eq(missing, [], msg="imported by cards, exported by nothing")
  assert_eq(overreach, [], msg="an effect the runtime should not be able to do")
}

///|
/// The export names of a wasm module, read out of section 7.
///
/// Twenty lines of decoder rather than a dependency: the alternative is asking
/// the wasm model to parse a module it just emitted, which tests the encoder
/// against itself.
fn exports_of(b : Bytes) -> Array[String] {
  let out : Array[String] = []
  let mut i = 8
  while i < b.length() {
    let id = b[i].to_int()
    i += 1
    let (len, next) = uleb(b, i)
    i = next
    if id == 7 {
      let (count, after) = uleb(b, i)
      let mut j = after
      for _ in 0..<count {
        let (nlen, nstart) = uleb(b, j)
        let name = StringBuilder()
        for k in nstart..<(nstart + nlen) {
          name.write_char(b[k].to_int().unsafe_to_char())
        }
        out.push(name.to_string())
        // one byte of kind, then the index
        let (_, past) = uleb(b, nstart + nlen + 1)
        j = past
      }
      return out
    }
    i += len
  }
  out
}

///|
/// One LEB128 unsigned integer: its value, and where it ended.
fn uleb(b : Bytes, at : Int) -> (Int, Int) {
  let mut i = at
  let mut value = 0
  let mut shift = 0
  while i < b.length() {
    let byte = b[i].to_int()
    i += 1
    value = value | ((byte & 0x7f) << shift)
    shift += 7
    if (byte & 0x80) == 0 {
      break
    }
  }
  (value, i)
}
