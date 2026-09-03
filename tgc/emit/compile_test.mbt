///|
/// The smallest card there is, end to end: it splits, checks, lowers, and the
/// Wax the emitter wrote compiles.
test "a counter card compiles" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Counter { count: Int, label: String }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive inc { .count += 1 }
    #|  receive setTo(n) { .count = n }
    #|  compute shown { $'count: {.count}' }
    #|</script>
    #|<template id="Counter:main" data-root>
    #|  <output @text="$shown"></output>
    #|</template>
  let out = @emit.compile(card, name="counter")
  assert_eq(out.component, "Counter")
  assert_eq(out.fields, ["count", "label"])
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}

///|
/// A card that does not check is REJECTED, whole. That is not a gap in this
/// backend: `.count = nope` does not typecheck against any of them, and a module
/// with a hole where the handler should be would turn a mistake into behaviour.
test "a card that does not check is rejected whole" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Counter { count: Int }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive inc { .count = nope }
    #|</script>
    #|<template id="Counter:main" data-root><b></b></template>
  let got = try {
    let _ = @emit.compile(card, name="counter")
    "compiled"
  } catch {
    e => e.message()
  }
  assert_true(got.contains("does not check"), msg=got)
  assert_true(got.contains("nope"), msg=got)
}

///|
/// A declaration this backend cannot lower is REFUSED — the rest of the card
/// still compiles, and the manifest leaves the refused name out so a host is
/// never told the component answers it.
test "one declaration is refused and the rest still compiles" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Counter { count: Int, rows: Array[String] }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive inc { .count += 1 }
    #|  receive ping { sendAt &.rows[0] 'ping' }
    #|</script>
    #|<template id="Counter:main" data-root><b></b></template>
  let out = @emit.compile(card, name="counter")
  assert_eq(out.refusals.map(r => r.name), ["ping"])
  assert_true(
    out.refusals[0].reason.contains("sendAt"),
    msg=out.refusals[0].reason,
  )
  assert_true(
    out.wax.contains("Counter_receive_inc"),
    msg="the rest did not compile",
  )
  assert_true(
    !out.wax.contains("Counter_receive_ping"),
    msg="a refused handler was emitted",
  )
}

///|
/// The import section is what the card DOES, not what a card could do.
///
/// A module's import section is its complete authority list — it declares no
/// memory and no table, so there is nothing else to reach through — and a host
/// reads it before running a line. That claim is only worth making if the
/// section discriminates: a card that performs no effect must not import the
/// machinery for one.
test "a card that performs no effect imports no effect" {
  let pure =
    #|<script type="tutuca/spec">
    #|  state Pure { n: Int }
    #|</script>
    #|<script type="tutuca/script">
    #|  compute doubled { .n * 2 }
    #|</script>
    #|<template id="Pure" data-root><b @text="$doubled"></b></template>
  let out = @emit.compile(pure, name="pure")
  assert_true(out.wax.contains("op_mul"), msg="the arithmetic it does use")
  for effect in ["eff_send", "eff_ask", "eff_reply", "eff_fail", "eff_log"] {
    assert_false(out.wax.contains("#[import = \"\{effect}\"]"), msg=effect)
  }
  // …and a card that DOES send says so.
  let sender =
    #|<script type="tutuca/spec">
    #|  state Loud { n: Int }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive shout { send 'heard' .n }
    #|</script>
    #|<template id="Loud" data-root><b></b></template>
  let loud = @emit.compile(sender, name="loud")
  assert_true(loud.wax.contains("#[import = \"eff_send\"]"), msg="a sender")
  assert_false(
    loud.wax.contains("#[import = \"eff_ask\"]"),
    msg="but not an asker",
  )
}
