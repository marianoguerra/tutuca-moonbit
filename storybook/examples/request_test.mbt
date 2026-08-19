///|
test "request-example: nothing loads until the host sends `init`" {
  let h = @harness.mount(request_module(), "RequestExample")
  // tutuca has no lifecycle — start() alone runs no request
  inspect(h.find_all(".rows .card-title").length(), content="0")
  inspect(h.find_all(".loading").length(), content="0")
}

///|
test "request-example: receive.init fires the request, and the response lands" {
  let h = @harness.mount(request_module(), "RequestExample")
  h.send_at_root("init")
  // the fixture responds synchronously, so by the time the send has drained the
  // loading flag is back off and the items are in
  inspect(h.find_all(".loading").length(), content="0")
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["Tutuca", "MoonBit", "Borges"]
    ),
  )
}

///|
test "request-example: the SAME component with a failing handler takes the error path" {
  // the request implementation lives OUTSIDE the component, so swapping it is
  // all it takes to drive the failure case
  let h = @harness.mount(
    request_module(intents=failing_request_handlers()),
    "RequestExample",
  )
  h.send_at_root("init")
  inspect(h.find_all(".card-title").length(), content="0")
  // The answer arrives as `loadDataError`, which is its OWN name and its own
  // shape. v1 sent one combined `[res, err]` payload to a default arm, and a
  // split arm that matched it read the wrong slot.
  inspect(h.find_all(".loading").length(), content="0")
}

///|
test "request-example: a scope that DECLINES is not a scope that failed" {
  // The answer v1 had no word for. A `RequestFn` had to respond, so a handler
  // with nothing to contribute could only invent an error; an `IntentFn`
  // answers `Pass`, the walk goes on, and the route runs out.
  //
  // The sender hears `loadDataUnhandled` — "nothing claimed it" — which is a
  // different sentence from "a handler refused it", and the distinction is the
  // one the refusal taxonomy already draws everywhere else.
  let h = @harness.mount(
    request_module(intents=declining_request_handlers()),
    "RequestExample",
  )
  h.send_at_root("init")
  inspect(h.text(".error"), content="nothing in the scope answers `loadData`")
  inspect(h.find_all(".loading").length(), content="0")
}

///|
test "request-example: onOkName / onErrorName route to different handlers" {
  let h = @harness.mount(
    request_module(intents=failing_request_handlers()),
    "RequestExample",
  )
  // "Load Another Way" names its own three outcomes in `IntentOpts`, where
  // the block's `intent lex 'loadData'` had them filled in from the schema.
  h.click(".another")
  inspect(h.text(".error"), content="network is down")
  inspect(h.find_all(".loading").length(), content="0")
}

///|
test "request-example: loaded items filter and switch views like any others" {
  let h = @harness.mount(request_module(), "RequestExample")
  h.send_at_root("init")
  h.type_into("input", "Moon")
  debug_inspect(
    h.texts(".card-title"),
    content=(
      #|["MoonBit"]
    ),
  )
  h.type_into("input", "")
  // @push-view=".view" flips every loaded Entry into its edit view at once
  h.click(".toggle-btn")
  inspect(h.find_all("input.title").length(), content="3")
  inspect(h.find_all(".card-title").length(), content="0")
}
