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

///|
/// A protocol operation has ONE dispatch name, however the script spells it.
///
/// The declaration's own spelling is local: `receive Holder::hold` names the
/// protocol by this file's import alias and `receive hold` by the bare member,
/// while the schema resolved both to `x/Holder@1::hold` before either was read.
/// That resolved name is the only one a host has ever heard of, and it is what
/// a compiled component answers to — so it is what a card must answer to, or
/// the two are not interchangeable and the format's whole claim fails for any
/// component that implements a protocol.
///
/// This backend used to answer the script's spelling, which made three names
/// for one operation and none of them `gen`'s.
test "a protocol receive answers its wire name, not the file's alias" {
  let spec =
    #|protocol Holder = "x/Holder@1" { handle { message { hold(Any) } } }
    #|state B implements Holder { n: Double }
    #|handle B { message { Holder::hold(Any) } }
  let out = @emit.compile(
    card(spec, "receive Holder::hold(x) { .n += 1.0 }"),
    name="b",
  )
  // The module matches on it…
  assert_true(out.wax.contains("str_eq(name, \"x/Holder@1::hold\")"))
  assert_false(out.wax.contains("str_eq(name, \"hold\")"))
  assert_false(out.wax.contains("str_eq(name, \"Holder::hold\")"))
  // …and the manifest advertises the same thing, which is the half a host
  // reads before it ever dispatches.
  guard out.manifest is Object(m) else { fail("no manifest") }
  guard m.get("components") is Some(Array(cs)) && cs[0] is Object(c0) else {
    fail("no component")
  }
  assert_eq(
    c0.get("receives"),
    Some(Json::array([Json::string("x/Holder@1::hold")])),
  )
}

///|
/// The two directions of one protocol agree.
///
/// `expressIntents` was already qualified while `receives` was bare, so a card
/// spoke one protocol in two vocabularies depending on which way a message was
/// going. Pinned together, because the bug was only visible by comparing them.
test "a card's inbound and outbound protocol names are both resolved" {
  let spec =
    #|protocol Holder = "x/Holder@1" {
    #|  handle { message { hold(Any) } }
    #|  express { intent { addRequested(Bool) } }
    #|}
    #|state B implements Holder { n: Double }
    #|handle B { message { Holder::hold(Any) } }
    #|express B { intent { Holder::addRequested(Bool) } }
  let out = @emit.compile(
    card(spec, "receive Holder::hold(x) { ask Holder::addRequested true }"),
    name="b",
  )
  guard out.manifest is Object(m) else { fail("no manifest") }
  guard m.get("components") is Some(Array(cs)) && cs[0] is Object(c0) else {
    fail("no component")
  }
  assert_eq(
    c0.get("receives"),
    Some(Json::array([Json::string("x/Holder@1::hold")])),
  )
  assert_eq(
    c0.get("expressIntents"),
    Some(Json::array([Json::string("x/Holder@1::addRequested")])),
  )
  // …and what it actually raises is that same name, not the local alias.
  assert_true(out.wax.contains("tg_str(\"x/Holder@1::addRequested\")"))
}

///|
/// A name with no protocol behind it is left exactly as written.
///
/// The control: resolution must not rewrite an ordinary handler, or every card
/// that never heard of a protocol pays for the ones that did.
test "an ordinary receive keeps its own name" {
  let out = @emit.compile(
    card("state B { n: Double }", "receive bump { .n += 1.0 }"),
    name="b",
  )
  assert_true(out.wax.contains("str_eq(name, \"bump\")"))
  guard out.manifest is Object(m) else { fail("no manifest") }
  guard m.get("components") is Some(Array(cs)) && cs[0] is Object(c0) else {
    fail("no component")
  }
  assert_eq(c0.get("receives"), Some(Json::array([Json::string("bump")])))
}

///|
/// A rule declared in the SPEC block is not its own duplicate.
///
/// Spec-block rules are synthesized into the declaration list so the compiler
/// can lower them, and checking that merged list made every one of them report
/// `RULE_IN_BOTH` against itself. Nine starter cards carried the finding
/// silently, because warnings were being dropped before anyone could read one.
///
/// The compiler sees both lists; the checker sees only what the author wrote.
test "a spec-block rule is not reported as declared twice" {
  let src = card(
    "state B { n: Double\n  pred positive { .n > 0.0 } }", "receive bump { .n += 1.0 }",
  )
  let c = @emit.check_card(src, name="b")
  assert_false(c.issues.map(i => i.code).contains("RULE_IN_BOTH"))
  // …and the rule still compiles, which is what the merge is for.
  let out = @emit.compile(src, name="b")
  assert_true(out.wax.contains("_pred_positive("))
}

///|
/// …and a rule written in BOTH places is still reported, which is the whole
/// point of the finding.
test "a rule written twice is still reported" {
  let c = @emit.check_card(
    card(
      "state B { n: Double\n  pred positive { .n > 0.0 } }", "pred positive { .n > 1.0 }\nreceive bump { .n += 1.0 }",
    ),
    name="b",
  )
  assert_true(c.issues.map(i => i.code).contains("RULE_IN_BOTH"))
}

///|
/// Each component answers for ITS OWN views, not the file's.
///
/// The view surface is built per component. Merged across the file it makes
/// every component answer for every other's view names, and the first attempt
/// at this reported six `NO_VIEW_HANDLER` findings in a card that has none.
test "one component's views are not another component's problem" {
  let src = "<script type=\"tutuca/spec\">" +
    "state Board { rows: Array[Row] }\nstate Row { label: String }" +
    "</script>" +
    "<script type=\"tutuca/script\" for=\"Board\">receive addRow { .rows.push 1 }</script>" +
    "<script type=\"tutuca/script\" for=\"Row\">receive strike { .label = '' }</script>" +
    "<template id=\"Board:main\" data-root><button @on.click=\"addRow\">+</button></template>" +
    "<template id=\"Row:main\"><button @on.click=\"strike\">x</button></template>"
  let c = @emit.check_card(src, name="b")
  // `Board` does not answer `strike` and must not be asked to.
  let unanswered = c.issues.filter(i => i.code == "NO_VIEW_HANDLER")
  assert_eq(unanswered, [])
}

///|
/// What `check_card` calls an error, `compile` refuses; what it calls a
/// warning, `compile` accepts.
///
/// The contract between the two entry points, and the one a caller that fails
/// on `issues.length > 0` gets wrong — it then refuses cards that run. Both
/// this repo's example gate and the first consumer to try it had that bug.
test "check_card and compile agree about what is fatal" {
  let probes = [
    // clean
    (card("state B { n: Double }", "receive bump { .n += 1.0 }"), true),
    // warning only: a view name nothing answers
    (
      card(
        "state B { n: Double }",
        "receive bump { .n += 1.0 }",
        template="<button @on.click=\"nobody\">x</button>",
      ),
      true,
    ),
    // error: a view naming a field that does not exist
    (
      card("state B { n: Double }", "", template="<i @text=\".nope\"></i>"),
      false,
    ),
    // error: a handler writing a field that does not exist
    (card("state B { n: Double }", "receive bump { .missing = 1.0 }"), false),
  ]
  for probe in probes {
    let (src, should_compile) = probe
    let c = @emit.check_card(src, name="b")
    let fatal = c.issues.filter(i => i.severity == "error")
    assert_eq(fatal.is_empty(), should_compile)
    let compiled = try {
      @emit.compile(src, name="b") |> ignore
      true
    } catch {
      _ => false
    }
    assert_eq(compiled, should_compile)
  }
}
