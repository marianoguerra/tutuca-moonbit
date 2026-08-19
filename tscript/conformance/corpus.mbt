// The corpus.
//
// Every case is one transition: a schema, a script, a starting state, a
// dispatch, and what the state and the effects are afterwards. `after: None`
// means the transition did not happen at all — which is a real answer and one
// a backend can get wrong in a way nothing else would notice.

///|
/// One transition, stated so that any backend can be held to it.
pub(all) struct Case {
  /// What the case is about, for the failure message.
  name : String
  /// The `<script type="tutuca/state">` block's contents. Every case carries
  /// one, because a backend that compiles needs the types and the interpreter
  /// needs the field list.
  schema : String
  /// The `<script type="tutuca/script">` block's contents.
  script : String
  /// The state before, as the fields map.
  before : Map[String, @tutuca.Value]
  /// The bucket and name dispatched, and the arguments it carried.
  bucket : Bucket
  handler : String
  args : Array[@tutuca.Value]
  /// The state after, or None when the transition produced no successor.
  ///
  /// None is the case worth having a corpus for. "Failure is no change" is the
  /// contract every layer of tutuca already keeps, and it is exactly the kind
  /// of thing a second implementation quietly gets wrong by writing half a
  /// change before noticing.
  after : Map[String, @tutuca.Value]?
  /// The effects, in order.
  effects : Array[CaseEffect]
}

///|
/// One effect a transition performed.
///
/// STRUCTURAL, and it used to be a printed string. The string was chosen so
/// that no backend's spelling of an effect became the language's — a fair worry
/// — but it had a cost nobody had to pay until a backend could not be driven
/// from MoonBit: `tutucard/wasm` sees an effect as a name and a list of values
/// arriving at a host import, and turning that back into `send flash RStr("a")`
/// meant reproducing MoonBit's derived `Debug` in JavaScript. So `cmd/corpus`
/// ran the INTERPRETER to recover the values the corpus had thrown away, and
/// the compiled backend's conformance harness depended on the interpreter
/// existing.
///
/// `kind` is a plain word rather than an enum arm for the original reason: it
/// is the corpus's own vocabulary and not one implementation's. The printed
/// form is still available, derived rather than stored — see `printed`.
pub(all) struct CaseEffect {
  /// v1: `send`, `bubble`, `request`, `sendAt`, or `stop`.
  /// v2: `send`, `sendAt`, `intent`, `forward`, `reply`, `fail`, or `stop`.
  kind : String
  /// The message name. Empty for `stop`, and for `forward`, `reply` and
  /// `fail`, which carry none — a `forward` re-dispatches the name that
  /// arrived, and an answer is addressed by the walk rather than by a name.
  name : String
  args : Array[@tutuca.Value]
  /// The route, for the two effects that have one: `intent` and `forward`.
  /// Written RESOLVED — a bare `intent 'save'` records `dyn lex` — because the
  /// default route is exactly the kind of thing two backends can agree to
  /// disagree about while every case with an explicit route passes. Empty for
  /// every other effect, and for every v1 case.
  route : String
} derive(Debug, Eq)

///|
/// The printed form — what the corpus used to store, now derived from what it
/// stores instead. Two adapters still compare against it, because what they
/// have in hand is a line their own recorder wrote.
pub fn CaseEffect::printed(self : CaseEffect) -> String {
  if self.kind == "stop" {
    return "stop"
  }
  let mut head = self.kind
  if !self.route.is_empty() {
    head = head + " " + self.route
  }
  if !self.name.is_empty() {
    head = head + " " + self.name
  }
  show_effect(head, self.args)
}

///|
/// A `send`, and the others by the same shape.
pub fn effect(
  kind : String,
  name? : String = "",
  args? : Array[@tutuca.Value] = [],
  route? : String = "",
) -> CaseEffect {
  { kind, name, args, route }
}

///|
/// One VALUE body, stated so that any backend can be held to it.
///
/// The cases above answer "what did the state become". These answer "what did
/// the block SAY", which is the other half of a block — and the half that had
/// no corpus while the MoonBit backend quietly compiled none of it: a `pred`
/// read like the rule and the compiled component answered Null.
pub(all) struct ValueCase {
  name : String
  schema : String
  script : String
  /// The state the body reads.
  state : Map[String, @tutuca.Value]
  /// Which callable, and in which ROLE. One `pred` is up to two functions —
  /// the renderer hands a `@when` the row and a `$name` nothing — so the role
  /// is part of the question, not of the answer.
  role : ValueRole
  callable : String
  /// A method's arguments; empty for the other roles.
  args : Array[@tutuca.Value]
  /// The loop's bindings, for the roles that are given them.
  key : @tutuca.Value
  value : @tutuca.Value
  /// What comes back.
  answer : Answer
}

///|
pub(all) enum ValueRole {
  VMethod
  VWhen
  VEnrich
  VEnrichScope
} derive(Debug, Eq)

