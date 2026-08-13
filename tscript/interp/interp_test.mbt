// The interpreter's semantics.
//
// This is the FIRST of three backends over one AST — the MoonBit emitter and,
// later, wasm-gc are the others — so what is asserted here is not "the
// interpreter works" but "the language means this". A case that only the
// interpreter passes is a case the other backends will disagree with, and the
// disagreement will show up as a component that behaves differently depending
// on how it was built.
//
// Which is why the shape is a table: a block, a starting state, a dispatch,
// and the state it lands in. `conformance_test.mbt` beside this file is the
// corpus proper; this file covers the pieces individually.

///|
fn decls_of(block : String) -> Map[String, @tscript.Decl] raise {
  let out : Map[String, @tscript.Decl] = Map([])
  for d in @tscript.parse_script(block) {
    out[d.name] = d
  }
  out
}

///|
/// Run the one declaration a block holds, against a state, with arguments.
fn run_one(
  block : String,
  state : Map[String, @tutuca.Value],
  args? : Array[@tutuca.Value] = [],
) -> @interp.Outcome raise {
  let all = @tscript.parse_script(block)
  let callables : Map[String, @tscript.Decl] = Map([])
  for d in all {
    if d.kind is (DPred | DCompute | DInvariant) {
      callables[d.name] = d
    }
  }
  @interp.dispatch(all[0], args, @interp.Env::of_state(state, callables~))
}

///|
/// The successor state, or None when the body did not finish.
fn after(
  block : String,
  state : Map[String, @tutuca.Value],
  args? : Array[@tutuca.Value] = [],
) -> Map[String, @tutuca.Value]? raise {
  run_one(block, state, args~).state
}

///|
/// Evaluate one expression body against a state.
fn value_of(
  block : String,
  state : Map[String, @tutuca.Value],
) -> @tutuca.Value? raise {
  let all = @tscript.parse_script(block)
  let callables : Map[String, @tscript.Decl] = Map([])
  for d in all {
    if d.kind is (DPred | DCompute | DInvariant) {
      callables[d.name] = d
    }
  }
  @interp.call(all[0], @interp.Env::of_state(state, callables~))
}

// -- assignment -------------------------------------------------------------

///|
test "assignment, compound assignment, and a parameter" {
  let s : Map[String, @tutuca.Value] = { "count": Num(3), "name": Str("x") }
  assert_eq(
    after("on add(d) { .count += d }", s, args=[Num(2)]),
    Some({ "count": Num(5), "name": Str("x") }),
  )
  assert_eq(
    after("on dec { .count -= 1 }", s),
    Some({ "count": Num(2), "name": Str("x") }),
  )
  assert_eq(
    after("on set(v) { .name = v }", s, args=[Str("y")]),
    Some({ "count": Num(3), "name": Str("y") }),
  )
  // The caller's map is untouched whatever a body does.
  assert_eq(s.get("count"), Some(Num(3)))
}

///|
test "the counter that every example in the corpus hand-writes" {
  // `Some(Inc) => Some({ count: s.count + 1 })`, which is written out again in
  // each example, each demo and each playground page. This is the whole
  // argument for the language in four lines.
  let s : Map[String, @tutuca.Value] = { "count": Num(0), "history": List([]) }
  assert_eq(
    after("on add(d) {\n  .count += d\n  .history.push .count\n}", s, args=[
      Num(1),
    ]),
    Some({ "count": Num(1), "history": List([Num(1)]) }),
  )
}

///|
test "a nested write rebuilds the spine, guards included" {
  // `ns_toggle_label` in full — the key's shape and the bounds check are what
  // "failure is no change" already promises, so neither is written.
  let s : Map[String, @tutuca.Value] = {
    "labels": List([
      Map({ "text": Str("a"), "done": Bool(false) }),
      Map({ "text": Str("b"), "done": Bool(false) }),
    ]),
  }
  let block = "on toggleLabel(key) { .labels[key].done = not .labels[key].done }"
  assert_eq(
    after(block, s, args=[Num(1)]),
    Some({
      "labels": List([
        Map({ "text": Str("a"), "done": Bool(false) }),
        Map({ "text": Str("b"), "done": Bool(true) }),
      ]),
    }),
  )
  // Past the end is no change at all — not a grown list, and not a partial
  // write of the fields above it.
  assert_eq(after(block, s, args=[Num(7)]), None)
  // A key of the wrong shape, likewise.
  assert_eq(after(block, s, args=[Map(Map([]))]), None)
}

