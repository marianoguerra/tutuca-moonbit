// What the MoonBit backend writes, and what it refuses.
//
// Assertions on SOURCE TEXT, which is unusual and is the point: this emitter's
// output is compiled by `moonc` later, in a package this test cannot reach, so
// the only thing pinned here is the shape. Whether that shape compiles is
// answered by the corpus in `storybook/examples`, which regenerates and builds
// on every `cmd/dev -- ci`.
//
// The refusals carry as much weight as the emissions. Roughly 15% of the
// corpus is reserved for MoonBit by design — `walk_path`, request options,
// node-replacing `swap` — and a backend that guessed at those would be worse
// than one that names the handler to write by hand.

///|
fn def_of(src : String) -> @statedef.StateDef raise {
  @statedef.parse_state(src)[0]
}

///|
/// One field of most shapes, so a case can pick what it needs.
fn schema() -> String {
  (
    #|enum Visibility { Done, Active }
    #|state Counter {
    #|  label   : String
    #|  count   : Int
    #|  ratio   : Double
    #|  ok      : Bool
    #|  history : Array[Int]
    #|  tags    : Set[String]
    #|  vis     : Set[Visibility]
    #|  byKey   : Map[String, String]
    #|  blob    : Any
    #|  note    : String?
    #|  year    : Int?
    #|}
    #|handle Counter { message { resetTo(Int), rename(String, Int) } }
  )
}

///|
/// The argument types the views imply, for the handlers whose parameters have
/// no schema to come from. This is `viewgen/surface.mbt`'s own inference,
/// handed over: an `@on.click="tag 'x'"` in a template is what says `tag`
/// takes text.
fn views() -> @check.Surface {
  {
    inputs: {
      "tag": [Some(TyText)],
      "flip": [Some(TyText)],
      "dropAt": [Some(TyInt(width=32, signed=true))],
      "show": [Some(TyText)],
    },
    knows_views: true,
    open_senders: false,
    comps: [],
  }
}

///|
/// Compile a block against the shared schema.
fn out(block : String) -> @emit_mbt.Emitted raise {
  @emit_mbt.emit(
    @tscript.parse_script(block),
    def_of(schema()),
    state_ty="CounterState",
    fn_name="counter_inline_update",
    surface=views(),
  )
}

///|
/// Compile a block with its value bodies asked for, the way the generator asks
/// once the views have said which name is reached how.
fn out_values(
  block : String,
  methods? : Array[String] = [],
  whens? : Array[String] = [],
  enriches? : Array[String] = [],
  enrich_scopes? : Array[String] = [],
) -> @emit_mbt.Emitted raise {
  @emit_mbt.emit(
    @tscript.parse_script(block),
    def_of(schema()),
    state_ty="CounterState",
    fn_name="counter_inline_update",
    prefix="counter",
    roles={ methods, whens, enriches, enrich_scopes, },
    surface=views(),
  )
}

///|
/// The emitted body of the first arm, with its indentation, or "" when nothing
/// compiled. What is asserted is the STATEMENTS, not the wrapper.
fn body(block : String) -> String raise {
  let src = out(block).source
  if src == "" {
    return ""
  }
  let lines : Array[String] = src.split("\n").map(l => l.to_owned()).collect()
  let keep : Array[String] = []
  let mut inside = false
  for l in lines {
    if l.has_prefix("    Input(") ||
      l.has_prefix("    Receive(") ||
      l.has_prefix("    Bubble(") ||
      l.has_prefix("    Response(") {
      inside = true
      continue
    }
    if inside {
      if l == "    }" {
        break
      }
      keep.push(l.trim(chars=" ").to_owned())
    }
  }
  keep.join("\n")
}

///|
/// The reasons a block's declarations were refused.
fn whys(block : String) -> Array[String] raise {
  out(block).refusals.map(r => r.why)
}

// -- what compiles ----------------------------------------------------------

///|
test "a compute and a pred compile into the functions the generator routes to" {
  // The bug this covers: the block declared the rule, the generated module
  // carried only its NAME, and the component answered `$over` with nothing —
  // so the view read false forever while the file said `.count > 3`.
  let e = out_values(
    (
      #|compute caption { $'{.count} left' }
      #|pred over { .count > 3 }
    ),
    methods=["caption", "over"],
  )
  assert_eq(e.answers_methods, ["caption", "over"])
  assert_eq(e.refusals.map(r => r.name), [])
  assert_true(
    e.source.contains(
      "fn counter_compute_over(s : CounterState, _args : Array[@tutuca.Value], _stack : &@tutuca.Stack) -> @tutuca.Value",
    ),
  )
  // A `pred` answers yes or no whatever its expression is, so the value that
  // comes back is a Bool — the same truthiness a card gives the same body.
  assert_true(
    e.source.contains("(Bool((s.count.to_double() > 3.0)) : @tutuca.Value)"),
  )
}

