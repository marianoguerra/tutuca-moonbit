// The driver, held against a component declared here.
//
// A self-contained fixture rather than one borrowed from storybook/examples,
// for the reason `testing/harness`'s own suite gives: this package is
// published and the storybook packages are repo demos excluded from the
// archive. It also makes the file readable on its own, which matters because
// it doubles as the driver's documentation.
//
// The fixture is a TILL: money in a drawer, and a `float` that must never
// exceed it. Nothing in the component's views can break that — the one handler
// guards — but `setTill` and `setFloat` are installed for every field whether
// or not anything sends them, and that gap is exactly what a fuzz run is for.

///|
priv struct TillState {
  till : Int
  float_ : Int
}

///|
/// The block this component was DECLARED in, as `gen` would carry it.
///
/// A hand-written component passes `spec~` itself; a generated one gets it
/// from the const `emit_spec_source` writes. Either way it is the same string
/// and the same `parse_state` reads it, which is what makes this fixture a
/// fair stand-in for a real component.
const TILL_SPEC : String =
  #|state Till {
  #|  till  : Int
  #|  float_ : Int
  #|
  #|  pred canDraw
  #|    format 'the drawer has nothing left to draw on' { .till > 0 }
  #|
  #|  invariant floatCovered
  #|    format 'the float is larger than the drawer holding it' { .float_ <= .till }
  #|}
  #|
  #|handle Till {
  #|  message {
  #|    draw(Int)
  #|  }
  #|}

///|
/// The till, with its rules compiled in or left as names only.
///
/// `enforced=false` is not a broken fixture. It is the shape a component takes
/// when a rule is declared and nothing implements it — which is a thing that
/// happens, silently, and which the schema cannot tell you because the schema
/// lists the NAME either way.
fn till_module(enforced? : Bool = true) -> @component.ModuleDef {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <span class="till" @text=".till"></span>
          #|  <span class="float" @text=".float_"></span>
          #|</div>
        ),
      ),
    },
    name="Till",
    initial=TillState::{ till: 10, float_: 5, },
    // The only transition the component itself offers, and it keeps the
    // invariant: drawing lowers the till and the float with it.
    update=(s : TillState, msg, _ctx) => {
      match msg {
        Receive("draw", args) => {
          let n = match args {
            [Num(n)] => n.to_int()
            _ => 1
          }
          let till = @cmp.maximum(0, s.till - n)
          Next({ till, float_: @cmp.minimum(s.float_, till), })
        }
        _ => Unhandled
      }
    },
    // The rules, as methods. This is the half `gen` writes from the
    // block — `bar_chart_compute_neverEmpty` in `svg_more_view_ir_gen.mbt` is
    // the generated shape of exactly this — and it is what puts something
    // behind the names the schema lists.
    compute=if enforced {
      {
        "floatCovered": (s : TillState, _args, _stack) => {
          Bool(s.float_ <= s.till)
        },
        "canDraw": (s : TillState, _args, _stack) => Bool(s.till > 0),
      }
    } else {
      { "canDraw": (s : TillState, _args, _stack) => Bool(s.till > 0) }
    },
    spec=TILL_SPEC,
  )
  @component.ModuleDef::new(name="till", components=[comp], examples=[
    { component: "Till", title: "Open", args: Map([]), view: None, },
  ])
}

///|
impl @component.Fields for TillState with fn encode(s) {
  { "till": Num(s.till.to_double()), "float_": Num(s.float_.to_double()) }
}

///|
impl @component.Fields for TillState with fn decode(f) {
  guard f.get("till") is Some(Num(t)) else { return None }
  guard f.get("float_") is Some(Num(v)) else { return None }
  Some({ till: t.to_int(), float_: v.to_int(), })
}

///|
impl @component.Fields for TillState with fn schema() {
  @component.SchemaInfo::new(
    name="Till",
    fingerprint="fuzz-till",
    fields=[
      @component.FieldInfo::new("till", TyInt(width=32, signed=true)),
      @component.FieldInfo::new("float_", TyInt(width=32, signed=true)),
    ],
    receives=["draw"],
    methods=["canDraw", "floatCovered"],
    invariants=["floatCovered"],
    view_names=["main"],
  )
}

///|
fn till_comp(enforced? : Bool = true) -> @component.Component {
  till_module(enforced~).components[0]
}

///|
fn till_plan(
  source? : @fuzz.Source = Fields,
  enforced? : Bool = true,
) -> @fuzz.Plan raise {
  guard @fuzz.Plan::of_component(till_comp(enforced~), source~) is Some(p) else {
    fail("Till carries a spec block, so it has a plan")
  }
  p
}

