// The checker's rules, one case per rule, plus the cases it must stay quiet
// about.
//
// The quiet ones carry as much weight as the loud ones. "Unknown is not wrong"
// is the rule the whole design turns on, and a checker that gets it wrong is
// not merely noisy — it is a build nobody can fix without an opt-out. So every
// opaque source (a bind, an `any` field, an `on` handler no view calls) has a
// test asserting SILENCE.
//
// `$method` and `*dyn` are the exception, and the distinction is worth
// keeping straight: their TYPE is unknown, which is never wrong, but their
// VALUE in a body is Null, which almost always is. So the type stays opaque
// and the sigil is reported — see RENDER_ONLY below.

///|
fn def_of(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  defs[0]
}

///|
/// A schema with one field of most shapes, so a case can pick what it needs.
fn schema() -> String {
  (
    #|enum Priority { Low, High }
    #|struct Label { text: String, done: Bool }
    #|state Counter {
    #|  name   : String
    #|  count  : Int
    #|  ratio  : Double
    #|  ok     : Bool
    #|  items  : Array[String]
    #|  labels : Array[Label]
    #|  tags   : Set[String]
    #|  byKey  : Map[String, String]
    #|  pri    : Priority
    #|  blob   : Any
    #|  maybe  : String?
    #|  row    : Instance
    #|  provide { count = .count }
    #|  lookup { theme, color = 'gray' }
    #|}
    #|handle Counter {
    #|  message { resetTo(Int), rename(String, Int) }
    #|  intent { rowPicked(Int), save(String) }
    #|}
    #|import protocol "example/Bus@1" as Bus
    #|express Counter {
    #|  message { flash, Bus::notify }
    #|  intent { persist }
    #|}
  )
}

///|
/// The codes a block reports against the shared schema, in order.
fn codes(block : String) -> Array[String] raise {
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema())).map(f => f.code)
}

///|
/// The messages, for the cases where the wording is the feature.
fn messages(block : String) -> Array[String] raise {
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema())).map(f => f.message)
}

///|
/// The messages reported with a view surface in hand — the caller that IS in a
/// position to say a `receive` name is answered by nothing.
fn messages_with_views(
  block : String,
  views : Array[String],
) -> Array[String] raise {
  let inputs : Map[String, Array[@tutuca.Ty?]] = Map([])
  for v in views {
    inputs[v] = [None]
  }
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema()), surface={
    inputs,
    knows_views: true,
    open_senders: false,
    comps: [],
  }).map(f => f.message)
}

// -- fields -----------------------------------------------------------------

///|
test "an unknown field is named, and the message guesses" {
  assert_eq(messages("receive x { .coutn = 1 }"), [
    "`.coutn` is not a field of the Counter state — did you mean `.count`?",
  ])
  assert_eq(messages("receive x { .wildlyDifferent = 1 }"), [
    "`.wildlyDifferent` is not a field of the Counter state; declare it in the <script type=\"tutuca/spec\"> block",
  ])
  assert_eq(codes("receive x { .count = 1 }"), [])
}

///|
test "a nested read is checked all the way down" {
  assert_eq(codes("receive x { .labels[0].done = true }"), [])
  assert_eq(messages("receive x { .labels[0].dnoe = true }"), [
    "`Label` has no field `dnoe`",
  ])
  assert_eq(messages("compute a { .count[0] }"), [
    "`Int` is not a collection, so it has nothing to index",
  ])
}

// -- assignment -------------------------------------------------------------

///|
test "assignment types have to fit, and the numeric surface is one" {
  assert_eq(codes("receive x { .count = 1 }"), [])
  // `Value` has one `Num(Double)`, so an s32 and an f64 are the same runtime
  // shape — narrowing is a range check at run time, not a type error here.
  assert_eq(codes("receive x { .count = .ratio }"), [])
  assert_eq(messages("receive x { .count = 'hi' }"), [
    "this place is Int, but the value is String",
  ])
  // `any` takes anything, which is what it is for.
  assert_eq(codes("receive x { .blob = 'hi' }"), [])
  // …and an enum is a string at runtime, so a computed string can name a case.
  assert_eq(codes("receive x { .pri = 'high' }"), [])
  // A non-null value fills an optional slot; `null` empties it.
  assert_eq(codes("receive x { .maybe = 'hi' }"), [])
  assert_eq(codes("receive x { .maybe = null }"), [])
}

///|
test "compound assignment is arithmetic" {
  assert_eq(codes("receive x { .count += 1 }"), [])
  assert_eq(messages("receive x { .name += 'x' }"), [
    "`+=` is arithmetic, but this place is String",
  ])
}

// -- messages ---------------------------------------------------------------

///|
test "a message handler's parameters come from the schema, exactly" {
  assert_eq(codes("receive resetTo(n) { .count = n }"), [])
  assert_eq(messages("receive resetTo(a, b) { .count = a }"), [
    "`receive resetTo` carries 1 value(s), but this takes 2",
  ])
  // …and the parameter really is typed by the payload, so misusing it is
  // caught rather than passing as opaque.
  assert_eq(messages("receive rename(s, n) { .count = s }"), [
    "this place is Int, but the value is String",
  ])
}

