///|
/// A card, end to end, through the one door there is.
///
/// The card compiler takes SOURCE TEXT and reads it internally, so a page
/// hands `compile` a `.tutu` and gets a module: no second entry point, and
/// nothing for a host to choose between.
test "a .tutu card compiles" {
  let card =
    #|spec:
    #|  Counter ~root:
    #|    field count :: Int
    #|    field label :: String
    #|
    #|logic:
    #|  Counter:
    #|    receive inc: it.count += 1
    #|    receive set_to(n): it.count := n
    #|    compute shown(): @str{count: @(it.count)}
    #|
    #|view:
    #|  Counter:
    #|    output():
    #|      @(shown())
  let out = @emit.compile(card, name="counter")
  assert_eq(out.component, "Counter")
  assert_eq(out.fields, ["count", "label"])
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}

///|
/// A card reads a field off the object a host answered with.
///
/// The shape every service answer has: `ask` goes out, a `{ms, iso, …}` comes
/// back, and the handler wants one key of it. `Any` is the honest declaration
/// for such a payload — it IS a `@tutuca.Value` — and it binds raw, the same
/// binder an undeclared argument gets.
///
/// It was refused twice over. The reader read `t.iso` as the loop binding
/// `@t`, so the message named a construct the author had not written; and once
/// that was fixed the backend refused an `Any` beside the scalar types, whose
/// reason — "none of the types a call site can state has fields" — is true of
/// `Int` and `String` and is exactly false of this one. A refused handler is
/// SILENT in a card: the module compiles, the dispatch table is short one
/// name, and the clock never ticks.
test "a card reads a field off an Any payload" {
  let card =
    #|spec:
    #|  Clock ~root:
    #|    field now :: Any
    #|    message ticked(Any)
    #|
    #|logic:
    #|  Clock:
    #|    receive ticked(t): it.now := t.iso
    #|
    #|view:
    #|  Clock:
    #|    output():
    #|      @(it.now)
  let out = @emit.compile(card, name="clock")
  assert_eq(out.refusals.map(r => "\{r.name}: \{r.reason}"), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}

///|
/// A SCALAR argument still has no fields, and the card is turned away.
///
/// The other side of the rule above, kept because it is the reason the guard
/// exists: a typed argument arrives unwrapped — `Str(name)` binds a String —
/// so there is nothing to read a field off. This one is a REJECTION rather
/// than a refusal, which is the better answer: the author gets a line and a
/// name instead of a card that draws and does nothing.
test "a field read on a scalar argument names the type it got" {
  let card =
    #|spec:
    #|  Clock ~root:
    #|    field now :: Any
    #|    message ticked(String)
    #|
    #|logic:
    #|  Clock:
    #|    receive ticked(t): it.now := t.iso
    #|
    #|view:
    #|  Clock:
    #|    output():
    #|      @(it.now)
  let checked = @emit.check_card(card, name="clock")
  let errors = checked.issues.filter(i => i.severity == "error")
  assert_true(
    errors.any(i => i.message.contains("`String` has no field `iso`")),
    msg="no report named the type: \{errors.map(i => i.message).join(" | ")}",
  )
}

///|
/// A protocol with no members, through the whole compiler.
///
/// The marker case: an id, no operations, and a slot that means "anything that
/// claims this". Both halves are here because they failed together — the
/// declaration was dropped for having no body, so the field typed against it
/// was refused for naming a protocol nobody declared.
test "a marker protocol reaches a card's manifest" {
  let card =
    #|spec:
    #|  protocol Value = "x/Value@1"
    #|
    #|  Slot ~root:
    #|    field held :: Instance.of(Value)
    #|
    #|view:
    #|  Slot:
    #|    div():
    #|      render(it.held)
  let out = @emit.compile(card, name="slot")
  assert_eq(out.component, "Slot")
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}
