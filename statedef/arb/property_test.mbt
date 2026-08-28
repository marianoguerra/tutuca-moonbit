// The generators' own properties.
//
// A generator is the one piece of test machinery nothing else tests: a
// property that passes because the generator never produced the interesting
// case looks exactly like a property that passes. So the claims here are about
// the GENERATOR, and every one of them is checked against a table this package
// did not write — `@info.ty_info`, `TyInfo::accepts`, `Value::to_json`, and the
// rules the spec block itself declares.

///|
/// Every scalar the spec block spells, at the widths that are range-checked on
/// decode, plus the three containers and both set kinds.
const SCALARS : String =
  #|state Wide {
  #|  flag   : Bool
  #|  small  : Int8
  #|  ushort : UInt16
  #|  n      : Int
  #|  ratio  : Double
  #|  label  : String
  #|  maybe  : Int?
  #|  pair   : (Int, String)
  #|  many   : Array[Int]
  #|  index  : Map[String, Int]
  #|  open   : Set[String]
  #|  loose  : Any
  #|}

///|
/// The declared shapes: a record, a payload-free enum, a variant that carries
/// one, a closed set over the enum, and a list of records. The four types
/// `ty_info` cannot answer for without consulting the declaration.
const SHAPES : String =
  #|struct Label {
  #|  text : String
  #|  done : Bool
  #|}
  #|
  #|enum Priority {
  #|  Low
  #|  High
  #|}
  #|
  #|enum Due {
  #|  Unscheduled
  #|  OnDay(Int)
  #|}
  #|
  #|state Card {
  #|  title    : String
  #|  labels   : Array[Label]
  #|  priority : Priority
  #|  due      : Due
  #|  seen     : Set[Priority]
  #|  nested   : Array[Array[Int]]
  #|}

///|
/// The rules, in all three arrangements: a plain `pred`, a `pred` that names
/// another one, and an `invariant` correlating three fields. Plus the messages
/// a dispatch is drawn from, with and without a payload.
const LEDGER : String =
  #|state Ledger {
  #|  here  : Int
  #|  there : Int
  #|  total : Int
  #|  busy  : Bool
  #|
  #|  pred canPush { .here > 0 }
  #|  pred idle { not .busy }
  #|  pred canMove { canPush and idle }
  #|
  #|  invariant capped { .here <= .total }
  #|}
  #|
  #|handle Ledger {
  #|  message {
  #|    push
  #|    moveTo(Int)
  #|    label(String, Bool)
  #|  }
  #|  intent {
  #|    settle(Int)
  #|  }
  #|}