///|
test "a handler for a message the schema does not declare" {
  // With the views in hand: the surface says nothing sends `resetTP`, and the
  // schema declares no case for it, so nothing can raise this handler.
  assert_eq(messages_with_views("receive resetTP(n) { .count = n }", []), [
    "the schema declares no `receive` case `resetTP` — did you mean `resetTo`?",
  ])
  // The buckets are separate questions: an `intent` case is not a `receive`.
  // `rowPicked` is one, and answering it as a message is answering a name
  // nothing addresses.
  assert_eq(messages_with_views("receive rowPicked(i) { .count = i }", []), [
    "the schema declares no `receive` case `rowPicked`; add it to `variant receive` in the <script type=\"tutuca/spec\"> block",
  ])
  assert_eq(codes("answer rowPicked(i) { .count = i }"), [])
}

///|
/// The other half of the same rule, and the one that broke every card on the
/// tutorial page.
///
/// `on` merged into `receive`, so a `receive` name is now either a view's or a
/// schema case's. A caller with no views in hand cannot tell which, and
/// `Surface::empty()` is exactly that caller — a card, a block on its own, a
/// test. Reporting NO_SUCH_MESSAGE there is the checker asserting knowledge it
/// has just said it lacks, and it made `receive warmer { send 'nudge' 1 }`
/// — an `on` handler the codemod moved, unchanged in behaviour — an error.
test "an unknown surface does not call a `receive` undeclared" {
  assert_eq(codes("receive resetTP(n) { .count = n }"), [])
  // The view SENDS it, so it is a view's name and takes its types from there
  // — opaque here, which is what a real join of disagreeing call sites gives.
  assert_eq(
    codes_with_views("receive warmer(by) { .count = by }", ["warmer"]),
    [],
  )
  // The view does NOT send it and no schema case declares it: with the views
  // in hand, that is a handler nothing can raise.
  assert_eq(codes_with_views("receive warmer(by) { .count = by }", []), [
    "NO_SUCH_MESSAGE",
  ])
}

// -- names and applications -------------------------------------------------

///|
test "a bare name is a parameter, a builtin, or something this block declares" {
  assert_eq(codes("receive set(value) { .name = value }"), [])
  assert_eq(messages("receive set(value) { .name = valeu }"), [
    "nothing here is called `valeu` — did you mean `value`?",
  ])
  // A predicate declared anywhere in the block, including below its use.
  assert_eq(
    codes("compute a { if ready { 1 } else { 2 } }\npred ready { .ok }"),
    [],
  )
}

///|
test "a builtin's arity is checked, and its result type is known" {
  assert_eq(codes("compute n { len .items }"), [])
  assert_eq(messages("compute n { len .items .name }"), [
    "`len` takes 1 argument(s), not 2",
  ])
  // `len` answers an integer, so this fits an s32 field.
  assert_eq(codes("receive x { .count = len .items }"), [])
  // …and `trim` answers text, so it does not.
  assert_eq(messages("receive x { .count = trim .name }"), [
    "this place is Int, but the value is String",
  ])
}

///|
test "a parameter cannot be applied" {
  assert_eq(messages("receive set(value) { .name = value .name }"), [
    "`value` is a parameter, so it takes no arguments",
  ])
}

// -- conditions -------------------------------------------------------------

///|
test "a container never decides a condition" {
  // The same finding `AlwaysTruthy` makes about `@show` over a list: a List,
  // a Map and an Obj are truthy unconditionally.
  assert_eq(messages("pred p { .items }"), [
    "Array[String] is always truthy, so this condition never decides anything — test `empty?` of it, or a field of it",
  ])
  assert_eq(codes("pred p { empty? .items }"), [])
  // A string and a number stay boolish on purpose: `@show=".name"` beside
  // `@text=".name"` is idiomatic.
  assert_eq(codes("pred p { .name }"), [])
  assert_eq(codes("pred p { .count }"), [])
}

///|
test "a pred's body is a condition, judged by the same rule as @show" {
  // Not a stricter one. A string is boolish in tutuca — `@show=".role"`
  // beside `@text=".role"` is idiomatic — so a `pred` answering a string is
  // answering yes or no by the language's own definition, and inventing a
  // narrower rule here would be a second truthiness to learn.
  assert_eq(codes("pred p { trim .name }"), [])
  assert_eq(codes("pred p { .ok and (not .name) }"), [])
  // What IS reported is the case that cannot decide, which is the same one
  // `@show` over a container reports.
  assert_eq(codes("pred p { .labels }"), ["ALWAYS_TRUE"])
}

// -- operators --------------------------------------------------------------

///|
test "arithmetic needs numbers, and + concatenates two strings" {
  assert_eq(codes("compute n { .count + 1 }"), [])
  assert_eq(codes("compute s { .name + 'x' }"), [])
  assert_eq(messages("compute n { .count + .name }"), [
    "arithmetic needs a number, but this is String",
  ])
  assert_eq(messages("compute n { .name * 2 }"), [
    "arithmetic needs a number, but this is String",
  ])
}

///|
test "a comparison that can only answer one way is reported" {
  assert_eq(codes("pred p { .count is 2 }"), [])
  assert_eq(codes("pred p { .name is 'x' }"), [])
  assert_eq(messages("pred p { .name is 2 }"), [
    "String and Double are never equal, so this comparison has one answer",
  ])
}

// -- collection methods -----------------------------------------------------

///|
test "a collection method has to fit its receiver" {
  assert_eq(codes("receive x(v) { .items.push v }"), [])
  assert_eq(codes("receive x(v) { .tags.add v }"), [])
  assert_eq(codes("receive x(k, v) { .byKey.setAt k v }"), [])
  assert_eq(messages("receive x(v) { .items.add v }"), [
    "`add` does not apply to Array[String]",
  ])
  assert_eq(messages("receive x(v) { .byKey.push v }"), [
    "`push` does not apply to Map[String, String]",
  ])
}

