// Spec for the view generator: the public data types plus `declare` stubs.
// Implementations live in split.mbt / surface.mbt / names.mbt / emit.mbt.
//
// The pipeline is three pure stages, the first of which now lives one package
// down in `viewfile` — a runtime that mounts a view file needs to find its
// blocks and has no use for an emitter:
//
//   source text  --@viewfile.split_file--> @viewfile.ViewFile (raw HTML, styles, blocks)
//                --view_surface---------->  Surface (handler names, args, ids)
//                --emit_module----------->   String (the generated .mbt)
//
// Each stage is independently testable; `generate` is the composition.

///|
/// What a generated payload position decodes to. `VValue` is the escape
/// hatch: the argument is not statically known (a field read, a `$method`,
/// an unrecognized `@bind`) or the call sites disagree.
pub(all) enum ArgType {
  VDouble
  VString
  VBool
  VValue
} derive(Eq, @debug.Debug)

///|
/// One `@on.<event>` handler name as referenced across all views, with the
/// argument shape inferred from its call sites. `args` is None when the call
/// sites disagree on arity — the variant then carries the raw argument list.
pub(all) struct InputSig {
  name : String
  args : Array[ArgType]?
  /// "@on.click" call sites, in document order — used for the doc comment.
  sites : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Everything the generator extracts from one file's compiled views.
pub(all) struct Surface {
  /// Bare `@on` handler names (the Input namespace), sorted.
  inputs : Array[InputSig]
  /// `$name` references anywhere in the views, sorted.
  methods : Array[String]
  /// State fields read at a view's root scope (see the caveat in emit.mbt).
  fields : Array[String]
  /// Constant `id` attributes, sorted.
  ids : Array[String]
  /// `@when` handler names on an `@each`, sorted. Split from the other alter
  /// directives rather than pooled with them because each bucket has its own
  /// handler signature — this one answers Bool.
  whens : Array[String]
  /// `@enrich-with` names INSIDE an `@each`: they mutate the binds map.
  enriches : Array[String]
  /// `@enrich-with` names with no `@each` around them: they RETURN the binds.
  enrich_scopes : Array[String]
  /// `@loop-with` names, sorted. They return a slice/order plan.
  loop_withs : Array[String]
} derive(Eq, @debug.Debug)

///|
/// Both generated modules from one shared view-compilation pass. `ir_source`
/// is absent for a schema-only file or when the compiled-tree emitter cannot
/// represent the views.
pub(all) struct GeneratedModules {
  types_source : String
  ir_source : String?
}

///|
/// Anything that makes generation impossible. Rendered by `Show` into the
/// message the CLI reports.
pub suberror GenError {
  /// The file does not split: its structure is wrong, or the state or init
  /// block it carries does not describe what it claims to. Wrapped rather
  /// than restated, so the two layers cannot drift into two wordings of one
  /// failure.
  File(@viewfile.FileError)
  /// The view does not parse, or parses with issues (a view that would warn
  /// at runtime is a generation failure — the types would be built on sand).
  ViewParseIssue(view~ : String, issue~ : String)
  /// A view is empty, so it has no root node to compile.
  EmptyView(String)
  /// Two source names capitalize to the same MoonBit variant.
  NameCollision(variant~ : String, first~ : String, second~ : String)
  /// `--name` is not usable as a MoonBit type prefix.
  BadComponentName(String)
  /// A schema-only file has no views to compile into a tree.
  NoViewsToCompile
  /// A `$name` in an `@on` handler position. It dispatches identically to
  /// the bare name (app/app.mbt collapses both into `push_input`), so the
  /// sigil suggests a second mechanism that does not exist.
  MethodInEventPosition(view~ : String, name~ : String, site~ : String)
  /// A view reads a name the schema does not declare. THE headline check:
  /// this used to render as null in the browser.
  UnknownStateField(
    view~ : String,
    name~ : String,
    scope~ : String,
    suggestion~ : String?
  )
  /// A constant `id` inside an `@each` body. The loop emits the body once per
  /// item, so the id is not unique the moment the sequence holds two.
  IdInLoop(view~ : String, id~ : String)
  /// `@show` / `@hide` over a container. `Value::is_truthy` answers `true`
  /// for List, Map and Obj unconditionally, so the test cannot fail — the
  /// element is always shown (or always hidden).
  AlwaysTruthy(
    view~ : String,
    directive~ : String,
    expr~ : String,
    ty~ : String
  )
  /// `@each` over something that is not a collection.
  NotIterable(view~ : String, expr~ : String, ty~ : String)
  /// `<x render>` on something that is not a component slot.
  NotRenderable(view~ : String, expr~ : String, ty~ : String)
  /// The `<script type="tutuca/script">` block does not parse. `line` is the
  /// line in the HTML file, not in the block, for the same reason a state
  /// block's is: that is the file the author has open.
  BadScriptBlock(comp~ : String, line~ : Int, message~ : String)
}

///|
/// The user-facing one-line message for a generation failure.
declare pub fn GenError::message(self : GenError) -> String

///|
/// Split an input file into the components it declares — `@viewfile.split_file`
/// with its failure wrapped as a `GenError`, so one pipeline has one error
/// type. See `viewfile` for what the conventions are.
declare pub fn split_file(
  source : String,
  name? : String,
) -> @viewfile.ViewFile raise GenError

///|
/// Compile the views and extract the typed surface. Every view is parsed into
/// a FRESH @anode.ParseContext with a collecting handler — the same shadow
/// discipline cli/lint_component.mbt uses, so no live component is touched.
declare pub fn view_surface(
  views : Array[@viewfile.RawView],
  macros? : Array[@viewfile.MacroDef],
) -> Surface raise GenError

///|
/// Emit the generated MoonBit module.
/// `hints` collects ADVISORY findings the schema check turns up — the ones a
/// `slots~` entry naming a bare `component` slot could legitimately defeat, so
/// they are reported rather than raised. Pass the caller's diagnostics array; omit it and they
/// are discarded, which is what a caller with nowhere to print them wants.
declare pub fn emit_module(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
  debug_derive? : Bool,
  hints? : Array[String],
  program? : ProgramIndex,
) -> String raise GenError

///|
/// Compile every view once, then emit the types module and optional compiled
/// tree module from the same roots and event tables. This is the preferred
/// entry point for build tools that need both outputs.
declare pub fn emit_modules(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
  include_ir? : Bool,
  debug_derive? : Bool,
  hints? : Array[String],
  program? : ProgramIndex,
) -> GeneratedModules raise GenError

///|
/// True when every view can be emitted as a compiled tree. A view whose tree
/// still holds a macro call cannot: macros are registered from MoonBit at
/// runtime, so the generator cannot expand them.
declare pub fn ir_supported(file : @viewfile.ViewFile) -> Bool

///|
/// Emit the companion IR module: the @anode.ANode tree and event table each
/// view parses into, written with anode's builders (`@anode.h` / `text` /
/// `attr` / `on` …), plus the `<v>_views()` builder (passed as `views~`).
/// Only valid when `ir_supported` holds.
declare pub fn emit_ir_module(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
) -> String raise GenError

///|
/// The companion IR module, or None when the file cannot be emitted as compiled
/// trees — `ir_supported` and `emit_ir_module` in one pass.
///
/// Prefer this to the pair: they compile every view separately, so asking the
/// question costs as much as emitting the answer. `ir_supported` remains for
/// callers that only want to know.
declare pub fn emit_ir_module_opt(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
) -> String?

///|
/// Build the compiled views directly, skipping codegen — the same value the
/// emitted IR module reconstructs.
declare pub fn build_views(
  views : @viewfile.ViewSet,
  macros? : Array[@viewfile.MacroDef],
) -> Map[String, @anode.View] raise GenError

///|
/// The whole pipeline: input file text -> generated MoonBit source.
declare pub fn generate(
  source : String,
  name~ : String,
  source_file~ : String,
) -> String raise GenError

///|
/// The component names a file gives views to. A schema interface outside
/// this set declares state for a component whose views are built in MoonBit.
declare pub fn declared_components(
  file : @viewfile.ViewFile,
  name : String,
) -> Array[String]