// -- failure is no change ---------------------------------------------------

///|
test "a body that cannot finish changes nothing and sends nothing" {
  let s : Map[String, @tutuca.Value] = { "count": Num(1), "items": List([]) }
  // The `send` is reached first and the bad index second; the effect goes
  // with the state, because half a transition is the one outcome nobody can
  // reason about afterwards.
  let o = run_one("on x {\n  send 'flash' 'hi'\n  .count = .items[3]\n}", s)
  assert_eq(o.state, None)
  assert_eq(o.effects, [])
}

///|
test "division by zero, a mixed pair, and a name that does not resolve" {
  let s : Map[String, @tutuca.Value] = { "n": Num(1), "s": Str("x") }
  assert_eq(after("on x { .n = .n / 0 }", s), None)
  assert_eq(after("on x { .n = .n + .s }", s), None)
  assert_eq(after("on x { .n = nope }", s), None)
  assert_eq(after("on x { .n = .n mod 0 }", s), None)
}

// -- expressions ------------------------------------------------------------

///|
test "the operator families" {
  let s : Map[String, @tutuca.Value] = {
    "a": Num(6),
    "b": Num(4),
    "t": Str("hi"),
    "ok": Bool(true),
    "off": Bool(false),
  }
  assert_eq(value_of("compute v { .a + .b }", s), Some(Num(10)))
  assert_eq(value_of("compute v { .a - .b }", s), Some(Num(2)))
  assert_eq(value_of("compute v { .a * .b }", s), Some(Num(24)))
  assert_eq(value_of("compute v { .a / .b }", s), Some(Num(1.5)))
  assert_eq(value_of("compute v { .a mod .b }", s), Some(Num(2)))
  assert_eq(value_of("compute v { .t + '!' }", s), Some(Str("hi!")))
  assert_eq(value_of("compute v { .a > .b }", s), Some(Bool(true)))
  assert_eq(value_of("compute v { .a is 6 }", s), Some(Bool(true)))
  assert_eq(value_of("compute v { .a is not 6 }", s), Some(Bool(false)))
  assert_eq(value_of("compute v { .ok and .off }", s), Some(Bool(false)))
  assert_eq(value_of("compute v { .ok or .off }", s), Some(Bool(true)))
  assert_eq(value_of("compute v { not .ok }", s), Some(Bool(false)))
  assert_eq(value_of("compute v { -.a }", s), Some(Num(-6)))
}

///|
test "and, or and implies short-circuit" {
  // Which is what keeps `(not .busy) and (.n > 0)` from evaluating the second
  // half once the first has decided — and what makes an implication over a
  // field that is not there safe to write.
  let s : Map[String, @tutuca.Value] = { "off": Bool(false), "on": Bool(true) }
  // The right-hand side would fail on its own…
  assert_eq(value_of("compute v { .missing[9] }", s), None)
  // …and is never reached.
  assert_eq(
    value_of("compute v { .off and .missing[9] }", s),
    Some(Bool(false)),
  )
  assert_eq(value_of("compute v { .on or .missing[9] }", s), Some(Bool(true)))
  assert_eq(
    value_of("compute v { .off implies .missing[9] }", s),
    Some(Bool(true)),
  )
}

///|
test "a chain evaluates left to right" {
  let s : Map[String, @tutuca.Value] = { "a": Num(10) }
  assert_eq(value_of("compute v { .a - 3 - 2 }", s), Some(Num(5)))
}

///|
test "if in a value position, and a string template" {
  let s : Map[String, @tutuca.Value] = { "ok": Bool(true), "n": Num(3) }
  assert_eq(
    value_of("compute v { if .ok { 'good' } else { 'bad' } }", s),
    Some(Str("good")),
  )
  assert_eq(value_of("compute v { $'n={.n}' }", s), Some(Str("n=3")))
}