// -- effects ----------------------------------------------------------------

///|
test "an effect's message name has to be known before anything runs" {
  assert_eq(codes("receive x { send 'flash' .name }"), [])
  assert_eq(codes("receive x { drop }"), [])
  assert_eq(codes("receive x { sendAt &.labels[0] 'select' }"), [])
  assert_eq(messages("receive x { send .name 'body' }"), [
    "`send` needs a raw quoted name or a declared protocol operation",
  ])
}

///|
test "raw, implicit, and named-protocol effects are distinct" {
  assert_eq(codes("receive x { send 'flash' }"), [])
  assert_eq(codes("receive x { send flash }"), [])
  assert_eq(codes("receive x { send Bus::notify }"), [])
  assert_eq(codes("receive x { ask persist }"), [])
  assert_eq(codes("receive x { send missing }"), [
    "PROTOCOL_EXPRESSION_UNDECLARED",
  ])
  assert_eq(codes("receive x { send Missing::notify }"), ["PROTOCOL_UNRESOLVED"])
}

///|
test "a binding is assignable only where bindings are produced" {
  assert_eq(codes("enrich rowInfo { @cls = 'row' }"), [])
  assert_eq(codes("bindWith header { @title = .name }"), [])
  assert_eq(messages("receive x { @cls = 'row' }"), [
    "`@cls` is a binding, and only `enrich` and `bindWith` produce bindings — a handler assigns state, and `new` builds a value in `cur`",
  ])
}

// -- the render stack's sigils ----------------------------------------------

///|
test "a substituted sigil in a block is refused, and says where it belongs" {
  // One reason said two ways: a macro is expanded at a CALL SITE and a host
  // binds its table before any of this is parsed, while a block is parsed once
  // for the component. `parse_script` takes no context at all, which is that
  // fact written into the signature — so `^title` here would read Null, and
  // silently, which is the failure the refusal exists to prevent.
  //
  // The grammar accepts both, because a conditional slot is written in this
  // same language and a slot DOES stand in a macro frame. That asymmetry is
  // real and is why these two are not in the slot/block "refuse alike" corpus.
  assert_eq(codes("compute a { ^title }"), ["NO_MACRO_FRAME"])
  assert_eq(codes("compute a { host.origin }"), ["NO_CONFIG_FRAME"])
  assert_eq(codes("pred p { empty? ^label }"), ["NO_MACRO_FRAME"])
  assert_eq(codes("receive x { .name = host.origin }"), ["NO_CONFIG_FRAME"])
  assert_true(
    messages("compute a { ^title }")[0].contains("has no macro slots"),
  )
  assert_true(
    messages("compute a { host.origin }")[0].contains("ahead of any host"),
  )
}

///|
test "a `$name` in a body is reported, and the message names the spelling that works" {
  // The trap this rule exists for: `$over` in a body is not a call, it is
  // Null — so the condition is false every time and nothing says so. The
  // ahead-of-time backend refuses it by name; this is the same refusal for a
  // card, which has no compiler to do it.
  assert_eq(
    messages(
      (
        #|pred over { .count > 10 }
        #|receive x { if $over { .count = 0 } }
      ),
    ),
    [
      "`$over` is answered by the render stack, and a body runs after one, so it reads Null here — this block declares `over`, so call it bare: `over`",
    ],
  )
  // The bare spelling is the one that works, and stays silent.
  assert_eq(
    codes(
      (
        #|pred over { .count > 10 }
        #|receive x { if over { .count = 0 } }
      ),
    ),
    [],
  )
  // A name nothing declares still reads Null, and the message says what a
  // body can call instead.
  assert_eq(messages("compute a { $summary }"), [
    "`$summary` is answered by the render stack, and a body runs after one, so it reads Null here; a `pred` or a `compute` is called bare from a body, and nothing here declares one by that name",
  ])
}

///|
test "a `*name` in a body is legal, and checked against what the state declares" {
  // `*name` is the one render-stack sigil a body CAN ask, because the two
  // environments it walks are the two an intent's route walks and the host can
  // answer both from a handler's position. What is checked is that this
  // component asked for the name — whether a producer is above it when it
  // renders is a runtime fact, and not this rule's business.
  // Declared, so it is read and nothing is said.
  assert_eq(codes("receive x { .name = *theme }"), [])
  // A producer reads its OWN provide by the same spelling.
  assert_eq(codes("receive x { .count = *count }"), [])
  // Undeclared, with a near miss among what is declared.
  assert_eq(messages("receive x { .name = *colour }"), [
    "`*colour` is a dynamic binding this component does not declare — add it to the `state` block's `lookup { … }`, or `provide { … }` it here — did you mean `*color`?",
  ])
  // Undeclared with nothing near it: the message lists what there is.
  assert_eq(messages("receive x { .name = *nowhere }"), [
    "`*nowhere` is a dynamic binding this component does not declare — add it to the `state` block's `lookup { … }`, or `provide { … }` it here; it declares `*theme`, `*color`, `*count`",
  ])
}

// -- unknown is not wrong ---------------------------------------------------