///|
test "one body calls another by name, which is how a body spells a callable" {
  let e = out_values(
    (
      #|pred over { .count > 3 }
      #|compute label { if over { 'over' } else { 'under' } }
    ),
    methods=["over", "label"],
  )
  assert_eq(e.answers_methods, ["over", "label"])
  // The call, not a second copy of the rule.
  assert_true(
    e.source.contains("counter_compute_over(s, [], stack).is_truthy()"),
  )
}

///|
test "a pred used as a @when is compiled again, with the row in scope" {
  let e = out_values(
    "pred matches { contains (lower @value) (lower .label) }",
    methods=["matches"],
    whens=["matches"],
  )
  // As a `@when` it compiles: the renderer hands it the row.
  assert_eq(e.answers_whens, ["matches"])
  assert_true(
    e.source.contains(
      "fn counter_when_matches(s : CounterState, _key : @tutuca.Value, value : @tutuca.Value, _iter_data : @tutuca.Value, _stack : &@tutuca.Stack) -> Bool",
    ),
  )
  // As a METHOD it cannot: a `$name` call site has no row to hand it, and
  // guessing one is the thing this backend does not do.
  assert_eq(e.answers_methods, [])
  assert_true(e.refusals[0].why.contains("@value"))
}

///|
test "an enricher writes bindings, and may read one it wrote" {
  let e = out_values(
    (
      #|enrich row {
      #|  @long = (len .label) > 3
      #|  @tag = str @long
      #|}
    ),
    enriches=["row"],
  )
  assert_eq(e.answers_enriches, ["row"])
  assert_true(e.source.contains("binds[\"long\"] ="))
  assert_true(e.source.contains("binds.get(\"long\").unwrap_or(Null)"))
}

///|
test "a scope enricher answers the map, since it is handed none" {
  let e = out_values("enrichScope info { @len = len .label }", enrich_scopes=[
    "info",
  ])
  assert_eq(e.answers_enrich_scopes, ["info"])
  assert_true(
    e.source.contains(
      "fn counter_enrich_scope_info(s : CounterState, _stack : &@tutuca.Stack) -> Map[String, @tutuca.Value]",
    ),
  )
  assert_true(e.source.contains("  binds\n"))
}

///|
test "`has` asks a set and a map for a KEY, and a list for a value" {
  // Three shapes, one question. The keyed cases go through the display string
  // because that is the key `hasIn<X>` writes and `tc_has` reads — a member
  // put in by `addInTags 3` has to be found by `has .tags 3`.
  let e = out_values(
    (
      #|pred inTags { has .tags .label }
      #|pred inMap { has .byKey .label }
      #|pred inList { has .history .count }
    ),
    methods=["inTags", "inMap", "inList"],
  )
  assert_eq(e.answers_methods, ["inTags", "inMap", "inList"])
  assert_true(
    e.source.contains(
      "s.tags.contains((Str(s.label) : @tutuca.Value).to_display_string())",
    ),
  )
  assert_true(
    e.source.contains(
      "s.byKey.contains((Str(s.label) : @tutuca.Value).to_display_string())",
    ),
  )
  // The list case compares at the ELEMENT's type, not as a Value.
  assert_true(e.source.contains("s.history.contains(s.count)"))
}

///|
test "`has` refuses a receiver with no membership to ask about" {
  let e = out_values("pred inLabel { has .label .label }", methods=["inLabel"])
  assert_eq(e.answers_methods, [])
  assert_true(e.refusals[0].why.contains("a set, a map or a list"))
}

///|
test "a value body nobody asks for is not written" {
  // Roles come from the VIEWS. A `compute` no slot reads is a function nobody
  // calls, and a generated file must not carry one.
  let e = out_values("compute caption { 'x' }")
  assert_eq(e.answers_methods, [])
  assert_eq(e.source, "")
}

