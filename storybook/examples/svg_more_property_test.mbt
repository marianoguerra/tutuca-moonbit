// `BarChart`, driven by generators derived from its own spec block.
//
// The example suite next door asserts what this component does with the two
// presses somebody wrote down. This asserts what it does with any sequence of
// messages at all — and the messages are not written down anywhere either:
// they are read off `<script type="tutuca/spec">`, the same declaration
// `gen-views` compiled, through `statedef/arb`.
//
// Why THIS component. It is the one in the corpus that declares all three
// kinds of rule — two `pred`s used as preconditions and an `invariant` — and
// every one of their bodies is in the vocabulary `@core.Val` can evaluate. So
// the rules can be read here, in the test, and held against the compiled arms
// `gen-views` emitted from the same source. Two readings of one declaration
// that have to agree is a differential test, and it costs one function call.
//
// The spec source is a constant rather than a read of `svg_more.html`: this
// package checks under wasm-gc, where there is no filesystem, and the point
// being made is about the generators rather than about file plumbing.

///|
/// `BarChart`'s spec block, verbatim from `svg_more.html`.
///
/// Kept in sync by `bar_chart_spec_matches_the_component` below, which holds
/// it against the schema the GENERATED module carries — so this drifting from
/// the file is a test failure rather than a silent divergence.
const BAR_CHART_SPEC : String =
  #|state BarChart {
  #|  values : Array[Any]
  #|
  #|  pred hasRoom
  #|    format $'nine bars is the cap, and there are already {len .values}' { (len .values) < 9 }
  #|
  #|  pred hasSpare
  #|    format 'one bar has to stay, or there is no chart left to look at' { (len .values) > 1 }
  #|
  #|  invariant neverEmpty
  #|    format 'the chart lost its last bar' { (len .values) > 0 }
  #|}

///|
/// Which handler asks which precondition, as the script block writes it.
///
/// The one fact in this file that a spec block does not carry: a `requires`
/// clause sits on the HANDLER's header, in the script block, because it says
/// when that handler applies. `statedef` records the rules and `tscript`
/// records the clauses, and the property below needs both.
fn contracts() -> Array[(String, String)] {
  [("addBar", "hasRoom"), ("removeBar", "hasSpare")]
}

///|
fn bar_chart_def() -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(BAR_CHART_SPEC)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// A fresh chart, or None when it could not be mounted.
///
/// A property body cannot raise — `@qc.forall` takes a plain function — and a
/// mount that fails is a different failure from a property that does not hold,
/// so it is carried as an absence rather than thrown through the harness.
fn fresh_chart() -> @harness.Harness[@memdom.MemNode]? {
  Some(@harness.mount_example(svg_bar_chart_module(), "Default")) catch {
    _ => None
  }
}

///|
/// Everything the runtime refused while one message was delivered.
///
/// The refusal channel is the only place a declined contract is visible: the
/// transition simply does not happen, and "nothing changed" is what a handler
/// with nothing to do looks like too.
fn refused_by(
  h : @harness.Harness[@memdom.MemNode],
  name : String,
) -> Array[@tutuca.Refusal] {
  @harness.refusals_while(() => h.send_at_root(name)) catch {
    _ => []
  }
}

///|
/// The state the component settled at, as the fields map a rule reads.
fn settled(h : @harness.Harness[@memdom.MemNode]) -> Map[String, @tutuca.Value] {
  match h.drive_value() {
    Map(m) => m
    Obj(o) => {
      let out : Map[String, @tutuca.Value] = Map([])
      guard o.obj_schema() is Some(sc) else { return out }
      for f in sc.fields {
        out[f.name] = o.obj_field(f.name).unwrap_or(Null)
      }
      out
    }
    _ => Map([])
  }
}

///|
/// The constant above still describes the component that ships.
///
/// Held against the schema the GENERATED module carries rather than against
/// the file, because that is what the component actually runs on: a field
/// renamed in `svg_more.html` reaches the generated schema through
/// `gen-views`, and this fails the moment the two stop agreeing.
test "the spec constant describes the component the module carries" {
  let def = bar_chart_def()
  let h = @harness.mount_example(svg_bar_chart_module(), "Default")
  guard h.drive_value() is Obj(o) && o.obj_schema() is Some(schema) else {
    fail("a mounted BarChart answers its own schema")
  }
  assert_eq(
    def.fields.map(f => f.name).join(","),
    schema.fields.map(f => f.name).join(","),
  )
  // And the rules, which is the half this file reads: the generated schema
  // lists its invariants by name, and `statedef` found the same ones.
  assert_eq(def.invariants().join(","), schema.invariants.join(","))
  // Every rule the block declares is one `@core.Val` can answer, so nothing
  // below is quietly skipped.
  let rules = @arb.rules_of(def)
  assert_eq(rules.unlowerable.map(u => "\{u.0}: \{u.1}").join("\n"), "")
}