///|
test "every opaque source silences the checks below it" {
  // A `$method` result and a `*dyn` are opaque, and the assignment they feed
  // is therefore unchecked — RENDER_ONLY is the finding about the sigil
  // itself, and nothing follows it about `.count`.
  assert_eq(codes("receive x { .count = $whatever }"), ["RENDER_ONLY"])
  // A `*name` is opaque the same way, and the finding here is about the name
  // being undeclared rather than about the sigil — nothing follows it about
  // `.count` either way.
  assert_eq(codes("receive x { .count = *nosuch }"), ["DYN_NOT_DECLARED"])
  // A binding comes from the slot that uses the declaration, which the block
  // cannot see — and so does everything under it.
  assert_eq(codes("pred p { @value.completed }"), [])
  assert_eq(codes("compute a { @iter.min }"), [])
  // An `any` field holds whatever it was given.
  assert_eq(codes("compute a { .blob + 1 }"), [])
  // An `on` handler no view calls has opaque arguments rather than none: a
  // name can be raised from MoonBit, and the block may answer one the
  // templates never mention.
  assert_eq(codes("receive neverCalled(a) { .count = a }"), [])
}

// -- the views' half --------------------------------------------------------

///|
test "an on handler's argument types come from the views' call sites" {
  let decls = @tscript.parse_script("receive add(d) { .name = d }")
  // With nothing known, nothing is checked.
  assert_eq(@check.check(decls, def_of(schema())).length(), 0)
  // With the call site saying `@on.click="add 1"`, the parameter is a number
  // and writing it into a string field is caught.
  let surface : @check.Surface = {
    inputs: { "add": [Some(TyFloat)] },
    knows_views: true,
    open_senders: false,
    comps: [],
  }
  assert_eq(
    @check.check(decls, def_of(schema()), surface~).map(f => f.message),
    ["this place is String, but the value is Double"],
  )
}

///|
test "a parameter list that disagrees with the call sites" {
  let decls = @tscript.parse_script("receive add(d, e) { .count = d }")
  let surface : @check.Surface = {
    inputs: { "add": [Some(TyFloat)] },
    knows_views: true,
    open_senders: false,
    comps: [],
  }
  assert_eq(
    @check.check(decls, def_of(schema()), surface~).map(f => f.message),
    ["`add` takes 2 parameter(s) here, but the views call it with 1"],
  )
}

///|
test "call sites that disagreed joined to opaque, and stay unchecked" {
  // `join_arg` answers `VValue` when two call sites disagree, which arrives
  // here as None — and None is never wrong.
  let decls = @tscript.parse_script("receive add(d) { .name = d }")
  let surface : @check.Surface = {
    inputs: { "add": [None] },
    knows_views: true,
    open_senders: false,
    comps: [],
  }
  assert_eq(@check.check(decls, def_of(schema()), surface~).length(), 0)
}

// -- findings carry positions -----------------------------------------------

///|
test "a finding points at the thing it is about" {
  let decls = @tscript.parse_script("receive x {\n  .coutn = 1\n}")
  let fs = @check.check(decls, def_of(schema()))
  assert_eq(fs.length(), 1)
  // `.coutn` starts at offset 14 — the block's own coordinates, which
  // `@viewfile.Block` rebases onto the file.
  assert_eq(fs[0].span, { start: 14, end_: 20, })
}

// -- new, and the target ----------------------------------------------------

///|
test "a new gives the target a type, so a field of it is checked" {
  assert_eq(
    codes("receive x {\n  new Label\n  cur.text = 'a'\n  .labels.push cur\n}"),
    [],
  )
  // The payoff for typing the target: `cur.dnoe` reads exactly like
  // `.labels[0].dnoe` does, because it goes through the same step walk.
  assert_eq(messages("receive x {\n  new Label\n  cur.dnoe = 'a'\n}"), [
    "`Label` has no field `dnoe`",
  ])
  assert_eq(messages("receive x {\n  new Label\n  cur.done = 'yes'\n}"), [
    "this place is Bool, but the value is String",
  ])
}

///|
test "the target does not exist until a new makes one" {
  assert_eq(messages("receive x { .labels.push cur }"), [
    "`cur` holds what a `new` built, and no `new` has run here — write `new <Type>` above this",
  ])
  // And the report is once, not once per step below it.
  assert_eq(codes("receive x { cur.text = 'a' }"), ["NO_TARGET"])
}

///|
test "a type the state does not declare is named, with the nearest one" {
  assert_eq(messages("receive x { new Labl }"), [
    "`Labl` is not a type the Counter state declares — did you mean `Label`?",
  ])
  assert_eq(messages("receive x { new Array[Widget] }"), [
    "`Array[Widget]` is not a type the Counter state declares; declare it in the <script type=\"tutuca/spec\"> block, or write a built-in type",
  ])
  // The built-in spellings the state block has, all of them legal here.
  assert_eq(
    codes(
      "receive x {\n  new Array[String]\n  new Map[String, Int]\n  new Set[String]\n  new Priority\n}",
    ),
    [],
  )
}

///|
test "a collection method on the target is checked against what it built" {
  assert_eq(codes("receive x {\n  new Array[String]\n  cur.push 'a'\n}"), [])
  assert_eq(messages("receive x {\n  new Label\n  cur.push 'a'\n}"), [
    "`push` does not apply to Label",
  ])
}

///|
test "a target built in a branch is known only where both arms agree" {
  // Same type on both sides: known below.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { new Label }\n  cur.text = 'a'\n}",
    ),
    [],
  )
  // One arm only: nothing is there on the other path, so a read below reports.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { .count = 1 }\n  cur.text = 'a'\n}",
    ),
    ["NO_TARGET"],
  )
  // Two different types: a target IS there, and its type is not knowable — so
  // the field goes unchecked rather than misreported.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { new Array[String] }\n  cur.dnoe = 'a'\n}",
    ),
    [],
  )
}