///|
/// A fresh till. The two mounts are separate functions rather than one with a
/// flag because `shrink` takes a remount as a plain `() -> Harness?`.
fn fresh() -> @harness.Harness[@memdom.MemNode] raise {
  @harness.mount_example(till_module(), "Open")
}

///|
fn fresh_leaky() -> @harness.Harness[@memdom.MemNode] raise {
  @harness.mount_example(till_module(enforced=false), "Open")
}

///|
/// The same, as `shrink` wants it: a mount that failed is a candidate that
/// could not be tried, not one that reproduced.
fn remount_leaky() -> @harness.Harness[@memdom.MemNode]? {
  Some(fresh_leaky()) catch {
    _ => None
  }
}

// ---------------------------------------------------------------------------
// What a plan is

///|
test "a plan comes from the block, and a component without one has none" {
  let p = till_plan()
  assert_eq(p.component, "Till")
  // Both rules lowered, so nothing below is quietly skipped.
  assert_eq(p.unchecked(), [])
  assert_true(p.has_oracle())
  // The same component with its spec stripped is not a plan.
  let bare = @component.Component::for_type(
    name="Bare",
    views=Map([]),
    schema=@component.SchemaInfo::new(fingerprint="bare"),
  )
  assert_true(@fuzz.Plan::of_component(bare) is None)
}

///|
/// A bare `state { … }` is still that component's block.
///
/// The name is part of the PARSE, not a filter applied after it: an unnamed
/// state belongs to the file's single unnamed component, and only the caller
/// knows what that component is called. Handing it over is what makes a plan
/// possible at all here — without it the arm parses as `""`, matches nothing,
/// and the whole corpus of bare-state components (counter, dnd, file-picker,
/// …) reports "declares no spec block" while declaring one.
test "a bare state block belongs to the component that carries it" {
  let comp = @component.Component::for_type(
    name="Tally",
    views=Map([]),
    schema=@component.SchemaInfo::new(name="Tally", fingerprint="tally"),
    spec=(
      #|state {
      #|  count : Int
      #|}
    ),
  )
  guard @fuzz.Plan::of_component(comp) is Some(p) else {
    fail("a bare state block gave no plan")
  }
  assert_eq(p.component, "Tally")
  assert_eq(p.def.fields.length(), 1)
  assert_eq(p.def.fields[0].name, "count")
}

///|
/// A seed is the whole address of a run.
///
/// The claim the profiling story rests on: the same four values redraw the
/// identical script, so a workload can be recorded twice and compared.
test "a script is a function of its seed" {
  let p = till_plan()
  let a = p.script(seed=7, steps=12)
  let b = p.script(seed=7, steps=12)
  let c = p.script(seed=8, steps=12)
  assert_eq(a.length(), 12)
  assert_eq(a, b)
  assert_not_eq(a, c)
}

///|
/// Every generated mutator is a `Receive`. An `Intent` here would mean the
/// generator invented one — a mutator is installed on the component and never
/// routed.
test "the field source draws only writes, and only declared field names" {
  let p = till_plan()
  let names : Array[String] = []
  for d in p.script(seed=3, steps=40) {
    guard d is SetField(name, _) else { fail("every drawn action is a write") }
    if !names.contains(name) {
      names.push(name)
    }
  }
  // Every name the generator drew is a FIELD this schema declares — which is
  // the whole of what a write can address, where a dispatch could name
  // anything and be answered by nothing.
  let declared = till_comp().schema.field_names()
  for n in names {
    assert_true(declared.contains(n))
  }
}

///|
/// The declared source draws the message the block spells, WITH its payload.
///
/// This is the half a schema-only generator could not reach: `receives` records
/// `draw` as a name, and `draw(Int)` is what says the argument is a number.
test "the declared source draws a message with its payload" {
  let p = till_plan(source=Declared(BReceive))
  let script = p.script(seed=11, steps=25)
  assert_true(script.length() > 0)
  for d in script {
    guard d is Message(Receive("draw", args)) else {
      fail("Till declares one message, and a draw is what should be drawn")
    }
    assert_eq(args.length(), 1)
    assert_true(args[0] is Num(_))
  }
}

// ---------------------------------------------------------------------------
// What a run finds

