// Spec for the interpreter: what running a body needs and what it produces.
// READONLY by convention; the implementation is in eval.mbt / run.mbt.

///|
/// What a body asked the framework to do, beyond changing its own state.
///
/// The vocabulary is the one `dyncomp`'s `ControlMsg` already has, and that is
/// not a coincidence: a guest dispatching inside its own wasm answers with
/// exactly this list, so an interpreted card and a compiled one hand the host
/// the same thing. Neither knows what the host will do with it.
pub(all) enum Effect {
  /// `send 'flash' .msg` — at this component.
  ESend(name~ : String, args~ : Array[@tutuca.Value])
  /// `bubble 'rowPicked' @key` — up the path it was raised on.
  EBubble(name~ : String, args~ : Array[@tutuca.Value])
  /// `request 'save' .draft` — resolved through the registry, not a position.
  ///
  /// The arguments are here because the ahead-of-time backend already emits
  /// them (`ctx.request(name, payload, RequestOpts::new())`) and a
  /// `RequestFn` has no component instance to read state from, so they are
  /// the only channel a request has. What stays out of the block is
  /// `RequestOpts` — response-name overrides and path pinning are the parts a
  /// small language would model badly.
  ERequest(name~ : String, args~ : Array[@tutuca.Value])
  /// `sendAt &.status 'flash' 'Saved'` — at a POSITION, relative to this
  /// component. The steps are what `&` reified; the host concatenates its own
  /// path in front, exactly as the MoonBit idiom does by hand.
  ESendAt(
    steps~ : Array[@tutuca.Step],
    name~ : String,
    args~ : Array[@tutuca.Value]
  )
  /// `stop`
  EStop
} derive(Debug, Eq)

///|
/// What a name means while a body runs.
///
/// Three scopes, and they do not shadow each other: `.field` is state, a bare
/// name is a parameter, `@name` is a binding. That is the same separation the
/// sigils make in a template, which is why a reader needs no scoping rule.
pub(all) struct Env {
  /// This component's fields.
  state : Map[String, @tutuca.Value]
  /// The declaration's parameters, bound to the dispatch arguments.
  params : Map[String, @tutuca.Value]
  /// `@value`, `@key`, `@index`, `@iter`, and whatever an `enrich` produced.
  binds : Map[String, @tutuca.Value]
  /// What the block declares, so an application can reach a `pred` or a
  /// `compute`. Keyed by name; a `pred` and a `compute` share the namespace
  /// because both answer an application.
  callables : Map[String, @tscript.Decl]
  /// The component's declared schema, when there is one. Used for exactly one
  /// thing: an assignment into an integer field truncates, matching what the
  /// generated codec's decode does with the same value.
  schema : @tutuca.SchemaInfo?
  /// The zero of a type a `new` names, or None for a caller that supplied no
  /// resolver — which makes every `new` a transition that does not happen.
  ///
  /// A function rather than a table because building one needs a
  /// `@statedef.StateDef`, and this package deliberately does not see one: it
  /// ships inside every card runtime, and a schema resolver is exactly the
  /// weight it should not carry. Whoever HAS the schema passes the answer in.
  zero : ((@tscript.TyRef) -> @tutuca.Value?)?
}

///|
/// An environment over a state map, with nothing else bound.
declare pub fn Env::of_state(
  state : Map[String, @tutuca.Value],
  callables? : Map[String, @tscript.Decl],
  schema? : @tutuca.SchemaInfo,
  zero? : (@tscript.TyRef) -> @tutuca.Value?,
) -> Env

///|
/// What running a statement body produced.
///
/// `state` is None when the body did not finish — a missing key, an index past
/// the end, a name that did not resolve, a value of the wrong shape. That is
/// not an error path bolted on: it IS the framework's existing contract, the
/// `Unchanged` an `update` arm answers and the same thing every generated
/// mutator does when handed something it cannot use. Effects are dropped with
/// it, because half a transition is worse than none.
///
/// There is no `Unhandled` here on purpose: this type describes a body that
/// RAN, and whether a name has a body at all is decided by the caller before
/// it gets here.
pub(all) struct Outcome {
  state : Map[String, @tutuca.Value]?
  effects : Array[Effect]
  /// The BINDINGS the body ended with: what it was handed, plus every `@name`
  /// it assigned — never `@cur`, which `run` withholds. The target is a
  /// workbench, and a workbench is not something to hand a renderer.
  ///
  /// Here rather than mutated in place, for the same reason `state` is. A body
  /// runs against copies so that abandoning it costs nothing, which means an
  /// `enrich` — whose whole output is the binds it wrote — has no other way to
  /// hand them back. A caller that passed no binds and a body that wrote none
  /// both get an empty map.
  binds : Map[String, @tutuca.Value]
} derive(Debug, Eq)

///|
/// The outcome of a body that could not finish.
declare pub fn Outcome::nothing() -> Outcome

///|
/// Evaluate one expression. None when it could not be evaluated at all —
/// which is the same thing as the transition around it not happening.
declare pub fn eval(e : @tscript.Expr, env : Env) -> @tutuca.Value?

///|
/// Run a statement body against an environment.
declare pub fn run(body : Array[@tscript.Stmt], env : Env) -> Outcome

///|
/// Run a declaration whose body is one expression — a `compute` or a `pred`.
declare pub fn call(d : @tscript.Decl, env : Env) -> @tutuca.Value?

///|
/// Run a declaration whose body is statements, with `args` bound to its
/// parameters in order.
///
/// A body declaring more parameters than the dispatch carried binds the extras
/// to `Null` rather than refusing: an argument list is what a caller happened
/// to write, and the checker is where a disagreement with the schema is
/// reported.
declare pub fn dispatch(
  d : @tscript.Decl,
  args : Array[@tutuca.Value],
  env : Env,
) -> Outcome