///|
test "the target is not a binding an enrich can publish" {
  // It never reaches a view — the interpreter withholds it — so an enricher
  // that assigned it would be writing into a workbench and calling it output.
  assert_eq(messages("enrich row { cur = 'x' }"), [
    "`cur` is the target `new` builds into, not a binding this `enrich` can hand a view — bind another name",
  ])
  // Building one and publishing something else is fine.
  assert_eq(
    codes("enrich row {\n  new Label\n  cur.text = 'a'\n  @tag = cur.text\n}"),
    [],
  )
}

// -- paths into arguments ---------------------------------------------------

///|
test "a path is written on an argument, and only on one that exists" {
  // An argument is opaque in a card (nothing declares what the views pass), so
  // reading a field off one is quiet — "unknown is not wrong" all the way down.
  assert_eq(codes("receive pick(f) { .name = f.name }"), [])
  assert_eq(codes("receive pick(f) { .name = f.meta.name }"), [])
  assert_eq(codes("receive resetTo(n) { .count = n }"), [])
  // The root has to BE a parameter: a bare name with an attached `.` is a path
  // and nothing else, so a name that is not one is a mistake rather than a call.
  assert_eq(messages("receive pick(file) { .name = payload.name }"), [
    "`payload` is not a parameter of `pick`; a path is only written on an argument, and `.payload` is how a state field is read",
  ])
  assert_eq(messages("receive pick(file) { .name = flie.name }"), [
    "`flie` is not a parameter of `pick` — did you mean `file`?",
  ])
}

///|
test "an argument is a value, not a place, so it cannot be assigned" {
  // Refused by the PARSER: a statement never starts with a bare name, so this
  // never reaches the checker — and the message says what the path is rather
  // than listing what a statement may be.
  let e = try {
    @tscript.parse_script("receive pick(f) { f.name = 'x' }") |> ignore
    ""
  } catch {
    err => err.message()
  }
  assert_eq(
    e, "expected a place this component owns — an argument is a value the caller handed over, so assign to a `.field` instead, found a path into `f`",
  )
}

///|
test "a path is checked against a DECLARED payload, where there is one" {
  // A `receive` case's payload types come from the schema, so unlike an `on`
  // handler's arguments they are known — and a field of an Int is not.
  assert_eq(messages("receive resetTo(n) { .count = n.whatever }"), [
    "`Int` has no field `whatever`",
  ])
}

// -- contracts --------------------------------------------------------------

///|
test "a contract names a `pred` the block declares" {
  assert_eq(
    codes(
      (
        #|receive bump requires enough { .count += 1 }
        #|pred enough { .count > 0 }
      ),
    ),
    [],
  )
  assert_eq(messages("receive bump requires enough { .count += 1 }"), [
    "`requires enough` names no `pred` the spec block declares; `bump` asks for it, so declare `pred enough { … }` inside `state Counter` in the spec block",
  ])
  // A `compute` is not a rule: nothing declares that its answer is a yes or a
  // no, so a contract over one would hold whenever it happened to be truthy.
  assert_eq(
    messages(
      (
        #|receive bump requires caption { .count += 1 }
        #|compute caption { .name }
      ),
    ),
    [
      "`requires caption` names no `pred` the spec block declares; `caption` is a `compute`, and a contract names a `pred`, whose answer is declared to be a yes or a no",
    ],
  )
}

///|
test "a near miss in a contract is named" {
  assert_eq(
    messages(
      (
        #|receive bump requires enouhg { .count += 1 }
        #|pred enough { .count > 0 }
      ),
    ),
    [
      "`requires enouhg` names no `pred` the spec block declares — did you mean `enough`?",
    ],
  )
}

///|
test "a contract is asked with nothing, so its rule takes nothing" {
  assert_eq(
    codes(
      (
        #|receive bump requires enough { .count += 1 }
        #|pred enough(n) { .count > n }
      ),
    ),
    ["CONTRACT_ARGS"],
  )
  // Same reason, from the other end: an invariant is asked after every
  // transition, and no two transitions carry the same arguments.
  assert_eq(codes("invariant sane(n) { .count > n }"), ["INVARIANT_ARGS"])
}

///|
test "an invariant's body is judged as a condition, like every other rule" {
  // `.items` is a container, and `Value::is_truthy` answers true for one
  // unconditionally — so the rule cannot fail, which is the same finding a
  // `@show` over a list gets.
  assert_eq(codes("invariant sane { .items }"), ["ALWAYS_TRUE"])
  assert_eq(codes("invariant sane { .count > 0 }"), [])
}

///|
test "an invariant is callable, exactly as a pred is" {
  // The badge in a view and the guard in an arm read one declaration. A block
  // where the rule is reachable from a handler but not from a slot would be a
  // block whose badge and whose behaviour could disagree.
  assert_eq(
    codes(
      (
        #|invariant conserved { (.count + 1) is .count }
        #|compute status { if conserved { 'ok' } else { 'broken' } }
      ),
    ),
    [],
  )
}

// -- formats ----------------------------------------------------------------

///|
test "a format is walked like any other expression" {
  // A field that is not there is reported where it is WRITTEN. The alternative
  // is an empty sentence at the moment somebody most wants to read one, which
  // is the worst place to discover a typo.
  assert_eq(codes("pred ok format $'{.nope} is wrong' { .ok }"), ["NO_FIELD"])
  assert_eq(codes("pred ok format $'{.name} is wrong' { .ok }"), [])
  assert_eq(codes("invariant sane format 'nothing doing' { .ok }"), [])
}

