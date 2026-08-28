// What to send: a component's generators, recovered from the block it was
// declared in.

///|
/// A component's generators, and the rules they are held to.
///
/// Built from `Component::spec` — the block SOURCE, which `gen-views` carries
/// into the compiled module — rather than from the schema beside it. The
/// schema is the block's projection and the projection is lossy in the two
/// places that matter here: a rule reaches `SchemaInfo` as a name with no
/// body, and a message as a name with no payload. Neither can be generated
/// from, and the rules are the whole oracle.
pub struct Plan {
  /// The component this plans for, by name — what a `Dispatch` is addressed to
  /// and what a mismatch is reported against.
  component : String
  /// The parsed declaration. Kept rather than discarded after the generators
  /// are built, because a caller re-drawing at a different length or bucket
  /// should not have to re-parse.
  def : @statedef.StateDef
  /// The `pred`s and `invariant`s, lowered. `Rules::usable` is false when the
  /// block declared none that `@core.Val` can evaluate — a plan is still fine
  /// then, it just has nothing to hold the component to.
  rules : @arb.Rules
  /// One dispatch, drawn from the chosen bucket. None when the component
  /// declares nothing to draw from: no fields to mutate and no messages.
  ///
  /// State-INDEPENDENT: built once, from the declaration alone. It is what
  /// `script` samples and what a component with no `where` needs; `next_at`
  /// rebuilds a state-aware one per step, which is why the two inputs it needs
  /// are kept below rather than discarded after this was made.
  one : @gen.Gen[@component.Dispatch]?
  source : Source
  depth : Int
}

///|
/// Which dispatches a run draws from.
///
/// The distinction that matters is not `Receive` vs `Intent` — `@arb.Bucket`
/// already says that — but whether a name was WRITTEN DOWN. `Declared` draws
/// the messages the block spells, which is what an author asks about when they
/// ask "does my component survive its own protocol". `Mutators` draws the
/// per-field setters the runtime installs for every field whether or not
/// anything sends them, which is what nobody writes a test for and where the
/// interesting failures are: `setValues []` is a legal dispatch that no button
/// in `svg_more.html` can produce, and `neverEmpty` is all that stands between
/// it and a chart with no bars.
pub(all) enum Source {
  Mutators
  Declared(@arb.Bucket)
  Either(@arb.Bucket)
} derive(Eq, @debug.Debug)

///|
/// The generators for `comp`, or None when it carries no spec block.
///
/// None is the ordinary answer for a hand-written component and for anything
/// `gen-views` did not build — there is no failure here, only nothing to
/// generate from.
pub fn Plan::of_component(
  comp : @component.Component,
  source? : Source = Mutators,
  depth? : Int = @arb.MAX_DEPTH,
) -> Plan? {
  guard comp.spec != "" else { return None }
  // The NAME is part of the parse, not a filter applied after it: a bare
  // `state { … }` belongs to the file's single unnamed component, and the
  // parser can only give it a name if the caller — the only thing that knows
  // what that component is called — hands one over. Without it every
  // bare-state component in the corpus (counter, dnd, file-picker, …) parsed
  // to a `StateDef` named "" and matched nothing below, so the Fuzz tab
  // reported "declares no spec block" for a component that declares one.
  let defs = @statedef.parse_state(comp.spec, name=comp.schema.name) catch {
    // A block that no longer parses is not a plan and not an error a fuzz run
    // can act on. It is a `gen-views` failure that has already been reported
    // somewhere the author will see it.
    _ => return None
  }
  // By NAME, because the block is the file's: a file declaring two components
  // carries both arms in every one of its wrappers.
  let name = comp.schema.name
  let mut found : @statedef.StateDef? = None
  for d in defs {
    if d.component == name {
      found = Some(d)
    }
  }
  guard found is Some(def) else { return None }
  Some({
    component: name,
    def,
    rules: @arb.rules_of(def),
    one: dispatch_gen(def, source, depth, Map([])),
    source,
    depth,
  })
}

///|
/// The one-dispatch generator for a source.
fn dispatch_gen(
  def : @statedef.StateDef,
  source : Source,
  depth : Int,
  /// The fields as they stand, for a `set<Field>` whose domain is relative to
  /// them. Empty means "no state in hand", which is what the up-front build
  /// passes and which draws exactly what it always did.
  state : Map[String, @tutuca.Value],
) -> @gen.Gen[@component.Dispatch]? {
  match source {
    Mutators => @arb.mutator_dispatch_of(def, depth~, state~)
    Declared(bucket) => @arb.dispatch_of(def, bucket~, depth~)
    Either(bucket) =>
      match
        (
          @arb.mutator_dispatch_of(def, depth~, state~),
          @arb.dispatch_of(def, bucket~, depth~),
        ) {
        (Some(m), Some(d)) => Some(@gen.one_of([m, d]))
        (Some(m), None) => Some(m)
        (None, d) => d
      }
  }
}

