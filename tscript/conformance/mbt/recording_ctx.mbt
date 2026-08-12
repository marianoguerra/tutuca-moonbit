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