///|
test "a format answers a string, because it is a sentence" {
  assert_eq(codes("pred ok format .count { .ok }"), ["FORMAT_TYPE"])
  assert_eq(messages("pred ok format .count { .ok }"), [
    "a `format` is the sentence a reader is shown, and this one answers Int — write a string, or a `$'…'` template that puts it in one",
  ])
  // The way to say the same thing: put the number in a template.
  assert_eq(codes("pred ok format $'{.count} left' { .ok }"), [])
  // Unknown is not wrong here either: an `any` field could be a string.
  assert_eq(codes("pred ok format .blob { .ok }"), [])
}

// -- v2: NOT_A_HANDLER and NO_VIEW_HANDLER ----------------------------------

///|
/// The codes reported against the shared schema with a view surface in hand.
fn codes_with_views(
  block : String,
  views : Array[String],
) -> Array[String] raise {
  let inputs : Map[String, Array[@tutuca.Ty?]] = Map([])
  for v in views {
    // One opaque argument: enough for a one-parameter handler to bind, and
    // opaque is what a real join of disagreeing call sites gives anyway.
    inputs[v] = [None]
  }
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema()), surface={
    inputs,
    knows_views: true,
    open_senders: false,
    comps: [],
  }).map(f => f.code)
}

///|
/// `reply` answers whoever asked, in either bucket, and the bucket decides
/// where the name comes from.
///
/// This is what the `reply` retirement bought: there was a second word for
/// the same operation, and the only thing it said that this one does not is
/// which bucket you were in — which the block already says, three lines up.
test "reply answers whoever asked, in either bucket" {
  // An intent's raiser declared arms, so the walk names the answer and the one
  // argument is the value.
  assert_eq(codes("answer rowPicked(k) { reply .count }"), [])
  // A message's sender declared none, so the replier names it: the first
  // argument is a message name, and a value there is reported as one.
  assert_eq(codes("receive resetTo(n) { reply 'wasReset' .count }"), [])
  assert_eq(messages("receive resetTo(n) { reply .count }"), [
    "`reply` needs a raw quoted name or a declared protocol operation",
  ])
  // A body that was asked nothing can answer nobody.
  assert_eq(codes("enrich row { reply 1 }"), ["NOT_A_HANDLER"])
}

///|
/// `fail` ends a WALK, and only an intent is on one.
///
/// It did not merge with anything: a message has no walk to end, and turning a
/// message down is a `reply` that says so — which the sender reads as an
/// ordinary message, because that is what it is.
test "fail ends the walk an intent is on, and a message is not on one" {
  assert_eq(codes("answer rowPicked(k) { fail 'no' }"), [])
  assert_eq(messages("receive click { fail 'no' }"), [
    "`fail` ends the walk an intent is on, and `receive click` is not on one — to turn a message down, answer the sender with a `reply` that says so",
  ])
}

///|
/// `forward` hands on a walk that is RUNNING, and only an `answer` body is on
/// one. Starting a walk from the message that arrived is a bare `ask`.
///
/// This is what the family bought: `forward` used to mean both, decided by
/// which body it sat in, so a reader had to look up three lines to find out
/// whether it was starting something or continuing it.
test "forward hands on a walk, and a bare ask starts one" {
  assert_eq(codes("answer rowPicked(k) { forward dyn }"), [])
  assert_eq(codes("receive resetTo(n) { ask }"), [])
  // The retired spelling in a `receive` body normalises to `ask`, so it is the
  // legal one and reports nothing.
  assert_eq(codes("receive resetTo(n) { ask }"), [])
  assert_eq(messages("compute a { .count }"), [])
  assert_eq(messages("enrich row { forward }"), [
    "`forward` hands on the walk this body is answering, and `enrich row` is not on one — to turn a message into an intent, write a bare `ask`",
  ])
  // A bare `ask` needs a question already in hand, which only a `receive` has.
  assert_eq(messages("answer rowPicked(k) { ask }"), [
    "a bare `ask` asks the question this body was handed, and `answer rowPicked` was handed none — the walk here is already running, and `forward` hands it on",
  ])
}

///|
test "reply and fail are not dynamic message names" {
  // "Is the first argument a literal message name?" is asked only of the
  // effects that NAME a message. `reply` in an `answer` body, `fail` and
  // `forward` name none — an answer is addressed by the walk and a `forward`
  // re-dispatches the name that arrived — so asking would report `reply 1` as
  // a dynamic message name.
  assert_eq(codes("answer rowPicked(k) { reply 1 }"), [])
  assert_eq(codes("answer rowPicked(k) { reply .count }"), [])
  assert_eq(codes("answer rowPicked(k) { fail .name }"), [])
  // `ask .name` is not a dynamic message name: a name has to be a literal or a
  // protocol operation, so a first argument that is neither is amending the
  // question that arrived rather than naming a new one.
  assert_eq(codes("receive resetTo(n) { ask .name }"), [])
  // ...and the rule still holds for the effects that DO name one.
  assert_eq(codes("receive x { ask 'a' }"), [])
  assert_eq(codes("receive x { send .name }"), ["DYNAMIC_MESSAGE"])
  assert_eq(codes("receive x { notify .name }"), ["DYNAMIC_MESSAGE"])
}

