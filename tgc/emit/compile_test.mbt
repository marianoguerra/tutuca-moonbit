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
    #|  receive ping { .count = @value }
    #|</script>
    #|<template id="Counter:main" data-root><b></b></template>
  let out = @emit.compile(card, name="counter")
  assert_eq(out.refusals.map(r => r.name), ["ping"])
  assert_true(
    out.refusals[0].reason.contains("handed no row"),
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

///|
/// `sendAt` addresses a PLACE, and a place is reified rather than read.
///
/// The walk happens when the card compiles; which wire case a keyed step
/// becomes is decided at run time, because `.rows[k]` and `.panes[k]` are the
/// same syntax and a list indexes where a map keys.
test "sendAt reifies its place" {
  let card =
    #|<script type="tutuca/spec">
    #|  struct Pane { inner: String }
    #|  state Board { rows: Array[String], panes: Map[String, Pane] }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive poke(i) { sendAt &.rows[i] 'ping' }
    #|  receive named(k) { sendAt &.panes[k].inner 'ping' 1 }
    #|  receive whole { sendAt &.rows 'ping' }
    #|</script>
    #|<template id="Board" data-root><b></b></template>
  let out = @emit.compile(card, name="board")
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wax.contains("eff_send_at"), msg="the effect")
  assert_true(out.wax.contains("mk_step_key(\"rows\""), msg="a keyed step")
  assert_true(
    out.wax.contains("mk_step_field(\"inner\")"),
    msg="a field after a key",
  )
  assert_true(out.wax.contains("mk_step_field(\"rows\")"), msg="a bare field")
}

///|
/// A key READ FROM LIVE STATE is refused, and the reason is the host's rather
/// than this backend's: `&.panes[.sel]` means "re-read `.sel` on every
/// dispatch", and freezing it would be a different path that looks like this
/// one.
test "a sendAt key read from live state is refused" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Board { panes: Map[String, String], sel: String }
    #|</script>
    #|<script type="tutuca/script">
    #|  receive poke { sendAt &.panes[.sel] 'ping' }
    #|</script>
    #|<template id="Board" data-root><b></b></template>
  let out = @emit.compile(card, name="board")
  assert_eq(out.refusals.map(r => r.name), ["poke"])
  assert_true(
    out.refusals[0].reason.contains("re-read"),
    msg=out.refusals[0].reason,
  )
}

///|
/// Every component says which module made it, and says it on the COMPONENT
/// rather than only on the manifest around it.
///
/// `<C>_desc()` is this same value, so this is the only place an instance can
/// answer "where did you come from". Without it a host holding instances from
/// two modules has nothing to tell them apart — a handle is minted per module
/// and `tg_inst.id` is a per-module counter starting at zero — and wrapping a
/// foreign instance with the wrong module's schema renders one component's view
/// over another's fields, silently and in both directions.
test "a component's descriptor names the module that made it" {
  let card =
    #|<script type="tutuca/spec">
    #|  state Hole { child: Instance }
    #|  state Text { body: String }
    #|</script>
    #|<template id="Hole:main" data-root><x render=".child"></x></template>
    #|<template id="Text:main"><b @text=".body"></b></template>
  let out = @emit.compile(card, name="kit")
  let str_at = (j : Json, key : String) => {
    match j {
      Object(o) =>
        match o.get(key) {
          Some(String(s)) => s
          _ => ""
        }
      _ => ""
    }
  }
  assert_eq(str_at(out.manifest, "moduleName"), "kit")
  // Both of them, not just the root: a card's second component crosses a
  // boundary exactly as often as its first.
  let named = match out.manifest {
    Object(m) =>
      match m.get("components") {
        Some(Array(cs)) => cs.map(c => (str_at(c, "name"), str_at(c, "module")))
        _ => []
      }
    _ => []
  }
  assert_eq(named, [("Hole", "kit"), ("Text", "kit")])
}