///|
test "a zero divisor leaves through the ROLE's answer, not the transition's" {
  // The bug this covers: `gen-views` emitted the divide-by-zero guard as
  // `return Unchanged` everywhere, which is an `Update` constructor — so a
  // `compute` or a `pred` containing `/` produced a module that did not
  // BUILD. Division in a transition body keeps `Unchanged`; a value body
  // answers what its signature says a body that cannot finish answers.
  let e = out_values(
    (
      #|compute half { .count / 2 }
      #|pred overQuota { (.count / 2) > 3 }
    ),
    methods=["half", "overQuota"],
  )
  assert_eq(e.answers_methods, ["half", "overQuota"])
  assert_eq(e.refusals.map(r => r.name), [])
  // A `compute` returns a Value: leaving is `Null`, the same answer an
  // opaque coercion at a type gets.
  assert_true(e.source.contains("guard d0 != 0.0 else { return Null }"))
  // A `@when` returns a Bool.
  let w = out_values("pred overQuota { (.count / 2) > 3 }", whens=["overQuota"])
  assert_eq(w.answers_whens, ["overQuota"])
  assert_true(w.source.contains("guard d0 != 0.0 else { return false }"))
}

///|
test "division in a transition still leaves through Unchanged" {
  // The half of the rule that always worked and must keep working: in a
  // transition the guard's answer IS `Unchanged`.
  assert_true(
    body("receive scale { .ratio = .ratio / .count }").contains(
      "guard d0 != 0.0 else { return Unchanged }",
    ),
  )
}

///|
test "an enricher refuses a construct that would have to leave mid-body" {
  // An enricher writes into the map it was handed as it goes, so no guard can
  // leave early without keeping the writes already made. A zero divisor has
  // no in-band answer there — refused with the reason named, like an opaque
  // coercion, rather than emitted as code that does not build.
  let e = out_values("enrich row { @half = .count / 2 }", enriches=["row"])
  assert_eq(e.answers_enriches, [])
  assert_eq(e.refusals.map(r => r.name), ["row"])
  assert_true(e.refusals[0].why.contains("an `enrich` cannot"))
}

///|
test "a bounds-checked collection method leaves through the role's answer too" {
  // Same family as the divisor guard: `insertAt` / `removeAt` / `setAt`
  // bounds-check before they build the fresh array. They are statement-shape,
  // so the two bodies that reach them are a transition (`Unchanged`) and an
  // `enrich` (refused — see above).
  assert_true(
    body("receive dropOne { .history.deleteAt .count }").contains(
      "guard at >= 0 && at < s.history.length() else { return Unchanged }",
    ),
  )
  let e = out_values("enrich row { .history.deleteAt .count }", enriches=["row"])
  assert_eq(e.answers_enriches, [])
  assert_eq(e.refusals.map(r => r.name), ["row"])
}

///|
test "negation is emitted as `!`, which is the spelling moonc does not deprecate" {
  // `not(x)` warns — "Use !expr instead" — and a generated file must not be
  // the thing that warns, let alone the thing that fails a --deny-warn build
  // over a block whose author wrote nothing wrong. All three negating forms
  // go through the same spelling.
  assert_true(
    body("receive x { if not .ok { .count = 1 } }").contains("(!s.ok)"),
  )
  assert_true(
    body("receive x { if .label is not 'hi' { .count = 1 } }").contains("(!("),
  )
  assert_true(
    body("receive x { if .ok implies .ok { .count = 1 } }").contains(
      "((!s.ok) ||",
    ),
  )
  // And nowhere does the old spelling survive.
  for
    block in [
      "receive x { if not .ok { .count = 1 } }", "receive x { if .label is not 'hi' { .count = 1 } }",
      "receive x { if .ok implies .ok { .count = 1 } }",
    ] {
    assert_false(body(block).contains("not("))
  }
}

///|
test "an assignment is a copy-on-write rebinding of `s`" {
  // Rebinding rather than accumulating one struct literal is what lets a later
  // statement read what an earlier one wrote — the same thing a hand-written
  // arm does, spelled the same way.
  inspect(
    body("receive setLabel { .label = 'hi' }"),
    content=(
      #|let s = { ..s, label: "hi" }
      #|Next(s)
    ),
  )
}

///|
/// A nullable field is filled from a block, which it could not be: `T?` was
/// writable only from MoonBit, so every optional field pushed its own handlers
/// out of the block language — and `Any`, which a block CAN write, became the
/// spelling people reached for instead. Both halves are decided by the PLACE:
/// `null` is the one literal with no type of its own, and a present value is
/// the same value one level in.
test "a nullable field takes `null` for its empty and the bare value for its full" {
  inspect(
    body("receive clear { .note = null }"),
    content=(
      #|let s = { ..s, note: None }
      #|Next(s)
    ),
  )
  inspect(
    body("receive name { .note = 'hi' }"),
    content=(
      #|let s = { ..s, note: Some("hi") }
      #|Next(s)
    ),
  )
  // Through the same `at` one level in, so the integer-literal shortcut still
  // fires: `Some(3)`, not `Some(3.0.to_int())`.
  inspect(
    body("receive setYear { .year = 3 }"),
    content=(
      #|let s = { ..s, year: Some(3) }
      #|Next(s)
    ),
  )
}

