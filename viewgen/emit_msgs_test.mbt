// The declared message buckets.
//
// These are the three the views can never type — Receive, Bubble and
// Response are raised from MoonBit, not written in an `@on` attribute — so
// before the schema they were string-keyed `Array[Value]` in both
// directions. What is asserted here is that the name is now written once.

///|
fn msgs_src(bucket_decls : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/spec\">\n" +
    bucket_decls +
    "\nstate Chat { n: Int }\n</script>\n" +
    "<template><p><x text=\".n\"></x></p></template>",
    name="Chat",
    source_file="chat.html",
  )
}

///|
test "a declared receive bucket gets an enum, a decode and a sender" {
  let src = msgs_src("handle Chat { message { init, tick, setAll(String) } }")
  assert_true(src.contains("pub(all) enum ChatMsg {"))
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
  assert_true(src.contains("pub fn ChatMsg::to_dispatch"))
  // Unqualified, resolved by the annotated return type — the playground's
  // @tutuca facade re-exports the Value TYPE but not its constructors, so a
  // qualified `@tutuca.Str(...)` would generate fine and then fail to compile
  // in the browser.
  assert_true(src.contains("SetAll(a0) => (\"setAll\", [Str(a0)])"))
  assert_true(
    src.contains("pub fn ChatMsg::send(self : ChatMsg, ctx : &@tutuca.Ctx)"),
  )
  assert_true(src.contains("ctx.send(name, args)"))
}

///|
test "each bucket decodes only its own dispatch arm" {
  let src = msgs_src("handle Chat { message { tick } intent { Changed(Int) } }")
  assert_true(src.contains("guard d is Receive(name, args)"))
  assert_true(src.contains("guard d is Intent(name, args)"))
  // Two buckets, two enums, and neither decodes the other's arm.
  assert_true(src.contains("pub(all) enum ChatIntent {"))
  assert_false(src.contains("ChatMsg::from_dispatch(Intent"))
  assert_false(src.contains("ChatIntent::from_dispatch(Receive"))
}

///|
test "an integer payload is range- and integrality-checked, not truncated" {
  let src = msgs_src(
    "handle Chat { message { setCount(Int), setByte(UInt8) } }",
  )
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
  let src = msgs_src("handle Chat { message { moveTo(Int, Int) } }")
  assert_true(src.contains("  MoveTo(Int, Int)\n"))
  assert_true(src.contains("[Num(a0), Num(a1)]"))
  assert_true(src.contains("MoveTo(a0.to_int(), a1.to_int())"))
}

///|
/// A payload the schema declares is DECODED, at the type it declares.
///
/// This used to be the one thing a schema could say that bought nothing: every
/// composite payload was erased to `@tutuca.Value` and every handler unpacked
/// it by hand, so `loadDataOk(Array[Row])` and `loadDataOk(Any)` generated the
/// same code. The decode is the state codec's own — `dec_stmts` — so a payload
/// and a field of the same declared type are read by one rule rather than two.
test "a composite payload is decoded at its declared type, not erased" {
  let src = msgs_src(
    "struct Row { title: String, n: Int }\n" +
    "handle Chat { message { gotRows(Array[Row]), errs(Map[String, String]) } }",
  )
  assert_true(src.contains("  GotRows(Array[ChatRow])\n"))
  assert_true(src.contains("  Errs(Map[String, String])\n"))
  // A function and not an inline arm: `dec_stmts` writes statements that
  // `return None`, which a `match` arm has nowhere to do.
  assert_true(
    src.contains(
      "fn chat_msg_got_rows_of_args(args : Array[@tutuca.Value]) -> ChatMsg?",
    ),
  )
  assert_true(src.contains("guard chat_row_of_value(e1_0) is Some(x1_0)"))
  // ...and the raise side converts back through the same projection, so the
  // name and the shape are both written once.
  assert_true(src.contains("GotRows(a0) => (\"gotRows\", ["))
}

///|
/// `Any` and a component slot are NOT decoded, because `@tutuca.Value` is what
/// they declare — there is nothing to read them into.
test "an Any payload stays the Value it declares" {
  let src = msgs_src("handle Chat { message { raw(Any), kid(Instance) } }")
  assert_true(src.contains("  Raw(@tutuca.Value)\n"))
  assert_true(src.contains("  Kid(@tutuca.Value)\n"))
  assert_true(src.contains("(\"raw\", [a0]) => Raw(a0)"))
  assert_false(src.contains("chat_msg_raw_of_args"))
}

///|
/// A DECLARED name whose arguments do not fit is reported.
///
/// `Unknown` answers two questions — nobody declares this name, and this name
/// is declared here and was handed the wrong shape — and the second is a bug
/// in the sender that used to be indistinguishable from silence. The decode's
/// ANSWER is unchanged; only the saying is new.
test "a declared name handed the wrong shape is reported, not just Unknown" {
  let src = msgs_src(
    "struct Row { title: String }\n" +
    "handle Chat { message { setAll(String), gotRows(Array[Row]) } }",
  )
  // The scalar arm cannot match, so it falls to `_` — which looks the name up
  // before answering, and quotes what the schema declared.
  assert_true(src.contains("@tutuca.bad_payload(name, \"String\", args)"))
  // The composite arm fails inside its decoder and says so there.
  assert_true(src.contains("@tutuca.bad_payload(name, \"Array[Row]\", args)"))
  // A name nothing declares still says nothing: an unaddressed message is a
  // message, not a mistake.
  assert_true(src.contains("_ => ()"))
}

