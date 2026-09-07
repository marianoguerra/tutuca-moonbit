// Three gaps found migrating a real project (marianoguerra/hmtp) from the
// backend this one replaced, each pinned here so it stays fixed.

///|
/// A one-component card: `spec` is the section's body, `script` is `B`'s
/// `logic:` body, and `view` is `B`'s only view.
///
/// Both bodies arrive already indented for the section they go in, because
/// re-indenting them here would mean a helper that reads shrubbery to write it.
fn card(spec : String, script : String, view? : String = "div()") -> String {
  "spec:\n\{spec}\nlogic:\n  B:\n\{script}\nview:\n  B:\n    \{view}\n"
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
    #|  protocol Bus = "example/Bus@1":
    #|    message notify(Any)
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    express message flash
    #|    express message Bus::notify
    #|    express intent persist
  let probes = [
    ("send(Bus::notify, \"x\")", "example/Bus@1::notify"),
    ("send(flash)", "flash"),
    ("ask(persist)", "persist"),
  ]
  for probe in probes {
    let (body, wire) = probe
    let out = @emit.compile(
      card(spec, "    receive x:\n      \{body}"),
      name="b",
    )
    assert_eq(out.refusals, [])
    // The WIRE name, resolved as `tscript/check` resolves it — not the local
    // spelling, which the host has never heard of.
    assert_true(out.wap.contains("tg_str(\"\{wire}\")"))
  }
}

