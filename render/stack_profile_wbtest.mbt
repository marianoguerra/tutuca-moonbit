// The stack carries the event-path profile from its root frame.
//
// `enter` spreads every field forward, so the profile set at `new` is what
// every nested scope evaluates handler args under — which is the whole point:
// a host that mounts with `Safe` holds every `e.<path>` in every component to
// the allowlist without anything at the call site changing.

///|
test "the root frame's event-path profile governs nested scopes" {
  fn probe(segs : Array[String]) -> @tutuca.Value {
    Str("REACHED:" + segs.join("."))
  }

  fn read_at(
    depth : Int,
    profile : @eventpath.EventPathProfile,
  ) -> @tutuca.Value {
    let e = DomEvent::new(name="click", read_path=EventPathReader(probe))
    let mut st = RenderStack::new(Map(Map([])), event=e, event_paths=profile)
    // Walk DOWN past the depth at which a real dispatch evaluates an arg,
    // mixing frames and transparent scopes so both kinds are covered.
    for i in 0..<depth {
      st = st.enter(
        Map(Map([("k", Str("\{i}"))])),
        Map([]),
        is_frame=i % 2 == 0,
      )
    }
    event_path(
      st.event.unwrap(),
      ["target", "form", "action"],
      profile=st.event_paths,
    )
  }

  // Open: any path reaches the resolver, at any depth.
  assert_eq(read_at(3, Open), Str("REACHED:target.form.action"))
  // A stack nobody configured is Open.
  let e = DomEvent::new(name="click", read_path=EventPathReader(probe))
  assert_eq(RenderStack::new(Map(Map([])), event=e).event_paths, Open)
  // Safe: refused past the allowlist, at the same depth.
  assert_eq(read_at(3, Safe), Null)
}

///|
test "the safe stack still answers what the allowlist permits" {
  let e = DomEvent::new(
    name="click",
    read_path=EventPathReader(segs => Str("REACHED:" + segs.join("."))),
  )
  let st = RenderStack::new(Map(Map([])), event=e, event_paths=Safe)
  assert_eq(
    @tutuca.Stack::lookup_event_path(st, ["target", "value"]),
    Str("REACHED:target.value"),
  )
  assert_eq(
    @tutuca.Stack::lookup_event_path(st, ["deltaY"]),
    Str("REACHED:deltaY"),
  )
}