///|
test "a component with no declared buckets emits none of this" {
  let src = msgs_src("")
  assert_false(src.contains("ChatMsg"))
  assert_false(src.contains("ChatBubble"))
  assert_false(src.contains("ChatResponse"))
  // ...but the Input bucket the views DO type is untouched.
  assert_true(src.contains("pub(all) struct ChatState {"))
}

///|
/// A file whose script block answers some of its `@on` names.
fn answered_src(script : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/spec\">\nstate Chat { n: Int }\n</script>\n" +
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
/// A name the script block answers stays IN the enum, and the doc says so.
///
/// `update` is composed behind the block, so it is only ever consulted for a
/// dispatch the block did not claim: an arm for `bump` could not run. That
/// used to drop the case, back when there were two enums and this one was
/// decode-only.
///
/// There is one now, and it is a RAISE surface as well as a decode surface —
/// a component sending `bump` to itself writes `ChatMsg::Bump(1.0).send(ctx)`,
/// and the block answering the name is exactly WHY it would. Dropping the case
/// would take the typed raise away with the dead arm, so the note is what is
/// left: it says which cases can never reach an `update` arm.
test "a name the script block answers stays, and the doc says it is dead" {
  let src = answered_src("receive bump(d) { .n += d }")
  assert_true(enum_body(src, "ChatMsg").contains("  Bump(Double)\n"))
  assert_true(enum_body(src, "ChatMsg").contains("  Reset\n"))
  assert_true(src.contains("The script block answers bump, so an `update` arm"))
  // …and the typed raise it is kept for.
  assert_true(src.contains("Bump(a0) => (\"bump\", [Num(a0)])"))
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
  let src = answered_src("receive bump(d) { .n[0] = d }")
  assert_true(src.contains("  Bump(Double)\n"))
  assert_false(src.contains("Absent, because the script block answers"))
}

// -- v2: the merge, and the build error it makes possible ---------------------

///|
/// A file with both a schema and views, so the merge has both halves.
fn merged_src(bucket_decls : String, view_body : String) -> String raise {
  @viewgen.generate(
    "<script type=\"tutuca/spec\">\n" +
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
    "<script type=\"tutuca/spec\">\n" +
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
  // A view name and a schema-declared name are ONE enum — `<T>Receive` from the
  // schema — and nothing relates them. v2 has ONE bucket for a message whoever
  // sent it, so one enum holds both.
  let src = merged_src(
    "handle Chat { message { init, setAll(String) } }",
    "<button @on.click=\"bump 1\">+</button>" +
    "<button @on.click=\"reset\">0</button>",
  )
  let body = enum_body(src, "ChatMsg")
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
  assert_true(src.contains("pub fn ChatMsg::send"))
}

///|
test "a view name the schema also declares is declared once, by the schema" {
  // Not twice. The schema wins, and the payload is the schema's — which is
  // exactly why the disagreement below can be reported at all.
  let src = merged_src(
    "handle Chat { message { bump(Int) } }", "<button @on.click=\"bump 1\">+</button>",
  )
  let body = enum_body(src, "ChatMsg")
  assert_true(body.contains("  Bump(Int)\n"))
  assert_false(body.contains("  Bump(Double)\n"))
}

///|
test "a call site that disagrees with the schema is a build error" {
  // THE error the merge buys. Two enums could not report it: the view's `bump`
  // variant and the schema's is a `ChatMsg` variant, and nothing in the
  // generator ever puts the two side by side.
  //
  // Both halves print the name as written, and the halves match because the
  // schema declares `bump` the way the call site writes it. A block that still
  // writes `Bump(Int)` prints that instead — accurate, and the whole reason
  // `message-case` nudges the declaration into the used spelling.
  assert_eq(
    merge_err(
      "handle Chat { message { bump(Int) } }", "<button @on.click=\"bump 1 2\">+</button>",
    ),
    "`bump` is declared in the state block as `bump(Int)` and called from @on.click as `bump(a number, a number)` — the schema declares what a message carries, so the call sites have to match it",
  )
  assert_eq(
    merge_err(
      "handle Chat { message { bump(Int) } }", "<button @on.click=\"bump 'x'\">+</button>",
    ),
    "`bump` is declared in the state block as `bump(Int)` and called from @on.click as `bump(text)` — the schema declares what a message carries, so the call sites have to match it",
  )
  // Agreeing is silent, and so is a call site the inference could not read:
  // unknown is not wrong, which is the rule the whole generator turns on.
  assert_eq(
    merge_err(
      "handle Chat { message { bump(Int) } }", "<button @on.click=\"bump 1\">+</button>",
    ),
    "",
  )
  assert_eq(
    merge_err(
      "handle Chat { message { bump(Int) } }", "<button @on.click=\"bump .n\">+</button>",
    ),
    "",
  )
}

///|
test "an intent bucket gets an enum, a decode and a dispatch" {
  let src = msgs_src(
    "handle Chat { intent { rowPicked(Int), saveDraft(String) } }",
  )
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