///|
/// A value body's answer, in the shape its role returns.
///
/// `ANothing` is the case worth having a corpus for, exactly as `after: None`
/// is above: a body that cannot finish answers nothing, and the two backends
/// have to fail at the same input rather than one of them guessing a value.
pub(all) enum Answer {
  AValue(@tutuca.Value)
  ABool(Bool)
  ABinds(Map[String, @tutuca.Value])
  ANothing
} derive(Debug, Eq)

///|
/// What an answer reads as in a failure message. Both adapters print one, so
/// it lives with the type rather than twice beside it.
pub impl Show for Answer with fn output(self, logger) {
  logger.write_string(
    match self {
      AValue(v) => v.to_repr().to_string()
      ABool(b) => if b { "true" } else { "false" }
      ABinds(m) => {
        let keys : Array[String] = []
        for k, _ in m {
          keys.push(k)
        }
        keys.sort()
        "{" +
        keys
        .map(k => k + ": " + m.get(k).unwrap().to_repr().to_string())
        .join(", ") +
        "}"
      }
      ANothing => "(nothing)"
    },
  )
}

///|
pub(all) enum Bucket {
  BInput
  BReceive
  BBubble
  BResponse
} derive(Debug, Eq)

///|
/// The printed form of an effect, which is what a case compares against.
///
/// A string rather than a type, because a type would be one backend's — and a
/// corpus that names one backend's types can only ever check that backend.
pub fn show_effect(name : String, args : Array[@tutuca.Value]) -> String {
  if args.is_empty() {
    name
  } else {
    name + " " + args.map(a => a.to_repr().to_string()).join(" ")
  }
}

///|
/// A schema most cases can share.
fn counter_schema() -> String {
  (
    #|struct Label { text: String, done: Bool }
    #|state C {
    #|  name   : String
    #|  count  : Int
    #|  ratio  : Double
    #|  ok     : Bool
    #|  items  : Array[String]
    #|  labels : Array[Label]
    #|  tags   : Set[String]
    #|  page   : Int
    #|}
    #|receive C { ResetTo(Int) }
  )
}

///|
/// The state those fields start at.
fn counter_state() -> Map[String, @tutuca.Value] {
  {
    "name": Str("ada"),
    "count": Num(0),
    "ratio": Num(0),
    "ok": Bool(false),
    "items": List([Str("a"), Str("b")]),
    "labels": List([
      Map({ "text": Str("x"), "done": Bool(false) }),
      Map({ "text": Str("y"), "done": Bool(false) }),
    ]),
    "tags": Map(Map([])),
    "page": Num(0),
  }
}

///|
/// `counter_state()` with the named fields replaced.
fn with_fields(
  changes : Map[String, @tutuca.Value],
) -> Map[String, @tutuca.Value] {
  let out = counter_state()
  for k, v in changes {
    out[k] = v
  }
  out
}

///|
/// One `on` case over the shared schema and state.
fn on_case(
  name : String,
  script : String,
  handler : String,
  args? : Array[@tutuca.Value] = [],
  after~ : Map[String, @tutuca.Value]?,
  effects? : Array[CaseEffect] = [],
) -> Case {
  {
    name,
    schema: counter_schema(),
    script,
    before: counter_state(),
    bucket: BInput,
    handler,
    args,
    after,
    effects,
  }
}

