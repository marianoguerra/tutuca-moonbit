// Example-based tests over Value trees, ported from test/path.test.js.

///|
fn num(n : Double) -> @core.Value {
  @core.Value::Num(n)
}

///|
fn str(s : String) -> @core.Value {
  @core.Value::Str(s)
}

///|
fn vmap(m : Map[String, @core.Value]) -> @core.Value {
  @core.Value::Map(m)
}

///|
/// The Value a path resolves to, Null when unresolvable (JS lookup dval).
fn resolved(p : @core.Path, root : &@core.PathNode) -> @core.Value {
  match p.lookup(root) {
    Some(n) => n.as_value().unwrap_or(@core.Value::Null)
    None => @core.Value::Null
  }
}

///|
test "lookup and set_value address nested fields" {
  let root : &@core.PathNode = vmap({ "a": vmap({ "b": num(42) }) })
  let p = @core.Path::new(steps=[FieldStep("a"), FieldStep("b")])
  assert_true(resolved(p, root) == num(42))
  let root2 = p.set_value(root, num(43))
  assert_true(resolved(p, root2) == num(43))
  // the old root is untouched (COW)
  assert_true(resolved(p, root) == num(42))
}

///|
test "empty path resolves to the root and set_value replaces it" {
  let root : &@core.PathNode = vmap({ "a": num(1) })
  let p = @core.Path::new()
  assert_true(resolved(p, root) == vmap({ "a": num(1) }))
  let v : &@core.PathNode = num(9)
  assert_true(physical_equal(p.set_value(root, v), v))
}

///|
test "compact drops frame-only steps; addressing is unaffected by them" {
  let root : &@core.PathNode = vmap({ "a": vmap({ "b": num(42) }) })
  let p = @core.Path::new(steps=[
    BindStep(binds={}),
    FieldStep("a"),
    BindStep(binds={ "key": str("x") }),
    FieldStep("b"),
  ])
  assert_true(p.compact().steps is [FieldStep("a"), FieldStep("b")])
  assert_true(resolved(p, root) == num(42))
  assert_true(resolved(p, p.set_value(root, num(1))) == num(1))
  // frame-only steps report no key
  assert_eq(p.to_keys().length(), 2)
}

///|
test "EachRenderItStep compacts to SeqStep preserving field and key" {
  let root : &@core.PathNode = vmap({
    "items": vmap({ "k": vmap({ "v": num(1) }) }),
  })
  let p = @core.Path::new(steps=[
    EachRenderItStep(field="items", key=KStr("k")),
    FieldStep("v"),
  ])
  let c = p.compact()
  assert_true(
    c.steps is [SeqStep(field="items", key=KStr("k")), FieldStep("v")],
  )
  // both address the same leaf, for lookup and for set_value
  assert_true(resolved(p, root) == num(1))
  assert_true(resolved(c, root) == num(1))
  assert_true(resolved(p, p.set_value(root, num(2))) == num(2))
  assert_true(resolved(p, c.set_value(root, num(3))) == num(3))
}

///|
test "SeqAccessStep resolves the item keyed by a sibling field" {
  let root : &@core.PathNode = vmap({
    "selId": str("b"),
    "sheets": vmap({ "a": str("first"), "b": str("second") }),
  })
  let p = @core.Path::new(steps=[
    SeqAccessStep(seq_field="sheets", key_field="selId"),
  ])
  assert_true(resolved(p, root) == str("second"))
  let root2 = p.set_value(root, str("renamed"))
  assert_true(resolved(p, root2) == str("renamed"))
  assert_true(
    @core.Path::new(steps=[SeqStep(field="sheets", key=KStr("a"))]).lookup(
      root2,
    )
    is Some(n) &&
    n.as_value() == Some(str("first")),
  )
}

///|
test "pin_keys freezes SeqAccessStep to the key as it is now" {
  let root : &@core.PathNode = vmap({
    "selId": str("b"),
    "sheets": vmap({ "a": str("first"), "b": str("second") }),
  })
  let p = @core.Path::new(steps=[
    SeqAccessStep(seq_field="sheets", key_field="selId"),
  ])
  let pinned = p.pin_keys(root)
  assert_true(pinned.steps is [SeqStep(field="sheets", key=KStr("b"))])
  // the selected id moves while a request is in flight...
  let moved : &@core.PathNode = vmap({
    "selId": str("a"),
    "sheets": vmap({ "a": str("first"), "b": str("second") }),
  })
  // ...the pinned path still lands on the request-time item,
  assert_true(resolved(pinned, moved) == str("second"))
  // while the live path follows the key
  assert_true(resolved(p, moved) == str("first"))
}

