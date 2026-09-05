// What a `.tutu` card says when it does not lower.
//
// The regression is measured rather than described: before this, the card
// below compiled to 5158 bytes and `tgc check` answered "0 issues", because
// the lowering emitted the blocks it could and the splitter had no reason to
// complain about a handler that was never in them. Repairing the one bad line
// gives 5812 bytes — the difference is the handler that was silently dropped,
// and the card in between rendered correctly and did nothing when clicked.

///|
/// A card whose `logic:` section does not lower. The `view:` and `spec:`
/// sections are deliberately fine, so what is under test is a PARTIAL
/// lowering rather than a file that fails whole.
let broken_tutu : String =
  #|spec:
  #|  Counter ~root:
  #|    field count :: Int
  #|
  #|logic:
  #|  Counter:
  #|    receive inc: it.count +== 1 ~~~ )(
  #|
  #|view:
  #|  Counter:
  #|    @output{@(it.count)}

///|
test "a .tutu card that does not lower says so, by message and by line" {
  let checked = @emit.check_card(broken_tutu, name="counter")
  let errors = checked.issues.filter(i => i.severity == "error")
  assert_true(
    errors.length() > 0,
    msg="a card with a broken `logic:` section reported nothing",
  )
  // The MESSAGE, not the count: a code is a constant and six broken messages
  // once shipped past a green suite in this repo.
  assert_true(
    errors.any(i => i.message.contains("`+==` cannot follow a value")),
    msg="no report named the operator: \{errors.map(i => i.message).join(" | ")}",
  )
  // And it points at the line the author has to edit, not at the section.
  assert_true(
    errors.any(i => i.line == 7),
    msg="no report landed on line 7: \{errors.map(i => i.line.to_string()).join(", ")}",
  )
}

///|
test "…and it does not compile" {
  let failed = try {
    let _ = @emit.compile(broken_tutu, name="counter")
    false
  } catch {
    _ => true
  }
  assert_true(failed, msg="a card that does not lower produced a module")
}

///|
test "a card that lowers cleanly reports nothing and keeps its handler" {
  let good = broken_tutu.replace(
    old="it.count +== 1 ~~~ )(",
    new="it.count += 1",
  )
  let checked = @emit.check_card(good, name="counter")
  assert_eq(
    checked.issues.filter(i => i.severity == "error").map(i => i.message),
    [],
  )
  let out = @emit.compile(good, name="counter")
  assert_eq(out.component, "Counter")
  // The handler is IN it. The broken twin above compiled 654 bytes smaller
  // because this was missing, which is the whole reason the reports matter.
  assert_true(out.wasm.length() > 5500, msg="\{out.wasm.length()} bytes")
}
