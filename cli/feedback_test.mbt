// feedback: pure pieces (record line, paths, parse) + iso8601_utc.

///|
let plain_opts : @cli.GlobalOpts = {
  format: None,
  output: None,
  pretty: false,
  module_path: None,
  help: false,
}

///|
test "record line matches the JS JSON.stringify shape" {
  assert_eq(
    @cli.feedback_record_line(
      "2026-07-14T12:00:00.000Z", "0.1.0", "the \"lint\" code was confusing",
    ),
    "{\"ts\":\"2026-07-14T12:00:00.000Z\",\"version\":\"0.1.0\"," +
    "\"message\":\"the \\\"lint\\\" code was confusing\"}\n",
  )
}

///|
test "paths under home" {
  let (dir, file) = @cli.feedback_paths("/home/x")
  assert_eq(dir, "/home/x/.tutuca")
  assert_eq(file, "/home/x/.tutuca/feedback.jsonl")
}

///|
test "positional message flows to the shell; multiple args join" {
  match @cli.plan(["feedback", "hello", "world"]) {
    Feedback(_, message~) => @debug.assert_eq(message, Some("hello world"))
    _ => abort("expected Feedback")
  }
  // no message -> shell decides via stdin
  match @cli.plan(["feedback"]) {
    Feedback(_, message~) => @debug.assert_eq(message, None)
    _ => abort("expected Feedback")
  }
}

///|
test "feedback -h prints its help text" {
  match @cli.plan(["feedback", "-h"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 0)
      assert_true(emit.out.has_prefix("tutuca feedback [message]\n"))
      assert_true(
        emit.out.contains("one JSON object per line: {ts, version, message}"),
      )
    }
    _ => abort("expected Done")
  }
}

///|
test "feedback rejects unknown flags with a coded error" {
  match @cli.plan(["feedback", "--hep", "x"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("Unknown flag '--hep'"))
      assert_true(emit.err.contains("did you mean '--help'?"))
    }
    _ => abort("expected Done")
  }
}

///|
test "missing-message error" {
  let emit = @cli.feedback_missing_message(plain_opts)
  assert_eq(emit.exit_code, 1)
  assert_true(
    emit.err.has_prefix(
      "tutuca: feedback requires a message (positional arg or piped stdin)\n",
    ),
  )
}

///|
test "iso8601_utc matches Date.toISOString" {
  assert_eq(@cli.iso8601_utc(0), "1970-01-01T00:00:00.000Z")
  // leap day: new Date(Date.UTC(2024,1,29,23,59,59,999)) = 1709251199999
  assert_eq(@cli.iso8601_utc(1709251199999), "2024-02-29T23:59:59.999Z")
  // cross-checked with `node -e 'console.log(new Date(1752494400123).toISOString())'`
  assert_eq(@cli.iso8601_utc(1752494400123), "2025-07-14T12:00:00.123Z")
  // century non-leap boundary
  assert_eq(@cli.iso8601_utc(4107542399000), "2100-02-28T23:59:59.000Z")
}
