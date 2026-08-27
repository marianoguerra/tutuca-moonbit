// The rules a component KEEPS, around the dispatches nothing wove them into.
//
// A `pred` and an `invariant` are declared in the spec block and compiled into
// the component's method bucket like any other `$name`; what the schema adds is
// the ROLE — that this one is asked after EVERY dispatch. The generator already
// wove an invariant into the arms it wrote itself, and more strictly than this
// can: an inline guard fires before the effect queue flushes. What was left
// uncovered is every dispatch the generator did NOT write, which is what these
// tests are about.

///|
priv struct LedgerState {
  here : Int
  there : Int
  total : Int
}

///|
impl @component.Fields for LedgerState with fn encode(s) {
  {
    "here": Num(s.here.to_double()),
    "there": Num(s.there.to_double()),
    "total": Num(s.total.to_double()),
  }
}

///|
impl @component.Fields for LedgerState with fn decode(f) {
  let num = (k : String) => {
    match f.get(k) {
      Some(Num(n)) => n.to_int()
      _ => 0
    }
  }
  Some({ here: num("here"), there: num("there"), total: num("total"), })
}

///|
impl @component.Fields for LedgerState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="ledger_state",
    fields=[
      @component.FieldInfo::new("here", TyInt),
      @component.FieldInfo::new("there", TyInt),
      @component.FieldInfo::new("total", TyInt),
    ],
    methods=["conserved"],
    // The role, and the whole of what the spec block contributes here: the
    // body is already one of the methods above.
    invariants=["conserved"],
  )
}

///|
/// A ledger that moves tokens between two piles and never mints one.
///
/// `move` is a hand-written `update~` arm — the path the generator does not
/// write, and therefore the path an inline guard never reached. `setHere` is
/// not written anywhere at all: it is the mutator every `Int` field gets.
fn ledger_comp() -> @component.Component {
  @component.component(
    name="Ledger",
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".here\"></x></div>",
      ),
    },
    init=LedgerState::{ here: 8, there: 0, total: 8, },
    update=(s : LedgerState, msg, _ctx) => {
      match msg {
        Receive("push", _) =>
          Next({ ..s, here: s.here - 1, there: s.there + 1, })
        // The one that mints a token out of nothing. It is written to succeed;
        // the rule is what stops it.
        Receive("cheat", _) => Next({ ..s, there: s.there + 1, })
        _ => Unhandled
      }
    },
    compute={
      "conserved": (s : LedgerState, _args, _stack) => {
        Bool(s.here + s.there == s.total)
      },
    },
  )
}

///|
fn ledger() -> @tutuca.Value {
  ledger_comp().make(Map([]))
}

///|
test "a transition that keeps the invariant is unaffected" {
  let after = send(ledger(), "push", [])
  assert_eq(after.field("here"), Num(7))
  assert_eq(after.field("there"), Num(1))
}

///|
test "a hand-written update arm that breaks the invariant is abandoned" {
  // `cheat` returns a successor and the arm is the author's own MoonBit, so
  // nothing wove a guard around it. Before the schema carried the rule this
  // minted a token and nobody heard about it.
  let before = ledger()
  let after = send(before, "cheat", [])
  assert_eq(after.field("there"), Num(0))
  assert_eq(after.field("here"), Num(8))
}

///|
test "a GENERATED mutator that breaks the invariant is abandoned too" {
  // `setThere` is not declared anywhere — it is what every field gets — so it
  // is the dispatch an invariant could not reach at all. A mutator raises no
  // effects, so the abandonment here is complete.
  let after = send(ledger(), "setThere", [Num(3)])
  assert_eq(after.field("there"), Num(0))
  // …and one that keeps the rule still goes through.
  let ok = send(ledger(), "setHere", [Num(8)])
  assert_eq(ok.field("here"), Num(8))
}

///|
test "the refusal names the rule and carries the state that was rejected" {
  let refused : Array[@tutuca.Refusal] = []
  let off = @tutuca.on_runtime_notice(n => {
    if n is Refused(r) {
      refused.push(r)
    }
  })
  let _ = send(ledger(), "setThere", [Num(3)])
  off()
  assert_eq(refused.length(), 1)
  assert_eq(refused[0].code, Invariant)
  assert_eq(refused[0].rule, "conserved")
  assert_eq(refused[0].asked, "setThere")
  // The state that was REJECTED, which is the thing you actually want to look
  // at and the thing nothing could reach before the channel existed.
  assert_eq(refused[0].state.field("there"), Num(3))
}

///|
test "a rule that cannot be evaluated does not refuse anything" {
  // Unknown is not wrong. A rule answering `Null` failed to run, and refusing
  // every transition because of it would turn a bad rule into a frozen
  // component.
  let comp = @component.component(
    name="Ledger",
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".here\"></x></div>",
      ),
    },
    init=LedgerState::{ here: 8, there: 0, total: 8, },
    compute={ "conserved": (_s : LedgerState, _args, _stack) => Null },
  )
  let after = send(comp.make(Map([])), "setThere", [Num(3)])
  assert_eq(after.field("there"), Num(3))
}
