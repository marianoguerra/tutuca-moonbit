// The spec block's rules, evaluated rather than compiled.
//
// A `pred` or an `invariant` is ONE expression over the state, with no
// arguments and no `@`-binding — the spec block refuses a parameterised rule
// by name, which is exactly what makes this possible. So the rule's source
// goes through `@tscript.parse_bool`, which lowers the block language to a
// `@core.Val`, and `Val::eval` answers it against a state map.
//
// That there are two ways to reach a rule's answer is the point rather than a
// duplication. The card compiler emits the rule into a wasm module and
// `gen-views` emits a `guard` into a generated MoonBit arm; this is a THIRD
// reading of the same declaration, and a property that runs all three against
// one state is a differential test of the two that ship.

///|
/// Every rule a spec block declares, lowered once.
///
/// Built ahead of a property rather than inside it: lowering is parsing, the
/// state is what varies, and a generator that re-parsed the same six rules on
/// every draw would spend its time there.
pub(all) struct Rules {
  /// `pred` by name — the rules a `requires` / `ensures` clause can name and a
  /// view can read as `$name`.
  preds : Map[String, @tutuca.Val]
  /// `invariant` by name — the rules that hold after EVERY dispatch.
  invariants : Map[String, @tutuca.Val]
  /// A rule whose source did not lower, with the reason.
  ///
  /// Reported rather than dropped, and never silently: a rule nobody can
  /// evaluate is a finding, and a `Rules` that quietly held none would make
  /// every property over it pass. `Rules::usable` is what a property asserts
  /// before it trusts the rest.
  unlowerable : Array[(String, String)]
}

///|
/// Lower every `pred` and `invariant` the spec block declares.
///
/// `format` is deliberately not lowered. It is the sentence a FAILING rule
/// says, evaluated against the state that was rejected, and a rule's truth
/// does not depend on it — the skill's own words: "a sentence that cannot be
/// evaluated is dropped and the report still fires".
pub fn rules_of(def : @statedef.StateDef) -> Rules {
  let preds : Map[String, @tutuca.Val] = Map([])
  let invariants : Map[String, @tutuca.Val] = Map([])
  let unlowerable : Array[(String, String)] = []
  for r in def.rules {
    let ctx = @tscript.ParseCtx::new()
    match @tscript.parse_bool(r.source, ctx) {
      Some(val) =>
        match r.kind {
          RPred => preds[r.name] = val
          RInvariant => invariants[r.name] = val
        }
      None => {
        // `parse_bool` records why on the context rather than raising, so the
        // reason is there to carry. Empty when the source was blank, which is
        // its own answer and a truthful one.
        let why = if ctx.issues.is_empty() {
          "the rule's source is empty"
        } else {
          ctx.issues.map(issue_why).join("; ")
        }
        unlowerable.push((r.name, why))
      }
    }
  }
  { preds, invariants, unlowerable, }
}

///|
/// Whether every declared rule lowered. False means the rest of this value
/// describes fewer rules than the spec block does.
pub fn Rules::usable(self : Rules) -> Bool {
  self.unlowerable.is_empty()
}