///|
/// Every case, in one list.
pub fn cases() -> Array[Case] {
  [
    // -- paths into arguments ----------------------------------------------
    //
    // The argument arrives as a `Value` and the steps pick through it, which
    // both backends have to do the same way — including what a MISSING field
    // reads as, since a handler that quietly wrote Null back is the failure
    // this row exists to catch.
    //
    // Every one goes through `str`, and that is about the ARGUMENT rather than
    // the path: an argument no call site types is refused at a typed field by
    // the compiled backend — the reserved case below this one says so — so
    // `str` is where the two backends meet and the path is what is left being
    // tested.
    on_case(
      "a field of an argument",
      "on pick(f) { .name = str f.name }",
      "pick",
      args=[Map({ "name": Str("report.pdf"), "size": Num(12) })],
      after=Some(with_fields({ "name": Str("report.pdf") })),
    ),
    on_case(
      "a field of a field of an argument",
      "on pick(f) { .name = str f.meta.kind }",
      "pick",
      args=[Map({ "meta": Map({ "kind": Str("pdf") }) })],
      after=Some(with_fields({ "name": Str("pdf") })),
    ),
    on_case(
      "a field the argument does not carry reads null",
      "on pick(f) { .name = str f.missing }",
      "pick",
      args=[Map({ "name": Str("x") })],
      after=Some(with_fields({ "name": Str("null") })),
    ),
    on_case(
      "a field of an argument that has no fields at all",
      "on pick(f) { .name = str f.name }",
      "pick",
      // A list, so the projected call site leaves it off and the argument
      // arrives raw. A NUMBER here would be typed by the call site instead,
      // and a typed argument has no fields — which the checker reports and the
      // compiled backend refuses, rather than answering Null the way a card
      // with no call sites to read does.
      args=[List([Str("a")])],
      after=Some(with_fields({ "name": Str("null") })),
    ),
    // -- assignment --------------------------------------------------------
    on_case(
      "a plain assignment",
      "on go { .count = 5 }",
      "go",
      after=Some(with_fields({ "count": Num(5) })),
    ),
    on_case(
      "compound assignment adds to what is there",
      "on add(d) { .count += d }",
      "add",
      args=[Num(3)],
      after=Some(with_fields({ "count": Num(3) })),
    ),
    on_case(
      "a parameter is bound by position",
      "on set(a, b) { .name = b }",
      "set",
      args=[Str("first"), Str("second")],
      after=Some(with_fields({ "name": Str("second") })),
    ),
    on_case(
      "a missing argument binds null, and writing it is still a write",
      "on set(a) { .name = str a }",
      "set",
      after=Some(with_fields({ "name": Str("null") })),
    ),
    on_case(
      "statements run in order",
      "on go {\n  .count = 1\n  .count += 1\n  .count += 1\n}",
      "go",
      after=Some(with_fields({ "count": Num(3) })),
    ),
    on_case(
      "an integer field truncates on the way in",
      "on go { .count = 2.7 }",
      "go",
      after=Some(with_fields({ "count": Num(2) })),
    ),
    on_case(
      "…and a float field does not",
      "on go { .ratio = 2.7 }",
      "go",
      after=Some(with_fields({ "ratio": Num(2.7) })),
    ),
    // -- failure is no change ----------------------------------------------
    on_case(
      "an index past the end abandons the whole transition",
      "on go {\n  .count = 1\n  .name = .items[9]\n}",
      "go",
      after=None,
    ),
    on_case(
      "division by zero abandons it",
      "on go { .count = 1 / 0 }",
      "go",
      after=None,
    ),
    on_case(
      "a mixed additive pair abandons it",
      "on go { .count = .count + .name }",
      "go",
      after=None,
    ),
    on_case(
      "a name that resolves to nothing abandons it",
      "on go { .count = nope }",
      "go",
      after=None,
    ),
    on_case(
      "an effect before a failure does not escape",
      "on go {\n  send 'flash' 'hi'\n  .count = 1 / 0\n}",
      "go",
      after=None,
      effects=[],
    ),
    // -- nested places -----------------------------------------------------
    on_case(
      "a nested write rebuilds the spine",
      "on go(i) { .labels[i].done = true }",
      "go",
      args=[Num(1)],
      after=Some(
        with_fields({
          "labels": List([
            Map({ "text": Str("x"), "done": Bool(false) }),
            Map({ "text": Str("y"), "done": Bool(true) }),
          ]),
        }),
      ),
    ),
    on_case(
      "a nested write past the end changes nothing",
      "on go(i) { .labels[i].done = true }",
      "go",
      args=[Num(9)],
      after=None,
    ),
    on_case(
      "a nested read reaches through",
      "on go { .name = .labels[0].text }",
      "go",
      after=Some(with_fields({ "name": Str("x") })),
    ),
    // -- new, and the target -----------------------------------------------
    on_case(
      "a record is built and appended",
      "on go {\n  new Label\n  @cur.text = 'z'\n  @cur.done = true\n  .labels.push @cur\n}",
      "go",
      after=Some(
        with_fields({
          "labels": List([
            Map({ "text": Str("x"), "done": Bool(false) }),
            Map({ "text": Str("y"), "done": Bool(false) }),
            Map({ "text": Str("z"), "done": Bool(true) }),
          ]),
        }),
      ),
    ),
    on_case(
      "a field the build did not touch is the type's zero",
      "on go {\n  new Label\n  .labels.push @cur\n}",
      "go",
      after=Some(
        with_fields({
          "labels": List([
            Map({ "text": Str("x"), "done": Bool(false) }),
            Map({ "text": Str("y"), "done": Bool(false) }),
            Map({ "text": Str(""), "done": Bool(false) }),
          ]),
        }),
      ),
    ),
    on_case(
      "a second new starts over, and the first is not disturbed",
      "on go {\n  new Label\n  @cur.text = 'p'\n  .labels.push @cur\n  new Label\n  @cur.text = 'q'\n  .labels.push @cur\n}",
      "go",
      after=Some(
        with_fields({
          "labels": List([
            Map({ "text": Str("x"), "done": Bool(false) }),
            Map({ "text": Str("y"), "done": Bool(false) }),
            Map({ "text": Str("p"), "done": Bool(false) }),
            Map({ "text": Str("q"), "done": Bool(false) }),
          ]),
        }),
      ),
    ),
    on_case(
      "a collection is built and assigned whole",
      "on go {\n  new Array[String]\n  @cur.push 'p'\n  @cur.push 'q'\n  .items = @cur\n}",
      "go",
      after=Some(with_fields({ "items": List([Str("p"), Str("q")]) })),
    ),
    on_case(
      "the target does not exist until a new makes one",
      "on go { .labels.push @cur }",
      "go",
      after=None,
    ),
    // -- expressions -------------------------------------------------------
    on_case(
      "and short-circuits, so the right-hand side is never evaluated",
      "on go { .ok = .ok and .items[9] }",
      "go",
      after=Some(with_fields({ "ok": Bool(false) })),
    ),
    on_case(
      "or short-circuits the same way",
      "on go {\n  .ok = true\n  .ok = .ok or .items[9]\n}",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
    ),
    on_case(
      "implies is true whenever its antecedent is false",
      "on go { .ok = .ok implies .items[9] }",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
    ),
    on_case(
      "a chain evaluates left to right",
      "on go { .count = 10 - 3 - 2 }",
      "go",
      after=Some(with_fields({ "count": Num(5) })),
    ),
    on_case(
      "mod wraps a counter, and takes the whole left-hand side with it",
      "on go { .count = (.count + 1) mod 3 }",
      "go",
      after=Some(with_fields({ "count": Num(1) })),
    ),
    on_case(
      "a quotient keeps its fraction until the field takes it",
      "on go { .ratio = (.count + 5) / 4 }",
      "go",
      after=Some(with_fields({ "ratio": Num(1.25) })),
    ),
    on_case(
      "plus concatenates two strings",
      "on go { .name = .name + '!' }",
      "go",
      after=Some(with_fields({ "name": Str("ada!") })),
    ),
    on_case(
      "a string template interpolates whole expressions",
      "on go { .name = $'{.name} has {(len .items)}' }",
      "go",
      after=Some(with_fields({ "name": Str("ada has 2") })),
    ),
    on_case(
      "if picks a branch in a value position",
      "on go { .name = if .ok { 'yes' } else { 'no' } }",
      "go",
      after=Some(with_fields({ "name": Str("no") })),
    ),
    on_case(
      "if picks a branch in a statement position",
      "on go { if .ok { .count = 1 } else { .count = 2 } }",
      "go",
      after=Some(with_fields({ "count": Num(2) })),
    ),
    on_case(
      "an if with no else and a false condition changes nothing else",
      "on go {\n  .count = 7\n  if .ok { .count = 1 }\n}",
      "go",
      after=Some(with_fields({ "count": Num(7) })),
    ),
    // -- the vocabulary ----------------------------------------------------
    on_case(
      "clamp, over the range the corpus's prev/next call sites use",
      "on go(p) { .page = clamp p 0 ((len .items) - 1) }",
      "go",
      args=[Num(5)],
      after=Some(with_fields({ "page": Num(1) })),
    ),
    on_case(
      "the shape predicates mean what they mean in a slot",
      "on go { .ok = empty? .tags }",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
    ),
    on_case(
      "truthy? treats an empty collection as falsy",
      "on go { .ok = truthy? .tags }",
      "go",
      after=Some(with_fields({ "ok": Bool(false) })),
    ),
    on_case(
      "a declared predicate applies exactly like a builtin",
      "pred long(s) { (len s) > 2 }\non go { .ok = long .name }",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
    ),
    // -- collection methods ------------------------------------------------
    on_case(
      "push appends",
      "on go { .items.push 'c' }",
      "go",
      after=Some(with_fields({ "items": List([Str("a"), Str("b"), Str("c")]) })),
    ),
    on_case(
      "insertAt puts it before the index",
      "on go { .items.insertAt 0 'z' }",
      "go",
      after=Some(with_fields({ "items": List([Str("z"), Str("a"), Str("b")]) })),
    ),
    on_case(
      "setAt replaces",
      "on go { .items.setAt 1 'B' }",
      "go",
      after=Some(with_fields({ "items": List([Str("a"), Str("B")]) })),
    ),
    on_case(
      "deleteAt removes, and a key that is not there refuses",
      "on go { .items.deleteAt 0 }",
      "go",
      after=Some(with_fields({ "items": List([Str("b")]) })),
    ),
    on_case(
      "deleteAt past the end changes nothing",
      "on go { .items.deleteAt 9 }",
      "go",
      after=None,
    ),
    on_case(
      "a set adds, removes and toggles by member",
      "on go {\n  .tags.add 'x'\n  .tags.add 'y'\n  .tags.remove 'x'\n  .tags.toggle 'z'\n}",
      "go",
      after=Some(
        with_fields({ "tags": Map({ "y": Bool(true), "z": Bool(true) }) }),
      ),
    ),
    // -- effects -----------------------------------------------------------
    on_case(
      "effects come out in order, with the state",
      "on go {\n  request 'loadData'\n  .ok = true\n  send 'flash' .name\n  stop\n}",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
      effects=[
        effect("request", name="loadData"),
        effect("send", name="flash", args=[Str("ada")]),
        effect("stop"),
      ],
    ),
    on_case(
      "a bubble carries what it was given",
      "on go(k) { bubble 'rowPicked' k }",
      "go",
      args=[Num(3)],
      after=Some(counter_state()),
      effects=[effect("bubble", name="rowPicked", args=[Num(3)])],
    ),
    // -- the other buckets -------------------------------------------------
    {
      name: "a receive arm answers a message no view writes",
      schema: counter_schema(),
      script: "receive resetTo(n) { .count = n }",
      before: counter_state(),
      bucket: BReceive,
      handler: "resetTo",
      args: [Num(4)],
      after: Some(with_fields({ "count": Num(4) })),
      effects: [],
    },
    {
      name: "an input name no arm answers is not this bucket's business",
      schema: counter_schema(),
      script: "receive resetTo(n) { .count = n }",
      before: counter_state(),
      bucket: BInput,
      handler: "resetTo",
      args: [Num(4)],
      // The name is declared in the RECEIVE bucket, so an Input dispatch of it
      // finds nothing here. A backend that shared one namespace across buckets
      // would pass every other case and fail this one.
      after: None,
      effects: [],
    },
    // -- contracts ---------------------------------------------------------
    //
    // `after: None` is the whole point of these rows. A contract that does not
    // hold produces no successor and no effects, and the two backends reach
    // that answer by different routes — one evaluates the rule and returns
    // `Outcome::nothing()`, the other compiled the rule into a `guard` that
    // leaves the arm before its effect queue is flushed. A row where one of
    // them let the transition through would be a component that behaves
    // differently depending on how it was built, which is exactly what a
    // corpus is for.
    // The rule comes FIRST and the handler last, which is the projection's
    // rule rather than the grammar's: `cmd/conformance` renames the last
    // declaration in a case and shares the ones above it, so a rule two cases
    // both declared under one name with two different bodies would be a clash
    // it drops. Hence a name per case.
    //
    // No `invariant` row here, and the reason is the projection too: every
    // case lands in ONE component, so a rule the component keeps would be
    // asked after every other case's transition as well. The mechanism is the
    // one these rows already pin — the same guard, in the same place, dropping
    // the same queue — and that it is written into EVERY arm is pinned in
    // `tscript/emit_mbt` and `tutucard/wasm` instead.
    on_case(
      "a precondition that holds is not in the way",
      "pred enoughA { .count >= 0 }\non bump requires enoughA {\n  .count += 1\n}",
      "bump",
      after=Some(with_fields({ "count": Num(1) })),
    ),
    on_case(
      "a precondition that does not hold declines the transition",
      "pred enoughB { .count > 0 }\non bump requires enoughB {\n  .count += 1\n}",
      "bump",
      after=None,
    ),
    on_case(
      "a postcondition abandons the successor, and the effects with it",
      "pred smallA { .count > 5 }\non bump ensures smallA {\n  .count += 1\n  send 'bumped' .count\n}",
      "bump",
      after=None,
      // Stated as none rather than omitted: the `send` is queued before the
      // rule is asked in both backends, and a row that let it out would be
      // half a transition.
      effects=[],
    ),
    on_case(
      "a postcondition that holds lets the effects out",
      "pred smallB { .count < 5 }\non bump ensures smallB {\n  .count += 1\n  send 'bumped' .count\n}",
      "bump",
      after=Some(with_fields({ "count": Num(1) })),
      effects=[effect("send", name="bumped", args=[Num(1)])],
    ),
  ]
}