///|
/// The invariant holds after every generated mutator, from every reachable
/// state.
///
/// The property the component was written for, and the one no hand-written
/// scene reaches: `setValues []` is a legal dispatch that nothing in
/// `svg_more.html` can produce — no button sends it, and the two handlers that
/// exist both guard against emptiness — but the runtime installs it for every
/// declared field, so a page, a parent, or a host can. `neverEmpty` is what
/// stands between that and a chart with no bars, and this is what asks whether
/// it does.
test "property: no generated mutator can drive the chart through its invariant" {
  let def = bar_chart_def()
  let rules = @arb.rules_of(def)
  guard @arb.mutator_dispatch_of(def) is Some(one) else {
    fail("BarChart declares a field, so it has generated mutators")
  }
  @qc.quick_check(
    @qc.forall_shrink(
      @gen.int_range(0, 6).bind(n => one.array_with_size(n)),
      @arb.shrink_script,
      script => {
        guard fresh_chart() is Some(h) else { return false }
        for d in script {
          // Every generated mutator is a Receive — a mutator is not routed —
          // so an Intent here would mean the generator invented one.
          guard d is Receive(name, args) else { return false }
          h.send_at_root(name, args~)
          // Read after EVERY step, not once at the end: an invariant that is
          // broken and then repaired by the next message is still broken, and
          // a check at the end would call that a pass.
          if !rules.invariants_hold(settled(h)) {
            return false
          }
        }
        true
      },
    ),
    max_success=200,
  )
}

///|
/// The interpreted precondition predicts the compiled one, dispatch by
/// dispatch.
///
/// This is the differential test, and it is worth being explicit about what
/// the two sides are. On the left, `@tscript.parse_bool` lowers
/// `(len .values) < 9` to a `@core.Val` and `Val::eval` walks it over the
/// state as it stands. On the right is the `guard` `gen-views` compiled from
/// that same line into the generated MoonBit arm, whose verdict reaches here
/// as a `Refusal` with `code: Precondition` and the rule's name on it.
///
/// They agree, or one of them is wrong about the component's own contract. A
/// hand-written test cannot make this claim — it asserts a state it chose,
/// against a rule it read — because the two sides only diverge on the states
/// nobody thought to write down.
test "property: an interpreted precondition predicts the compiled one" {
  let def = bar_chart_def()
  let rules = @arb.rules_of(def)
  let names = contracts().map(c => c.0)
  @qc.quick_check(
    @qc.forall(
      @gen.int_range(0, 6).bind(n => @gen.one_of_array(names).array_with_size(n)),
      script => {
        guard fresh_chart() is Some(h) else { return false }
        for name in script {
          guard contracts().filter(c => c.0 == name)[0] is (_, rule)
          // The rule, asked HERE, against the state as it arrived — which is
          // exactly when a precondition is asked.
          let predicted = rules.holds(rule, settled(h))
          let declined = refused_by(h, name).filter(r => {
            r.code is Precondition && r.rule == rule
          })
          match predicted {
            // The rule held, so the handler must have run and said nothing.
            Some(true) => if !declined.is_empty() { return false }
            // The rule did not hold, so the runtime must have declined by name.
            Some(false) => if declined.length() != 1 { return false }
            // A rule that answers neither is a rule this file should not be
            // making a claim about, and the suite above pins that it cannot
            // happen for this component.
            None => return false
          }
        }
        true
      },
    ),
    max_success=150,
  )
}

///|
/// A refusal carries the rule's own sentence, with the values that made it
/// fail.
///
/// The `format` half, which the property above does not reach: it asserts WHEN
/// a rule declines, and this asserts what the decline SAYS. Driven to the cap
/// by generated mutators rather than by nine button presses, so the sentence
/// is checked against a state the generator found.
test "a declined precondition says the rule's own sentence" {
  let h = @harness.mount_example(svg_bar_chart_module(), "Default")
  // Nine bars, through the mutator rather than the button: `pushInValues` is
  // generated, ungated, and the shortest way to the cap.
  while true {
    let before = h.render_count()
    h.send_at_root("pushInValues", args=[Num(1.0)])
    if h.render_count() == before {
      break
    }
    if settled(h).get("values") is Some(List(vs)) && vs.length() >= 9 {
      break
    }
  }
  let refused = @harness.refusals_while(() => h.send_at_root("addBar"))
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].rule, "hasRoom")
  inspect(
    refused[0].sentence,
    content="nine bars is the cap, and there are already 9",
  )
}