///|
/// Evaluate one rule — `pred` or `invariant` — over a state.
///
/// `None` for a name this spec does not declare, and `None` for a rule that
/// did not answer a boolean. The second case is the one worth having: `Null`
/// out of `Val::eval` means a name resolved to nothing, which is a rule that
/// reads a field it does not have. A `Bool` answer and "no answer" are
/// different facts and a property asserts against both.
pub fn Rules::holds(
  self : Rules,
  name : String,
  state : Map[String, @tutuca.Value],
) -> Bool? {
  guard self.lookup(name) is Some(val) else { return None }
  match val.eval(RuleStack::{ state, rules: self, }) {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
/// Whether every declared invariant holds over a state.
///
/// A rule that does not answer a boolean counts as NOT holding. The strict
/// reading, and the right one for a filter: a state a rule cannot be evaluated
/// over is not a state the rule has approved.
pub fn Rules::invariants_hold(
  self : Rules,
  state : Map[String, @tutuca.Value],
) -> Bool {
  for name, _ in self.invariants {
    if self.holds(name, state) != Some(true) {
      return false
    }
  }
  true
}

///|
/// The names of the invariants a state breaks, in sorted order.
///
/// What `invariants_hold` answers as a Bool, said so a failure can be read.
pub fn Rules::broken(
  self : Rules,
  state : Map[String, @tutuca.Value],
) -> Array[String] {
  let out : Array[String] = []
  for name, _ in self.invariants {
    if self.holds(name, state) != Some(true) {
      out.push(name)
    }
  }
  out.sort_by(@statedef.str_cmp)
  out
}

///|
/// A rule by name, whichever kind it is.
///
/// One namespace, because an `invariant` IS a `pred` with a role — `$conserved`
/// reads one from a view exactly as `$canPush` reads the other — so a
/// `requires` may name either and so may another rule.
fn Rules::lookup(self : Rules, name : String) -> @tutuca.Val? {
  match self.preds.get(name) {
    Some(v) => Some(v)
    None => self.invariants.get(name)
  }
}

///|
/// Narrow a state generator to the states the component considers valid.
///
/// Rejection sampling, and the one place in this package that uses it. The
/// preference everywhere else is to construct valid values rather than to
/// filter for them — but an invariant is an arbitrary predicate over the WHOLE
/// state (`(.here + .there) is .total` correlates three fields), and there is
/// nothing to construct against. `such_that_maybe` rather than `such_that` so
/// a rule nothing satisfies gives up instead of looping forever; the `None`
/// draws are what a caller discards with `@qc.filter`.
pub fn Rules::filter(
  self : Rules,
  g : @gen.Gen[Map[String, @tutuca.Value]],
) -> @gen.Gen[Map[String, @tutuca.Value]?] {
  g.such_that_maybe(s => self.invariants_hold(s))
}

///|
/// The stack a rule reads through.
///
/// Two lookups and no more, because a spec-block rule has no more to read:
/// `.field` is the state, and `$name` is another rule. Everything else on the
/// trait keeps its default of `Null`, which is the honest answer — a rule that
/// reaches for a binding is one the spec block refuses.
priv struct RuleStack {
  state : Map[String, @tutuca.Value]
  rules : Rules
}

///|
impl @tutuca.Stack for RuleStack with fn lookup_field_raw(self, name) {
  self.state.get(name).unwrap_or(Null)
}

///|
/// `$name` in a rule: another rule, evaluated here.
///
/// The composition the block language allows — "two rules become one by naming
/// their `and`: `pred canMove { canPush and (not .busy) }`" — so this recurses
/// through the same stack. A rule that names itself would not terminate, and
/// cannot: `statedef` rejects a cyclic declaration before this sees it.
impl @tutuca.Stack for RuleStack with fn lookup_method(self, name) {
  match self.rules.lookup(name) {
    Some(val) => val.eval(self)
    None => Null
  }
}

///|
/// A bare `name` in a rule reads as a rule too.
///
/// `pred canMove { canPush and (not .busy) }` writes the operand WITHOUT the
/// sigil — inside a rule body a bare name is another rule, not a binding — and
/// the lowering keeps it as `Name`. Same resolution as `$name`, one meaning.
impl @tutuca.Stack for RuleStack with fn lookup_name(self, name) {
  match self.rules.lookup(name) {
    Some(val) => val.eval(self)
    None => Null
  }
}

///|
/// Why one parse issue happened, as a sentence.
///
/// `BadExpression` already carries the block grammar's own words, which is the
/// whole reason that role holds a `why` rather than a code; the rest are named
/// after what was wrong with them, because no sentence is stored to quote.
fn issue_why(i : @tscript.Issue) -> String {
  match i.role {
    BadExpression(why~) => why
    UnknownPredicate => "`\{i.value}` is not a name a rule can call"
    PredicateArity(name~, want~) => "`\{name}` takes \{want} argument(s) here"
    BadPredicateArg => "`\{i.value}` is not an argument that call can take"
    BadHandlerName | BadHandlerArg =>
      "a rule is a value, and `\{i.value}` names a handler"
    BadMacroVar | BadConfigVar =>
      "`\{i.value}` is a substitution, and a rule is parsed with none bound"
  }
}