///|
/// A bare `ask` amends the question that arrived and names nothing, so its
/// first argument is a value and must keep being read as one.
test "a bare ask still takes a value in the slot a name would use" {
  let out = @emit.compile(
    card("  B ~root:\n    field n :: Double", "    receive x:\n      ask(it.n)"),
    name="b",
  )
  assert_eq(out.refusals, [])
  assert_true(out.wap.contains("eff_forward("))
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
    card("  B ~root:\n    field n :: Double", "", view="div(): @(it.nope)"),
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
    "  B ~root:\n    field n :: Double",
    "    receive bump:\n      it.n += 1.0",
    view="button(~on_click: noSuchThing): \"x\"",
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
    #|  protocol Lifecycle = "tutuca.dev/std/Lifecycle@1":
    #|    message init
    #|    express message didInit
    #|    property active :: Bool
    #|    view display
    #|
    #|  B ~root:
    #|    field active :: Bool
    #|    implements Lifecycle
    #|    property active :: Bool ~public:
    #|      get: it.active
    #|    property Lifecycle::active = active
    #|    view Lifecycle::display = main
    #|    message Lifecycle::init
    #|    express message Lifecycle::didInit
  let out = @emit.compile(
    card(spec, "    receive Lifecycle::init:\n      it.active := true"),
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
    #|  protocol Holder = "x/Holder@1":
    #|    message hold(Any)
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    message Holder::hold(Any)
  let out = @emit.compile(
    card(spec, "    receive Holder::hold(x):\n      it.n += 1.0"),
    name="b",
  )
  // The module matches on it…
  assert_true(out.wap.contains("str_eq(name, \"x/Holder@1::hold\")"))
  assert_false(out.wap.contains("str_eq(name, \"hold\")"))
  assert_false(out.wap.contains("str_eq(name, \"Holder::hold\")"))
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
    #|  protocol Holder = "x/Holder@1":
    #|    message hold(Any)
    #|    express intent addRequested(Bool)
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    message Holder::hold(Any)
    #|    express intent Holder::addRequested(Bool)
  let out = @emit.compile(
    card(
      spec, "    receive Holder::hold(x):\n      ask(Holder::addRequested, true)",
    ),
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
  assert_true(out.wap.contains("tg_str(\"x/Holder@1::addRequested\")"))
}

///|
/// A name with no protocol behind it is left exactly as written.
///
/// The control: resolution must not rewrite an ordinary handler, or every card
/// that never heard of a protocol pays for the ones that did.
test "an ordinary receive keeps its own name" {
  let out = @emit.compile(
    card(
      "  B ~root:\n    field n :: Double", "    receive bump:\n      it.n += 1.0",
    ),
    name="b",
  )
  assert_true(out.wap.contains("str_eq(name, \"bump\")"))
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
    "  B ~root:\n    field n :: Double\n    pred positive: it.n > 0.0", "    receive bump:\n      it.n += 1.0",
  )
  let c = @emit.check_card(src, name="b")
  assert_false(c.issues.map(i => i.code).contains("RULE_IN_BOTH"))
  // …and the rule still compiles, which is what the merge is for.
  let out = @emit.compile(src, name="b")
  assert_true(out.wap.contains("_pred_positive("))
}

///|
/// …and a rule written in BOTH places is still reported, which is the whole
/// point of the finding.
test "a rule written twice is still reported" {
  let c = @emit.check_card(
    card(
      "  B ~root:\n    field n :: Double\n    pred positive: it.n > 0.0", "    pred positive:\n      it.n > 1.0\n    receive bump:\n      it.n += 1.0",
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
  let src =
    #|spec:
    #|  Board ~root:
    #|    field rows :: List.of(Row)
    #|
    #|  Row:
    #|    field label :: String
    #|
    #|logic:
    #|  Board:
    #|    receive addRow:
    #|      it.rows.push(1)
    #|
    #|  Row:
    #|    receive strike:
    #|      it.label := ""
    #|
    #|view:
    #|  Board:
    #|    button(~on_click: addRow):
    #|      "+"
    #|
    #|  Row:
    #|    button(~on_click: strike):
    #|      "x"
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
    (
      card(
        "  B ~root:\n    field n :: Double", "    receive bump:\n      it.n += 1.0",
      ),
      true,
    ),
    // warning only: a view name nothing answers
    (
      card(
        "  B ~root:\n    field n :: Double",
        "    receive bump:\n      it.n += 1.0",
        view="button(~on_click: nobody): \"x\"",
      ),
      true,
    ),
    // error: a view naming a field that does not exist
    (
      card("  B ~root:\n    field n :: Double", "", view="@i{@(it.nope)}"),
      false,
    ),
    // error: a handler writing a field that does not exist
    (
      card(
        "  B ~root:\n    field n :: Double", "    receive bump:\n      it.missing := 1.0",
      ),
      false,
    ),
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
    #|  protocol Holder = "x/Holder@1":
    #|    message hold(Any)
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    message Holder::hold(Any)
  // The spec declares the operation; the logic answers a name of its own.
  let c = @emit.check_card(
    card(spec, "    receive hold(x):\n      it.n += 1.0"),
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
    @emit.compile(
      card(spec, "    receive hold(x):\n      it.n += 1.0"),
      name="b",
    )
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
    #|  protocol Holder = "x/Holder@1":
    #|    message hold(Any)
    #|    intent emptied
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    message Holder::hold(Any)
    #|    intent Holder::emptied
  let script = "    receive Holder::hold(x):\n      it.n += 1.0\n" +
    "    answer Holder::emptied:\n      reply(1)"
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
    #|  protocol Holder = "x/Holder@1":
    #|    intent emptied
    #|
    #|  B ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    intent Holder::emptied
  let c = @emit.check_card(
    card(spec, "    receive bump:\n      it.n += 1.0"),
    name="b",
  )
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
    #|  protocol Holder = "x/Holder@1":
    #|    message hold(Any)
    #|
    #|  A ~root:
    #|    field n :: Double
    #|    implements Holder
    #|    message Holder::hold(Any)
    #|
    #|  B:
    #|    field m :: Double
  let src = "spec:\n\{spec}\n" +
    "logic:\n" +
    "  A:\n    receive Holder::hold(x):\n      it.n += 1.0\n" +
    "  B:\n    receive bump:\n      it.m += 1.0\n" +
    "view:\n  A:\n    div()\n\n  B:\n    div()\n"
  let c = @emit.check_card(src, name="b")
  assert_eq(c.issues.filter(i => i.severity == "error"), [])
}

///|
/// A declared message that used to be answered by a generated mutator.
///
/// Before 0.48 a component got `set_x` / `toggle_x` / `reset_x` per field from its
/// kind alone, and a dispatch no arm claimed fell through to one. So
/// `handle B { message { set_view(String) } }` was a complete declaration —
/// nothing had to answer it. 0.48 removed the fallback and left the
/// declaration, which still advertises the name on `receives` and still lets an
/// outside sender send it, so the send refuses at run time with `NO_HANDLER`.
///
/// A consumer carried nineteen of these across their tree. What surfaced them
/// was three test failures whose assertions were about something else entirely.
test "a message named for a removed generated mutator is reported" {
  let spec =
    #|  B ~root:
    #|    field view :: String
    #|    field done :: Bool
    #|    message set_view(String)
    #|    message toggle_done
    #|    message realOne
  let c = @emit.check_card(
    card(spec, "    receive realOne:\n      it.done := true"),
    name="b",
  )
  let stale = c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE")
  assert_eq(stale.length(), 2)
  // A warning: a handler of that name is legal, and this cannot see a MoonBit
  // `update~`. What it can see is the mutator spelling for a member the
  // component declares, which is what makes it a leftover and not a name.
  assert_true(stale.iter().all(i => i.severity == "warning"))
  // The repair, named. `set_view` writes a field, `toggle_done` flips one, and
  // "declares a message nothing answers" with no next step is a finding an
  // author has to go and derive.
  guard stale.iter().find_first(i => i.message.contains("`set_view`"))
    is Some(set_) else {
    fail("no finding for set_view")
  }
  assert_true(set_.message.contains("it.view := v"))
  guard stale.iter().find_first(i => i.message.contains("`toggle_done`"))
    is Some(tog) else {
    fail("no finding for toggle_done")
  }
  assert_true(tog.message.contains("it.done := !it.done"))
  // …and it compiles, because a warning is a thing to say and not a build to
  // stop.
  let out = @emit.compile(
    card(spec, "    receive realOne:\n      it.done := true"),
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
    #|  B ~root:
    #|    field view :: String
    #|    message refresh
    #|    message set_somethingElse(String)
  let c = @emit.check_card(
    card(spec, "    receive refresh:\n      it.view := \"x\""),
    name="b",
  )
  assert_eq(c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE"), [])
}

///|
/// A mutator-named message the block DOES answer is not reported.
///
/// The control that matters most, and the one this repo's own
/// `tut-6-messages` card supplied: it declares `set_mode(String)` and answers it
/// with a `receive set_mode(m)` that also appends to a log. The first version of
/// this check keyed on the spelling alone and flagged that card — a warning
/// that fires on correct code is a warning nobody reads.
test "a mutator-named message the script answers is left alone" {
  let spec =
    #|  B ~root:
    #|    field mode :: String
    #|    field log :: List.of(String)
    #|    message set_mode(String)
  let c = @emit.check_card(
    card(
      spec, "    receive set_mode(m):\n      it.mode := m\n      it.log.push(m)",
    ),
    name="b",
  )
  assert_eq(c.issues.filter(i => i.code == "STALE_MUTATOR_MESSAGE"), [])
}