///|
test "an if statement takes the branch, and an absent else changes nothing" {
  let s : Map[String, @tutuca.Value] = { "ok": Bool(false), "n": Num(0) }
  assert_eq(
    after("on x { if .ok { .n = 1 } else { .n = 2 } }", s),
    Some({ "ok": Bool(false), "n": Num(2) }),
  )
  assert_eq(
    after("on x { if .ok { .n = 1 } }", s),
    Some({ "ok": Bool(false), "n": Num(0) }),
  )
}

// -- the vocabulary ---------------------------------------------------------

///|
test "the shape predicates come from core's table, so they mean one thing" {
  let s : Map[String, @tutuca.Value] = {
    "empty": List([]),
    "full": List([Num(1)]),
    "blank": Str(""),
    "nil": Null,
  }
  assert_eq(value_of("pred p { empty? .empty }", s), Some(Bool(true)))
  assert_eq(value_of("pred p { empty? .full }", s), Some(Bool(false)))
  // `truthy?` treats an empty collection as falsy, and plain truthiness does
  // not. The difference is deliberate and is why both exist.
  assert_eq(value_of("pred p { truthy? .empty }", s), Some(Bool(false)))
  assert_eq(value_of("pred p { falsy? .blank }", s), Some(Bool(true)))
  assert_eq(value_of("pred p { null? .nil }", s), Some(Bool(true)))
}

///|
test "the reading builtins" {
  let s : Map[String, @tutuca.Value] = {
    "items": List([Num(1), Num(2), Num(3)]),
    "name": Str("  Ada Lovelace  "),
    "tags": Map({ "urgent": Bool(true) }),
    "n": Num(7),
  }
  assert_eq(value_of("compute v { len .items }", s), Some(Num(3)))
  assert_eq(value_of("compute v { min .n 3 }", s), Some(Num(3)))
  assert_eq(value_of("compute v { max .n 3 }", s), Some(Num(7)))
  assert_eq(value_of("compute v { clamp .n 0 5 }", s), Some(Num(5)))
  assert_eq(value_of("compute v { clamp .n 0 9 }", s), Some(Num(7)))
  assert_eq(value_of("compute v { int 2.7 }", s), Some(Num(2)))
  assert_eq(value_of("compute v { num '2.5' }", s), Some(Num(2.5)))
  assert_eq(value_of("compute v { str .n }", s), Some(Str("7")))
  assert_eq(value_of("compute v { trim .name }", s), Some(Str("Ada Lovelace")))
  assert_eq(
    value_of("compute v { lower (trim .name) }", s),
    Some(Str("ada lovelace")),
  )
  assert_eq(value_of("compute v { contains .name 'Ada' }", s), Some(Bool(true)))
  assert_eq(value_of("compute v { has .tags 'urgent' }", s), Some(Bool(true)))
  assert_eq(value_of("compute v { has .tags 'calm' }", s), Some(Bool(false)))
}

///|
test "clamp answers lo when the range is empty" {
  // The 42-call-site `prev`/`next` builtin, over a list that is empty: `hi` is
  // -1 and the honest answer is `lo`, not a negative index.
  let s : Map[String, @tutuca.Value] = { "page": Num(0) }
  assert_eq(value_of("compute v { clamp .page 0 (0 - 1) }", s), Some(Num(0)))
}

///|
test "a declared predicate is applied exactly like a builtin" {
  let s : Map[String, @tutuca.Value] = {
    "title": Str(""),
    "published": Bool(true),
  }
  let block =
    #|pred nonBlank(t) { (trim t) is not '' }
    #|pred publishedNeedsTitle { .published implies (nonBlank .title) }
  let decls = decls_of(block)
  let env = @interp.Env::of_state(s, callables=decls)
  guard! decls.get("publishedNeedsTitle") is Some(d)
  assert_eq(@interp.call(d, env), Some(Bool(false)))
  // …and with a title, it holds.
  let ok = @interp.Env::of_state(
    { "title": Str("Notes"), "published": Bool(true) },
    callables=decls,
  )
  assert_eq(@interp.call(d, ok), Some(Bool(true)))
}

// -- collection methods -----------------------------------------------------