///|
/// The widening stays honest. `Some(...)` is written only around a conversion
/// that was already legal, so the two pairs a non-optional place refuses are
/// refused through a `?` too — rather than becoming a `Some` wrapped around a
/// guess about what an opaque value holds.
test "a nullable place widens nothing a plain one would not" {
  let e = out("receive bad { .note = 3 }")
  assert_eq(e.source, "")
  assert_true(e.refusals[0].why.contains("does not fit"))
  let e2 = out("receive badAny { .note = .blob }")
  assert_eq(e2.source, "")
  assert_true(e2.refusals[0].why.contains("does not fit"))
}

///|
test "arithmetic goes through Double and comes back at the field's type" {
  // The rule that makes this backend agree with the interpreter without either
  // consulting the other: `Value` has ONE number, so an expression that rounds
  // at the boundary here rounds where the interpreter rounds too.
  inspect(
    body("receive bump { .count += 1 }"),
    content=(
      #|let s = { ..s, count: (s.count.to_double() + 1.0).to_int() }
      #|Next(s)
    ),
  )
  // …and a Double field needs no conversion at all.
  inspect(
    body("receive scale { .ratio += 0.5 }"),
    content=(
      #|let s = { ..s, ratio: (s.ratio + 0.5) }
      #|Next(s)
    ),
  )
}

///|
/// Author names and generated names share one namespace in the emitted
/// function, so a parameter used to be able to shadow a local this backend
/// needs — `receive rename(s, n) { .label = s }` wrote
/// `let s = { ..s, label: s }`, the parameter standing where the state should
/// have been, in a module that does not compile. The block was fine and
/// `gen-views` reported nothing; `moonc` found it, in a file nobody reads.
///
/// The table is one name per generated-name FAMILY, the counted ones included:
/// `v1`, `cur0` and `d0` come off counters, so no reserved-name list could
/// have covered them, which is why the fix renames the author's name rather
/// than refusing it.
test "a parameter cannot shadow a name the emitter generates" {
  for
    name in [
      "s", "_s", "args", "_args", "ctx", "stack", "binds", "key", "value", "iter_data",
      "at", "v1", "cur0", "d0",
    ] {
    assert_eq(
      body("receive rename(\{name}, n) { .label = \{name} }"),
      "guard args.get(0) is Some(Str(\{name}_)) else { return Unchanged }\n" +
      "guard args.get(1) is Some(Num(_)) else { return Unchanged }\n" +
      "let s = { ..s, label: \{name}_ }\n" +
      "Next(s)",
    )
  }
}

///|
/// The same rename on the value-body side, where the parameter binds out of
/// `args` and the state is the function's first parameter.
test "a compute parameter cannot shadow the state it is compiled beside" {
  let src = out_values("compute pick(s) { s }", methods=["pick"]).source
  assert_true(src.contains("let s_ = args.get(0).unwrap_or(Null)"))
  // The state parameter keeps its own spelling — a body that does not read it
  // gets the underscore, and nothing here is renamed on the generated side.
  assert_true(src.contains("_s : CounterState"))
}

///|
test "a receive handler's parameters are typed by the schema's payload" {
  inspect(
    body("receive resetTo(n) { .count = n }"),
    content=(
      #|guard args.get(0) is Some(Num(n_)) else { return Unchanged }
      #|let s = { ..s, count: n_.to_int() }
      #|Next(s)
    ),
  )
  // Two payload values, two guards, each at its own type.
  inspect(
    body("receive rename(t, n) { .label = t; .count = n }"),
    content=(
      #|guard args.get(0) is Some(Str(t_)) else { return Unchanged }
      #|guard args.get(1) is Some(Num(n_)) else { return Unchanged }
      #|let s = { ..s, label: t_ }
      #|let s = { ..s, count: n_.to_int() }
      #|Next(s)
    ),
  )
}

///|
test "a list method answers a fresh array, never a mutation of the receiver" {
  // The previous state is still on the transactor's stack, so writing through
  // `s.history` would edit a value someone else is holding.
  inspect(
    body("receive add1 { .history.push 1 }"),
    content=(
      #|let s = { ..s, history: (s.history + [1]) }
      #|Next(s)
    ),
  )
  // An index out of range is `Unchanged`, not a crash. A MoonBit slice
  // ABORTS past the end where the interpreter answers "no change", and this is
  // the whole reason both backends are held to one corpus.
  inspect(
    body("receive dropAt(i) { .history.removeAt i }"),
    content=(
      #|guard args.get(0) is Some(Num(i_)) else { return Unchanged }
      #|let at = i_.to_int()
      #|guard at >= 0 && at < s.history.length() else { return Unchanged }
      #|let s = { ..s, history: (s.history[0:at].to_owned() + s.history[at + 1:].to_owned()) }
      #|Next(s)
    ),
  )
}

