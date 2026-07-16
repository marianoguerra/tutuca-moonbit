// Spec for the port of tutuca's value parser (src/value.js).
// READONLY by convention: concrete public data types plus `declare` stubs for
// every function/method. Implement the declares in separate files; this file
// and the value_*_test.mbt suites define the contract.
//
// Why the value layer (this file, value_*.mbt) and the path layer
// (path_spec.mbt, path_*.mbt) share ONE package (this `core/` package)
// instead of splitting into value/ and path/ subpackages: their core types
// form a single dependency
// cycle that MoonBit packages cannot express across an import edge —
// Obj::obj_handler returns Handler (path side), Handler carries &Ctx and
// &PathNode, Ctx returns DispatchPath (whose Steps carry Val), and
// Value::Obj(&Obj) closes the loop. Breaking the cycle would mean removing
// obj_handler from Obj, which needs a trait-object downcast MoonBit doesn't
// have. The value_/path_ file prefixes are the intended organization.

///|
/// Literal constant payload (JS ConstVal.val: string | number | boolean | null)
pub(all) enum Lit {
  LNull
  LBool(Bool)
  LNum(Double)
  LStr(String)
} derive(Debug, Eq)

///|
/// Boolean predicates usable in conditional slots (JS PREDICATES table)
pub(all) enum Pred {
  IsEmpty // "empty?"  arity 1
  IsTruthy // "truthy?" arity 1
  IsFalsy // "falsy?"  arity 1
  IsNull // "null?"   arity 1
  Equals // "equals?" arity 2
} derive(Debug, Eq)

///|
/// Handler namespaces are a fixed enumeration (JS passes "input"/"alter" strings)
pub(all) enum HandlerNamespace {
  Input // @on.<event>
  Alter // @when, @enrich-with, @loop-with
} derive(Debug, Eq)

///|
/// Parsed value AST. One variant per JS BaseVal subclass. `from_macro` ports
/// ConstVal.fromMacroVar: set when a `^name` macro var resolves to a constant,
/// which makes an enclosing template non-literal. StrTpl parts alternate text
/// constants and placeholder expressions; a `None` part is a placeholder whose
/// inner expression failed to parse (JS keeps null there).
pub(all) enum Val {
  Const(lit~ : Lit, from_macro~ : Bool)
  StrTpl(Array[Val?])
  Predicate(pred~ : Pred, args~ : Array[Val])
  Name(String) // bare lowercase name
  HandlerName(name~ : String, ns~ : HandlerNamespace)
  TypeName(String) // bare Uppercase name
  Bind(String) // @name
  BindMember(name~ : String, prop~ : String) // @name.member (one level)
  Dyn(String) // *name
  Field(String) // .name
  Method(String) // $name
  SeqAccess(seq~ : String, key~ : String) // .seq[.key] (both plain fields)
} derive(Debug, Eq)

///|
/// A concrete sequence key: list index or map key (JS SeqStep.key is int|string)
pub(all) enum PathKey {
  KInt(Int)
  KStr(String)
} derive(Debug, Eq)

///|
/// Path steps (src/path.js). FieldStep/SeqAccessStep are what values address
/// (Val::to_path_item); SeqStep is a field + concrete key (also the pinned form
/// of SeqAccessStep); EachRenderItStep is an iterated render target that
/// compacts to a SeqStep; Bind/ScopeBind/EachBind are frame-only (stack
/// rebuild). Dynamic-var markers live on DispatchStep in the path package.
pub(all) enum Step {
  FieldStep(String)
  SeqStep(field~ : String, key~ : PathKey)
  SeqAccessStep(seq_field~ : String, key_field~ : String)
  EachRenderItStep(field~ : String, key~ : PathKey)
  // Frame-only: addresses no field (lookup/set pass through), exists so a
  // rebuilt stack can replay the scope bindings a render frame introduced.
  BindStep(binds~ : Map[String, Value])
  // Frame-only: replays a loop-less @enrich-with scope by re-evaluating
  // `val` as a handler against the rebuilt stack (binds computed lazily at
  // rebuild time, matching the renderer).
  ScopeBindStep(val~ : Val)
  // Frame-only: replays the renderer's per-item binds ({key, value} plus any
  // @enrich-with binds) for the @each item addressed by `key`. Carries the
  // iteration Vals (JS IterInfo) so binds are computed lazily at rebuild
  // time; loop-with is deferred with the renderer's @loop-with support.
  EachBindStep(
    val~ : Val,
    when_val~ : Val?,
    enrich_with_val~ : Val?,
    loop_with_val~ : Val?,
    key~ : PathKey
  )
} derive(Debug, Eq)

///|
/// Dynamic runtime value: what eval(stack) reads and returns.
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  List(Array[Value])
  Map(Map[String, Value])
  Fn((Array[Value]) -> Value) // handler / raw-function values
  Obj(&Obj) // component instance (see trait Obj — the hybrid seam)
}