///|
test "the collection methods do what their mutators do" {
  let s : Map[String, @tutuca.Value] = {
    "xs": List([Str("a"), Str("b")]),
    "tags": Map({ "x": Bool(true) }),
  }
  assert_eq(
    after("on x { .xs.push 'c' }", s).unwrap().get("xs"),
    Some(List([Str("a"), Str("b"), Str("c")])),
  )
  assert_eq(
    after("on x { .xs.insertAt 0 'z' }", s).unwrap().get("xs"),
    Some(List([Str("z"), Str("a"), Str("b")])),
  )
  assert_eq(
    after("on x { .xs.setAt 1 'B' }", s).unwrap().get("xs"),
    Some(List([Str("a"), Str("B")])),
  )
  assert_eq(
    after("on x { .xs.deleteAt 0 }", s).unwrap().get("xs"),
    Some(List([Str("b")])),
  )
  assert_eq(
    after("on x { .tags.add 'y' }", s).unwrap().get("tags"),
    Some(Map({ "x": Bool(true), "y": Bool(true) })),
  )
  assert_eq(
    after("on x { .tags.remove 'x' }", s).unwrap().get("tags"),
    Some(Map(Map([]))),
  )
  assert_eq(
    after("on x { .tags.toggle 'x' }", s).unwrap().get("tags"),
    Some(Map(Map([]))),
  )
  assert_eq(
    after("on x { .tags.toggle 'y' }", s).unwrap().get("tags"),
    Some(Map({ "x": Bool(true), "y": Bool(true) })),
  )
  // Deleting what is not there refuses, exactly as `deleteInXAt` does.
  assert_eq(after("on x { .xs.deleteAt 9 }", s), None)
}

// -- effects ----------------------------------------------------------------

///|
test "the effects are collected in order, with the state" {
  let s : Map[String, @tutuca.Value] = {
    "msg": Str("hi"),
    "loading": Bool(false),
  }
  let o = run_one(
    "on go {\n  request 'loadData'\n  .loading = true\n  send 'flash' .msg\n  stop\n}",
    s,
  )
  assert_eq(o.state, Some({ "msg": Str("hi"), "loading": Bool(true) }))
  assert_eq(o.effects, [
    ERequest(name="loadData", args=[]),
    ESend(name="flash", args=[Str("hi")]),
    EStop,
  ])
}

///|
test "a request carries its arguments, the way the compiled backend emits them" {
  // `emit_mbt` writes `ctx.request(name, [payload], RequestOpts::new())`, and
  // a `RequestFn` has no component instance to read state from — arguments
  // are the only channel a request has. Dropping them here made the two
  // backends of one language disagree about it.
  let s : Map[String, @tutuca.Value] = { "draft": Str("hi"), "id": Num(7) }
  let o = run_one("on save {\n  request 'persist' .id (trim .draft)\n}", s)
  assert_eq(o.effects, [ERequest(name="persist", args=[Num(7), Str("hi")])])
}

///|
test "a place reifies a position, and when the key resolves is the point" {
  let s : Map[String, @tutuca.Value] = {
    "status": Str("ok"),
    "rows": List([Str("a"), Str("b")]),
    "selId": Str("k"),
    "sheets": Map({ "k": Str("s") }),
  }
  // A plain field.
  assert_eq(run_one("on x { sendAt &.status 'flash' 'Saved' }", s).effects, [
    ESendAt(steps=[FieldStep("status")], name="flash", args=[Str("Saved")]),
  ])
  // A literal key, frozen now.
  assert_eq(run_one("on x { sendAt &.rows[1] 'select' }", s).effects, [
    ESendAt(steps=[SeqStep(field="rows", key=KInt(1))], name="select", args=[]),
  ])
  // A parameter key, frozen from the value in hand.
  assert_eq(
    run_one("on x(k) { sendAt &.rows[k] 'select' }", s, args=[Num(0)]).effects,
    [
      ESendAt(steps=[SeqStep(field="rows", key=KInt(0))], name="select", args=[]),
    ],
  )
  // A key that names a live STATE FIELD stays a reference, so it is re-read on
  // every dispatch and pinned at request time. This is the only one of the
  // three that can follow a moving selection, and the only one that can race.
  assert_eq(run_one("on x { sendAt &.sheets[.selId] 'select' }", s).effects, [
    ESendAt(
      steps=[SeqAccessStep(seq_field="sheets", key_field="selId")],
      name="select",
      args=[],
    ),
  ])
  // A deeper path keeps the field-then-key shape a `Path` step has.
  assert_eq(run_one("on x { sendAt &.rows[0].note 'select' }", s).effects, [
    ESendAt(
      steps=[SeqStep(field="rows", key=KInt(0)), FieldStep("note")],
      name="select",
      args=[],
    ),
  ])
}

