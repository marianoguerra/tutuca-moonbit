// diff_props contract: outer None = no diff, inner None = removal marker.

///|
test "diff_props: no changes yields None" {
  let a : Map[String, @vdom.AttrValue] = { "id": Str("x"), "n": Num(1) }
  let b : Map[String, @vdom.AttrValue] = { "id": Str("x"), "n": Num(1) }
  assert_true(@vdom.diff_props(a, a) is None)
  assert_true(@vdom.diff_props(a, b) is None)
}

///|
test "diff_props: changed, removed and added keys" {
  let a : Map[String, @vdom.AttrValue] = {
    "keep": Str("same"),
    "change": Str("old"),
    "drop": Bool(true),
  }
  let b : Map[String, @vdom.AttrValue] = {
    "keep": Str("same"),
    "change": Str("new"),
    "add": Num(3),
  }
  guard @vdom.diff_props(a, b) is Some(diff)
  inspect(diff.length(), content="3")
  assert_true(diff.get("change") is Some(Some(Str("new"))))
  assert_true(diff.get("drop") is Some(None))
  assert_true(diff.get("add") is Some(Some(Num(3))))
  assert_true(diff.get("keep") is None)
}

///|
test "diff_props: application order is a-keys then b-only keys" {
  let a : Map[String, @vdom.AttrValue] = { "x": Str("1"), "y": Str("2") }
  let b : Map[String, @vdom.AttrValue] = {
    "z": Str("3"),
    "y": Str("2b"),
    "x": Str("1"),
  }
  guard @vdom.diff_props(a, b) is Some(diff)
  let keys : Array[String] = []
  for k, _v in diff {
    keys.push(k)
  }
  // y changed (a-order first), then b-only z
  @debug.assert_eq(keys, ["y", "z"])
}

///|
test "diff_props: empty maps" {
  let empty : Map[String, @vdom.AttrValue] = {}
  assert_true(@vdom.diff_props(empty, {}) is None)
  guard @vdom.diff_props(empty, { "a": Str("1") }) is Some(added)
  assert_true(added.get("a") is Some(Some(Str("1"))))
  guard @vdom.diff_props({ "a": Str("1") }, empty) is Some(removed)
  assert_true(removed.get("a") is Some(None))
}