// ---------------------------------------------------------------------------
// Value bodies

///|
/// One value case over the shared schema and state.
fn value_case(
  name : String,
  script : String,
  callable : String,
  role? : ValueRole = VMethod,
  args? : Array[@tutuca.Value] = [],
  key? : @tutuca.Value = Null,
  value? : @tutuca.Value = Null,
  answer~ : Answer,
) -> ValueCase {
  {
    name,
    schema: counter_schema(),
    script,
    state: counter_state(),
    role,
    callable,
    args,
    key,
    value,
    answer,
  }
}

///|
/// Every value case, in one list.
///
/// Most of these are lifted from blocks that exist in this repo — the site's
/// counter card, the tutorial's steps, `storybook/examples/render_child.html`
/// — rather than invented, because the thing worth pinning is what people
/// actually write. A corpus of constructed cases would have missed the filter
/// idiom, which is the one every list component grows.
pub fn value_cases() -> Array[ValueCase] {
  [
    // -- a compute is one expression ---------------------------------------
    value_case(
      "a compute reads state and interpolates it",
      "compute summary { $'{.name}: {.count}' }",
      "summary",
      answer=AValue(Str("ada: 0")),
    ),
    value_case(
      "a compute does arithmetic across two fields",
      "compute left { .count - (len .items) }",
      "left",
      answer=AValue(Num(-2)),
    ),
    // -- a pred answers yes or no ------------------------------------------
    value_case(
      "a pred compares",
      "pred over { .count > 3 }",
      "over",
      answer=AValue(Bool(false)),
    ),
    value_case(
      "a pred over a collection's size",
      "pred moved { (len .items) > 0 }",
      "moved",
      answer=AValue(Bool(true)),
    ),
    value_case(
      "a pred read as a method answers its own expression",
      // NOT a Bool: the interpreter hands back what the body evaluated to, and
      // truthiness is applied by whoever asked. A backend that boxed this into
      // `Bool(true)` would print "true" where a card prints "ada" — which is
      // what happened, and what this case caught.
      "pred named { .name }",
      "named",
      answer=AValue(Str("ada")),
    ),
    value_case(
      "…and the same pred as a when is that value's truthiness",
      "pred named { .name }",
      "named",
      role=VWhen,
      answer=ABool(true),
    ),
    value_case(
      "a string comparison, which is structural",
      "pred isAda { .name is 'ada' }",
      "isAda",
      answer=AValue(Bool(true)),
    ),
    // -- one body calling another ------------------------------------------
    value_case(
      "a compute calls a pred by name, which is how a body spells one",
      (
        #|pred over { .count > 3 }
        #|compute status { if over { 'over' } else { 'under' } }
      ),
      "status",
      answer=AValue(Str("under")),
    ),
    // -- arguments ---------------------------------------------------------
    value_case(
      "a method reads the argument its call site passed",
      // `storybook/examples/render_child.html`, shortened: a parent's `@when`
      // asks every child this, and nothing declares what it is handed.
      "pred containsText(q) { contains (lower .name) (lower q) }",
      "containsText",
      args=[Str("AD")],
      answer=AValue(Bool(true)),
    ),
    value_case(
      "an argument of the wrong shape answers Null, rather than guessing",
      // Null and not `false`: a body that cannot finish answers nothing, and
      // nothing at a slot IS Null — `CardObj::callable_fn` maps the
      // interpreter's None onto it, and the compiled body returns it from the
      // guard. Both backends refuse the same argument at the same place.
      "pred containsText(q) { contains (lower .name) (lower q) }",
      "containsText",
      args=[Num(3)],
      answer=AValue(Null),
    ),
    // -- the loop's roles --------------------------------------------------
    value_case(
      "a when reads the row it is judging",
      // The filter idiom, from the tutorial's step 5 and the card
      // playground's `filter` starter.
      "pred matches { (empty? .name) or (contains (lower @value) (lower .name)) }",
      "matches",
      role=VWhen,
      value=Str("Ada Lovelace"),
      answer=ABool(true),
    ),
    value_case(
      "…and drops the row that does not match",
      "pred matches { (empty? .name) or (contains (lower @value) (lower .name)) }",
      "matches",
      role=VWhen,
      value=Str("Grace Hopper"),
      answer=ABool(false),
    ),
    value_case(
      "a when handed a row of the wrong shape keeps nothing",
      "pred matches { contains (lower @value) 'a' }",
      "matches",
      role=VWhen,
      value=Num(7),
      answer=ABool(false),
    ),
    value_case(
      "a when may read the key instead",
      "pred firstOnly { @key is 0 }",
      "firstOnly",
      role=VWhen,
      key=Num(0),
      value=Str("a"),
      answer=ABool(true),
    ),
    // -- enrichment --------------------------------------------------------
    value_case(
      "an enricher binds what the row does not carry",
      "enrich row { @tag = str @value }",
      "row",
      role=VEnrich,
      key=Num(1),
      value=Str("b"),
      answer=ABinds({ "tag": Str("b") }),
    ),
    value_case(
      "an enricher may read a binding it wrote",
      (
        #|enrich row {
        #|  @tag = str @value
        #|  @echo = str @tag
        #|}
      ),
      "row",
      role=VEnrich,
      value=Str("b"),
      answer=ABinds({ "tag": Str("b"), "echo": Str("b") }),
    ),
    value_case(
      "a scope enricher is handed no row, and answers the map",
      // `storybook/examples/collections.html`'s RenderWithScope, in one line.
      "enrichScope info { @len = len .name }",
      "info",
      role=VEnrichScope,
      answer=ABinds({ "len": Num(3) }),
    ),
  ]
}