// -- new, and the target ----------------------------------------------------

///|
/// Run one declaration with a `tutuca/state` block behind it, which is what a
/// `new` needs: the block parses the type's NAME, and only a schema can say
/// what it is.
fn after_typed(
  schema : String,
  block : String,
  state : Map[String, @tutuca.Value],
  args? : Array[@tutuca.Value] = [],
) -> @interp.Outcome raise {
  let def = @statedef.parse_state(schema)[0]
  let all = @tscript.parse_script(block)
  let env = @interp.Env::of_state(state, schema=@info.schema_info(def), zero=t => {
    @info.zero_of_ref(def, t)
  })
  @interp.dispatch(all[0], args, env)
}

///|
const ROWS_SCHEMA : String =
  #|struct Label { text : String, done : Bool }
  #|state Card { labels : Array[Label], grid : Array[Array[String]] }
  #|receive Card { Init }

///|
test "a record is built into the target and pushed" {
  // The gap this closes: an `Array[Label]` could be READ into and written
  // through, but never appended to, because a record had no spelling.
  let s : Map[String, @tutuca.Value] = { "labels": List([]), "grid": List([]) }
  assert_eq(
    after_typed(
      ROWS_SCHEMA,
      (
        #|receive init {
        #|  new Label
        #|  @cur.text = 'Buy milk'
        #|  @cur.done = true
        #|  .labels.push @cur
        #|}
      ),
      s,
    ).state,
    Some({
      "labels": List([Map({ "text": Str("Buy milk"), "done": Bool(true) })]),
      "grid": List([]),
    }),
  )
}

///|
test "a fresh list is built into the target and pushed" {
  let s : Map[String, @tutuca.Value] = { "labels": List([]), "grid": List([]) }
  assert_eq(
    after_typed(
      ROWS_SCHEMA,
      (
        #|receive init {
        #|  new Array[String]
        #|  @cur.push 'a'
        #|  @cur.push 'b'
        #|  .grid.push @cur
        #|}
      ),
      s,
    ).state,
    Some({ "labels": List([]), "grid": List([List([Str("a"), Str("b")])]) }),
  )
}

///|
test "a new resets the target, and two of them do not alias" {
  // The zero is handed out rather than copied, which is only safe because
  // every write below is copy-on-write. Two rows built from one zero proves
  // it: if they aliased, both would read 'second'.
  let s : Map[String, @tutuca.Value] = { "labels": List([]), "grid": List([]) }
  assert_eq(
    after_typed(
      ROWS_SCHEMA,
      (
        #|receive init {
        #|  new Label
        #|  @cur.text = 'first'
        #|  .labels.push @cur
        #|  new Label
        #|  @cur.text = 'second'
        #|  .labels.push @cur
        #|}
      ),
      s,
    ).state,
    Some({
      "labels": List([
        Map({ "text": Str("first"), "done": Bool(false) }),
        Map({ "text": Str("second"), "done": Bool(false) }),
      ]),
      "grid": List([]),
    }),
  )
}

///|
test "the target does not exist until a new makes one" {
  let s : Map[String, @tutuca.Value] = { "labels": List([]), "grid": List([]) }
  // Reading it, and writing through it, are both the transition not happening
  // rather than a Null landing in the state.
  assert_eq(
    after_typed(ROWS_SCHEMA, "receive init { .labels.push @cur }", s).state,
    None,
  )
  assert_eq(
    after_typed(ROWS_SCHEMA, "receive init { @cur.text = 'x' }", s).state,
    None,
  )
}

