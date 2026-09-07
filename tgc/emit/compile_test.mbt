///|
/// The smallest card there is, end to end: it splits, checks, lowers, and the
/// wap the emitter wrote compiles.
test "a counter card compiles" {
  let card =
    #|spec:
    #|  Counter ~root:
    #|    field count :: Int
    #|    field label :: String
    #|
    #|logic:
    #|  Counter:
    #|    receive inc:
    #|      it.count += 1
    #|
    #|    receive setTo(n):
    #|      it.count := n
    #|
    #|    compute shown:
    #|      @str{count: @(it.count)}
    #|
    #|view:
    #|  Counter:
    #|    @output{@(shown())}
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
    #|spec:
    #|  Counter ~root:
    #|    field count :: Int
    #|
    #|logic:
    #|  Counter:
    #|    receive inc:
    #|      it.count := nope
    #|
    #|view:
    #|  Counter:
    #|    @b{}
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
///
/// `clear` is the one construct that reaches this from a `.tutu` card, and it
/// is not a contrived one: it is the only spelling for emptying a list — there
/// is no list literal to assign instead — so a card that empties a list loses
/// that handler and keeps the others.
test "one declaration is refused and the rest still compiles" {
  let card =
    #|spec:
    #|  Counter ~root:
    #|    field count :: Int
    #|    field rows :: List.of(String)
    #|
    #|logic:
    #|  Counter:
    #|    receive inc:
    #|      it.count += 1
    #|
    #|    receive wipe:
    #|      it.rows.clear()
    #|
    #|view:
    #|  Counter:
    #|    @b{}
  let out = @emit.compile(card, name="counter")
  assert_eq(out.refusals.map(r => r.name), ["wipe"])
  assert_true(
    out.refusals[0].reason.contains("no backend has ever"),
    msg=out.refusals[0].reason,
  )
  assert_true(
    out.wap.contains("Counter_receive_inc"),
    msg="the rest did not compile",
  )
  assert_true(
    !out.wap.contains("Counter_receive_wipe"),
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
    #|spec:
    #|  Pure ~root:
    #|    field n :: Int
    #|
    #|logic:
    #|  Pure:
    #|    compute doubled:
    #|      it.n * 2
    #|
    #|view:
    #|  Pure:
    #|    @b{@(doubled())}
  let out = @emit.compile(pure, name="pure")
  assert_true(out.wap.contains("op_mul"), msg="the arithmetic it does use")
  // The wap spelling: one `import "tut":` block, one `fn` line per name. An
  // effect a card does not perform is not in it — which is the property, not
  // the syntax, and `tgc/SECURITY.md` rests on it.
  for effect in ["eff_send", "eff_ask", "eff_reply", "eff_fail", "eff_log"] {
    assert_false(out.wap.contains("fn \{effect}("), msg=effect)
  }
  // …and a card that DOES send says so.
  let sender =
    #|spec:
    #|  Loud ~root:
    #|    field n :: Int
    #|
    #|logic:
    #|  Loud:
    #|    receive shout:
    #|      send("heard", it.n)
    #|
    #|view:
    #|  Loud:
    #|    @b{}
  let loud = @emit.compile(sender, name="loud")
  assert_true(loud.wap.contains("fn eff_send("), msg="a sender")
  assert_false(loud.wap.contains("fn eff_ask("), msg="but not an asker")
}

///|
/// `sendAt` addresses a PLACE, and a place is reified rather than read.
///
/// The walk happens when the card compiles; which wire case a keyed step
/// becomes is decided at run time, because `.rows[k]` and `.panes[k]` are the
/// same syntax and a list indexes where a map keys.
test "sendAt reifies its place" {
  let card =
    #|spec:
    #|  struct Pane(inner :: String)
    #|
    #|  Board ~root:
    #|    field rows :: List.of(String)
    #|    field panes :: Map.of(String, Pane)
    #|
    #|logic:
    #|  Board:
    #|    receive poke(i):
    #|      send("ping", ~to: it.rows[i])
    #|
    #|    receive named(k):
    #|      send("ping", 1, ~to: it.panes[k].inner)
    #|
    #|    receive whole:
    #|      send("ping", ~to: it.rows)
    #|
    #|view:
    #|  Board:
    #|    @b{}
  let out = @emit.compile(card, name="board")
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wap.contains("eff_send_at"), msg="the effect")
  assert_true(out.wap.contains("mk_step_key(\"rows\""), msg="a keyed step")
  assert_true(
    out.wap.contains("mk_step_field(\"inner\")"),
    msg="a field after a key",
  )
  assert_true(out.wap.contains("mk_step_field(\"rows\")"), msg="a bare field")
}

///|
/// A key READ FROM LIVE STATE is refused, and the reason is the host's rather
/// than this backend's: `&.panes[.sel]` means "re-read `.sel` on every
/// dispatch", and freezing it would be a different path that looks like this
/// one.
test "a sendAt key read from live state is refused" {
  let card =
    #|spec:
    #|  Board ~root:
    #|    field panes :: Map.of(String, String)
    #|    field sel :: String
    #|
    #|logic:
    #|  Board:
    #|    receive poke:
    #|      send("ping", ~to: it.panes[it.sel])
    #|
    #|view:
    #|  Board:
    #|    @b{}
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
    #|spec:
    #|  Hole ~root:
    #|    field child :: Instance
    #|
    #|  Text:
    #|    field body :: String
    #|
    #|view:
    #|  Hole:
    #|    @render(it.child)
    #|
    #|  Text:
    #|    @b{@(it.body)}
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
