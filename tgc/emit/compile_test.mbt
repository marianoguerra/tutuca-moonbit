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