///|
/// A component whose rules are compiled holds, and the runtime is what holds
/// it.
///
/// Worth being precise about what passes here. `setFloat` is a legal dispatch
/// that nothing in the views can produce — the one handler lowers the float
/// with the till — and the generator sends it constantly. It does not break
/// the invariant because the runtime ABANDONS the transition and refuses; the
/// state never lands. So a green run over an enforced component is a claim
/// about the enforcement, not about the generator having found nothing.
test "an enforced component holds against generated mutators" {
  let p = till_plan()
  for seed in [1UL, 2, 3, 4, 5, 6] {
    let run = p.run(fresh(), p.script(seed~, steps=40))
    assert_eq(run.outcome, Held)
  }
}

///|
/// …and the refusals are there, which is what says the run reached the
/// interesting dispatches rather than missing them.
///
/// A property that passes because the generator never produced the interesting
/// case looks exactly like a property that passes, so this asks whether it
/// did.
test "the run reaches the dispatches the invariant has to decline" {
  let p = till_plan()
  let run = p.run(fresh(), p.script(seed=1, steps=40))
  let declined : Array[String] = []
  for st in run.steps {
    for r in st.refused {
      if r.code is Invariant && !declined.contains(r.rule) {
        declined.push(r.rule)
      }
    }
  }
  assert_eq(declined, ["floatCovered"])
}

///|
/// A rule that is declared and never implemented is enforced by nothing, and
/// this is what finds it.
///
/// The failure the package exists for. The schema lists `floatCovered` either
/// way, so nothing about the component's own description says which of these
/// two it is — only driving it does.
test "an unenforced invariant is broken, and the break is reported" {
  let p = till_plan(enforced=false)
  let run = p.run(fresh_leaky(), p.script(seed=1, steps=30))
  guard run.outcome is Broke(rule~, sentence~, at~) else {
    fail("nothing implements floatCovered, so a generated setFloat lands")
  }
  assert_eq(rule, "floatCovered")
  // The author's own words, with the block's quote delimiters gone.
  assert_eq(sentence, "the float is larger than the drawer holding it")
  // Stopped AT the break rather than running on: an invariant repaired by the
  // next message is still broken, and a check at the end would call that a
  // pass.
  assert_eq(run.steps.length(), at + 1)
  assert_eq(run.steps[at].broke, ["floatCovered"])
  // The state really is out of contract — not merely reported as such.
  guard run.steps[at].after.get("float_") is Some(Num(f)) else {
    fail("float_ is a declared Int field")
  }
  guard run.steps[at].after.get("till") is Some(Num(t)) else {
    fail("till is a declared Int field")
  }
  assert_true(f > t)
}

///|
/// The messages the component DECLARES keep it, either way.
///
/// The other half of the same claim: the gap is the generated mutators, not
/// the protocol. `draw` lowers the float with the till in the component's own
/// MoonBit, so it cannot break the rule even where nothing would stop it.
test "no declared message can break the invariant" {
  let p = till_plan(source=Declared(BReceive), enforced=false)
  for seed in [1UL, 2, 3, 4, 5] {
    let run = p.run(fresh_leaky(), p.script(seed~, steps=40))
    assert_eq(run.outcome, Held)
  }
}

///|
/// Every refusal the runtime raised, the block agrees with.
///
/// The differential claim, and the one that costs nothing to make: on one side
/// the rule's source lowered to a `@core.Expr` and evaluated over the state as
/// it stood, on the other the compiled guard whose verdict arrived as a
/// `Refusal`. A hand-written test cannot make this claim — it asserts a state
/// it chose against a rule it read — because the two only diverge on the
/// states nobody thought to write down.
test "the interpreted rule agrees with every refusal the compiled one raised" {
  let p = till_plan()
  for seed in [1UL, 2, 3, 4, 5, 6, 7, 8] {
    let run = p.run(fresh(), p.script(seed~, steps=40))
    for st in run.steps {
      assert_eq(st.disagreed, [])
    }
    assert_true(!(run.outcome is Disagreed(..)))
  }
}

///|
/// A refusal is reported and is not a failure.
///
/// `setTill 0` while the float is 5 would leave the float uncovered, so the
/// runtime abandons it and says so. The run records that and keeps going,
/// because a rule doing its job is not a bug — and recording it is the only
/// way to tell it apart from a dispatch that simply had nothing to do, which
/// looks identical from the state's side.
test "a refused transition is recorded, not failed" {
  let p = till_plan()
  let h = fresh()
  let declined = p.step(h, SetField("till", Num(0.0)))
  assert_eq(declined.refused.length(), 1)
  assert_eq(declined.refused[0].code, Invariant)
  assert_eq(declined.refused[0].rule, "floatCovered")
  assert_eq(declined.broke, [])
  // Abandoned means abandoned: the till did not move.
  assert_eq(declined.after.get("till"), Some(Num(10)))
  // Lower the float first and the same dispatch goes through.
  assert_eq(p.step(h, SetField("float_", Num(0.0))).refused, [])
  let ok = p.step(h, SetField("till", Num(0.0)))
  assert_eq(ok.refused, [])
  assert_eq(ok.after.get("till"), Some(Num(0)))
}