///|
test "a view name the block neither answers nor forwards is a warning" {
  assert_eq(codes_with_views("receive save(t) { ask }", ["save"]), [])
  assert_eq(codes_with_views("receive save(t) { .name = t }", ["save"]), [])
  // The handler answers a name the SCHEMA declares, and the view's `saev` is
  // answered by nothing — one warning, and no NO_SUCH_MESSAGE, because
  // `resetTo` is a real case.
  assert_eq(codes_with_views("receive resetTo(n) { .count = n }", ["saev"]), [
    "NO_VIEW_HANDLER",
  ])
}

///|
test "NO_VIEW_HANDLER names both fixes, and is not fatal" {
  let inputs : Map[String, Array[@tutuca.Ty?]] = Map([])
  inputs["saveDraft"] = [None]
  let found = @check.check(
    @tscript.parse_script("receive resetTo(n) { .count = n }"),
    def_of(schema()),
    surface={ inputs, knows_views: true, open_senders: false, comps: [], },
  )
  assert_eq(found.length(), 1)
  assert_eq(found[0].severity, SWarning)
  assert_eq(
    found[0].message,
    "the view sends `saveDraft`, and this block neither answers it nor forwards it — write `receive saveDraft(…) { forward }` to dispatch it as an intent, or `receive saveDraft(…) { … }` to answer it here",
  )
}

///|
test "a mutator spelling is reported, and names the property action" {
  // The premise this test used to hold — "a generated mutator answers it, so
  // stay quiet" — is what 0.48 deleted. These are now the names MOST likely to
  // be dead, because they are the ones that used to work without a handler.
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["setCount"]),
    ["NO_VIEW_HANDLER"],
  )
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["toggleOk"]),
    ["NO_VIEW_HANDLER"],
  )
  // `At` is part of the generated name, not of the verb.
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["removeInItemsAt"]),
    ["NO_VIEW_HANDLER"],
  )
  // A name that is no mutator of any member is reported too — the rule is the
  // same one, and only the repair it names differs.
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["setWidget"]),
    ["NO_VIEW_HANDLER"],
  )
}

///|
test "the repair a mutator spelling names is a property action" {
  let inputs : Map[String, Array[@tutuca.Ty?]] = Map([])
  inputs["setName"] = [None]
  let found = @check.check(
    @tscript.parse_script("receive resetTo(n) { .count = n }"),
    def_of(schema()),
    surface={ inputs, knows_views: true, open_senders: false, comps: [], },
  )
  assert_eq(found.length(), 1)
  assert_eq(found[0].severity, SWarning)
  assert_eq(
    found[0].message,
    "the view sends `setName`, and this block neither answers it nor forwards it — `setName` is the generated `set` mutator's name for `name`, and generated mutators stopped answering dispatches in 0.48 — write `.name = v` in the view where it is sent, or answer it here with `receive setName(…) { … }`",
  )
}

///|
test "an intent declaration does not answer a view name" {
  // A view raises MESSAGES. An `intent` declaration answers a routed dispatch,
  // which is a different channel, so it does not silence this rule.
  assert_eq(codes_with_views("answer save(t) { reply 1 }", ["save"]), [
    "NO_VIEW_HANDLER",
  ])
}

// -- the spec block's rules -------------------------------------------------

///|
fn rule_findings(spec : String) -> Array[String] raise {
  let def = @statedef.parse_state(spec)[0]
  @check.check_rules(def).map(f => f.message)
}

///|
test "a rule reading a field the state does not declare is reported" {
  debug_inspect(
    rule_findings("state Counter { count : Int  pred ok { .nope > 0 } }"),
    content=(
      #|["`.nope` is not a field of the Counter state; declare it in the <script type=\"tutuca/spec\"> block"]
    ),
  )
}

///|
test "a rule body that cannot decide anything is reported" {
  // The same ALWAYS_TRUE rule every other condition gets, and not a stricter
  // one: a string and a number are boolish in tutuca.
  debug_inspect(
    rule_findings("state Counter { items : Array[Int]  pred any { .items } }"),
    content=(
      #|["Array[Int] is always truthy, so this condition never decides anything — test `empty?` of it, or a field of it"]
    ),
  )
}

///|
test "a format that answers a number is reported, and one that answers a string is not" {
  debug_inspect(
    rule_findings(
      "state Counter { count : Int  invariant ok format .count { .count > 0 } }",
    ),
    content=(
      #|["a `format` is the sentence a reader is shown, and this one answers Int — write a string, or a `$'…'` template that puts it in one"]
    ),
  )
  assert_eq(
    rule_findings(
      "state Counter { count : Int  invariant ok format $'{.count} is not above zero' { .count > 0 } }",
    ),
    [],
  )
}

///|
test "a rule that does not parse is reported where it broke, not where it started" {
  let out = rule_findings(
    "state Counter { count : Int  pred ok { .a + .b * .c } }",
  )
  assert_eq(out.length(), 1)
  // The block language refuses two operator families in one unparenthesized
  // chain, which is the whole reason it has no precedence table.
  assert_true(out[0].contains("parenthes") || out[0].contains("`*`"))
}

///|
test "a contract naming a spec-block rule resolves" {
  let def = @statedef.parse_state(
      "state Ledger { here : Int  there : Int  pred canPush { .here > 0 } }",
    )[0]
  let decls = @tscript.parse_script(
    "receive push requires canPush { .here -= 1\n.there += 1 }",
  )
  assert_eq(@check.check(decls, def).map(f => f.message), [])
}

