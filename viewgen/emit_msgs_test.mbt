// The declared message buckets.
//
// These are the three the views can never type — Receive, Bubble and
// Response are raised from MoonBit, not written in an `@on` attribute — so
// before the schema they were string-keyed `Array[Value]` in both
// directions. What is asserted here is that the name is now written once.

///|
fn msgs_src(bucket_decls : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/state\">\ninterface chat {\n" +
    bucket_decls +
    "\nrecord state { n: s32 }\n}\n</script>\n" +
    "<template><p><x text=\".n\"></x></p></template>",
    name="Chat",
    source_file="chat.html",
  )
}

///|
test "a declared receive bucket gets an enum, a decode and a sender" {
  let src = msgs_src("variant receive { init, tick, set-all(string) }")
  assert_true(src.contains("pub(all) enum ChatReceive {"))
  assert_true(src.contains("  Init\n"))
  assert_true(src.contains("  SetAll(String)\n"))
  // The escape hatch is mandatory: a dispatch the schema does not declare
  // still has to land somewhere.
  assert_true(src.contains("Unknown(String, Array[@tutuca.Value])"))
  // Decode is scoped to its own bucket, so a Receive named `tick` and a
  // Bubble named `tick` cannot be confused for each other.
  assert_true(
    src.contains("guard d is Receive(name, args) else { return None }"),
  )
  assert_true(src.contains("(\"setAll\", [Str(a0)]) => SetAll(a0)"))
  // ...and the raise side, so the name is never written as a string twice.
  assert_true(src.contains("pub fn ChatReceive::to_dispatch"))
  // Unqualified, resolved by the annotated return type — the playground's
  // @tutuca facade re-exports the Value TYPE but not its constructors, so a
  // qualified `@tutuca.Str(...)` would generate fine and then fail to compile
  // in the browser.
  assert_true(src.contains("SetAll(a0) => (\"setAll\", [Str(a0)])"))
  assert_true(
    src.contains(
      "pub fn ChatReceive::send(self : ChatReceive, ctx : &@tutuca.Ctx)",
    ),
  )
  assert_true(src.contains("ctx.send(name, args)"))
}

///|
test "each bucket decodes only its own dispatch arm" {
  let src = msgs_src(
    "variant receive { tick }\nvariant bubble { changed(s32) }\nvariant response { loaded(string) }",
  )
  assert_true(src.contains("guard d is Receive(name, args)"))
  assert_true(src.contains("guard d is Bubble(name, args)"))
  assert_true(src.contains("guard d is Response(name, args)"))
  assert_true(src.contains("pub fn ChatBubble::bubble(self : ChatBubble"))
  assert_true(src.contains("ctx.bubble(name, args)"))
  // A response is raised by the host answering a request, never by the
  // component, so it gets a decode but no sender.
  assert_true(src.contains("pub(all) enum ChatResponse {"))
  assert_false(src.contains("ChatResponse::send"))
  assert_false(src.contains("ChatResponse::bubble"))
}

///|
test "an integer payload is range- and integrality-checked, not truncated" {
  let src = msgs_src("variant receive { set-count(s32), set-byte(u8) }")
  // 2.5 arriving at an s32 handler is a wrong send, and silently truncating
  // it to 2 would hide that — so the guard drops it into Unknown instead.
  assert_true(src.contains("a0.to_int().to_double() == a0"))
  assert_true(src.contains("=> SetCount(a0.to_int())"))
  // Width buys a range check even though every width emits a MoonBit Int.
  assert_true(src.contains("a0 >= 0.0 && a0 <= 255.0"))
  assert_true(src.contains("a0 >= -2147483648.0 && a0 <= 2147483647.0"))
}

///|
test "a multi-argument message is spelled as a tuple payload" {
  let src = msgs_src("variant receive { move-to(tuple<s32, s32>) }")
  assert_true(src.contains("  MoveTo(Int, Int)\n"))
  assert_true(src.contains("[Num(a0), Num(a1)]"))
  assert_true(src.contains("MoveTo(a0.to_int(), a1.to_int())"))
}

///|
test "a component with no declared buckets emits none of this" {
  let src = msgs_src("")
  assert_false(src.contains("ChatReceive"))
  assert_false(src.contains("ChatBubble"))
  assert_false(src.contains("ChatResponse"))
  // ...but the Input bucket the views DO type is untouched.
  assert_true(src.contains("priv struct ChatState {"))
}