///|
/// A `pred` nothing asks for declines nothing.
///
/// Worth pinning, because it is the fact that decides what the differential
/// check above can claim. `canDraw` is declared and compiled, and `draw` still
/// runs on an empty drawer — a `pred` becomes a PRECONDITION only where a
/// handler's header names it in a `requires`, and that header lives in the
/// script block. A component whose handlers are hand-written MoonBit, like
/// this one, has no headers at all.
test "a pred no handler requires is not a precondition" {
  let p = till_plan()
  let h = fresh()
  assert_eq(p.step(h, SetField("float_", Num(0.0))).refused, [])
  assert_eq(p.step(h, SetField("till", Num(0.0))).refused, [])
  // The drawer is empty, so `canDraw` does not hold…
  assert_eq(p.rules.holds("canDraw", @fuzz.settled(h)), Some(false))
  // …and drawing is not declined, because nothing asked.
  let drew = p.step(h, Message(Receive("draw", [Num(1.0)])))
  assert_eq(drew.refused, [])
  assert_eq(drew.disagreed, [])
}

///|
/// A step counts the renders it caused.
///
/// Not a measurement — the loop is clock-free and this is a count — but it is
/// what tells a dispatch that changed nothing apart from one that redrew the
/// tree, which is the question a run answers before a profiler is opened.
test "a step counts the renders it caused" {
  let p = till_plan()
  let h = fresh()
  assert_eq(p.step(h, SetField("till", Num(14.0))).renders, 1)
  // The same value again: the root does not swap, so nothing re-renders.
  assert_eq(p.step(h, SetField("till", Num(14.0))).renders, 0)
}

// ---------------------------------------------------------------------------
// Making it readable

///|
/// The reproducer shrinks to the one dispatch that does it.
///
/// Thirty generated mutators reach the break; one `setFloat` above the till is
/// what it MEANS, and that is the difference between a bug report somebody
/// acts on and a log somebody closes.
test "a failing run shrinks to its cause" {
  let p = till_plan(enforced=false)
  let run = p.run(fresh_leaky(), p.script(seed=1, steps=30))
  assert_true(run.outcome is Broke(..))
  let small = @fuzz.shrink(p, run.reproducer(), remount_leaky)
  assert_true(small.length() <= run.reproducer().length())
  // Still the same failure, from a fresh mount.
  assert_true(@fuzz.Plan::run(p, fresh_leaky(), small).outcome is Broke(..))
  // One dispatch is enough: nothing has to happen first for an unenforced
  // setter to write a float the drawer cannot cover.
  assert_eq(small.length(), 1)
}

// ---------------------------------------------------------------------------
// Domains: the `where` clauses, and what they do to a run.
//
// The Till above is about RULES — a named boolean the runtime asks after every
// dispatch. What follows is about the other half: a relation between two
// fields that no type can state, and that a rule can only ever check.
//
// The distinction shows in exactly one place, and it is the reason the feature
// exists. `invariant inRange { … }` would catch a bad index and `Rules::filter`
// would try to generate around it by rejection — draw, ask, discard — which
// for `0 <= i < len(items)` never lands. A `where` is read BACKWARDS instead:
// the same declaration is the range to draw from.

///|
priv struct AlbumState {
  photos : Array[@tutuca.Value]
  cursor : Int
}

///|
const ALBUM_SPEC : String =
  #|state Album {
  #|  photos : Array[String]
  #|  cursor : Int
  #|
  #|  where cursor is index of .photos
  #|}

///|
impl @component.Fields for AlbumState with fn encode(s) {
  { "photos": List(s.photos), "cursor": Num(s.cursor.to_double()) }
}

///|
impl @component.Fields for AlbumState with fn decode(f) {
  guard f.get("cursor") is Some(Num(c)) else { return None }
  Some({
    photos: match f.get("photos") {
      Some(List(a)) => a
      _ => []
    },
    cursor: c.to_int(),
  })
}

///|
impl @component.Fields for AlbumState with fn schema() {
  @component.SchemaInfo::new(
    name="Album",
    fingerprint="fuzz-album",
    fields=[
      @component.FieldInfo::new("photos", TyList(TyText)),
      @component.FieldInfo::new("cursor", TyInt(width=32, signed=true)),
    ],
    domains=[
      { field: "cursor", domain: DIndexOf(field="photos", allow_none=false), },
    ],
    view_names=["main"],
  )
}