///|
test "a set is Map-backed and copied before it is written" {
  inspect(
    body("receive tag(t) { .tags.add t }"),
    content=(
      #|guard args.get(0) is Some(Str(t_)) else { return Unchanged }
      #|let s = { ..s, tags: { let m = s.tags.copy(); m[t_] = true; m } }
      #|Next(s)
    ),
  )
  // Toggle reads before it writes, which is why it needs the binding.
  inspect(
    body("receive flip(t) { .tags.toggle t }"),
    content=(
      #|guard args.get(0) is Some(Str(t_)) else { return Unchanged }
      #|let s = { ..s, tags: { let m = s.tags.copy(); let k = t_; if m.get(k) is Some(true) { m.remove(k) } else { m[k] = true }; m } }
      #|Next(s)
    ),
  )
  // A closed set takes the same three, because the two share one runtime shape.
  assert_eq(whys("receive show(v) { .vis.add v }"), [])
}

///|
test "an if rebinds `s` through an expression, not two statement blocks" {
  // A `let` inside a braced statement would not escape it, so both branches
  // have to ANSWER the state.
  inspect(
    body("receive maybe { if .ok { .count += 1 } else { .count = 0 } }"),
    content=(
      #|let s = if s.ok {
      #|let s = { ..s, count: (s.count.to_double() + 1.0).to_int() }
      #|s
      #|} else {
      #|let s = { ..s, count: 0 }
      #|s
      #|}
      #|Next(s)
    ),
  )
}

///|
test "the answers are reported per bucket, for the enums to be trimmed by" {
  let e = out(
    (
      #|receive bump { .count += 1 }
      #|receive reset { .count = 0 }
      #|receive resetTo(n) { .count = n }
    ),
  )
  assert_eq(e.answers_input, ["bump", "reset"])
  assert_eq(e.answers_receive, ["resetTo"])
}

///|
test "a block that declares no transition emits no function at all" {
  // A `compute` and a `pred` are answered elsewhere; emitting an unused
  // function for them would be a thing to explain to `moon check`.
  let e = out("compute label { .label }\npred ready { .ok }")
  assert_eq(e.source, "")
  assert_eq(e.refusals, [])
}

// -- what it refuses --------------------------------------------------------

///|
test "a write through a path is refused by name, with what to do instead" {
  let w = whys("receive deep(i) { .history[0] = i }")
  assert_eq(w.length(), 1)
  assert_true(w[0].contains("spine rebuild"))
  assert_true(w[0].contains("write the handler in MoonBit"))
}

///|
test "a method the field's type does not have names the type" {
  let w = whys("receive nope { .count.push 1 }")
  assert_eq(w, [
    "`push` does not apply to `.count`, which is Int — write the handler in MoonBit",
  ])
}

///|
test "one refusal does not cost the block its other handlers" {
  // The whole reason refusals are DATA: a block with one handler that reaches
  // for something this backend cannot spell still has others that compile.
  let e = out(
    (
      #|receive bump { .count += 1 }
      #|receive deep(i) { .history[0] = i }
      #|receive reset { .count = 0 }
    ),
  )
  assert_eq(e.answers_input, ["bump", "reset"])
  assert_eq(e.refusals.map(r => r.name), ["deep"])
  assert_true(e.source.contains("Receive(\"bump\", _args)"))
  assert_true(e.source.contains("Receive(\"reset\", _args)"))
  assert_false(e.source.contains("Receive(\"deep\", "))
}

///|
test "a refusal carries the declaration's span, not the block's" {
  let e = out(
    "receive bump { .count += 1 }\nreceive deep(i) { .history[0] = i }",
  )
  assert_eq(e.refusals.length(), 1)
  // The second declaration starts after the first, which is the only thing
  // that makes the span useful for pointing at a line.
  assert_true(e.refusals[0].span.start > 20)
}

// -- new, and the target ----------------------------------------------------

///|
/// A schema with records in it, which the shared one has no field for.
fn rows_schema() -> String {
  (
    #|struct Label { text : String, done : Bool, tags : Array[String] }
    #|state Card {
    #|  labels : Array[Label]
    #|  grid   : Array[Array[String]]
    #|}
    #|handle Card { message { init } }
  )
}

