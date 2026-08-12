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
  /// The effects, in order, in their printed form: `send flash "hi"`.
  effects : Array[String]
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
  effects? : Array[String] = [],
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
      effects=["request loadData", "send flash RStr(\"ada\")", "stop"],
    ),
    on_case(
      "a bubble carries what it was given",
      "on go(k) { bubble 'rowPicked' k }",
      "go",
      args=[Num(3)],
      after=Some(counter_state()),
      effects=["bubble rowPicked RNum(3)"],
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
  ]
}
