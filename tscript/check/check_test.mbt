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
    #|  provide { count = .count }
    #|  lookup { theme, color = 'gray' }
    #|}
    #|receive Counter { resetTo(Int), rename(String, Int) }
    #|intent  Counter { rowPicked(Int), save(String) }
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
  let inputs : Map[String, Array[@statedef.StateTy?]] = Map([])
  for v in views {
    inputs[v] = [None]
  }
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema()), surface={
    inputs,
    knows_views: true,
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
    "`.wildlyDifferent` is not a field of the Counter state; declare it in the <script type=\"tutuca/state\"> block",
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
    "the schema declares no `receive` case `rowPicked`; add it to `variant receive` in the <script type=\"tutuca/state\"> block",
  ])
  assert_eq(codes("intent rowPicked(i) { .count = i }"), [])
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
  assert_eq(codes("receive x { stop }"), [])
  assert_eq(codes("receive x { sendAt &.labels[0] 'select' }"), [])
  assert_eq(messages("receive x { send .name 'body' }"), [
    "`send` needs a literal message name: the generator routes it, so it has to be known before anything runs",
  ])
}

///|
test "a binding is assignable only where bindings are produced" {
  assert_eq(codes("enrich rowInfo { @cls = 'row' }"), [])
  assert_eq(codes("enrichScope header { @title = .name }"), [])
  assert_eq(messages("receive x { @cls = 'row' }"), [
    "`@cls` is a binding, and only `enrich` and `enrichScope` produce bindings — a handler assigns state, and `new` builds a value in `@cur`",
  ])
}

// -- the render stack's sigils ----------------------------------------------

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
    inputs: { "add": [Some(TFloat)] },
    knows_views: true,
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
    inputs: { "add": [Some(TFloat)] },
    knows_views: true,
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
  assert_eq(fs[0].span, { start: 14, end_: 20 })
}

// -- new, and the target ----------------------------------------------------

///|
test "a new gives the target a type, so a field of it is checked" {
  assert_eq(
    codes("receive x {\n  new Label\n  @cur.text = 'a'\n  .labels.push @cur\n}"),
    [],
  )
  // The payoff for typing the target: `@cur.dnoe` reads exactly like
  // `.labels[0].dnoe` does, because it goes through the same step walk.
  assert_eq(messages("receive x {\n  new Label\n  @cur.dnoe = 'a'\n}"), [
    "`Label` has no field `dnoe`",
  ])
  assert_eq(messages("receive x {\n  new Label\n  @cur.done = 'yes'\n}"), [
    "this place is Bool, but the value is String",
  ])
}

///|
test "the target does not exist until a new makes one" {
  assert_eq(messages("receive x { .labels.push @cur }"), [
    "`@cur` holds what a `new` built, and no `new` has run here — write `new <Type>` above this",
  ])
  // And the report is once, not once per step below it.
  assert_eq(codes("receive x { @cur.text = 'a' }"), ["NO_TARGET"])
}

///|
test "a type the state does not declare is named, with the nearest one" {
  assert_eq(messages("receive x { new Labl }"), [
    "`Labl` is not a type the Counter state declares — did you mean `Label`?",
  ])
  assert_eq(messages("receive x { new Array[Widget] }"), [
    "`Array[Widget]` is not a type the Counter state declares; declare it in the <script type=\"tutuca/state\"> block, or write a built-in type",
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
  assert_eq(codes("receive x {\n  new Array[String]\n  @cur.push 'a'\n}"), [])
  assert_eq(messages("receive x {\n  new Label\n  @cur.push 'a'\n}"), [
    "`push` does not apply to Label",
  ])
}

///|
test "a target built in a branch is known only where both arms agree" {
  // Same type on both sides: known below.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { new Label }\n  @cur.text = 'a'\n}",
    ),
    [],
  )
  // One arm only: nothing is there on the other path, so a read below reports.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { .count = 1 }\n  @cur.text = 'a'\n}",
    ),
    ["NO_TARGET"],
  )
  // Two different types: a target IS there, and its type is not knowable — so
  // the field goes unchecked rather than misreported.
  assert_eq(
    codes(
      "receive x {\n  if .ok { new Label } else { new Array[String] }\n  @cur.dnoe = 'a'\n}",
    ),
    [],
  )
}

