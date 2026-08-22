// `e.<path>`: the two layers, and which one wins.
//
// The order is the whole of what makes this work, and the plan asks for it to
// be asserted rather than commented — so the first test below is the one that
// would fail if layer 2 were ever consulted first.

///|
/// An event with a resolver that answers a marker for whatever it is handed,
/// so a test can tell WHICH layer answered rather than only what it said.
fn evt_with_reader(
  name? : String = "input",
  value? : @tutuca.Value = Null,
  key? : String = "",
) -> @render.DomEvent {
  @render.DomEvent::new(
    name~,
    value~,
    key~,
    read_path=EventPathReader(segs => Str("layer2:" + segs.join("."))),
  )
}

///|
test "layer 1 shadows layer 2, and a DOM Event has no value property" {
  // THE test. `value` is computed by the glue — the checked state on a
  // checkbox, the file metadata on a file input, the `detail` on a
  // CustomEvent, the input's string otherwise — and a DOM `Event` has no
  // `value` property at all. If the path walk were consulted first, all 315
  // `e.value` call sites in this repository would read the resolver's answer
  // instead, and every form would stop working.
  let e = evt_with_reader(value=Str("typed"))
  assert_eq(@render.event_path(e, ["value"]), Str("typed"))
  // ...and the resolver IS reachable, so the assertion above is about order
  // and not about the resolver being absent.
  assert_eq(@render.event_path(e, ["deltaY"]), Str("layer2:deltaY"))
}

///|
test "every computed accessor shadows, including the falsy ones" {
  // The shadow test is on the NAME and not on the answer, which matters for
  // exactly these: `e.value` on an empty input is legitimately `Str("")` and
  // `e.isAlt` is legitimately `Bool(false)`. An implementation that fell
  // through when layer 1 answered falsily would send both to the resolver.
  let e = evt_with_reader(name="keydown", value=Str(""), key="Enter")
  assert_eq(@render.event_path(e, ["value"]), Str(""))
  assert_eq(@render.event_path(e, ["isAlt"]), Bool(false))
  assert_eq(@render.event_path(e, ["isShift"]), Bool(false))
  assert_eq(@render.event_path(e, ["key"]), Str("Enter"))
  assert_eq(@render.event_path(e, ["isSend"]), Bool(true))
  assert_eq(@render.event_path(e, ["isCancel"]), Bool(false))
  assert_eq(@render.event_path(e, ["keyCode"]), Num(0))
}

///|
test "a computed accessor is a whole path, not a first segment" {
  // `value` is a framework name and not a property of anything, so
  // `e.value.length` is not a read of a shorter accessor — it is a path, and
  // it goes to layer 2. There `value` is not a step on the safe profile's
  // allowlist, so the two profiles disagree about it: Open (the default)
  // resolves, Safe refuses.
  let e = evt_with_reader(value=Str("abcd"))
  assert_eq(
    @render.event_path(e, ["value", "length"]),
    Str("layer2:value.length"),
  )
  assert_eq(@render.event_path(e, ["value", "length"], profile=Safe), Null)
}

///|
test "layer 2 answers a path the allowlist permits" {
  let e = evt_with_reader()
  assert_eq(
    @render.event_path(e, ["target", "value"]),
    Str("layer2:target.value"),
  )
  assert_eq(
    @render.event_path(e, ["target", "dataset", "rowId"]),
    Str("layer2:target.dataset.rowId"),
  )
  assert_eq(
    @render.event_path(e, ["detail", "unicode"]),
    Str("layer2:detail.unicode"),
  )
  assert_eq(@render.event_path(e, ["pointerId"]), Str("layer2:pointerId"))
}

///|
test "the default profile is Open, and it reaches the resolver" {
  // Open is the default for native component authoring — the views are the
  // author's own code, so any path resolves. The escape paths the safe
  // profile refuses are exactly the ones this asserts DO reach the resolver.
  let asked : Array[String] = []
  let e = @render.DomEvent::new(
    name="click",
    read_path=EventPathReader(segs => {
      asked.push(segs.join("."))
      Str("REACHED")
    }),
  )
  assert_eq(
    @render.event_path(e, [
      "target", "ownerDocument", "defaultView", "localStorage", "length",
    ]),
    Str("REACHED"),
  )
  assert_eq(@render.event_path(e, ["target", "form", "action"]), Str("REACHED"))
}

///|
test "a refused path never reaches the resolver under Safe" {
  // The profile is checked HERE, before the call, so a backend's resolver
  // only ever sees a walk that was already permitted — one place decides, and
  // no backend can forget to ask. This is what a host rendering guest-supplied
  // views runs; see `@eventpath.EventPathProfile`.
  let asked : Array[String] = []
  let e = @render.DomEvent::new(
    name="click",
    read_path=EventPathReader(segs => {
      asked.push(segs.join("."))
      Str("REACHED")
    }),
  )
  assert_eq(
    @render.event_path(
      e,
      ["target", "ownerDocument", "defaultView", "localStorage", "length"],
      profile=Safe,
    ),
    Null,
  )
  assert_eq(
    @render.event_path(e, ["target", "form", "action"], profile=Safe),
    Null,
  )
  assert_eq(asked.length(), 0)
  // ...and a permitted one does reach it.
  assert_eq(
    @render.event_path(e, ["target", "id"], profile=Safe),
    Str("REACHED"),
  )
  assert_eq(asked, ["target.id"])
}

///|
test "an event with no resolver answers Null, as a test's event does" {
  // Every `DomEvent` a test builds has none, and so does any backend that has
  // not grown one. A path that does not resolve is Null, which is the same
  // answer — so nothing has to special-case the absence.
  let e = @render.DomEvent::new(name="click", value=Str("v"))
  assert_eq(@render.event_path(e, ["target", "value"]), Null)
  // Layer 1 still works without one, which is what keeps the 315 call sites
  // driveable from a test with no DOM at all.
  assert_eq(@render.event_path(e, ["value"]), Str("v"))
}