// ---------------------------------------------------------------------------
// v2: two channels
//
// Written BEFORE either backend can run them, which is the whole reason they
// are here. A corpus written after the backends records what the backends
// agreed on; a corpus written first records what the design said, and the
// backends have to come to it. `totuka-v2.md` is that design.
//
// Nothing consumes `cases_v2()` yet. The projection (`cmd/conformance`) and
// the two adapters pick it up in the plan's tasks 10 and 11, and `cases()`
// goes away when they do. Until then these rows are data with one test on
// them — that the batch is still all here and still says what it says.
//
// WHAT IS NOT HERE, and why. A case is ONE transition: one handler, one
// dispatch, one successor, one effect list. So a row can say what a body
// EMITS, and cannot say where it goes. These belong to the transactor's own
// suite instead (the plan's task 4), and listing them here is what stops them
// from being forgotten in the gap between the two files:
//
//   - an observer above a replier, and the replier ending the walk;
//   - a `requires` refusing mid-walk and the walk CONTINUING past it — the
//     half that is one transition is `a requires that does not hold takes the
//     reply with it` below;
//   - `reply` twice across two HOPS, which is the one-shot the transactor
//     owns; the row below is two replies in one body, which is what a backend
//     can get wrong on its own;
//   - route exhaustion in its three shapes (`<name>Unhandled` declared,
//     only `<name>Error` declared, neither) — the sender's schema decides it
//     and the walk performs it, and no single transition contains both.

