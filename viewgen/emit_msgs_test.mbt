// The declared message buckets.
//
// These are the three the views can never type — Receive, Bubble and
// Response are raised from MoonBit, not written in an `@on` attribute — so
// before the schema they were string-keyed `Array[Value]` in both
// directions. What is asserted here is that the name is now written once.

///|
fn msgs_src(bucket_decls : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/state\">\n" +
    bucket_decls +
    "\nstate Chat { n: Int }\n</script>\n" +
    "<template><p><x text=\".n\"></x></p></template>",
    name="Chat",
    source_file="chat.html",
  )
}

///|
test "a declared receive bucket gets an enum, a decode and a sender" {
  let src = msgs_src("receive Chat { Init, Tick, SetAll(String) }")
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
    "receive Chat { Tick }\nbubble Chat { Changed(Int) }\nresponse Chat { Loaded(String) }",
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
  let src = msgs_src("receive Chat { SetCount(Int), SetByte(UInt8) }")
  // 2.5 arriving at an Int handler is a wrong send, and silently truncating
  // it to 2 would hide that — so the guard drops it into Unknown instead.
  assert_true(src.contains("a0.to_int().to_double() == a0"))
  assert_true(src.contains("=> SetCount(a0.to_int())"))
  // Width buys a range check even though every width emits a MoonBit Int.
  assert_true(src.contains("a0 >= 0.0 && a0 <= 255.0"))
  assert_true(src.contains("a0 >= -2147483648.0 && a0 <= 2147483647.0"))
}

///|
test "a multi-argument message is spelled as a tuple payload" {
  let src = msgs_src("receive Chat { MoveTo(Int, Int) }")
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
  assert_true(src.contains("pub(all) struct ChatState {"))
}

///|
/// A file whose script block answers some of its `@on` names.
fn answered_src(script : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/state\">\nstate Chat { n: Int }\n</script>\n" +
    "<script type=\"tutuca/script\">\n" +
    script +
    "\n</script>\n" +
    "<template><p><x text=\".n\"></x>" +
    "<button @on.click=\"bump 1\">+</button>" +
    "<button @on.click=\"reset\">0</button></p></template>",
    name="Chat",
    source_file="chat.html",
  )
}

///|
/// One generated enum's body, so an assertion can be about ONE of them.
///
/// v2 emits a view name into two enums — `<T>Msg`, which decodes, and the
/// merged `<T>Receive`, which decodes and raises — so `src.contains(…)` stopped
/// being able to say which one it meant.
fn enum_body(src : String, ty : String) -> String {
  let head = "pub(all) enum " + ty + " {"
  guard src.find(head) is Some(i) else { return "" }
  let rest = src[i + head.length():].to_owned()
  match rest.find("\n}") {
    Some(j) => rest[0:j].to_owned()
    None => rest
  }
}

///|
test "a name the script block answers is dropped from the Msg enum" {
  // A5. `update` is composed BEHIND the block, so it is only ever consulted
  // for a dispatch the block did not claim — an arm for `bump` could not run,
  // and making the author write `Some(Bump(_)) => Unhandled` would move the
  // noise rather than remove it.
  let src = answered_src("on bump(d) { .n += d }")
  // Asked of the `<T>Msg` enum BODY rather than of the whole file, because v2
  // emits the same name again in the merged `<T>Receive` — deliberately. That
  // enum is a RAISE surface as well as a decode surface: a component sending
  // `bump` to itself writes `ChatReceive::Bump(1.0).send(ctx)`, and the block
  // answering the name is exactly why it would. `<T>Msg` is decode-only, so
  // dropping an unreachable arm there costs nothing and removes noise.
  assert_false(enum_body(src, "ChatMsg").contains("  Bump(Double)\n"))
  assert_true(enum_body(src, "ChatMsg").contains("  Reset\n"))
  assert_true(src.contains("  Reset\n"))
  assert_true(
    src.contains("Absent, because the script block answers them: bump."),
  )
  // …and the INPUT enum keeps it. That one keys `swap`, which wins over
  // `update` and replaces the node rather than the state — something the
  // block cannot say, so answering a name must not take swapping it away.
  assert_true(src.contains("pub(all) enum ChatInput {"))
  assert_true(src.contains("  Bump\n"))
}

///|
test "a block that answers nothing leaves the enum exactly as it was" {
  let src = answered_src("compute label { .n }")
  assert_true(src.contains("  Bump(Double)\n"))
  assert_true(src.contains("  Reset\n"))
  assert_false(src.contains("Absent, because the script block answers"))
}

///|
test "a declaration the backend refuses is NOT counted as answered" {
  // The arm was not emitted, so `update` still sees the dispatch and still
  // needs a case for it. Reporting it as answered would delete the only place
  // the author could handle it.
  let src = answered_src("on bump(d) { .n[0] = d }")
  assert_true(src.contains("  Bump(Double)\n"))
  assert_false(src.contains("Absent, because the script block answers"))
}