///|
test "pin_keys returns the same Path when nothing needs pinning" {
  let root : &@core.PathNode = vmap({ "a": vmap({ "b": num(1) }) })
  let p = @core.Path::new(steps=[FieldStep("a"), FieldStep("b")])
  assert_true(physical_equal(p.pin_keys(root), p))
}

///|
test "set_value through a missing branch returns the identical root" {
  let root : &@core.PathNode = vmap({ "a": vmap({ "b": num(1) }) })
  let p = @core.Path::new(steps=[FieldStep("a"), FieldStep("missing")])
  assert_true(physical_equal(p.set_value(root, num(9)), root))
  let bad_idx = @core.Path::new(steps=[SeqStep(field="a", key=KInt(3))])
  assert_true(physical_equal(bad_idx.set_value(root, num(9)), root))
}

///|
test "set_value shares untouched siblings (structural sharing)" {
  let sib = vmap({ "x": num(1) })
  let root_v = vmap({ "a": vmap({ "b": num(2) }), "sib": sib })
  let root : &@core.PathNode = root_v
  let p = @core.Path::new(steps=[FieldStep("a"), FieldStep("b")])
  let root2 = p.set_value(root, num(3))
  guard root2.as_value() is Some(Map(m2)) else { fail("expected a map root") }
  guard m2.get("sib") is Some(sib2) else { fail("sibling dropped") }
  assert_true(physical_equal(sib2, sib))
}

///|
test "resolve_chain returns root plus entered values, stopping early" {
  let root : &@core.PathNode = vmap({ "a": vmap({ "b": num(1) }) })
  let full = @core.Path::new(steps=[FieldStep("a"), FieldStep("b")])
  let chain = full.resolve_chain(root)
  assert_eq(chain.length(), 3)
  assert_true(physical_equal(chain[0], root))
  assert_true(chain[2].as_value() == Some(num(1)))
  let broken = @core.Path::new(steps=[FieldStep("a"), FieldStep("nope")])
  assert_eq(broken.resolve_chain(root).length(), 2)
}

///|
test "to_keys reports addressing steps; SeqAccessStep has no concrete key" {
  let p = @core.Path::new(steps=[
    FieldStep("a"),
    SeqStep(field="items", key=KInt(2)),
    SeqAccessStep(seq_field="sheets", key_field="selId"),
  ])
  debug_inspect(
    p.to_keys(),
    content=(
      #|[
      #|  { field: "a", key: None },
      #|  { field: "items", key: Some(KInt(2)) },
      #|  { field: "sheets", key: None },
      #|]
    ),
  )
}

///|
test "lists index by KInt" {
  let root : &@core.PathNode = vmap({
    "items": @core.Value::List([num(10), num(20)]),
  })
  let p = @core.Path::new(steps=[SeqStep(field="items", key=KInt(1))])
  assert_true(resolved(p, root) == num(20))
  assert_true(resolved(p, p.set_value(root, num(21))) == num(21))
  // wrong key kind is unresolvable
  let bad = @core.Path::new(steps=[SeqStep(field="items", key=KStr("1"))])
  assert_true(bad.lookup(root) is None)
}

///|
test "concat and pop_step" {
  let p = @core.Path::new(steps=[FieldStep("a")]).concat([FieldStep("b")])
  assert_true(p.steps is [FieldStep("a"), FieldStep("b")])
  assert_true(p.pop_step().steps is [FieldStep("a")])
  assert_true(@core.Path::new().pop_step().steps is [])
}

///|
test "plain Value leaves have no handlers: update is an identity no-op" {
  let root : &@core.PathNode = vmap({ "a": num(1) })
  let p = @core.Path::new(steps=[FieldStep("a")])
  assert_true(physical_equal(p.update(root, Receive, "rename", []), root))
}
