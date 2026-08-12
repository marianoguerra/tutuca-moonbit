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
    #|}
    #|receive Counter { ResetTo(Int), Rename(String, Int) }
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
      "tag": [Some(TText)],
      "flip": [Some(TText)],
      "dropAt": [Some(TInt(width=32, signed=true))],
      "show": [Some(TText)],
    },
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
test "an assignment is a copy-on-write rebinding of `s`" {
  // Rebinding rather than accumulating one struct literal is what lets a later
  // statement read what an earlier one wrote — the same thing a hand-written
  // arm does, spelled the same way.
  inspect(
    body("on setLabel { .label = 'hi' }"),
    content=(
      #|let s = { ..s, label: "hi" }
      #|Next(s)
    ),
  )
}

///|
test "arithmetic goes through Double and comes back at the field's type" {
  // The rule that makes this backend agree with the interpreter without either
  // consulting the other: `Value` has ONE number, so an expression that rounds
  // at the boundary here rounds where the interpreter rounds too.
  inspect(
    body("on bump { .count += 1 }"),
    content=(
      #|let s = { ..s, count: (s.count.to_double() + 1.0).to_int() }
      #|Next(s)
    ),
  )
  // …and a Double field needs no conversion at all.
  inspect(
    body("on scale { .ratio += 0.5 }"),
    content=(
      #|let s = { ..s, ratio: (s.ratio + 0.5) }
      #|Next(s)
    ),
  )
}

///|
test "a receive handler's parameters are typed by the schema's payload" {
  inspect(
    body("receive resetTo(n) { .count = n }"),
    content=(
      #|guard args.get(0) is Some(Num(n)) else { return Unchanged }
      #|let s = { ..s, count: n.to_int() }
      #|Next(s)
    ),
  )
  // Two payload values, two guards, each at its own type.
  inspect(
    body("receive rename(t, n) { .label = t; .count = n }"),
    content=(
      #|guard args.get(0) is Some(Str(t)) else { return Unchanged }
      #|guard args.get(1) is Some(Num(n)) else { return Unchanged }
      #|let s = { ..s, label: t }
      #|let s = { ..s, count: n.to_int() }
      #|Next(s)
    ),
  )
}

///|
test "a list method answers a fresh array, never a mutation of the receiver" {
  // The previous state is still on the transactor's stack, so writing through
  // `s.history` would edit a value someone else is holding.
  inspect(
    body("on add1 { .history.push 1 }"),
    content=(
      #|let s = { ..s, history: (s.history + [1]) }
      #|Next(s)
    ),
  )
  // An index out of range is `Unchanged`, not a crash. A MoonBit slice
  // ABORTS past the end where the interpreter answers "no change", and this is
  // the whole reason both backends are held to one corpus.
  inspect(
    body("on dropAt(i) { .history.removeAt i }"),
    content=(
      #|guard args.get(0) is Some(Num(i)) else { return Unchanged }
      #|let at = i.to_int()
      #|guard at >= 0 && at < s.history.length() else { return Unchanged }
      #|let s = { ..s, history: (s.history[0:at].to_owned() + s.history[at + 1:].to_owned()) }
      #|Next(s)
    ),
  )
}

///|
test "a set is Map-backed and copied before it is written" {
  inspect(
    body("on tag(t) { .tags.add t }"),
    content=(
      #|guard args.get(0) is Some(Str(t)) else { return Unchanged }
      #|let s = { ..s, tags: { let m = s.tags.copy(); m[t] = true; m } }
      #|Next(s)
    ),
  )
  // Toggle reads before it writes, which is why it needs the binding.
  inspect(
    body("on flip(t) { .tags.toggle t }"),
    content=(
      #|guard args.get(0) is Some(Str(t)) else { return Unchanged }
      #|let s = { ..s, tags: { let m = s.tags.copy(); let k = t; if m.get(k) is Some(true) { m.remove(k) } else { m[k] = true }; m } }
      #|Next(s)
    ),
  )
  // A closed set takes the same three, because the two share one runtime shape.
  assert_eq(whys("on show(v) { .vis.add v }"), [])
}

///|
test "an if rebinds `s` through an expression, not two statement blocks" {
  // A `let` inside a braced statement would not escape it, so both branches
  // have to ANSWER the state.
  inspect(
    body("on maybe { if .ok { .count += 1 } else { .count = 0 } }"),
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
      #|on bump { .count += 1 }
      #|on reset { .count = 0 }
      #|receive resetTo(n) { .count = n }
    ),
  )
  assert_eq(e.answers_input, ["bump", "reset"])
  assert_eq(e.answers_receive, ["resetTo"])
  assert_eq(e.answers_bubble, [])
  assert_eq(e.answers_response, [])
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
  let w = whys("on deep(i) { .history[0] = i }")
  assert_eq(w.length(), 1)
  assert_true(w[0].contains("spine rebuild"))
  assert_true(w[0].contains("write the handler in MoonBit"))
}

///|
test "a method the field's type does not have names the type" {
  let w = whys("on nope { .count.push 1 }")
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
      #|on bump { .count += 1 }
      #|on deep(i) { .history[0] = i }
      #|on reset { .count = 0 }
    ),
  )
  assert_eq(e.answers_input, ["bump", "reset"])
  assert_eq(e.refusals.map(r => r.name), ["deep"])
  assert_true(e.source.contains("Input(\"bump\", _args)"))
  assert_true(e.source.contains("Input(\"reset\", _args)"))
  assert_false(e.source.contains("Input(\"deep\", "))
}

///|
test "a refusal carries the declaration's span, not the block's" {
  let e = out("on bump { .count += 1 }\non deep(i) { .history[0] = i }")
  assert_eq(e.refusals.length(), 1)
  // The second declaration starts after the first, which is the only thing
  // that makes the span useful for pointing at a line.
  assert_true(e.refusals[0].span.start > 20)
}
