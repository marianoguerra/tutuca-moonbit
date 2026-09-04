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
    card(spec, "receive Lifecycle::init { .active = true }"),
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

///|
/// A component that CLAIMS a protocol and answers none of its operations is
/// reported, at the step an author runs before paying for a compile.
///
/// The failure this catches is silent twice over: the card compiles, and the
/// manifest reads `implements: ["x/Holder@1"]` beside `receives: ["hold"]` — so
/// a host matches the component by protocol id and then `conforms` refuses it
/// when something tries to fill a slot with it, which is a long way from the
/// line that is wrong. A real card carried exactly this for its whole life; the
/// only thing that ever noticed was a release changing what `receives` said.
test "a card claiming a protocol it does not answer is reported" {
  let spec =
    #|protocol Holder = "x/Holder@1" { handle { message { hold(Any) } } }
    #|state B implements Holder { n: Double }
    #|handle B { message { Holder::hold(Any) } }
  // The spec declares the operation; the script answers a name of its own.
  let c = @emit.check_card(
    card(spec, "receive hold(x) { .n += 1.0 }"),
    name="b",
  )
  let found = c.issues.filter(i => i.code == "PROTOCOL_MEMBER_UNANSWERED")
  assert_eq(found.length(), 1)
  assert_eq(found[0].severity, "error")
  // The message names the spelling to write, because "does not conform" with
  // no repair is a finding an author has to go and derive.
  assert_true(found[0].message.contains("receive Holder::hold"))
  // …and it is fatal, so the card does not quietly compile into a component
  // the host will refuse.
  let compiled = try {
    @emit.compile(card(spec, "receive hold(x) { .n += 1.0 }"), name="b")
    |> ignore
    true
  } catch {
    _ => false
  }
  assert_false(compiled)
}

///|
/// …and the same card answering under the protocol's name is clean.
test "a card that answers its protocol's operations checks clean" {
  let spec =
    #|protocol Holder = "x/Holder@1" {
    #|  handle { message { hold(Any) } intent { emptied } }
    #|}
    #|state B implements Holder { n: Double }
    #|handle B { message { Holder::hold(Any) } intent { Holder::emptied } }
  let script = "receive Holder::hold(x) { .n += 1.0 }\n" +
    "answer Holder::emptied { reply 1 }"
  let c = @emit.check_card(card(spec, script), name="b")
  assert_eq(c.issues.filter(i => i.severity == "error"), [])
  let out = @emit.compile(card(spec, script), name="b")
  assert_eq(out.component, "B")
}

///|
/// A handled INTENT is checked the same way, and named as one.
///
/// The two buckets take different keywords, so a message's advice would send an
/// author to write `receive` for something only `answer` can declare.
test "an unanswered protocol intent names `answer`, not `receive`" {
  let spec =
    #|protocol Holder = "x/Holder@1" { handle { intent { emptied } } }
    #|state B implements Holder { n: Double }
    #|handle B { intent { Holder::emptied } }
  let c = @emit.check_card(card(spec, "receive bump { .n += 1.0 }"), name="b")
  let found = c.issues.filter(i => i.code == "PROTOCOL_MEMBER_UNANSWERED")
  assert_eq(found.length(), 1)
  assert_true(found[0].message.contains("answer Holder::emptied"))
}

///|
/// A component that does not CLAIM the protocol answers for nothing.
///
/// The control. A card's `protocols` list is every protocol in the FILE — it is
/// the dictionary a slot's declared type is resolved through — so checking
/// conformance against that list rather than against `implements` would hold
/// every component in a card to every protocol any of them uses.
test "a component that implements nothing is held to nothing" {
  let spec =
    #|protocol Holder = "x/Holder@1" { handle { message { hold(Any) } } }
    #|state A implements Holder { n: Double }
    #|handle A { message { Holder::hold(Any) } }
    #|state B { m: Double }
  let src = "<script type=\"tutuca/spec\">\{spec}</script>" +
    "<script type=\"tutuca/script\" for=\"A\">receive Holder::hold(x) { .n += 1.0 }</script>" +
    "<script type=\"tutuca/script\" for=\"B\">receive bump { .m += 1.0 }</script>" +
    "<template id=\"A:main\" data-root><div></div></template>" +
    "<template id=\"B:main\"><div></div></template>"
  let c = @emit.check_card(src, name="b")
  assert_eq(c.issues.filter(i => i.severity == "error"), [])
}

///|
/// A declared message that used to be answered by a generated mutator.
///
/// Before 0.48 a component got `setX` / `toggleX` / `resetX` per field from its
/// kind alone, and a dispatch no arm claimed fell through to one. So
/// `handle B { message { setView(String) } }` was a complete declaration —
/// nothing had to answer it. 0.48 removed the fallback and left the
/// declaration, which still advertises the name on `receives` and still lets an
/// outside sender send it, so the send refuses at run time with `NO_HANDLER`.
///
/// A consumer carried nineteen of these across their tree. What surfaced them
/// was three test failures whose assertions were about something else entirely.
test "a message named for a removed generated mutator is reported" {
  let spec =
    #|state B { view: String, done: Bool }
    #|handle B { message { setView(String), toggleDone, realOne } }
  let c = @emit.check_card(
    card(spec, "receive realOne { .done = true }"),
    name="b",
  )
  let stale = c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE")
  assert_eq(stale.length(), 2)
  // A warning: a handler of that name is legal, and this cannot see a MoonBit
  // `update~`. What it can see is the mutator spelling for a member the
  // component declares, which is what makes it a leftover and not a name.
  assert_true(stale.iter().all(i => i.severity == "warning"))
  // The repair, named. `setView` writes a field, `toggleDone` flips one, and
  // "declares a message nothing answers" with no next step is a finding an
  // author has to go and derive.
  guard stale.iter().find_first(i => i.message.contains("`setView`"))
    is Some(set_) else {
    fail("no finding for setView")
  }
  assert_true(set_.message.contains(".view = v"))
  guard stale.iter().find_first(i => i.message.contains("`toggleDone`"))
    is Some(tog) else {
    fail("no finding for toggleDone")
  }
  assert_true(tog.message.contains(".done = not .done"))
  // …and it compiles, because a warning is a thing to say and not a build to
  // stop.
  let out = @emit.compile(
    card(spec, "receive realOne { .done = true }"),
    name="b",
  )
  assert_eq(out.component, "B")
}

///|
/// A message whose name is nobody's mutator is left alone.
///
/// The control, and it matters: the finding keys off a mutator SPELLING for a
/// member this component declares, so an ordinary handler named for nothing in
/// particular must not trip it.
test "an ordinary declared message is not reported as a stale mutator" {
  let spec =
    #|state B { view: String }
    #|handle B { message { refresh, setSomethingElse(String) } }
  let c = @emit.check_card(
    card(spec, "receive refresh { .view = 'x' }"),
    name="b",
  )
  assert_eq(c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE"), [])
}

///|
/// A mutator-named message the block DOES answer is not reported.
///
/// The control that matters most, and the one this repo's own
/// `tut-6-messages` card supplied: it declares `setMode(String)` and answers it
/// with a `receive setMode(m)` that also appends to a log. The first version of
/// this check keyed on the spelling alone and flagged that card — a warning
/// that fires on correct code is a warning nobody reads.
test "a mutator-named message the script answers is left alone" {
  let spec =
    #|state B { mode: String, log: Array[String] }
    #|handle B { message { setMode(String) } }
  let c = @emit.check_card(
    card(spec, "receive setMode(m) { .mode = m\n  .log.push m }"),
    name="b",
  )
  assert_eq(c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE"), [])
}