///|
test "a new with no resolver behind it is a transition that does not happen" {
  // A card with no state block cannot name a type, so it cannot build one.
  let all = @tscript.parse_script("receive init { new Label }")
  let env = @interp.Env::of_state({ "labels": List([]) })
  assert_eq(@interp.dispatch(all[0], [], env).state, None)
}

///|
test "the target never leaves the body that built it" {
  // An `enrich`'s binds become a VIEW's scope — `@name` in a template, replayed
  // on every rebuild. The target is a workbench, so it is withheld on the way
  // out; and a `@cur` handed IN is dropped on the way in, so a body cannot
  // read one it did not build.
  let def = @statedef.parse_state(ROWS_SCHEMA)[0]
  let all = @tscript.parse_script(
    (
      #|enrich row {
      #|  new Label
      #|  @cur.text = 'workbench'
      #|  @tag = 'published'
      #|}
    ),
  )
  let env : @interp.Env = {
    ..@interp.Env::of_state({ "labels": List([]) }, zero=t => {
      @info.zero_of_ref(def, t)
    }),
    binds: { "cur": Str("handed in"), "key": Num(0) },
  }
  guard all[0].body is Stmts(ss) else { fail("an enrich holds statements") }
  let out = @interp.run(ss, env)
  // What the renderer would publish: the enrich's own binding and the loop's,
  // and no target.
  assert_eq(out.binds, { "tag": Str("published"), "key": Num(0) })
}

// -- the schema's one job ---------------------------------------------------

///|
test "an integer field truncates on the way in" {
  // The one thing the declared schema is consulted for. `Value` has a single
  // `Num(Double)`, so nothing else about width is knowable here — but storing
  // 2.5 in a field the type says is an s32 would leave a value the generated
  // codec's decode would have refused.
  let schema = @tutuca.SchemaInfo::new(fingerprint="x", fields=[
    @tutuca.FieldInfo::new("count", TyInt),
    @tutuca.FieldInfo::new("ratio", TyFloat),
  ])
  let all = @tscript.parse_script("on x { .count = 2.7\n  .ratio = 2.7 }")
  let env = @interp.Env::of_state({ "count": Num(0), "ratio": Num(0) }, schema~)
  let o = @interp.dispatch(all[0], [], env)
  assert_eq(o.state, Some({ "count": Num(2), "ratio": Num(2.7) }))
}

///|
test "with no schema in hand, nothing is coerced" {
  // A card with no state block is legal, and inventing a type for its fields
  // would be the checker guessing — which is the thing "unknown is not wrong"
  // exists to stop.
  let all = @tscript.parse_script("on x { .count = 2.7 }")
  let env = @interp.Env::of_state({ "count": Num(0) })
  assert_eq(
    @interp.dispatch(all[0], [], env).state,
    Some({ "count": Num(2.7) }),
  )
}

///|
test "the escapes a string literal carries, and the two case folds" {
  let s : Map[String, @tutuca.Value] = { "name": Str("Ada Lovelace") }
  // `\n`, `\t` and `\r` join `\'` and `\\`, so a seed can stay on one line.
  assert_eq(value_of("compute v { 'a\\nb' }", s), Some(Str("a\nb")))
  assert_eq(value_of("compute v { 'a\\tb' }", s), Some(Str("a\tb")))
  assert_eq(value_of("compute v { 'it\\'s' }", s), Some(Str("it's")))
  // …and a literal may still span lines as itself, which is what a markdown
  // seed wants. Both spellings mean the same string.
  assert_eq(value_of("compute v { 'a\nb' }", s), Some(Str("a\nb")))
  // A backslash before anything else stays literal, as it always has.
  assert_eq(value_of("compute v { 'a\\qb' }", s), Some(Str("a\\qb")))
  // `upper` beside `lower`: one case fold each way, and the same guard.
  assert_eq(value_of("compute v { upper .name }", s), Some(Str("ADA LOVELACE")))
  assert_eq(value_of("compute v { lower .name }", s), Some(Str("ada lovelace")))
  assert_eq(value_of("compute v { upper 3 }", s), None)
}

// -- contracts --------------------------------------------------------------