///|
/// The two buckets v2 has. `Input`, `Bubble` and `Response` are gone: the
/// first folded into `Receive` (a message is a message whoever sent it), and
/// the other two into `Intent` (a route is a route whichever scope it walks).
pub(all) enum V2Bucket {
  VReceive
  VIntent
} derive(Debug, Eq)

///|
/// One v2 transition. `Case` with the bucket swapped, and deliberately a
/// second type rather than a widened first one: the two vocabularies should
/// not be mixable in one list while both exist.
pub(all) struct V2Case {
  name : String
  schema : String
  script : String
  before : Map[String, @tutuca.Value]
  bucket : V2Bucket
  handler : String
  args : Array[@tutuca.Value]
  after : Map[String, @tutuca.Value]?
  effects : Array[CaseEffect]
}

///|
/// The v2 schema: the same fields, with the three message variants down to
/// two. `SaveDraftOk` and `SaveDraftError` are declared because declaring them
/// is what makes `saveDraft` a request rather than a notification (design
/// section 6), and a row below turns on that being visible in the schema.
fn v2_schema() -> String {
  (
    #|struct Label { text: String, done: Bool }
    #|state C {
    #|  name   : String
    #|  count  : Int
    #|  ratio  : Double
    #|  ok     : Bool
    #|  items  : Array[String]
    #|  labels : Array[Label]
    #|  tags   : Set[String]
    #|  page   : Int
    #|}
    #|receive C { ResetTo(Int), SaveDraftOk(Int), SaveDraftError(String) }
    #|intent  C { SaveDraft(String), Picked(Int) }
  )
}

