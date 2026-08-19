// A `&Ctx` that records instead of dispatching.
//
// Every method of the trait has a default, so recording needs only the four an
// effect can reach: the two absolute forms (`send` and `bubble` are spelled in
// terms of them), `request`, and `stop_propagation`. Printed in the corpus's
// own form, so what is compared is a string both backends produce
// independently rather than one backend's type.

///|
/// Effects, in the order they happened.
pub(all) struct Recorder {
  seen : Array[String]
}

///|
pub fn Recorder::new() -> Recorder {
  { seen: [] }
}

///|
pub impl @tutuca.Ctx for Recorder with fn send_at_path(self, path, name, args) {
  // A `send` to this component's own (empty) path is the corpus's `send`; a
  // path with steps is its `sendAt`. One method answers both because
  // `Ctx::send` is defined as `send_at_path` at the ctx's own path, which is
  // the whole reason there are only four to implement.
  let verb = if path.items.is_empty() { "send" } else { "sendAt" }
  self.seen.push(@conformance.show_effect(verb + " " + name, args))
}

///|
pub impl @tutuca.Ctx for Recorder with fn bubble_at_path(
  self,
  _path,
  name,
  args,
) {
  self.seen.push(@conformance.show_effect("bubble " + name, args))
}

///|
pub impl @tutuca.Ctx for Recorder with fn request(self, name, _args, _opts) {
  // The corpus prints a request by NAME only: its arguments are the request
  // function's business and no backend can answer for them here.
  self.seen.push(@conformance.show_effect("request " + name, []))
}

///|
pub impl @tutuca.Ctx for Recorder with fn stop_propagation(self) {
  self.seen.push("stop")
}

// The v2 four. `intent` and `forward` carry a route, and the corpus records it
// RESOLVED — a bare `intent 'save'` is `dyn lex` — so this is where the
// generated call's opts are read back into the corpus's own spelling. The
// emitter writes no `route=` for a default route, precisely so the default
// lives in `IntentOpts::new`; `opts.route` therefore already holds it, and
// asking the opts rather than the source is what makes the resolved form
// checkable at all.

///|
pub impl @tutuca.Ctx for Recorder with fn intent_at_path(
  self,
  _path,
  name,
  args,
  opts,
) {
  self.seen.push(
    @conformance.show_effect(
      "intent " + @tutuca.route_label(opts.route) + " " + name,
      args,
    ),
  )
}

///|
pub impl @tutuca.Ctx for Recorder with fn forward(self, args, opts) {
  // A forward with no opts keeps the route the walk is already on, which the
  // corpus writes as the default — there is no walk here to ask.
  let route = match opts {
    Some(o) => o.route
    None => @tutuca.IntentOpts::new().route
  }
  self.seen.push(
    @conformance.show_effect(
      "forward " + @tutuca.route_label(route),
      args.unwrap_or([]),
    ),
  )
}

///|
pub impl @tutuca.Ctx for Recorder with fn reply(self, value) {
  self.seen.push(@conformance.show_effect("reply", [value]))
}

///|
pub impl @tutuca.Ctx for Recorder with fn fail(self, error) {
  self.seen.push(@conformance.show_effect("fail", [error]))
}