///|
/// The one component in a source, or a failure naming what did not parse.
fn one(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// Every fixture, so a property may be quantified over the SCHEMAS as well as
/// over the values — a generator that is right about one declaration and wrong
/// about the next is the failure this catches.
fn fixtures() -> Array[@statedef.StateDef] raise {
  [one(SCALARS), one(SHAPES), one(LEDGER)]
}

///|
/// A schema and a state of it, drawn together. A state generated against one
/// schema and checked against another would pass vacuously.
fn gen_state_of(
  def : @statedef.StateDef,
) -> @gen.Gen[(@statedef.StateDef, Map[String, @tutuca.Value])] {
  @arb.state_of(def).fmap(s => (def, s))
}

///|
/// Every field of a state, against the type its declaration projects to.
fn well_typed(
  def : @statedef.StateDef,
  state : Map[String, @tutuca.Value],
) -> Bool {
  for f in def.fields {
    guard state.get(f.name) is Some(v) else { return false }
    // A slot is the one field whose zero its own type declines: `TyComp::zero`
    // is Null and `TyComp::accepts(Null)` is false, because an empty slot is
    // not an instance. Nothing here can build one, so the field is skipped
    // rather than asserted about — the same answer `@info.zero_of` gives.
    // Two types decline their own zero, and both are declared gaps rather
    // than surprises. A slot's zero is Null because nothing here builds an
    // instance, and a variant's is Null because `TyInfo` keeps only the name
    // and "its zero is its first case, which this cannot name"
    // (`statedef/info/info.mbt`). A GENERATOR has the declaration in hand and
    // so names the case — which is the one place `arb` knows more than `info`
    // — but the zero it is being compared against does not.
    if @info.ty_info(def, f.ty)
      is (TyComp(_) | TyCompProtocols(_) | TyVariant(_)) {
      continue
    }
    guard @info.ty_info(def, f.ty).accepts(v) else { return false }
  }
  true
}

///|
test "property: every generated value inhabits the type it was drawn at" {
  for def in fixtures() {
    @qc.quick_check(
      @qc.forall(gen_state_of(def), p => well_typed(p.0, p.1)),
      max_success=300,
    )
  }
}

///|
test "property: a generated state carries exactly the declared fields" {
  for def in fixtures() {
    @qc.quick_check(
      @qc.forall(gen_state_of(def), p => {
        let (d, s) = p
        guard s.length() == d.fields.length() else { return false }
        for f in d.fields {
          guard s.contains(f.name) else { return false }
        }
        true
      }),
      max_success=100,
    )
  }
}

///|
/// The zero is in the generator's own range.
///
/// Not a property over draws — there is one zero — but it belongs here, beside
/// the table it is checked against. `@info.zero_value` and `state_of` walk the
/// same `StateTy` tree, so a type either package gets wrong shows up as the
/// zero failing the check every draw passes.
test "the zero state is well-typed by the same table the generator is" {
  for def in fixtures() {
    assert_true(well_typed(def, @info.zero_value(def)))
  }
}

///|
test "property: a generated state round-trips through JSON" {
  for def in fixtures() {
    @qc.quick_check(
      @qc.forall(gen_state_of(def), p => {
        let v : @tutuca.Value = Map(p.1)
        @tutuca.Value::from_json(v.to_json()) == v
      }),
      max_success=300,
    )
  }
}

///|
test "every rule the fixtures declare lowers to something evaluable" {
  for def in fixtures() {
    let rules = @arb.rules_of(def)
    // Named rather than asserted as a bare Bool: a rule that did not lower
    // says why, and that sentence is the whole diagnostic.
    assert_eq(rules.unlowerable.map(u => "\{u.0}: \{u.1}").join("\n"), "")
  }
}

///|
/// A rule answers yes or no, over any state at all.
///
/// The property that catches what `tscript/check` cannot see. `Val::eval`
/// answers `Null` for a name that resolved to nothing, so a rule reading a
/// field the state does not have comes back neither true nor false — and a
/// filter written over it would silently reject every state.
test "property: every rule answers a boolean over any generated state" {
  let def = one(LEDGER)
  let rules = @arb.rules_of(def)
  let names = ["canPush", "idle", "canMove", "capped"]
  @qc.quick_check(
    @qc.forall(gen_state_of(def), p => {
      for n in names {
        guard rules.holds(n, p.1) is Some(_) else { return false }
      }
      true
    }),
    max_success=300,
  )
}

///|
/// The interpreted rule agrees with what it declares.
///
/// Not a tautology: the left side is `@tscript.parse_bool` lowering the rule's
/// source to a `@core.Val` and `Val::eval` walking it, and the right side is
/// the comparison done here in MoonBit. They agree only if the block
/// language's `<=`, `>`, `not` and `and` mean what the declaration says they
/// do — which is the same claim the two shipping backends make when they
/// compile the same rule.
test "property: an interpreted rule agrees with what it declares" {
  let def = one(LEDGER)
  let rules = @arb.rules_of(def)
  @qc.quick_check(
    @qc.forall(gen_state_of(def), p => {
      let s = p.1
      guard s.get("here") is Some(Num(here)) &&
        s.get("total") is Some(Num(total)) &&
        s.get("busy") is Some(Bool(busy)) else {
        return false
      }
      rules.holds("capped", s) == Some(here <= total) &&
      rules.holds("canPush", s) == Some(here > 0.0) &&
      rules.holds("idle", s) == Some(!busy) &&
      // The composed rule, which is the one that proves a rule may name
      // another: `canMove` reads `canPush` and `idle` through the stack.
      rules.holds("canMove", s) == Some(here > 0.0 && !busy)
    }),
    max_success=400,
  )
}

///|
/// The invariant filter only ever hands back states the invariant approves.
///
/// `such_that_maybe` gives up rather than looping, so a `None` is a legal
/// answer and is discarded; what may never happen is a `Some` holding a state
/// the rule rejects.
test "property: the invariant filter admits only states the invariant holds for" {
  let def = one(LEDGER)
  let rules = @arb.rules_of(def)
  @qc.quick_check(
    @qc.forall(rules.filter(@arb.state_of(def)), s => {
      match s {
        None => true
        Some(state) => rules.invariants_hold(state)
      }
    }),
    max_success=300,
  )
}

///|
/// The filter is not vacuous.
///
/// The other half, and the one a filter written by mistake would fail: a
/// `such_that_maybe` that never succeeds also never admits a bad state. So
/// this asserts the filter actually produces conserved ledgers — and, because
/// `conserved` correlates three independently-drawn fields, that it is doing
/// real work rather than accepting everything.
test "the invariant filter finds states, and the unfiltered generator does not" {
  let def = one(LEDGER)
  let rules = @arb.rules_of(def)
  let kept = rules
    .filter(@arb.state_of(def))
    .samples(size=8, seed=20260827)
    .filter(s => s is Some(_))
  assert_true(kept.length() > 0)
  // And the unfiltered draw is often NOT capped, which is why the filter
  // exists. If this ever fails, the generator has collapsed to a corner.
  let raw = @arb.state_of(def).samples(size=8, seed=20260827)
  let broken = raw.filter(s => !rules.invariants_hold(s))
  assert_true(broken.length() > 0)
}

///|
/// A dispatch is drawn only from what the component declares, with arguments
/// at the declared types.
test "property: a generated dispatch is one the component declares" {
  let def = one(LEDGER)
  guard @arb.dispatch_of(def) is Some(g) else {
    fail("Ledger declares messages, so a generator must exist")
  }
  @qc.quick_check(
    @qc.forall(g, d => {
      let (name, args, declared) = match d {
        Receive(n, a) => (n, a, def.receive)
        Intent(n, a) => (n, a, def.intent)
      }
      for m in declared {
        if m.name != name {
          continue
        }
        guard args.length() == m.payload.length() else { return false }
        for i, ty in m.payload {
          guard @info.ty_info(def, ty).accepts(args[i]) else { return false }
        }
        return true
      }
      false
    }),
    max_success=300,
  )
}

///|
test "a component that declares no intent generates no intent" {
  let def = one(SCALARS)
  // `Wide` declares no `handle` block at all, so both buckets are empty and
  // the honest answer is no generator rather than a made-up name.
  assert_true(@arb.dispatch_of(def) is None)
  assert_true(@arb.script_of(def) is None)
  let ledger = one(LEDGER)
  assert_true(@arb.dispatch_of(ledger, bucket=BIntent) is Some(_))
}

///|
/// The shrinker reaches the empty script and never grows one.
///
/// The two properties that make a search terminate: every candidate is
/// strictly shorter, so the recursion bottoms out, and the empty script is
/// reachable, so a failure present from the start shrinks all the way to it.
test "property: shrinking a script only ever shortens it" {
  let def = one(LEDGER)
  guard @arb.script_of(def) is Some(g) else { fail("Ledger declares messages") }
  @qc.quick_check(
    @qc.forall(g, script => {
      let n = script.length()
      for candidate in @arb.shrink_script(script) {
        guard candidate.length() < n else { return false }
      }
      // A non-empty script offers at least one candidate, or the search stops
      // before it has started.
      n == 0 || @arb.shrink_script(script).count() > 0
    }),
    max_success=200,
  )
}

///|
/// Where this reading of a rule stops, said out loud.
///
/// `@tscript.parse_bool` lowers the block language to a `@core.Val`, and a
/// `Val` is what a SLOT holds — so it admits exactly the slot vocabulary:
/// comparisons, `and` / `or` / `not` / `implies`, `is`, the `empty?` family,
/// `len`, `min` / `max` / `clamp`, `has` / `contains`, the converters and the
/// string verbs. It has no arithmetic, deliberately: "a slot has no arithmetic
/// — name the value with a `compute`".
///
/// So a rule that adds two fields — `invariant conserved { (.here + .there) is
/// .total }`, which is the form the skill's own example uses — compiles in
/// both shipping backends and does NOT lower here. That is a bound on this
/// package, not a bug in it, and the bound is pinned rather than described:
/// `unlowerable` names the rule and quotes the grammar's own sentence, so a
/// caller can see which rules it is holding a component to and which it is
/// not. A rule that reaches for arithmetic should name the sum with a
/// `compute` and compare against `$name`, which lowers.
test "a rule the slot grammar has no operator for is reported, not dropped" {
  let def = one(
    (
      #|state Ledger {
      #|  here  : Int
      #|  there : Int
      #|  total : Int
      #|  invariant conserved { (.here + .there) is .total }
      #|  invariant capped { .here <= .total }
      #|}
    ),
  )
  let rules = @arb.rules_of(def)
  assert_false(rules.usable())
  inspect(
    rules.unlowerable.map(u => "\{u.0}: \{u.1}").join("\n"),
    content="conserved: `+` is not a slot operator",
  )
  // The rule that DOES lower is unaffected — one refusal does not take the
  // others with it, which is the same treatment a card's refused handler gets.
  assert_true(
    rules.holds("capped", { "here": Num(1.0), "total": Num(2.0) }) == Some(true),
  )
  // And an unlowerable invariant is not silently treated as satisfied: it is
  // absent from `invariants`, so `invariants_hold` speaks only for the rules
  // it actually holds. `usable()` is what a caller checks first.
  assert_eq(rules.invariants.length(), 1)
}

///|
/// The mutator table here covers the one the runtime installs.
///
/// `mutator_dispatch_of` drops a name the runtime does not have, so a name
/// this package invented is harmless. The dangerous direction is the other
/// one: a mutator the runtime installs and this has no arguments for is a
/// message that never gets generated, and a hole in an alphabet looks exactly
/// like a component with nothing more to test. So the two sets are compared
/// both ways, over every field kind the fixtures declare between them.
test "every mutator the runtime installs is one this package can generate" {
  for def in fixtures() {
    let installed = @component.schema_mutators(@info.schema_info(def))
    let known = @arb.mutator_args(def)
    let missing : Array[String] = []
    for name, _ in installed {
      if !known.contains(name) {
        missing.push(name)
      }
    }
    missing.sort_by(@statedef.str_cmp)
    assert_eq(missing.join(", "), "")
  }
}

///|
/// And the alphabet is not empty for a component that declares fields.
///
/// The other half: a `mutator_args` that returned nothing would pass the
/// coverage check above vacuously, since the empty set covers nothing.
test "a component with fields has generated mutators to send" {
  for def in fixtures() {
    let known = @arb.mutator_args(def)
    assert_true(known.length() >= def.fields.length() * 3)
    assert_true(@arb.mutator_dispatch_of(def) is Some(_))
  }
}

///|
/// A generated script contains nothing the component cannot answer.
///
/// The join with `schema_writers` is what makes this true, and the property is
/// worth stating because the failure it prevents is invisible: a dispatch
/// nothing claims does not crash, it just does nothing, and the run reports it
/// as a refusal that reads exactly like a finding. `<field>Len` and
/// `hasIn<Field>` are the shapes that used to leak through — generated
/// callables that answer a scalar rather than a successor.
test "property: every generated mutator is a name the component can be sent" {
  for def in fixtures() {
    let schema = @info.schema_info(def)
    let writers = @component.schema_writers(schema)
    let all = @component.schema_mutators(schema)
    guard @arb.mutator_dispatch_of(def) is Some(one) else { continue }
    @qc.quick_check(
      @qc.forall(@gen.int_range(0, 8).bind(n => one.array_with_size(n)), script => {
        for d in script {
          guard d is Receive(name, _) else { return false }
          // In the runtime's own table, and on the half of it that writes.
          if !all.contains(name) || !writers.contains(name) {
            return false
          }
        }
        true
      }),
      max_success=100,
    )
  }
}

///|
/// …and the readers really are reachable, so the filter removed the right
/// things rather than simply removing things.
test "the readers the generators skip are still generated callables" {
  let def = one(SCALARS)
  let schema = @info.schema_info(def)
  let all = @component.schema_mutators(schema)
  let writers = @component.schema_writers(schema)
  // `SCALARS` declares `many : Array[Int]` and `open : Set[String]`.
  for reader in ["manyLen", "hasInOpen"] {
    assert_true(all.contains(reader))
    assert_false(writers.contains(reader))
  }
}