// -- v2: the merge, and the build error it makes possible ---------------------

///|
/// A file with both a schema and views, so the merge has both halves.
fn merged_src(bucket_decls : String, view_body : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/state\">\n" +
    bucket_decls +
    "\nstate Chat { n: Int, name: String }\n</script>\n" +
    "<template><p>" +
    view_body +
    "</p></template>",
    name="Chat",
    source_file="chat.html",
  )
}

///|
/// The message a merged file fails generation with, or "" when it generates.
///
/// `gen_err` in `check_state_test.mbt` is the same idea over a whole document;
/// this one builds the document from the two halves the merge needs.
fn merge_err(bucket_decls : String, view_body : String) -> String {
  gen_err(
    "<script type=\"tutuca/state\">\n" +
    bucket_decls +
    "\nstate Chat { n: Int, name: String }\n</script>\n" +
    "<template><p>" +
    view_body +
    "</p></template>",
    "Chat",
  )
}

///|
test "the receive bucket merges the schema with the view names" {
  // v1 puts these in two enums — `<T>Msg` from the views, `<T>Receive` from the
  // schema — and nothing relates them. v2 has ONE bucket for a message whoever
  // sent it, so one enum holds both.
  let src = merged_src(
    "receive Chat { Init, SetAll(String) }",
    "<button @on.click=\"bump 1\">+</button>" +
    "<button @on.click=\"reset\">0</button>",
  )
  let body = enum_body(src, "ChatReceive")
  // From the schema...
  assert_true(body.contains("  Init\n"))
  assert_true(body.contains("  SetAll(String)\n"))
  // ...and from the views, typed by what the call sites wrote.
  assert_true(body.contains("  Bump(Double)\n"))
  assert_true(body.contains("  Reset\n"))
  // One decode, over one bucket.
  assert_true(
    src.contains("guard d is Receive(name, args) else { return None }"),
  )
  assert_true(src.contains("(\"bump\", [Num(a0)]) => Bump(a0)"))
  // The raise side reaches both halves, which is what makes the merge worth
  // having: a parent can send a name the child's own view also raises.
  assert_true(src.contains("pub fn ChatReceive::send"))
}

///|
test "a view name the schema also declares is declared once, by the schema" {
  // Not twice. The schema wins, and the payload is the schema's — which is
  // exactly why the disagreement below can be reported at all.
  let src = merged_src(
    "receive Chat { Bump(Int) }", "<button @on.click=\"bump 1\">+</button>",
  )
  let body = enum_body(src, "ChatReceive")
  assert_true(body.contains("  Bump(Int)\n"))
  assert_false(body.contains("  Bump(Double)\n"))
}

///|
test "a call site that disagrees with the schema is a build error" {
  // THE new error. v1 cannot report it: the view's `bump` is a `ChatMsg`
  // variant and the schema's is a `ChatReceive` variant, and nothing in the
  // generator ever puts the two side by side.
  assert_eq(
    merge_err(
      "receive Chat { Bump(Int) }", "<button @on.click=\"bump 1 2\">+</button>",
    ),
    "`bump` is declared in the state block as `Bump(Int)` and called from @on.click as `bump(a number, a number)` — the schema declares what a message carries, so the call sites have to match it",
  )
  assert_eq(
    merge_err(
      "receive Chat { Bump(Int) }", "<button @on.click=\"bump 'x'\">+</button>",
    ),
    "`bump` is declared in the state block as `Bump(Int)` and called from @on.click as `bump(text)` — the schema declares what a message carries, so the call sites have to match it",
  )
  // Agreeing is silent, and so is a call site the inference could not read:
  // unknown is not wrong, which is the rule the whole generator turns on.
  assert_eq(
    merge_err(
      "receive Chat { Bump(Int) }", "<button @on.click=\"bump 1\">+</button>",
    ),
    "",
  )
  assert_eq(
    merge_err(
      "receive Chat { Bump(Int) }", "<button @on.click=\"bump .n\">+</button>",
    ),
    "",
  )
}

///|
test "an intent bucket gets an enum, a decode and a dispatch" {
  let src = msgs_src("intent Chat { RowPicked(Int), SaveDraft(String) }")
  assert_true(src.contains("pub(all) enum ChatIntent {"))
  assert_true(src.contains("  RowPicked(Int)\n"))
  // Its own bucket, so an intent named `rowPicked` and a message named
  // `rowPicked` cannot be confused for each other.
  assert_true(
    src.contains("guard d is Intent(name, args) else { return None }"),
  )
  // `dispatch` replaces `bubble`, and it takes the route — which is the whole
  // of what v2 added. The default is not spelled here; it is asked for.
  assert_true(src.contains("pub fn ChatIntent::dispatch("))
  assert_true(
    src.contains("opts? : @tutuca.IntentOpts = @tutuca.IntentOpts::new()"),
  )
  assert_true(src.contains("ctx.intent(name, args, opts)"))
}