///|
/// Run a block and answer both halves: what the transition did, and what it
/// REPORTED. The two are one answer here — a contract that abandons a
/// transition and says nothing would be indistinguishable from a body that had
/// nothing to do, which is the failure the report exists to end.
fn contracted(
  block : String,
  state : Map[String, @tutuca.Value],
  args? : Array[@tutuca.Value] = [],
) -> (Map[String, @tutuca.Value]?, Array[String]) raise {
  let said : Array[String] = []
  let before = @tutuca.warn_hook.val
  @tutuca.warn_hook.val = msg => said.push(msg)
  let out = run_one(block, state, args~)
  @tutuca.warn_hook.val = before
  (out.state, said)
}

///|
test "a precondition declines the transition, and the decline has a name" {
  let block =
    #|on push requires canPush {
    #|  .here -= 1
    #|  .there += 1
    #|}
    #|pred canPush { .here > 0 }
  let (moved, quiet) = contracted(block, { "here": Num(2), "there": Num(0) })
  assert_eq(moved, Some({ "here": Num(1), "there": Num(1) }))
  assert_eq(quiet, [])
  // Nothing has moved yet when the rule is asked, so there is nothing to undo
  // — and the state that comes back is the one that went in.
  let (still, said) = contracted(block, { "here": Num(0), "there": Num(2) })
  assert_eq(still, None)
  assert_eq(said, [
    "contract: `push` declined — its precondition `canPush` does not hold",
  ])
}

///|
test "a postcondition abandons the whole transition, effects included" {
  let block =
    #|on push ensures moved {
    #|  .there += 1
    #|  send 'moved' .there
    #|}
    #|pred moved { .here > .there }
  let said : Array[String] = []
  let before = @tutuca.warn_hook.val
  @tutuca.warn_hook.val = msg => said.push(msg)
  let out = run_one(block, { "here": Num(1), "there": Num(3) })
  @tutuca.warn_hook.val = before
  // Half a transition — nothing moved but a `send` went out — is the one
  // outcome nobody can reason about afterwards. The queue is still a queue
  // when the rule is asked, so the effect never leaves.
  assert_eq(out.state, None)
  assert_eq(out.effects.length(), 0)
  assert_eq(said, [
    "contract: `push` was abandoned — its postcondition `moved` does not hold after it",
  ])
}

///|
test "an invariant is asked after every transition the block declares" {
  let block =
    #|on move {
    #|  .here -= 1
    #|  .there += 1
    #|}
    #|on cheat {
    #|  .there += 1
    #|}
    #|invariant conserved { (.here + .there) is .total }
  let start : Map[String, @tutuca.Value] = {
    "here": Num(2),
    "there": Num(0),
    "total": Num(2),
  }
  // The handler that keeps it is not asked to say so.
  let (moved, quiet) = contracted(block, start)
  assert_eq(moved, Some({ "here": Num(1), "there": Num(1), "total": Num(2) }))
  assert_eq(quiet, [])
  // The one that mints a token out of nothing is refused by a rule it never
  // mentions — which is what "the component keeps this" means.
  let all = @tscript.parse_script(block)
  let callables : Map[String, @tscript.Decl] = Map([])
  for d in all {
    if d.kind is (DPred | DCompute | DInvariant) {
      callables[d.name] = d
    }
  }
  let said : Array[String] = []
  let before = @tutuca.warn_hook.val
  @tutuca.warn_hook.val = msg => said.push(msg)
  let out = @interp.dispatch(
    all[1],
    [],
    @interp.Env::of_state(start, callables~),
  )
  @tutuca.warn_hook.val = before
  assert_eq(out.state, None)
  assert_eq(said, [
    "contract: `cheat` was abandoned — it broke the invariant `conserved`",
  ])
}

///|
test "a rule nobody can evaluate has not been kept" {
  // `.missing` is not a field, so the rule answers nothing at all. Letting the
  // transition through would make an unevaluable contract weaker than no
  // contract, which is the one reading that cannot be right.
  let block =
    #|on bump requires ok {
    #|  .count += 1
    #|}
    #|pred ok { .missing.deep > 0 }
  let (state, said) = contracted(block, { "count": Num(1) })
  assert_eq(state, None)
  assert_eq(said.length(), 1)
}