///|
/// A script of `steps` dispatches, drawn at `seed`.
///
/// Deterministic, and that is the point of taking a seed rather than a
/// `RandomState`: a run is addressed entirely by (component, source, seed,
/// steps), so the same four values redraw the identical script — in another
/// session, on another backend, or under a profiler that needs the workload to
/// be the same one twice.
///
/// Empty when the component has nothing to draw from.
pub fn Plan::script(
  self : Plan,
  seed~ : UInt64,
  steps~ : Int,
) -> Array[@component.Dispatch] {
  guard self.one is Some(one) else { return [] }
  guard steps > 0 else { return [] }
  one.array_with_size(steps).sample(seed~)
}

///|
/// The dispatch to send NEXT, drawn against the state the component is in.
///
/// The state-aware half of `script`, and the reason it exists: a domain is a
/// relation between fields, so `setCurrentIndex` cannot be drawn in range
/// until `items` has a length — and `script` samples the whole run before the
/// first dispatch, when no field has a value yet.
///
/// Still addressed entirely by `(component, source, seed, steps)`: the seed
/// for step `i` is derived from the run's seed and `i`, so the same four
/// values redraw the identical run. What changed is only WHEN each step is
/// drawn, not whether it is reproducible.
///
/// `None` when the component has nothing to draw from, exactly as `script`
/// answers with an empty array.
pub fn Plan::next_at(
  self : Plan,
  state : Map[String, @tutuca.Value],
  seed~ : UInt64,
  step~ : Int,
) -> @component.Dispatch? {
  guard self.one is Some(_) else { return None }
  guard dispatch_gen(self.def, self.source, self.depth, state) is Some(g) else {
    return None
  }
  Some(g.sample(seed=step_seed(seed, step)))
}

///|
/// Whether drawing against the live state can produce anything `script` could
/// not.
///
/// False for the great majority of components, and a caller that asks first
/// keeps the cheap path: with no `where` in the block, a per-step draw and a
/// sampled script are the same dispatches at more cost.
pub fn Plan::state_aware(self : Plan) -> Bool {
  !self.def.wheres.is_empty()
}

///|
/// The seed for one step of a run.
///
/// SplitMix64's finalizer over `seed + i * GOLDEN`, written out rather than
/// depended on: the property wanted is only that consecutive steps get
/// unrelated streams, and `seed + i` does not give that — `@gen.Gen`s built
/// from neighbouring seeds draw visibly similar values, which would make step
/// three a near-copy of step two.
fn step_seed(seed : UInt64, step : Int) -> UInt64 {
  let mut z = seed + step.to_uint64() * 0x9E3779B97F4A7C15UL
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}

///|
/// A script of `steps` dispatches, as a GENERATOR.
///
/// `script` draws one; this hands the generator over so a `@qc.forall` can
/// draw its own, shrink it with `@arb.shrink_script`, and report the minimal
/// counterexample the way a property test expects. The two exist side by side
/// because they answer different questions: a property asks "for all scripts",
/// and a run somebody is watching asks for ONE script that can be redrawn
/// tomorrow.
///
/// Empty scripts when the component has nothing to draw from, rather than a
/// missing generator: a `forall` over nothing is a property that passes
/// vacuously either way, and an Option here would make every call site say so.
pub fn Plan::script_gen(
  self : Plan,
  steps : Int,
) -> @gen.Gen[Array[@component.Dispatch]] {
  guard self.one is Some(one) && steps > 0 else { return @gen.pure([]) }
  one.array_with_size(steps)
}

///|
/// Whether this plan can hold the component to anything.
///
/// A plan with no usable rules still generates and still catches a crash or a
/// refusal; it just cannot say a state was WRONG. Worth telling a caller,
/// because "no invariant broke" reads the same either way.
pub fn Plan::has_oracle(self : Plan) -> Bool {
  self.rules.usable()
}

///|
/// The rules the block declared that `@core.Val` could not lower, as
/// (name, why).
///
/// Empty is the good answer and the common one. A non-empty list is the honest
/// version of a green run: those rules were not checked, and the run is
/// quieter than it looks. `invariant conserved { (.here + .there) is .total }`
/// lands here — the slot vocabulary has no arithmetic — and the fix is to name
/// the sum with a `compute` and compare against `$name`.
pub fn Plan::unchecked(self : Plan) -> Array[(String, String)] {
  self.rules.unlowerable
}