///|
/// The emitted body of the first arm, against the record schema.
fn rows_body(block : String) -> String raise {
  let e = @emit_mbt.emit(
    @tscript.parse_script(block),
    def_of(rows_schema()),
    state_ty="CardState",
    fn_name="card_inline_update",
  )
  let keep : Array[String] = []
  let mut inside = false
  for l in e.source.split("\n").map(l => l.to_owned()) {
    if l.has_prefix("    Receive(") {
      inside = true
      continue
    }
    if inside {
      if l == "    }" {
        break
      }
      keep.push(l.trim(chars=" ").to_owned())
    }
  }
  keep.join("\n")
}

///|
/// Why the record-schema block's declarations were refused.
fn rows_whys(block : String) -> Array[String] raise {
  @emit_mbt.emit(
    @tscript.parse_script(block),
    def_of(rows_schema()),
    state_ty="CardState",
    fn_name="card_inline_update",
  ).refusals.map(r => r.why)
}

///|
test "a new is a let at the type's zero, and a write to it rebinds" {
  // The annotation is load-bearing: `zero_expr` writes the record literal
  // unqualified, because every other position it lands in has a type wanted.
  assert_eq(
    rows_body(
      (
        #|receive init {
        #|  new Label
        #|  @cur.text = 'Buy milk'
        #|  @cur.done = true
        #|  .labels.push @cur
        #|}
      ),
    ),
    (
      #|let cur0 : CardLabel = { text: "", done: false, tags: [] }
      #|let cur0 = { ..cur0, text: "Buy milk" }
      #|let cur0 = { ..cur0, done: true }
      #|let s = { ..s, labels: (s.labels + [cur0]) }
      #|Next(s)
    ),
  )
}

///|
test "a collection method on the target works on the target" {
  assert_eq(
    rows_body(
      (
        #|receive init {
        #|  new Array[String]
        #|  @cur.push 'a'
        #|  .grid.push @cur
        #|}
      ),
    ),
    (
      #|let cur0 : Array[String] = []
      #|let cur0 = (cur0 + ["a"])
      #|let s = { ..s, grid: (s.grid + [cur0]) }
      #|Next(s)
    ),
  )
}

///|
test "a path into the target is a record update, not a spine rebuild" {
  // The write this backend refuses on `.a.b` is emittable here, and for one
  // reason: the target is a local whose type is known at every step.
  assert_eq(
    rows_body("receive init {\n  new Label\n  @cur.tags.push 'x'\n}"),
    (
      #|let cur0 : CardLabel = { text: "", done: false, tags: [] }
      #|let cur0 = { ..cur0, tags: (cur0.tags + ["x"]) }
      #|Next(s)
    ),
  )
}

///|
test "two news in one body do not shadow each other" {
  let src = rows_body(
    (
      #|receive init {
      #|  new Label
      #|  .labels.push @cur
      #|  new Label
      #|  .labels.push @cur
      #|}
    ),
  )
  assert_true(src.contains("let cur0 : CardLabel ="))
  assert_true(src.contains("let cur1 : CardLabel ="))
}

///|
test "the target a branch built does not outlive the branch" {
  // A `let` inside the branch EXPRESSION does not escape it, so a `@cur` below
  // is refused by name rather than emitted as a temporary out of scope.
  assert_eq(
    rows_whys(
      (
        #|receive init {
        #|  if true { new Label } else { stop }
        #|  .labels.push @cur
        #|}
      ),
    ),
    [
      "`@cur` holds what a `new` built, and no `new` is in scope here — one inside a branch does not outlive it",
    ],
  )
}

///|
test "a new of a type the state does not declare says so" {
  assert_eq(rows_whys("receive init { new Widget }"), [
    "`Widget` is not a type the state declares, so there is nothing to build",
  ])
}

///|
test "an index into the target is refused, as one into the state is" {
  assert_eq(rows_whys("receive init {\n  new Label\n  @cur.tags[0] = 'x'\n}"), [
    "writing through an index into `@cur` needs a bounds check this backend does not emit yet — write the handler in MoonBit",
  ])
}

// -- contracts --------------------------------------------------------------

