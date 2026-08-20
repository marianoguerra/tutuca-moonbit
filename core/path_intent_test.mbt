// The v2 intent surface on `Ctx`, at the layer that owns the types and nothing
// that uses them.
//
// Two things are worth a test here and only here. The DEFAULT ROUTE, because
// it is written once in `IntentOpts::new` and every package that dispatches an
// intent gets it from there — a default two packages spell for themselves is
// the kind of difference that shows up as a component answering in one build
// and not another. And that the four new methods are NO-OPS with no
// dispatcher: every method on this trait defaults to nothing so a handler can
// be run by `Path::update` and by a test, and `reply` is the one where "no
// walk to answer" could plausibly have been written as a crash instead.

///|
test "the default route is dyn lex, and it is written in one place" {
  let opts = @core.IntentOpts::new()
  assert_eq(opts.route, [Dyn, Lex])
  assert_eq(@core.route_label(opts.route), "dyn lex")
  assert_eq(opts.on_ok_name, None)
  assert_eq(opts.on_error_name, None)
  assert_eq(opts.on_unhandled_name, None)
  assert_false(opts.live_path)
}

///|
test "a route says which legs, in the order written" {
  assert_eq(@core.route_label([Dyn]), "dyn")
  assert_eq(@core.route_label([Lex]), "lex")
  assert_eq(@core.route_label([Lex, Dyn]), "lex dyn")
  assert_eq(@core.route_label([]), "")
}

///|
test "the three outcome names are carried separately, not as one pair" {
  // Three outcome names, each with its own payload, and no combined
  // result-or-error arm for a handler to read the wrong half of.
  let opts = @core.IntentOpts::new(
    route=[Dyn],
    on_ok_name="saveDraftOk",
    on_error_name="saveDraftError",
    on_unhandled_name="saveDraftUnhandled",
    live_path=true,
  )
  assert_eq(opts.on_ok_name, Some("saveDraftOk"))
  assert_eq(opts.on_error_name, Some("saveDraftError"))
  assert_eq(opts.on_unhandled_name, Some("saveDraftUnhandled"))
  assert_true(opts.live_path)
}

///|
test "a handler with no dispatcher can reply, and nothing happens" {
  let ctx : &@core.Ctx = @core.NullCtx::{  }
  // None of these has a transactor under it. Each is a no-op, and the test is
  // that the call returns at all.
  ctx.intent("saveDraft", [Str("x")], @core.IntentOpts::new())
  ctx.intent_at_path(
    @core.DispatchPath::new(),
    "saveDraft",
    [],
    @core.IntentOpts::new(),
  )
  ctx.forward(None, None)
  ctx.forward(
    Some([Str("amended")]),
    Some(@core.IntentOpts::new(route=[@core.Leg::Lex])),
  )
  ctx.reply(Str("done"))
  ctx.fail(Str("nope"))
  assert_true(true)
}
