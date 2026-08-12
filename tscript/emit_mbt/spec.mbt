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
/// What the backend produced.
pub(all) struct Emitted {
  /// The whole `<v>_inline_update` function, or "" when nothing compiled.
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
  answers_bubble : Array[String]
  answers_response : Array[String]
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
declare pub fn emit(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  state_ty~ : String,
  fn_name~ : String,
  surface? : @check.Surface,
) -> Emitted
