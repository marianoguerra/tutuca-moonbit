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
    request_module(requests=failing_request_handlers()),
    "RequestExample",
  )
  h.send_at_root("init")
  inspect(h.find_all(".card-title").length(), content="0")
  // the default `response.loadData` gets (res, err) — res is Null on failure
  inspect(h.find_all(".loading").length(), content="0")
}

///|
test "request-example: onOkName / onErrorName route to different handlers" {
  let h = @harness.mount(
    request_module(requests=failing_request_handlers()),
    "RequestExample",
  )
  // "Load Another Way" passes onErrorName: "loadDataErr"
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