///|
test "the target is not a binding an enrich can publish" {
  // It never reaches a view — the interpreter withholds it — so an enricher
  // that assigned it would be writing into a workbench and calling it output.
  assert_eq(messages("enrich row { @cur = 'x' }"), [
    "`@cur` is the target `new` builds into, not a binding this `enrich` can hand a view — bind another name",
  ])
  // Building one and publishing something else is fine.
  assert_eq(
    codes("enrich row {\n  new Label\n  @cur.text = 'a'\n  @tag = @cur.text\n}"),
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
    "`requires enough` names no `pred` this block declares; declare `pred enough { … }` above `bump`",
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
      "`requires caption` names no `pred` this block declares; `caption` is a `compute`, and a contract names a `pred`, whose answer is declared to be a yes or a no",
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
      "`requires enouhg` names no `pred` this block declares — did you mean `enough`?",
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
  let inputs : Map[String, Array[@statedef.StateTy?]] = Map([])
  for v in views {
    // One opaque argument: enough for a one-parameter handler to bind, and
    // opaque is what a real join of disagreeing call sites gives anyway.
    inputs[v] = [None]
  }
  let decls = @tscript.parse_script(block)
  @check.check(decls, def_of(schema()), surface={
    inputs,
    knows_views: true,
    comps: [],
  }).map(f => f.code)
}

///|
test "reply and fail answer a sender, and only an intent has one" {
  assert_eq(codes("intent rowPicked(k) { reply .count }"), [])
  assert_eq(codes("intent rowPicked(k) { fail 'no' }"), [])
  assert_eq(messages("receive resetTo(n) { reply .count }"), [
    "`reply` answers the sender of an intent, and `receive resetTo` has none — a message is addressed, so nobody is waiting for an answer",
  ])
  assert_eq(messages("receive click { fail 'no' }"), [
    "`fail` answers the sender of an intent, and `receive click` has none — a message is addressed, so nobody is waiting for an answer",
  ])
  assert_eq(codes("enrich row { reply 1 }"), ["NOT_A_HANDLER"])
}

///|
test "forward passes on the message this body is handling" {
  assert_eq(codes("receive resetTo(n) { forward }"), [])
  assert_eq(codes("intent rowPicked(k) { forward dyn }"), [])
  assert_eq(messages("compute a { .count }"), [])
  assert_eq(messages("enrich row { forward }"), [
    "`forward` passes on the message this body is handling, and `enrich row` is not handling one",
  ])
}

///|
test "reply and fail are not dynamic message names" {
  // "Is the first argument a literal message name?" is asked only of the
  // effects that NAME a message. `reply`, `fail` and `forward` name none — an
  // answer is addressed by the walk and a `forward` re-dispatches the name
  // that arrived — so asking would report `reply 1` as a dynamic message name.
  assert_eq(codes("intent rowPicked(k) { reply 1 }"), [])
  assert_eq(codes("intent rowPicked(k) { reply .count }"), [])
  assert_eq(codes("intent rowPicked(k) { fail .name }"), [])
  assert_eq(codes("receive resetTo(n) { forward .name }"), [])
  // ...and the rule still holds for the effects that DO name one.
  assert_eq(codes("receive x { intent .name }"), ["DYNAMIC_MESSAGE"])
  assert_eq(codes("receive x { send .name }"), ["DYNAMIC_MESSAGE"])
}

///|
test "a view name the block neither answers nor forwards is a warning" {
  assert_eq(codes_with_views("receive save(t) { forward }", ["save"]), [])
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
  let inputs : Map[String, Array[@statedef.StateTy?]] = Map([])
  inputs["saveDraft"] = [None]
  let found = @check.check(
    @tscript.parse_script("receive resetTo(n) { .count = n }"),
    def_of(schema()),
    surface={ inputs, knows_views: true, comps: [] },
  )
  assert_eq(found.length(), 1)
  assert_eq(found[0].severity, SWarning)
  assert_eq(
    found[0].message,
    "the view sends `saveDraft`, and this block neither answers it nor forwards it — write `receive saveDraft(…) { forward }` to dispatch it as an intent, or `receive saveDraft(…) { … }` to answer it here",
  )
}

///|
test "a generated mutator answers a view name, so it is not reported" {
  // The checker cannot see `component/gen_mutators`' verb table, so it asks
  // the conservative question instead: does the name address a declared field?
  // Erring toward silence is this package's governing rule.
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["setCount"]),
    [],
  )
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["countLen"]),
    [],
  )
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["removeInItemsAt"]),
    [],
  )
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["toggleOk"]),
    [],
  )
  // A name that addresses no field is not a mutator, whatever it looks like.
  assert_eq(
    codes_with_views("receive resetTo(n) { .count = n }", ["setWidget"]),
    ["NO_VIEW_HANDLER"],
  )
}

///|
test "an intent declaration does not answer a view name" {
  // A view raises MESSAGES. An `intent` declaration answers a routed dispatch,
  // which is a different channel, so it does not silence this rule.
  assert_eq(codes_with_views("intent save(t) { reply 1 }", ["save"]), [
    "NO_VIEW_HANDLER",
  ])
}