///|
test "a contract compiles into the arm, at the moment it is about" {
  let src = body(
    (
      #|receive bump requires enough ensures small {
      #|  .count += 1
      #|  send 'bumped' .count
      #|}
      #|pred enough { .count > 0 }
      #|pred small { .count < 10 }
    ),
  )
  // The precondition reads the state the arm arrived with, the postcondition
  // the successor — and both are `s`, because every write rebinds it. Nothing
  // else had to be arranged for that: the two checks are simply written at the
  // two points where `s` already means the right thing.
  inspect(
    src,
    content=(
      #|guard (s.count.to_double() > 0.0) else {
      #|@tutuca.precondition_failed(handler="bump", pred="enough", state=(Map(@component.Fields::encode(s)) : @tutuca.Value))
      #|return Unchanged
      #|}
      #|let effects : Array[() -> Unit] = []
      #|let s = { ..s, count: (s.count.to_double() + 1.0).to_int() }
      #|effects.push(() => ctx.send("bumped", [(Num(s.count.to_double()) : @tutuca.Value)]))
      #|guard (s.count.to_double() < 10.0) else {
      #|@tutuca.postcondition_failed(handler="bump", pred="small", state=(Map(@component.Fields::encode(s)) : @tutuca.Value))
      #|return Unchanged
      #|}
      #|for f in effects {
      #|f()
      #|}
      #|Next(s)
    ),
  )
}

///|
test "an invariant is written into every arm the block declares" {
  let e = out(
    (
      #|receive bump { .count += 1 }
      #|receive tag(t) { .label = t }
      #|invariant sane { .count >= 0 }
    ),
  )
  // Two arms, two checks, one rule. The `guard` is what makes it after-only:
  // an invariant that held before the body ran held because the transition
  // before this one was made to keep it.
  assert_eq(
    e.source.split("@tutuca.invariant_failed(handler=").collect().length() - 1,
    2,
  )
  // Each one carries the state it rejected — the successor, encoded only here,
  // inside the refusal, and never on the path where the rule holds.
  assert_true(
    e.source.contains(
      "@tutuca.invariant_failed(handler=\"bump\", pred=\"sane\", state=(Map(@component.Fields::encode(s)) : @tutuca.Value))",
    ),
  )
  assert_true(
    e.source.contains(
      "@tutuca.invariant_failed(handler=\"tag\", pred=\"sane\", state=(Map(@component.Fields::encode(s)) : @tutuca.Value))",
    ),
  )
  assert_eq(e.refusals.map(r => r.name), [])
}

///|
test "an invariant is a pred with a role, and compiles as one too" {
  // The badge in a view and the guard in an arm read the SAME declaration, so
  // a card whose badge is green and whose handler was refused is not a state
  // the two can be in.
  let e = out_values(
    (
      #|receive bump { .count += 1 }
      #|invariant sane { .count >= 0 }
    ),
    methods=["sane"],
  )
  assert_eq(e.answers_methods, ["sane"])
  assert_true(e.source.contains("fn counter_compute_sane("))
}

///|
test "a contract naming a rule the block does not declare refuses its arm" {
  // Not a silently-dropped check: the arm is refused, with the reason the
  // author reads. A generated file that quietly kept the handler and dropped
  // its guarantee is the outcome worth refusing over.
  assert_eq(whys("receive bump requires enough { .count += 1 }"), [
    "`enough` is not a `pred` this block declares, so there is no rule to check",
  ])
}

///|
test "a rule's format is compiled into the refusal, beside the rule" {
  let src = body(
    (
      #|receive bump requires enough {
      #|  .count += 1
      #|}
      #|pred enough
      #|  format $'{.label} is out of counts'
      #|{ .count > 0 }
    ),
  )
  // The sentence is compiled where the rule is, so it reads the state at the
  // moment the rule was asked — and it is built inside the guard's `else`,
  // which is the only path that pays for it.
  inspect(
    src,
    content=(
      #|guard (s.count.to_double() > 0.0) else {
      #|@tutuca.precondition_failed(handler="bump", pred="enough", sentence=((Str(s.label) : @tutuca.Value).to_display_string() + " is out of counts"), state=(Map(@component.Fields::encode(s)) : @tutuca.Value))
      #|return Unchanged
      #|}
      #|let s = { ..s, count: (s.count.to_double() + 1.0).to_int() }
      #|Next(s)
    ),
  )
}

///|
test "a sentence that would need a guard is dropped, and the record stands" {
  // A guard stands in FRONT of the condition and leaves the arm when it does
  // not hold, so a sentence that needed one would decide whether the transition
  // happens. `.blob` is `Any`, and reading it as text is exactly that guard.
  let e = out(
    (
      #|receive bump requires enough {
      #|  .count += 1
      #|}
      #|pred enough format (lower .blob) { .count > 0 }
    ),
  )
  assert_eq(e.refusals.map(r => r.name), [])
  assert_true(
    e.source.contains(
      "@tutuca.precondition_failed(handler=\"bump\", pred=\"enough\", state=",
    ),
  )
  assert_false(e.source.contains("sentence="))
}

// -- the render stack a value body is handed -------------------------------

