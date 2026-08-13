// What the script block answers, and what the author is still asked for.
//
// One rule across five enums: a name the block answers is routed BEFORE the
// author's match is consulted, so it must not be a variant the author has to
// write an arm for. `emit_msgs_test.mbt` pins the `Msg` half of it. This file
// pins the four HANDLER buckets, where the same trimming decides two more
// things — whether the wrapper offers a parameter at all, and what the
// generated router is keyed by.
//
// The cost of getting it wrong is not only the dead arms. An author who writes
// a REAL handler on an answered name gets one that silently never fires, which
// is the failure the bucket enums exist to prevent.

///|
/// A file whose views call two `$name`s and name one `@when`, so a block can
/// answer part of the method bucket and all of the when bucket. Returns the
/// types module and the IR module, since the enum and the wrapper it keys are
/// emitted into different files.
fn bucket_src(script : String) -> (String, String) raise {
  let file = @viewgen.split_file(
    "<script type=\"tutuca/state\">\n" +
    "state Mail { items: Array[Int], n: Int }\n" +
    "</script>\n" +
    "<script type=\"tutuca/script\">\n" +
    script +
    "\n</script>\n" +
    "<template><div>" +
    "<x text=\"$hasAttachments\"></x><x text=\"$rowLabel\"></x>" +
    "<ul><li @each=\".items\" @when=\"keepItem\"><x text=\"@value\"></x></li></ul>" +
    "</div></template>",
    name="Mail",
  )
  let mods = @viewgen.emit_modules("Mail", "mail.html", file, include_ir=true)
  (
    mods.types_source,
    match mods.ir_source {
      Some(s) => s
      None => ""
    },
  )
}

///|
test "a $name the block answers is dropped from the Method enum" {
  let (types, _) = bucket_src("compute hasAttachments { .n }")
  assert_true(types.contains("pub(all) enum MailMethod {\n  RowLabel\n}"))
  assert_true(
    types.contains(
      "Absent, because the script block answers them: hasAttachments.",
    ),
  )
  // The name still keys the bucket at runtime — it is answered, not removed —
  // so `name()` losing it is the point: nothing left asks the author for it.
  assert_false(types.contains("HasAttachments"))
}

///|
test "a bucket the block answers WHOLE loses its enum and its parameter" {
  let (types, ir) = bucket_src(
    "compute hasAttachments { .n }\npred keepItem { .n > 0 }",
  )
  // `keepItem` was the only `@when` the views named, so there is no enum to
  // key a parameter by and nothing an author could add.
  assert_false(types.contains("enum MailWhen"))
  assert_false(ir.contains("  when? :"))
  // The map the block built IS the bucket, passed straight through.
  assert_true(ir.contains("    when=mail_inline_when(),"))
  // ...while the mixed bucket keeps both halves.
  assert_true(ir.contains("  compute? : (MailMethod) ->"))
}

///|
test "a mixed bucket merges the block's map over the author's" {
  let (_, ir) = bucket_src("compute hasAttachments { .n }")
  assert_true(
    ir.contains(
      "@component.build_bucket(([RowLabel] : Array[MailMethod]), MailMethod::name, f)",
    ),
  )
  assert_true(ir.contains("for k, h in mail_inline_compute() {"))
  assert_true(ir.contains("        bucket[k] = h\n"))
}

///|
/// The router is keyed by the SOURCE name, not by the bucket enum — it holds
/// exactly the names the enum no longer carries, so there is no variant left
/// to spell them with. It is a built map rather than a match for the same
/// reason: with the two halves disjoint there is nothing to fall through to.
test "the generated router is a map keyed by source name" {
  let (_, ir) = bucket_src("compute hasAttachments { .n }")
  assert_true(
    ir.contains(
      "fn mail_inline_compute() -> Map[String, (MailState, Array[@tutuca.Value]) -> @tutuca.Value] {",
    ),
  )
  assert_true(ir.contains("\"hasAttachments\": mail_compute_hasAttachments,"))
  assert_false(ir.contains("mail_inline_compute(k)"))
}

///|
/// The same rule the Msg enum follows: `Emitted` reports what COMPILED, so a
/// refused declaration keeps its variant. Trimming it would delete the only
/// place left to answer the name.
test "a declaration the backend refuses is NOT trimmed" {
  let (types, ir) = bucket_src("compute hasAttachments { .items[0] }")
  assert_true(types.contains("  HasAttachments\n"))
  assert_true(types.contains("  RowLabel\n"))
  assert_false(types.contains("Absent, because the script block answers"))
  // No router either, so the bucket is the author's match alone.
  assert_false(ir.contains("mail_inline_compute"))
}

///|
test "a block that answers nothing leaves every bucket exactly as it was" {
  let (types, ir) = bucket_src("on tick { .n += 1 }")
  assert_true(types.contains("  HasAttachments\n"))
  assert_true(types.contains("  RowLabel\n"))
  assert_true(types.contains("pub(all) enum MailWhen {\n  KeepItem\n}"))
  assert_false(types.contains("Absent, because the script block answers them"))
  assert_true(ir.contains("  compute? : (MailMethod) ->"))
  assert_true(ir.contains("  when? : (MailWhen) ->"))
}