///|
/// Component-instance protocol (the port of JS's runtime Records tagged with
/// a hidden component symbol). ONE trait serves both hybrid representations:
/// the Value-backed Instance (component package) and user-defined typed
/// structs. Instances live INSIDE Value so they flow through every
/// Value-typed seam (binds, handler args, dynamic lookups, iterated seqs).
/// Fns returned by obj_field / obj_render_handler and the Handler returned
/// by obj_handler are SELF-PRE-BOUND (they close over the concrete Self —
/// the no-downcast analogue of JS late `this`) and ignore args element 0.
/// Every method defaults to an empty/None answer.
pub(open) trait Obj {
  fn component_id(Self) -> Int? = _
  fn obj_field(Self, name : String) -> Value? = _ // fields; methods surface as pre-bound Fn
  fn obj_with_field(Self, name : String, v : Value) -> Value? = _ // COW -> Some(Obj(new_self))
  fn obj_item(Self, key : PathKey) -> Value? = _
  fn obj_with_item(Self, key : PathKey, v : Value) -> Value? = _
  // Custom-sequence hook (the port of JS SEQ_INFO): ordered (key, value)
  // entries so `@each` can iterate a non-List/Map Obj. None = not a sequence
  // (the JS unkIter default). Keyed entries use KStr keys ("sk" breadcrumbs),
  // indexed ones KInt ("si"); obj_item resolves the same keys for path lookup.
  fn obj_seq_entries(Self) -> Array[(PathKey, Value)]? = _
  fn obj_render_handler(Self, name : String, ns : HandlerNamespace) -> Value = _ // alter bucket
  fn obj_handler(Self, bucket : HandlerBucket, name : String) -> Handler? = _ // dispatch buckets
  fn obj_eq(Self, other : &Obj) -> Bool = _ // structural; false by default (Fn precedent)
  fn obj_debug(Self) -> String = _
}

///|
impl Obj with fn component_id(_self) {
  None
}

///|
impl Obj with fn obj_field(_self, _name) {
  None
}

///|
impl Obj with fn obj_with_field(_self, _name, _v) {
  None
}

///|
impl Obj with fn obj_item(_self, _key) {
  None
}

///|
impl Obj with fn obj_with_item(_self, _key, _v) {
  None
}

///|
impl Obj with fn obj_seq_entries(_self) {
  None
}

///|
impl Obj with fn obj_render_handler(_self, _name, _ns) {
  Value::Null
}

///|
impl Obj with fn obj_handler(_self, _bucket, _name) {
  None
}

///|
impl Obj with fn obj_eq(_self, _other) {
  false
}

///|
impl Obj with fn obj_debug(_self) {
  "<obj>"
}

///|
/// Structural equality (immutable.js `is`); Fn values are never equal.
declare pub impl Eq for Value

///|
/// Debug rendering for tests/diagnostics; Fn renders opaquely (RFn).
declare pub impl Debug for Value

///|
/// Evaluation environment (JS `stack`). Every method defaults to Null so
/// implementations (and test mocks) provide only the lookups they use.
/// lookup_method returns the RESULT of the no-arg call — the stack invokes.
/// get_handler_for returns Null when no handler is registered.
pub(open) trait Stack {
  fn lookup_name(Self, String) -> Value = _
  fn lookup_bind(Self, String) -> Value = _
  fn lookup_dynamic(Self, String) -> Value = _
  fn lookup_field_raw(Self, String) -> Value = _
  fn lookup_method(Self, String) -> Value = _
  fn lookup_type(Self, String) -> Value = _
  fn get_handler_for(Self, String, HandlerNamespace) -> Value = _
}

///|
impl Stack with fn lookup_name(_self, _name) {
  Value::Null
}

///|
impl Stack with fn lookup_bind(_self, _name) {
  Value::Null
}

///|
impl Stack with fn lookup_dynamic(_self, _name) {
  Value::Null
}

///|
impl Stack with fn lookup_field_raw(_self, _name) {
  Value::Null
}

///|
impl Stack with fn lookup_method(_self, _name) {
  Value::Null
}

///|
impl Stack with fn lookup_type(_self, _name) {
  Value::Null
}

///|
impl Stack with fn get_handler_for(_self, _name, _namespace) {
  Value::Null
}

///|
/// Stand-in for JS `eval(null)` on values that touch no stack
pub(all) struct NullStack {}

///|
pub impl Stack for NullStack

///|
/// JS onParseIssue kind — only "bad-value" occurs in value.js; other kinds
/// (x-op, x-attr, …) join this enum when their modules are ported.
pub(all) enum IssueKind {
  BadValue
} derive(Debug, Eq)

///|
/// What was malformed (JS `info.role`)
pub(all) enum IssueRole {
  BadMacroVar // "macro-var": unknown ^name
  BadHandlerName // "handler-name"
  BadHandlerArg // "handler-arg"
  UnknownPredicate // "predicate"
  PredicateArity(Pred) // "predicate-arity": wrong arg count for this predicate
  BadPredicateArg // "predicate-arg"
} derive(Debug, Eq)