///|
fn album_module() -> @component.ModuleDef {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><span class=\"cursor\" @text=\".cursor\"></span></div>",
      ),
    },
    name="Album",
    initial=AlbumState::{ photos: [Str("a"), Str("b"), Str("c")], cursor: 0, },
    spec=ALBUM_SPEC,
  )
  @component.ModuleDef::new(name="album", components=[comp], examples=[
    { component: "Album", title: "Three", args: Map([]), view: None, },
  ])
}

///|
fn album_plan() -> @fuzz.Plan raise {
  guard @fuzz.Plan::of_component(album_module().components[0], source=Fields)
    is Some(p) else {
    fail("Album carries a spec block, so it has a plan")
  }
  p
}

///|
test "a plan says whether drawing against the live state can help" {
  assert_true(album_plan().state_aware())
  // The Till declares rules and no domains, so a per-step draw would cost more
  // and produce the same dispatches.
  assert_false(till_plan().state_aware())
}

///|
test "a live draw puts the cursor in range; a script drawn up front does not" {
  // The whole complaint, as a measurement. Both runs send the same number of
  // `setCursor`s to the same component from the same seed; the difference is
  // only WHEN the argument was drawn.
  let plan = album_plan()
  let in_range = (d : @fuzz.Action) => {
    match d {
      SetField("cursor", Num(n)) => n >= 0.0 && n < 3.0
      _ => true
    }
  }
  let count = (script : Array[@fuzz.Action]) => {
    let mut good = 0
    let mut total = 0
    for d in script {
      if d is SetField("cursor", _) {
        total = total + 1
        if in_range(d) {
          good = good + 1
        }
      }
    }
    (good, total)
  }
  // Drawn up front, with no field yet holding a value: `cursor` can only be
  // drawn at `Int`'s own edges, so almost nothing lands.
  let blind = plan.script(seed=7, steps=60)
  let (blind_good, blind_total) = count(blind)
  // Drawn against the state as it stands.
  let h = @harness.mount_example(album_module(), "Three")
  let live = plan.run_live(h, steps=60, seed=7)
  let (live_good, live_total) = count(live.script)
  // Both runs actually exercised the setter, or the comparison means nothing.
  assert_true(blind_total > 5)
  assert_true(live_total > 5)
  // The claim: the live run mostly lands in range and the blind one mostly
  // does not. Stated as a ratio rather than a count, because the number of
  // `setCursor`s drawn differs between the two.
  assert_true(live_good * 2 > live_total)
  assert_true(blind_good * 2 < blind_total)
}

///|
test "the out-of-domain share is kept, so the refusal itself is exercised" {
  // A generator that only ever drew valid values would leave the runtime's
  // rejection with no coverage from the one tool built to find gaps in it.
  let plan = album_plan()
  let h = @harness.mount_example(album_module(), "Three")
  let run = plan.run_live(h, steps=120, seed=3)
  let mut refused = 0
  for s in run.steps {
    for r in s.refused {
      if r.code is OutOfRange {
        refused = refused + 1
      }
    }
  }
  assert_true(refused > 0)
}

///|
test "a live run is addressed by its seed, exactly as a script is" {
  // What changed with per-step drawing is WHEN each step is drawn, not
  // whether the run can be redrawn tomorrow.
  let plan = album_plan()
  let a = plan.run_live(
    @harness.mount_example(album_module(), "Three"),
    steps=25,
    seed=11,
  )
  let b = plan.run_live(
    @harness.mount_example(album_module(), "Three"),
    steps=25,
    seed=11,
  )
  assert_eq(a.script.length(), b.script.length())
  for i, d in a.script {
    assert_true(d == b.script[i])
  }
  // …and a different seed is a different run.
  let c = plan.run_live(
    @harness.mount_example(album_module(), "Three"),
    steps=25,
    seed=12,
  )
  assert_false(a.script == c.script)
}

///|
test "every state a domain-carrying schema generates satisfies its domains" {
  // The generator's own claim, over `state_of` rather than over a run: a whole
  // state is drawn field by field in dependency order, so `cursor` is drawn
  // after `photos` and against the length it actually got.
  let defs = @statedef.parse_state(ALBUM_SPEC, name="Album")
  let def = defs[0]
  let domains = @info.domains_of(def)
  for seed in 0UL..<40UL {
    let st = @arb.state_of(def).sample(seed~)
    for d in domains {
      assert_true(
        @tutuca.domain_holds(d.domain, st.get(d.field).unwrap_or(Null), st),
      )
    }
  }
}
