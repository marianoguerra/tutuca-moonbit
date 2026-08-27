// The corpus.
//
// Every case is one transition: a schema, a script, a starting state, a
// dispatch, and what the state and the effects are afterwards. `after: None`
// means the transition did not happen at all — which is a real answer and one
// a backend can get wrong in a way nothing else would notice.

///|
/// One effect a transition performed.
///
/// STRUCTURAL.
///
/// `kind` is a plain word rather than an enum arm: it
/// is the corpus's own vocabulary and not one implementation's. The printed
/// form is still available, derived rather than stored — see `printed`.
pub(all) struct CaseEffect {
  /// One of `send`, `sendReply`, `sendAt`, `intent`, `forward`, `reply`,
  /// `fail`, or `stop`.
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
  /// every other effect.
  route : String
} derive(Debug, Eq)

///|
/// The printed form — derived from what the corpus stores. Two adapters still
/// compare against it, because what they have in hand is a line their own
/// recorder wrote.
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
    #|handle C { message { resetTo(Int) } }
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
// backends have to come to it. The two-channel model is that design.
//
// Nothing consumes `cases()` yet. The projection (`cmd/conformance`) and
// the two adapters pick it up, and `cases()`
// goes away when they do. Until then these rows are data with one test on
// them — that the batch is still all here and still says what it says.
//
// WHAT IS NOT HERE, and why. A case is ONE transition: one handler, one
// dispatch, one successor, one effect list. So a row can say what a body
// EMITS, and cannot say where it goes. These belong to the transactor's own
// suite instead, and listing them here is what stops them
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
/// The two buckets, and the whole of the split. `Receive` is ADDRESSED: it
/// names one component and stops there, whoever sent the message and whether
/// it is a first word or an answer. `Intent` is ROUTED: it names a job and
/// walks until something answers, whichever legs the route lists.
pub(all) enum Bucket {
  BReceive
  BIntent
} derive(Debug, Eq)

///|
/// One transition, stated so that any backend can be held to it.
///
/// A schema, a script, a starting state, a dispatch, and what the state and
/// the effects are afterwards. `after: None` means the transition did not
/// happen at all — which is a real answer, and one a backend can get wrong in
/// a way nothing else would notice.
pub(all) struct Case {
  name : String
  schema : String
  script : String
  before : Map[String, @tutuca.Value]
  bucket : Bucket
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
    #|handle C {
    #|  message { resetTo(Int), saveDraftOk(Int), saveDraftError(String) }
    #|  intent { saveDraft(String), picked(Int) }
    #|}
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
) -> Case {
  {
    name,
    schema: v2_schema(),
    script,
    before: counter_state(),
    bucket: BReceive,
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
) -> Case {
  {
    name,
    schema: v2_schema(),
    script,
    before: counter_state(),
    bucket: BIntent,
    handler,
    args,
    after,
    effects,
  }
}

///|
/// The state-block type a case's payload is declared as, inferred from the
/// VALUES it dispatches.
///
/// Here rather than in either projection because BOTH need it — the MoonBit
/// backend's writes one schema for the whole corpus, the card backend's writes
/// one per case — and two copies of a type inference is two ways for the two
/// backends to be handed different declarations for the same case.
///
/// Narrow on purpose: a wider guess would declare a payload the case does not
/// exercise, and `Any` is what "the corpus did not say" honestly reads as.
pub fn payload_ty(v : @tutuca.Value) -> String {
  match v {
    Num(n) => if n == n.to_int().to_double() { "Int" } else { "Double" }
    Str(_) => "String"
    Bool(_) => "Bool"
    _ => "Any"
  }
}

///|
/// The variant case a v2 case's handler is declared as: `Picked(Int)`.
///
/// The name is the handler's, capitalized — the state block declares
/// PascalCase and the dispatch name is its lowerCamel twin.
pub fn Case::variant_case(self : Case) -> String {
  let capped = self.handler[0:1].to_owned().to_upper() +
    self.handler[1:].to_owned()
  if self.args.is_empty() {
    capped
  } else {
    capped + "(" + self.args.map(a => payload_ty(a)).join(", ") + ")"
  }
}

///|
/// Every v2 case, in one list.
pub fn cases() -> Array[Case] {
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
    // One bucket, stated as a case. `resetTo` is declared in the schema's
    // receive bucket and reached here by the name a view raises: there is no
    // second bucket for view names, so a name declared once answers both a
    // parent's `ctx.send` and the view's own `@on`. The row above is the same
    // dispatch with a name nothing declares, which lands nowhere.
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
      "a reply to a message names itself",
      "receive ping {\n  sendReply 'pong' .name\n}",
      "ping",
      // The transition HAPPENED and changed nothing, which is not the same as
      // not happening: `after: None` is a refusal, and a handler that only
      // answers is still a handler that ran.
      after=Some(with_fields({})),
      effects=[effect("sendReply", name="pong", args=[Str("ada")])],
    ),
    recv_case(
      "a reply is an effect like the rest, and buffers with them",
      "receive ping {\n  .count += 1\n  sendReply 'pong' .count\n  send 'flash' .name\n}",
      "ping",
      after=Some(with_fields({ "count": Num(1) })),
      effects=[
        effect("sendReply", name="pong", args=[Num(1)]),
        effect("send", name="flash", args=[Str("ada")]),
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