///|
/// A parse issue, collected on the ParseCtx (JS px.onParseIssue callback)
pub(all) struct Issue {
  kind : IssueKind
  role : IssueRole
  value : String // offending token / source string
} derive(Debug, Eq)

///|
/// Parse context (JS `px`): macro variables in scope plus collected issues
pub struct ParseCtx {
  macro_vars : Map[String, String]
  issues : Array[Issue]
}

///|
declare pub fn ParseCtx::new(macro_vars? : Map[String, String]) -> ParseCtx

///|
/// Split a value source string into tokens: `$'…'` template runs and `'…'`
/// literal runs (escapes kept) stay single tokens; otherwise maximal
/// non-whitespace runs. An unterminated quote falls back to a plain run.
declare pub fn tokenize_value(s : String) -> Array[String]

///|
/// Parse a single token into the richest Val it can be, with no context/kind
/// filtering. None when the token is not a well-formed value.
declare pub fn parse_token(s : String, ctx : ParseCtx) -> Val?

///|
/// Conditionals (@show, @hide, @if.<attr>, …): a single token is a plain
/// boolean-group value; multiple tokens are a predicate call `empty? .items`.
declare pub fn parse_bool(s : String, ctx : ParseCtx) -> Val?

///|
/// Text values (:attr, @text, <x text>, @then/@else, @push-view, @html)
declare pub fn parse_text(s : String, ctx : ParseCtx) -> Val?

///|
/// A single component to render (<x render>)
declare pub fn parse_component(s : String, ctx : ParseCtx) -> Val?

///|
/// A sequence to iterate (@each, <x render-each>)
declare pub fn parse_sequence(s : String, ctx : ParseCtx) -> Val?

///|
/// A `provide:` field definition or `lookup` default: field, seq-access,
/// method reference, or constant.
declare pub fn parse_field(s : String, ctx : ParseCtx) -> Val?

///|
/// A `provide:` value — addressable kinds only (field or seq-access)
declare pub fn parse_provide(s : String, ctx : ParseCtx) -> Val?

///|
/// A single argument passed to an event handler
declare pub fn parse_handler_arg(s : String, ctx : ParseCtx) -> Val?

///|
/// Pass-through values on a macro-call element (:attr on a macro)
declare pub fn parse_macro_attr(s : String, ctx : ParseCtx) -> Val?

///|
/// Handler reference plus parsed args for @on.<event>
pub(all) struct HandlerParse {
  handler : Val
  args : Array[Val]
} derive(Debug, Eq)

///|
/// `$name` → Method, bare name → HandlerName(Input); args allowed, a bad arg
/// becomes Const(LNull) and reports an issue.
declare pub fn parse_input_handler(s : String, ctx : ParseCtx) -> HandlerParse?

///|
/// Handler for @when/@enrich-with/@loop-with: no args, silent on failure
declare pub fn parse_alter_handler(s : String, ctx : ParseCtx) -> Val?

///|
/// Evaluate this value against a stack
declare pub fn Val::eval(self : Val, stack : &Stack) -> Value

///|
/// Value in handler position: Method hands back the raw function
/// (lookup_field_raw) instead of invoking; everything else is eval.
declare pub fn Val::eval_as_handler(self : Val, stack : &Stack) -> Value

///|
/// Render-slot value: Some(eval) for renderable kinds, None where the JS
/// BaseVal.render returns undefined (Name, HandlerName, TypeName, Predicate).
declare pub fn Val::render(self : Val, stack : &Stack) -> Value?

///|
/// Path step for path-bearing slots: Field and SeqAccess only
declare pub fn Val::to_path_item(self : Val) -> Step?

///|
/// True for constants and for templates whose every part is a plain
/// non-macro constant (a literal written the long way).
declare pub fn Val::is_literal(self : Val) -> Bool

// NOTE(dropped): Val::to_literal_source (the equivalent `'…'` source literal
// of a literal StrTpl) was removed as dead code; re-add it when the
// PLACEHOLDERLESS_TEMPLATE_STRING lint rule is ported — it exists to power
// that nudge.

///|
/// Source round-trip: every Val prints back as its original syntax
declare pub impl Show for Val

///|
declare pub fn Pred::of_name(name : String) -> Pred?

///|
/// Source name: "empty?", "truthy?", "falsy?", "null?", "equals?"
declare pub fn Pred::name(self : Pred) -> String

///|
declare pub fn Pred::arity(self : Pred) -> Int

///|
/// Apply the predicate to already-evaluated args (length must equal arity)
declare pub fn Pred::apply(self : Pred, args : Array[Value]) -> Bool

///|
/// JS sizeOf: Some(length) for Str/List/Map, None for unsized values
declare pub fn size_of(v : Value) -> Int?
