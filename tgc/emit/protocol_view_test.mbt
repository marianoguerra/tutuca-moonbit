// Three gaps found migrating a real project (marianoguerra/hmtp) from the
// backend this one replaced, each pinned here so it stays fixed.

///|
fn card(
  spec : String,
  script : String,
  template? : String = "<div></div>",
) -> String {
  "<script type=\"tutuca/spec\">\{spec}</script>" +
  "<script type=\"tutuca/script\" for=\"B\">\{script}</script>" +
  "<template id=\"B:main\" data-root>\{template}</template>"
}

///|
/// A message name is a SLOT OF SYNTAX, not an expression.
///
/// `send flash` and `send Bus::notify` write a name where a value would go, and
/// reading either as a value refused the whole effect — over a name the checker
/// had already resolved, which is the worst kind of disagreement between two
/// passes. A card author's way out was to write the resolved id by hand, which
/// is exactly what the `as Bus` alias exists to avoid.
test "a named message slot takes a bare or qualified protocol name" {
  let spec =
    #|state B { n: Double }
    #|import protocol "example/Bus@1" as Bus
    #|express B {
    #|  message { flash, Bus::notify }
    #|  intent { persist }
    #|}
  let probes = [
    ("send Bus::notify 'x'", "example/Bus@1::notify"),
    ("send flash", "flash"),
    ("ask persist", "persist"),
  ]
  for probe in probes {
    let (body, wire) = probe
    let out = @emit.compile(card(spec, "receive x { \{body} }"), name="b")
    assert_eq(out.refusals, [])
    // The WIRE name, resolved as `tscript/check` resolves it — not the local
    // spelling, which the host has never heard of.
    assert_true(out.wax.contains("tg_str(\"\{wire}\")"))
  }
}

///|
/// A bare `ask` amends the question that arrived and names nothing, so its
/// first argument is a value and must keep being read as one.
test "a bare ask still takes a value in the slot a name would use" {
  let out = @emit.compile(
    card("state B { n: Double }", "receive x { ask .n }"),
    name="b",
  )
  assert_eq(out.refusals, [])
  assert_true(out.wax.contains("eff_forward("))
}

///|
/// A card's templates are checked, and the surface that checking answers is
/// what turns on the three script rules that need to know what a view reaches.
///
/// Before this, a template naming a field the spec does not declare compiled
/// clean and drew blank — the worst failure the format has, because
/// `check_card` is the loop an author runs before paying for a compile.
test "check_card reports a view that names a field the spec does not declare" {
  let c = @emit.check_card(
    card("state B { n: Double }", "", template="<div @text=\".nope\"></div>"),
    name="b",
  )
  let codes = c.issues.map(i => i.code)
  assert_true(codes.contains("UNKNOWN_STATE_FIELD"))
  assert_true(c.issues.iter().all(i => i.severity == "error"))
}

///|
/// A view name nothing answers is a WARNING and not an error, and the
/// difference is load-bearing: it is the shape of a misspelling and also the
/// shape of a name the host dispatches, and a card cannot tell them apart. So
/// it is said and the card still compiles.
test "an unanswered view handler is reported, and does not stop the compile" {
  let src = card(
    "state B { n: Double }",
    "receive bump { .n += 1.0 }",
    template="<button @on.click=\"noSuchThing\">x</button>",
  )
  let c = @emit.check_card(src, name="b")
  let warned = c.issues.filter(i => i.code == "NO_VIEW_HANDLER")
  assert_eq(warned.length(), 1)
  assert_eq(warned[0].severity, "warning")
  // …and it compiles, which is the half a severity exists to say.
  let out = @emit.compile(src, name="b")
  assert_eq(out.component, "B")
}

///|
/// The manifest carries protocol DEFINITIONS, not just the ids in `implements`.
///
/// A host that resolves a slot through a protocol reads the definition; one
/// that only had the id would match and then find nothing to match against.
test "a card's manifest carries its protocol definitions and bindings" {
  let spec =
    #|protocol Lifecycle = "tutuca.dev/std/Lifecycle@1" {
    #|  handle { message { init } }
    #|  express { message { didInit } }
    #|  property { active: Bool }
    #|  view { display }
    #|}
    #|state B implements Lifecycle {
    #|  active: Bool
    #|  property {
    #|    active: Bool { get .active }
    #|    Lifecycle::active = active
    #|  }
    #|  view { Lifecycle::display = main }
    #|}
    #|handle B { message { Lifecycle::init } }
    #|express B { message { Lifecycle::didInit } }
  let out = @emit.compile(
    card(spec, "receive init { .active = true }"),
    name="b",
  )
  guard out.manifest is Object(m) else { fail("no manifest") }
  guard m.get("components") is Some(Array(cs)) && cs[0] is Object(c0) else {
    fail("no component")
  }
  guard c0.get("protocols") is Some(Array(ps)) && ps[0] is Object(p) else {
    fail("no protocol definition")
  }
  assert_eq(p.get("id"), Some(Json::string("tutuca.dev/std/Lifecycle@1")))
  assert_eq(p.get("handleMessages"), Some(Json::array([Json::string("init")])))
  assert_eq(
    p.get("expressMessages"),
    Some(Json::array([Json::string("didInit")])),
  )
  // A property is READ, so a host needs its type; a message is matched by name.
  guard p.get("properties") is Some(Array(props)) && props[0] is Object(pr) else {
    fail("no protocol property")
  }
  assert_eq(pr.get("name"), Some(Json::string("active")))
  assert_true(pr.get("ty") is Some(Object(_)))
  // …and which of this component's own members answers for each.
  guard c0.get("propertyBindings") is Some(Array(bs)) && bs[0] is Object(b) else {
    fail("no property binding")
  }
  assert_eq(
    b.get("protocolId"),
    Some(Json::string("tutuca.dev/std/Lifecycle@1")),
  )
  assert_eq(b.get("member"), Some(Json::string("active")))
  assert_eq(b.get("source"), Some(Json::string("active")))
  guard c0.get("viewBindings") is Some(Array(vs)) && vs[0] is Object(v) else {
    fail("no view binding")
  }
  assert_eq(v.get("source"), Some(Json::string("main")))
}
