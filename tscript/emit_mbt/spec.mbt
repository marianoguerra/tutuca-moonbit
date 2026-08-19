// Spec for the MoonBit backend. READONLY by convention; the implementation is
// in emit.mbt.

///|
/// A declaration this backend will not compile, and why.
///
/// Refusals are DATA and are part of the answer, not an error beside it. A
/// script block with one handler that reaches for `walk_path` still has five
/// that compile, and the generator's job is to emit those and say which one
/// the author writes by hand — which is the same shape `Card` takes with its
/// issues, and for the same reason.
pub(all) struct Refusal {
  /// The declaration's name, as the author wrote it.
  name : String
  /// What cannot be compiled, and what to do instead.
  why : String
  span : @tscript.Span
} derive(Debug, Eq)

///|
/// Which generated bucket each declared name is reached through.
///
/// The caller knows and this cannot: a `pred` is one declaration and up to two
/// functions, because `@when="matches"` hands it the row and `@show="$matches"`
/// does not, and only the VIEWS say which of those happens. Emitting both
/// unasked would put a function nobody calls in a generated file, which is a
/// warning; emitting neither is the bug this exists to fix.
///
/// Empty lists mean "the views name none of these", so a block whose caller
/// passes `Roles::none()` compiles its transitions and nothing else — which is
/// what every caller did before value bodies were compiled at all.
pub(all) struct Roles {
  /// `$name` in a value slot, and every `compute`.
  methods : Array[String]
  /// `@when="name"` — a `pred` with the row in scope.
  whens : Array[String]
  /// `@enrich-with="name"` inside a loop.
  enriches : Array[String]
  /// `@enrich-with="name"` on a scope.
  enrich_scopes : Array[String]
} derive(Debug, Eq)

///|
/// No name is reached through anything: transitions only.
declare pub fn Roles::none() -> Roles

///|
/// The four shapes a value body is compiled into, which differ in what is in
/// scope and what comes back.
pub(all) enum Role {
  RMethod
  RWhen
  REnrich
  REnrichScope
} derive(Debug, Eq, Hash, Compare)

///|
/// The generated function's name for one declaration in one role.
///
/// Both sides of the seam call this rather than agreeing on a convention:
/// `emit` writes the functions and the generator writes the `match` that
/// routes to them.
declare pub fn value_fn_name(
  prefix : String,
  role : Role,
  name : String,
) -> String

///|
/// What the backend produced.
pub(all) struct Emitted {
  /// The whole `<v>_inline_update` function, followed by one function per
  /// value body that compiled — or "" when nothing compiled.
  ///
  /// Empty rather than absent when every declaration was refused, because a
  /// caller that emitted an unused function would have to explain it to
  /// `moon check`.
  source : String
  /// The names this function ANSWERS, by bucket. What the generator needs in
  /// order to trim the bucket enums: a name answered here must not also
  /// appear as a variant the author is asked to write an arm for.
  answers_input : Array[String]
  answers_receive : Array[String]
  answers_intent : Array[String]
  answers_bubble : Array[String]
  answers_response : Array[String]
  /// The value bodies that compiled, by role — what the generator routes to.
  /// A name asked for in `Roles` and missing here was refused, and its
  /// `Refusal` says why.
  answers_methods : Array[String]
  answers_whens : Array[String]
  answers_enriches : Array[String]
  answers_enrich_scopes : Array[String]
  refusals : Array[Refusal]
} derive(Debug, Eq)

///|
/// Compile a script block against a schema.
///
/// `state_ty` is the generated state struct's name (`CounterState`), `fn_name`
/// the function to emit. `surface` supplies the argument types the views imply,
/// exactly as it does for the checker — an `on` handler whose types are not
/// known binds its parameters as raw `@tutuca.Value`, and any TYPED use of one
/// is refused rather than guessed.
/// `prefix` names the value-body functions (`<prefix>_compute_over`), and
/// `roles` says which of them to write. A caller that wants transitions only
/// passes neither.
declare pub fn emit(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  state_ty~ : String,
  fn_name~ : String,
  prefix? : String,
  roles? : Roles,
  surface? : @check.Surface,
) -> Emitted
