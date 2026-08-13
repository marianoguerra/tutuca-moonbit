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
    #|}
    #|receive Counter { ResetTo(Int), Rename(String, Int) }
    #|bubble  Counter { RowPicked(Int) }
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

// -- fields -----------------------------------------------------------------

///|
test "an unknown field is named, and the message guesses" {
  assert_eq(messages("on x { .coutn = 1 }"), [
    "`.coutn` is not a field of the Counter state — did you mean `.count`?",
  ])
  assert_eq(messages("on x { .wildlyDifferent = 1 }"), [
    "`.wildlyDifferent` is not a field of the Counter state; declare it in the <script type=\"tutuca/state\"> block",
  ])
  assert_eq(codes("on x { .count = 1 }"), [])
}

///|
test "a nested read is checked all the way down" {
  assert_eq(codes("on x { .labels[0].done = true }"), [])
  assert_eq(messages("on x { .labels[0].dnoe = true }"), [
    "`Label` has no field `dnoe`",
  ])
  assert_eq(messages("compute a { .count[0] }"), [
    "`Int` is not a collection, so it has nothing to index",
  ])
}

// -- assignment -------------------------------------------------------------

///|
test "assignment types have to fit, and the numeric surface is one" {
  assert_eq(codes("on x { .count = 1 }"), [])
  // `Value` has one `Num(Double)`, so an s32 and an f64 are the same runtime
  // shape — narrowing is a range check at run time, not a type error here.
  assert_eq(codes("on x { .count = .ratio }"), [])
  assert_eq(messages("on x { .count = 'hi' }"), [
    "this place is Int, but the value is String",
  ])
  // `any` takes anything, which is what it is for.
  assert_eq(codes("on x { .blob = 'hi' }"), [])
  // …and an enum is a string at runtime, so a computed string can name a case.
  assert_eq(codes("on x { .pri = 'high' }"), [])
}