///|
/// One `receive` case over the shared schema and state.
fn recv_case(
  name : String,
  script : String,
  handler : String,
  args? : Array[@tutuca.Value] = [],
  after~ : Map[String, @tutuca.Value]?,
  effects? : Array[CaseEffect] = [],
) -> V2Case {
  {
    name,
    schema: v2_schema(),
    script,
    before: counter_state(),
    bucket: VReceive,
    handler,
    args,
    after,
    effects,
  }
}

///|
/// One `intent` case over the shared schema and state.
fn intent_case(
  name : String,
  script : String,
  handler : String,
  args? : Array[@tutuca.Value] = [],
  after~ : Map[String, @tutuca.Value]?,
  effects? : Array[CaseEffect] = [],
) -> V2Case {
  {
    name,
    schema: v2_schema(),
    script,
    before: counter_state(),
    bucket: VIntent,
    handler,
    args,
    after,
    effects,
  }
}

///|
/// Every v2 case, in one list.
pub fn cases_v2() -> Array[V2Case] {
  [
    // -- a message is addressed, and stops ---------------------------------
    recv_case(
      "a message answered at home",
      "receive inc { .count += 1 }",
      "inc",
      after=Some(with_fields({ "count": Num(1) })),
    ),
    recv_case(
      "a message no arm answers produces no successor",
      "receive inc { .count += 1 }",
      "nope",
      after=None,
    ),
    // The merge, stated as a case. In v1 this row's twin is `an input name no
    // arm answers is not this bucket's business`: `resetTo` was declared in
    // the RECEIVE bucket, so an `Input` dispatch of it found nothing. v2 has
    // one bucket for both, so the same dispatch now lands — which is the
    // widening in the design's section 2, and the one behaviour change a
    // migration can trip over.
    recv_case(
      "a view name and a schema-declared name share one bucket",
      "receive resetTo(n) { .count = n }",
      "resetTo",
      args=[Num(4)],
      after=Some(with_fields({ "count": Num(4) })),
    ),
    // -- forward: the bridge -----------------------------------------------
    recv_case(
      "forward with no legs takes the default route",
      "receive saveDraft(text) { forward }",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("forward", route="dyn lex")],
    ),
    recv_case(
      "forward dyn walks the ancestors only",
      "receive picked(k) { forward dyn }",
      "picked",
      args=[Num(3)],
      after=Some(counter_state()),
      effects=[effect("forward", route="dyn")],
    ),
    recv_case(
      "forward lex walks the registered handlers only",
      "receive saveDraft(text) { forward lex }",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("forward", route="lex")],
    ),
    recv_case(
      "forward lex dyn walks the legs in the order written",
      "receive saveDraft(text) { forward lex dyn }",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("forward", route="lex dyn")],
    ),
    recv_case(
      "forward amends the arguments and keeps the name and the route",
      "receive saveDraft(text) { forward .name }",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("forward", args=[Str("ada")], route="dyn lex")],
    ),
    recv_case(
      "a handler may run and then forward",
      "receive saveDraft(text) {\n  .count += 1\n  forward\n}",
      "saveDraft",
      args=[Str("hi")],
      after=Some(with_fields({ "count": Num(1) })),
      effects=[effect("forward", route="dyn lex")],
    ),
    // -- intent: the routed dispatch ---------------------------------------
    recv_case(
      "an intent with no legs takes the default route",
      "receive go { intent 'saveDraft' .name }",
      "go",
      after=Some(counter_state()),
      effects=[
        effect("intent", name="saveDraft", args=[Str("ada")], route="dyn lex"),
      ],
    ),
    recv_case(
      "intent dyn is what v1 spelled bubble",
      "receive go(k) { intent dyn 'picked' k }",
      "go",
      args=[Num(3)],
      after=Some(counter_state()),
      effects=[effect("intent", name="picked", args=[Num(3)], route="dyn")],
    ),
    recv_case(
      "intent lex is what v1 spelled request",
      "receive go { intent lex 'loadRows' .name }",
      "go",
      after=Some(counter_state()),
      effects=[
        effect("intent", name="loadRows", args=[Str("ada")], route="lex"),
      ],
    ),
    recv_case(
      "intent lex dyn reverses the legs",
      "receive go { intent lex dyn 'saveDraft' .name }",
      "go",
      after=Some(counter_state()),
      effects=[
        effect("intent", name="saveDraft", args=[Str("ada")], route="lex dyn"),
      ],
    ),
    recv_case(
      "effects come out in order, with the state",
      "receive go {\n  intent lex 'loadRows'\n  .ok = true\n  send 'flash' .name\n  stop\n}",
      "go",
      after=Some(with_fields({ "ok": Bool(true) })),
      effects=[
        effect("intent", name="loadRows", route="lex"),
        effect("send", name="flash", args=[Str("ada")]),
        effect("stop"),
      ],
    ),
    // -- answering an intent ------------------------------------------------
    intent_case(
      "an intent answered where it arrives",
      "intent saveDraft(text) {\n  .count += 1\n  reply .count\n}",
      "saveDraft",
      args=[Str("hi")],
      after=Some(with_fields({ "count": Num(1) })),
      effects=[effect("reply", args=[Num(1)])],
    ),
    intent_case(
      "fail answers with an error and ends the walk",
      "intent saveDraft(text) { fail 'disk full' }",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("fail", args=[Str("disk full")])],
    ),
    // An observer: it runs, it changes state, and it does not answer. The
    // design's one rule — a reply ends the walk, running does not — is what
    // this row is half of. The other half is the transactor's.
    intent_case(
      "a handler that does not reply is an observer",
      "intent picked(k) { .page = k }",
      "picked",
      args=[Num(2)],
      after=Some(with_fields({ "page": Num(2) })),
    ),
    intent_case(
      "an intent handler may run and then continue the walk",
      "intent picked(k) {\n  .page = k\n  forward\n}",
      "picked",
      args=[Num(2)],
      after=Some(with_fields({ "page": Num(2) })),
      effects=[effect("forward", route="dyn lex")],
    ),
    // Two replies in ONE body. Both are queued, because the effect queue does
    // not judge; the transactor honours the first and refuses the second, and
    // that one-shot is per intent ACROSS hops rather than per body, which is
    // why it is pinned there and not here.
    intent_case(
      "a body may queue two replies, and both come out of it",
      "intent saveDraft(text) {\n  reply 1\n  reply 2\n}",
      "saveDraft",
      args=[Str("hi")],
      after=Some(counter_state()),
      effects=[effect("reply", args=[Num(1)]), effect("reply", args=[Num(2)])],
    ),
    intent_case(
      "stop ends the walk before any reply, and answers nothing",
      "intent saveDraft(text) {\n  .count += 1\n  stop\n}",
      "saveDraft",
      args=[Str("hi")],
      after=Some(with_fields({ "count": Num(1) })),
      effects=[effect("stop")],
    ),
    // The transition does not happen, so the queue is dropped, so the reply
    // never leaves. The walk continuing past this position is the transactor's
    // half of the same rule.
    intent_case(
      "a requires that does not hold takes the reply with it",
      "pred hasSome { .count > 0 }\nintent saveDraft(text) requires hasSome {\n  .count += 1\n  reply .count\n}",
      "saveDraft",
      args=[Str("hi")],
      after=None,
      effects=[],
    ),
    intent_case(
      "an ensures that does not hold takes the reply with it",
      "pred small { .count > 5 }\nintent saveDraft(text) ensures small {\n  .count += 1\n  reply .count\n}",
      "saveDraft",
      args=[Str("hi")],
      after=None,
      effects=[],
    ),
    // -- an answer is a message ---------------------------------------------
    //
    // Nothing here says "an answer". `saveDraftOk` is dispatched into the
    // receive bucket like every other message, and the arm cannot tell that
    // the runtime wrote it rather than a parent. That is the design's claim,
    // and this row is what makes it a claim a backend can fail.
    recv_case(
      "an answer arrives as an ordinary message",
      "receive saveDraftOk(n) { .count = n }",
      "saveDraftOk",
      args=[Num(7)],
      after=Some(with_fields({ "count": Num(7) })),
    ),
    recv_case(
      "an error answer arrives as an ordinary message too",
      "receive saveDraftError(why) { .name = why }",
      "saveDraftError",
      args=[Str("disk full")],
      after=Some(with_fields({ "name": Str("disk full") })),
    ),
  ]
}
