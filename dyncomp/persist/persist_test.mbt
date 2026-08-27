///| The store layer on its own: what a snapshot survives, and what it refuses.
///
/// No bundle and no guest here — that is the point of the package being a leaf.
/// The host's own round trip (a real instance, out through `persist` and back
/// through `restore`) lives in `dyncomp/host`.

///|
fn sample() -> @persist.Snapshot {
  {
    module_: "notelib",
    component: "Notepad",
    id: "slot/n3",
    state: b"\x00\x01binary\xff",
    fields: { "title": Json::string("shopping") },
  }
}

///|
test "a snapshot survives text, bytes and all" {
  let store = @persist.MemStore::new()
  let snap = sample()
  assert_true(@persist.save(store, snap))
  guard! @persist.load(store, "slot/n3") is Some(back)
  assert_eq(back, snap)
  // the bytes went through base64 to get here, which is what lets a text-only
  // store hold a guest's binary state
  assert_true(back.has_state())
  @debug.assert_eq(back.state, b"\x00\x01binary\xff")
}

///|
test "a snapshot with no id is not stored" {
  let store = @persist.MemStore::new()
  assert_false(@persist.save(store, { ..sample(), id: "", }))
  assert_eq(store.size(), 0)
}

///|
test "the prefix separates kinds of thing, and saved_ids strips it" {
  let store = @persist.MemStore::new()
  let _ = @persist.save(store, sample())
  let _ = @persist.save(store, { ..sample(), id: "doc/main", }, prefix="other:")
  @debug.assert_eq(@persist.saved_ids(store), ["slot/n3"])
  @debug.assert_eq(@persist.saved_ids(store, prefix="other:"), ["doc/main"])
  // and a load under the wrong prefix finds nothing rather than the wrong thing
  assert_true(@persist.load(store, "doc/main") is None)
}

///|
test "forget is idempotent" {
  let store = @persist.MemStore::new()
  let _ = @persist.save(store, sample())
  @persist.forget(store, "slot/n3")
  @persist.forget(store, "slot/n3")
  assert_eq(store.size(), 0)
}

///|
/// A store is shared with whoever else writes to the origin, so everything
/// read out of one is untrusted input.
test "anything that is not a snapshot reads as none" {
  let store = @persist.MemStore::new()
  store.set("tutuca:junk", "not json at all")
  store.set("tutuca:half", "{\"module\": \"notelib\"}")
  store.set("tutuca:wrong", "[1, 2, 3]")
  assert_true(@persist.load(store, "junk") is None)
  assert_true(@persist.load(store, "half") is None)
  assert_true(@persist.load(store, "wrong") is None)
  assert_true(@persist.load(store, "never-written") is None)
}

///|
/// Base64 that will not decode is "no guest bytes" rather than a failure: the
/// declared fields are still worth having, and the guest would have refused
/// the bytes anyway.
test "unreadable state degrades to the declared fields" {
  let store = @persist.MemStore::new()
  store.set(
    "tutuca:bad", "{\"module\": \"notelib\", \"component\": \"Notepad\", \"id\": \"bad\", \"state\": \"!!!not base64!!!\", \"fields\": {\"title\": \"kept\"}}",
  )
  guard! @persist.load(store, "bad") is Some(snap)
  assert_false(snap.has_state())
  @debug.assert_eq(snap.field_args().get("title").unwrap(), Str("kept"))
}

///|
test "field_args is what a constructor takes" {
  let snap : @persist.Snapshot = {
    ..sample(),
    fields: { "count": Json::number(3), "tags": [Json::string("a")] },
  }
  let args = snap.field_args()
  @debug.assert_eq(args.get("count").unwrap(), Num(3))
  @debug.assert_eq(args.get("tags").unwrap(), List([Str("a")]))
}