///|
test "a contract naming nothing says where the rule goes" {
  let def = @statedef.parse_state("state Ledger { here : Int }")[0]
  let decls = @tscript.parse_script(
    "receive push requires canPush { .here -= 1 }",
  )
  debug_inspect(
    @check.check(decls, def).map(f => f.message),
    content=(
      #|["`requires canPush` names no `pred` the spec block declares; `push` asks for it, so declare `pred canPush { … }` inside `state Ledger` in the spec block"]
    ),
  )
}

///|
test "a rule declared in both blocks is reported rather than silently resolved" {
  let def = @statedef.parse_state(
      "state Ledger { here : Int  pred canPush { .here > 0 } }",
    )[0]
  let decls = @tscript.parse_script(
    "pred canPush { .here > 99 }\nreceive push requires canPush { .here -= 1 }",
  )
  let out = @check.check(decls, def)
  assert_eq(out.length(), 1)
  assert_eq(out[0].code, "RULE_IN_BOTH")
  assert_eq(out[0].severity, SWarning)
}

///|
/// `notify` is an `ask` with no answer channel, and the checker holds it to
/// that.
///
/// The word exists because `ask 'x'` whose sender declares no answer arms and
/// `ask 'x'` whose sender FORGOT them read identically at the call site — one
/// is a notification and the other is a bug, and which it is was decided
/// somewhere else in the file. `notify` says it where it is written. The price
/// of the promise is this: an answer arm for a name only ever notified is an
/// arm that can never fire, and a promise nothing enforces is a comment.
test "an answer arm for a notified name never fires, and is reported" {
  assert_eq(codes("receive x { notify 'rowPicked' .count }"), [])
  assert_eq(
    codes(
      "receive x { notify 'rowPicked' }\nreceive rowPickedOk(v) { .count = 1 }",
    ),
    ["ANSWERS_A_NOTIFY"],
  )
  assert_eq(
    messages(
      "receive x { notify 'rowPicked' }\nreceive rowPickedFailed(v) { .count = 1 }",
    ),
    [
      "`receive rowPickedFailed` answers a question, and `notify 'rowPicked'` asks none — a notification has no answer channel, so this arm never fires. Write `ask 'rowPicked'` if an answer was meant",
    ],
  )
  // A name that is BOTH asked and notified has an answer channel: one call
  // site is a question and the other is an announcement, which is unusual and
  // not wrong.
  assert_eq(
    codes(
      "receive x { notify 'rowPicked' }\nreceive y { ask 'rowPicked' }\nreceive rowPickedOk(v) { .count = 1 }",
    ),
    [],
  )
}

///|
/// `.child.x = v` writes a member of a CHILD, and the checker lets it.
///
/// It is not a spine rebuild: a child is a separate instance, and the write is
/// addressed at its position the way a view's `.x = v` is addressed at its
/// own. This is the door M6 left open when the `sendAt 'setX'` workaround went
/// away with the generated mutators — after that a card could not write a
/// child's member at all.
///
/// One step only. The member's type belongs to the child's schema, which this
/// component does not have, so the value crosses opaque and nothing deeper is
/// addressable.
test "a write into a child is a path this component may address" {
  assert_eq(codes("receive focusIt { .row.text = 'x' }"), [])
  assert_eq(codes("receive focusIt { .row.n = .count }"), [])
}

// -- the property block's diagnostics ---------------------------------------
//
// Every one of these asserts the MESSAGE, not the code, and that is the whole
// point of the group: all six shipped in 0.49.5 printing a literal `{d.name}`
// because MoonBit interpolation is `\{…}` and the backslash was missing. A
// suite that asserts codes cannot see that — the code is a constant — so the
// family that names a subject is tested by its wording or not at all.
// Reported independently by two consumers, neither of whom could tell from the
// diagnostic which `get` in their spec block was the wrong one.

///|
fn prop_messages(spec : String, block : String) -> Array[String] raise {
  @check.check(@tscript.parse_script(block), def_of(spec)).map(f => f.message)
}

///|
/// A spec whose one property is FIELD-BACKED, so nothing else in the block is
/// missing: a `{ get }` with no body of its own reports its own finding, which
/// would ride along in every assertion below and hide the one being made.
fn backed_spec() -> String {
  "state Counter { count : Int  view : String  property { reading : String { get .view set .view } } }"
}

///|
test "NO_PROPERTY names the property the block asked for" {
  assert_eq(prop_messages(backed_spec(), "get heading { .view }"), [
    "`get heading` names no property in the spec block",
  ])
  assert_eq(prop_messages(backed_spec(), "set heading { .view = value }"), [
    "`set heading` names no property in the spec block",
  ])
}

///|
test "READ_ONLY_PROPERTY names the property that did not opt into `set`" {
  assert_eq(
    prop_messages(
      "state Counter { count : Int  view : String  property { reading : String { get .view } } }",
      "set reading { .view = value }",
    ),
    ["property `reading` did not opt into `set`"],
  )
}

///|
test "PROPERTY_ALREADY_BACKED names the property backed by a field" {
  assert_eq(prop_messages(backed_spec(), "get reading { .view }"), [
    "property `reading` already names a backing field for `get`, so it cannot also have a complex getter",
  ])
  assert_eq(prop_messages(backed_spec(), "set reading { .view = value }"), [
    "property `reading` already names a backing field for `set`, so it cannot also have a complex setter",
  ])
}

///|
test "PROPERTY_EFFECT names the effect to move" {
  assert_eq(
    prop_messages(
      "state Counter { count : Int  view : String  property { reading : String { get set } } }",
      "get reading { .view }\nset reading { send 'saved' }",
    ),
    [
      "a property setter is synchronous and pure; move `send` to a message handler",
    ],
  )
}