///|
test "a `*name` in a value body reads the render stack" {
  // The defect this covers: `pred picked { .title is *currentSectionTitle }`
  // was accepted with no refusal and emitted `ctx.lookup(...)` into a function
  // whose parameter list is `(s, args)` — so the generated module did not
  // BUILD. The cause was a category error, not a missing check: `ctx` is a
  // DISPATCH context and there is none while a view is being rendered.
  //
  // `stack.lookup_dynamic` is literally the call `core/value_eval.mbt` makes
  // for a `Val::Dyn` in a slot, so the compiled and the interpreted backends
  // answer one question one way rather than by two tables kept in step.
  let e = out_values(
    "pred picked { .label is *sectionTitle }",
    methods=["picked"],
    whens=["picked"],
  )
  assert_eq(e.refusals.map(r => r.name), [])
  assert_eq(e.answers_methods, ["picked"])
  assert_eq(e.answers_whens, ["picked"])
  assert_true(e.source.contains("stack.lookup_dynamic(\"sectionTitle\")"))
  // The regression proper: no free `ctx` anywhere in a value body.
  assert_false(e.source.contains("ctx.lookup"))
  // Both roles are handed one, and both name it, because they are one body.
  assert_true(
    e.source.contains(
      "fn counter_compute_picked(s : CounterState, _args : Array[@tutuca.Value], stack : &@tutuca.Stack) -> @tutuca.Value",
    ),
  )
  assert_true(
    e.source.contains(
      "fn counter_when_picked(s : CounterState, _key : @tutuca.Value, _value : @tutuca.Value, _iter_data : @tutuca.Value, stack : &@tutuca.Stack) -> Bool",
    ),
  )
}

///|
test "a value body that asks the stack nothing names the parameter `_stack`" {
  // A generated file must not be the thing that warns — the same rule `s`,
  // `args` and the loop's three already follow.
  assert_true(
    out_values("compute two { 2 }", methods=["two"]).source.contains(
      "fn counter_compute_two(_s : CounterState, _args : Array[@tutuca.Value], _stack : &@tutuca.Stack) -> @tutuca.Value",
    ),
  )
}

///|
test "an enricher takes the stack too, in both its shapes" {
  let e = out_values("enrich row { @t = *theme }", enriches=["row"])
  assert_eq(e.refusals.map(r => r.name), [])
  assert_true(
    e.source.contains(
      "binds : Map[String, @tutuca.Value], _key : @tutuca.Value, _value : @tutuca.Value, _iter_data : @tutuca.Value, stack : &@tutuca.Stack) -> Unit",
    ),
  )
  assert_true(
    out_values("enrichScope info { @t = *theme }", enrich_scopes=["info"]).source.contains(
      "fn counter_enrich_scope_info(_s : CounterState, stack : &@tutuca.Stack) -> Map[String, @tutuca.Value]",
    ),
  )
}

///|
test "a transition still reads `*name` through its ctx, and names the parameter" {
  // The half that always worked, pinned so the split above cannot quietly
  // take it with it. A transition IS a dispatch, so `ctx.lookup` — which walks
  // the intent's dyn/lex route from this handler's position — is the right
  // question there.
  // `.blob`, not `.label`: an opaque value at a TYPED field is refused in a
  // transition on a different rule that predates this one, and the point here
  // is the ctx, not that rule.
  let e = out("receive rename(a, b) { .blob = *theme }")
  assert_eq(e.refusals.map(r => r.why), [])
  assert_true(e.source.contains("ctx.lookup(\"theme\""))
  assert_true(e.source.contains("\n  ctx : &@tutuca.Ctx,\n"))
  assert_false(e.source.contains("stack.lookup_dynamic"))
}

///|
test "a sibling call carries the stack, and a transition builds one from its ctx" {
  // One `lookup_dynamic` seam, two producers: the render chain a view is being
  // built on, and the dispatch route a handler is already standing on. A
  // `NullStack` here instead would make `$dark` answer one thing in a `@show`
  // and another in the `receive` beside it, silently.
  let e = out_values(
    (
      #|pred dark { *theme is 'dark' }
      #|compute cls { if dark { 'a' } else { 'b' } }
    ),
    methods=["dark", "cls"],
  )
  assert_true(e.source.contains("counter_compute_dark(s, [], stack)"))
  // The transition side of the same call: it holds a `&Ctx`, so it wears one.
  assert_true(
    out_values(
      (
        #|pred dark { *theme is 'dark' }
        #|receive rename(a, b) { if dark { .count = 1 } }
      ),
      methods=["dark"],
    ).source.contains("counter_compute_dark(s, [], @tutuca.CtxStack(ctx))"),
  )
}