///|
test "compound assignment is arithmetic" {
  assert_eq(codes("on x { .count += 1 }"), [])
  assert_eq(messages("on x { .name += 'x' }"), [
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
  assert_eq(messages("receive resetTP(n) { .count = n }"), [
    "the schema declares no `receive` case `resetTP` — did you mean `resetTo`?",
  ])
  // The buckets are separate questions: a `bubble` case is not a `receive`.
  assert_eq(messages("receive rowPicked(i) { .count = i }"), [
    "the schema declares no `receive` case `rowPicked`; add it to `variant receive` in the <script type=\"tutuca/state\"> block",
  ])
  assert_eq(codes("bubble rowPicked(i) { .count = i }"), [])
}

// -- names and applications -------------------------------------------------

///|
test "a bare name is a parameter, a builtin, or something this block declares" {
  assert_eq(codes("on set(value) { .name = value }"), [])
  assert_eq(messages("on set(value) { .name = valeu }"), [
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
  assert_eq(codes("on x { .count = len .items }"), [])
  // …and `trim` answers text, so it does not.
  assert_eq(messages("on x { .count = trim .name }"), [
    "this place is Int, but the value is String",
  ])
}

///|
test "a parameter cannot be applied" {
  assert_eq(messages("on set(value) { .name = value .name }"), [
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
  assert_eq(codes("on x(v) { .items.push v }"), [])
  assert_eq(codes("on x(v) { .tags.add v }"), [])
  assert_eq(codes("on x(k, v) { .byKey.setAt k v }"), [])
  assert_eq(messages("on x(v) { .items.add v }"), [
    "`add` does not apply to Array[String]",
  ])
  assert_eq(messages("on x(v) { .byKey.push v }"), [
    "`push` does not apply to Map[String, String]",
  ])
}

// -- effects ----------------------------------------------------------------

///|
test "an effect's message name has to be known before anything runs" {
  assert_eq(codes("on x { send 'flash' .name }"), [])
  assert_eq(codes("on x { stop }"), [])
  assert_eq(codes("on x { sendAt &.labels[0] 'select' }"), [])
  assert_eq(messages("on x { send .name 'body' }"), [
    "`send` needs a literal message name: the generator routes it, so it has to be known before anything runs",
  ])
}

///|
test "a binding is assignable only where bindings are produced" {
  assert_eq(codes("enrich rowInfo { @cls = 'row' }"), [])
  assert_eq(codes("enrichScope header { @title = .name }"), [])
  assert_eq(messages("on x { @cls = 'row' }"), [
    "`@cls` is a binding, and only `enrich` and `enrichScope` produce bindings — a handler assigns state",
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
        #|on x { if $over { .count = 0 } }
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
        #|on x { if over { .count = 0 } }
      ),
    ),
    [],
  )
  // A name nothing declares still reads Null, and the message says what a
  // body can call instead.
  assert_eq(messages("compute a { $summary }"), [
    "`$summary` is answered by the render stack, and a body runs after one, so it reads Null here; a `pred` or a `compute` is called bare from a body, and nothing here declares one by that name",
  ])
  // A dynamic binding has no spelling that works from a body.
  assert_eq(messages("on x { .name = *theme }"), [
    "`*theme` is answered by the render stack, and a body runs after one, so it reads Null here; a body cannot read a dynamic binding at all",
  ])
}

// -- unknown is not wrong ---------------------------------------------------

///|
test "every opaque source silences the checks below it" {
  // A `$method` result and a `*dyn` are opaque, and the assignment they feed
  // is therefore unchecked — RENDER_ONLY is the finding about the sigil
  // itself, and nothing follows it about `.count`.
  assert_eq(codes("on x { .count = $whatever }"), ["RENDER_ONLY"])
  assert_eq(codes("on x { .count = *theme }"), ["RENDER_ONLY"])
  // A binding comes from the slot that uses the declaration, which the block
  // cannot see — and so does everything under it.
  assert_eq(codes("pred p { @value.completed }"), [])
  assert_eq(codes("compute a { @iter.min }"), [])
  // An `any` field holds whatever it was given.
  assert_eq(codes("compute a { .blob + 1 }"), [])
  // An `on` handler no view calls has opaque arguments rather than none: a
  // name can be raised from MoonBit, and the block may answer one the
  // templates never mention.
  assert_eq(codes("on neverCalled(a) { .count = a }"), [])
}

// -- the views' half --------------------------------------------------------

///|
test "an on handler's argument types come from the views' call sites" {
  let decls = @tscript.parse_script("on add(d) { .name = d }")
  // With nothing known, nothing is checked.
  assert_eq(@check.check(decls, def_of(schema())).length(), 0)
  // With the call site saying `@on.click="add 1"`, the parameter is a number
  // and writing it into a string field is caught.
  let surface : @check.Surface = { inputs: { "add": [Some(TFloat)] } }
  assert_eq(
    @check.check(decls, def_of(schema()), surface~).map(f => f.message),
    ["this place is String, but the value is Double"],
  )
}

///|
test "a parameter list that disagrees with the call sites" {
  let decls = @tscript.parse_script("on add(d, e) { .count = d }")
  let surface : @check.Surface = { inputs: { "add": [Some(TFloat)] } }
  assert_eq(
    @check.check(decls, def_of(schema()), surface~).map(f => f.message),
    ["`add` takes 2 parameter(s) here, but the views call it with 1"],
  )
}

///|
test "call sites that disagreed joined to opaque, and stay unchecked" {
  // `join_arg` answers `VValue` when two call sites disagree, which arrives
  // here as None — and None is never wrong.
  let decls = @tscript.parse_script("on add(d) { .name = d }")
  let surface : @check.Surface = { inputs: { "add": [None] } }
  assert_eq(@check.check(decls, def_of(schema()), surface~).length(), 0)
}

// -- findings carry positions -----------------------------------------------

///|
test "a finding points at the thing it is about" {
  let decls = @tscript.parse_script("on x {\n  .coutn = 1\n}")
  let fs = @check.check(decls, def_of(schema()))
  assert_eq(fs.length(), 1)
  // `.coutn` starts at offset 9 — the block's own coordinates, which
  // `@viewfile.Block` rebases onto the file.
  assert_eq(fs[0].span, { start: 9, end_: 15 })
}
