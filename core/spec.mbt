// Spec for tutuca's value parser.
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
// returns a Value, Ctx returns DispatchPath (whose Steps carry Val), and
// Value::Obj(&Obj) closes the loop. Breaking the cycle would mean removing
// obj_handler from Obj, which needs a trait-object downcast MoonBit doesn't
// have. The value_/path_ file prefixes are the intended organization.

///|
/// Literal constant payload (string | number | boolean | null)
pub(all) enum Lit {
  LNull
  LBool(Bool)
  LNum(Double)
  LStr(String)
} derive(Debug, Eq)

///|
/// One name an application may head: its arity, and what it does to
/// already-evaluated arguments.
///
/// The table lives in `value_builtin.mbt` and is reachable only through
/// `builtin` / `builtin_names`, so a caller sees a vocabulary rather than an
/// enum it would have to match exhaustively. `apply` is only ever called with
/// exactly `arity` arguments — the parser refuses anything else, which is what
/// lets the implementations index positionally.
pub struct Builtin {
  name : String
  arity : Int
  apply : (Array[Value]) -> Value
}

///|
/// Which namespace a handler name is looked up in.
///
/// `Receive` is the dispatch side — a name an `@on.<event>` raises, delivered
/// as an addressed message. `Alter` is the render side, where a name answers a
/// question about a row instead of changing anything.
pub(all) enum HandlerNamespace {
  Receive // @on.<event>
  Alter // @when, @enrich-with, @loop-with
} derive(Debug, Eq)

///|
/// A concrete sequence key: list index or map key (int|string)
pub(all) enum PathKey {
  KInt(Int)
  KStr(String)
} derive(Debug, Eq)

///|
/// Path steps: the ways one value addresses another.
///
/// `FieldStep` / `SeqAccessStep` are what an expression addresses
/// (`Val::to_path_item`); `SeqStep` is a field plus a concrete key, and also
/// the pinned form of a `SeqAccessStep`; `EachRenderItStep` is an iterated
/// render target that compacts to a `SeqStep`. Dynamic-var markers live on
/// `DispatchStep` in the path package.
///
/// EVERY step addresses something. The three that did not — a scope's binds, an
/// `@each` item's binds, a generic bind frame — are not steps and never were:
/// they said what a rebuilt render stack should have IN SCOPE, which is a
/// different question from where a value lives, and answering it here meant
/// every walk over a path carried a pass-through arm and every reader had to
/// know which steps were real. They are `FrameBind`s now, carried beside a
/// `DispatchFrame`'s items (`path_spec.mbt`).
pub(all) enum Step {
  FieldStep(String)
  SeqStep(field~ : String, key~ : PathKey)
  SeqAccessStep(seq_field~ : String, key_field~ : String)
  EachRenderItStep(field~ : String, key~ : PathKey)
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
/// Result of a synchronous public property write.
///
/// `PRefused` means the property exists and is writable, but its setter or a
/// child setter declined the transition. Refusal details travel through the
/// existing refusal recorder, so this value remains small and composable.
pub(all) enum PropertyWrite {
  PMissing
  PUnchanged
  PRefused
  PChanged(Value)
}

///|
/// A render-cache bucket for one instance: a structural fingerprint fixed when
/// the instance was created, and a revision bumped by each successor.
///
/// NOT an identity, and deliberately not unique. Two unrelated instances can
/// land on the same pair — two bundles loaded at runtime declaring the same
/// component, or two structurally equal siblings of one — and that is fine: a
/// bucket collision costs a MISS, never a wrong subtree, because the cache
/// validates its stored value by physical identity before returning it.
///
/// Giving up on uniqueness is what removes the need for a process-global
/// counter, and with it the question of how two independently loaded
/// components avoid clashing: they do not have to.
pub(all) struct ObjId {
  origin : UInt64
  /// 0 at creation, +1 per successor. Two generations of one instance differ
  /// here even when nothing else does, so a pass that still holds both does
  /// not make them fight for one bucket.
  rev : Int
} derive(Eq, Debug)

///|
/// The fingerprint of a freshly created instance: its component's schema
/// fingerprint mixed with the fields it starts with.
declare pub fn ObjId::of(
  fingerprint : String,
  fields : Map[String, Value],
) -> ObjId

///|
/// The successor's id: same origin, next revision.
declare pub fn ObjId::next(self : ObjId) -> ObjId

///|
/// The origin as 16 hex digits — for looking at, not for keying on.
declare pub fn ObjId::to_hex(self : ObjId) -> String

///|
/// Component-instance protocol (the port of JS's runtime Records tagged with
/// a hidden component symbol). ONE trait serves both hybrid representations:
/// the Value-backed Instance (component package) and user-defined typed
/// structs. Instances live INSIDE Value so they flow through every
/// Value-typed seam (binds, handler args, dynamic lookups, iterated seqs).
/// Fns returned by obj_field / obj_callable and the Handler returned
/// by obj_handler are SELF-PRE-BOUND (they close over the concrete Self —
/// the no-downcast analogue of late-bound `this`) and ignore args element 0.
/// Every method defaults to an empty/None answer.
pub(open) trait Obj {
  fn component_id(Self) -> Int? = _
  fn obj_field(Self, name : String) -> Value? = _ // fields; methods surface as pre-bound Fn
  fn obj_with_field(Self, name : String, v : Value) -> Value? = _ // COW -> Some(Obj(new_self))
  /// Read a declared public abstract property. This is distinct from
  /// `obj_field`: fields are representation; properties are interface.
  fn obj_property(Self, name : String) -> Value? = _
  /// Apply one synchronous, pure property transition.
  fn obj_set_property(Self, name : String, v : Value) -> PropertyWrite = _
  /// Read a virtual member for the component's own view. Unlike
  /// `obj_property`, this includes private properties. The stack-bearing form
  /// leaves room for computed members that resolve dynamic render bindings.
  fn obj_member_at(Self, name : String, stack : &Stack) -> Value? = _
  /// Apply a property transition from the component's own view. This is the
  /// private-capable counterpart of `obj_set_property`.
  fn obj_set_member(Self, name : String, v : Value) -> PropertyWrite = _
  /// Apply a collection/scalar operation to a private-or-public member from
  /// the component's own view. Operation names are source-level verbs such as
  /// `push`, `removeAt`, and `toggle`; generated handler spellings never cross
  /// this boundary.
  fn obj_mutate_member(
    Self,
    name : String,
    operation : String,
    args : Array[Value],
  ) -> PropertyWrite = _
  fn obj_item(Self, key : PathKey) -> Value? = _
  fn obj_with_item(Self, key : PathKey, v : Value) -> Value? = _
  // Custom-sequence hook (the analogue of SEQ_INFO): ordered (key, value)
  // entries so `@each` can iterate a non-List/Map Obj. None = not a sequence
  // (the default iteration falls back to empty). Keyed entries use KStr keys ("sk" breadcrumbs),
  // indexed ones KInt ("si"); obj_item resolves the same keys for path lookup.
  fn obj_seq_entries(Self) -> Array[(PathKey, Value)]? = _
  // The named CALLABLE this instance exposes for evaluation: the render-time
  // buckets (@when / @enrich-with / @loop-with) under Alter, and whatever
  // answers a bare name otherwise. Distinct from obj_handler, which resolves a
  // leaf-UPDATING handler in a dispatch bucket — different question, different
  // answer.
  fn obj_callable(Self, name : String, ns : HandlerNamespace) -> Value? = _
  // The two above, asked WITH the stack they are being asked from.
  //
  // A `Value::Fn` carries `(Array[Value]) -> Value` and nothing else, so a
  // body that reads `*name` — a `compute`, a `pred`, a `@when`, an `enrich` —
  // has no way to ask its environment anything. These are the one seam that
  // hands it one, and they exist as a PAIR because the two questions already
  // are one: `obj_field` surfaces a `$compute` as a pre-bound Fn and
  // `obj_callable` does the same for the render-time buckets.
  //
  // Defaulted to the stackless answer, so an `Obj` with nothing to do with a
  // stack — every hand-written one — implements neither and keeps working.
  fn obj_method_at(Self, name : String, stack : &Stack) -> Value? = _
  fn obj_callable_at(Self, name : String, ns : HandlerNamespace, stack : &Stack) -> Value? = _
  fn obj_handler(Self, bucket : HandlerBucket, name : String) -> Handler? = _ // dispatch buckets
  // What this instance DECLARES: the one method that makes the nine above
  // describable. Without it a holder of a bare `Value` can ask for a NAMED
  // field and nothing else — not which names exist, not what they hold — and
  // every consumer worked around that differently (a `Components` registry, a
  // hardcoded name list, a JSON projection).
  //
  // Answering `Some` is a claim that the schema names every field this
  // instance PUBLISHES, because the defaults below range over it: a field left
  // out is a field that does not exist as far as equality, the debug rendering
  // and the JSON form are concerned. None is the honest answer when even that
  // is more than can be said — an ad-hoc Obj standing in for a record.
  //
  // Keeping state the schema does not name is legal and ordinary — an opaque
  // guest's draft, a cursor, a parser's arena — and costs exactly one thing:
  // two instances that differ only there compare EQUAL. Nothing that detects
  // change may lean on that, which is why identity (`obj_identity`) rather
  // than equality is what decides whether a successor replaces its
  // predecessor.
  //
  // MUST return a STORED value, never build one: the defaults read it in loops.
  fn obj_schema(Self) -> SchemaInfo? = _
  // The sized half of the obj_seq_entries hook, so `size_of` stops answering
  // None for a custom collection. The default counts the entries; override
  // when the length is known without materializing them.
  fn obj_size(Self) -> Int? = _
  // This instance's render-cache bucket (see ObjId). None is the honest answer
  // for an ad-hoc Obj that does not track its own generations, and it is what
  // makes the cache DECLINE at that render site rather than build a key and
  // miss — the reintroduction condition benchmarks/OPTIMIZATIONS.md #8 sets.
  //
  // MUST return a STORED value, never compute one: it is read once per render
  // site per pass.
  fn obj_identity(Self) -> ObjId? = _
  fn obj_eq(Self, other : &Obj) -> Bool = _ // structural over the schema; false when there is none
  fn obj_debug(Self) -> String = _
  // What this instance is CALLED across sessions, if anything. `obj_identity`
  // is the render cache's bucket and is deliberately not this: it is a handle
  // and a revision, both of which are facts about this run of the program.
  // A persist id is the other kind of name — the one a store keys on, so that
  // the thing that comes back after a reload is the same thing.
  //
  // None is the honest answer for an instance nobody named, and it means "do
  // not store me" rather than "store me somewhere arbitrary": a key invented
  // at save time would not be found at load time.
  fn obj_persist_id(Self) -> String? = _
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
impl Obj with fn obj_property(_self, _name) {
  None
}

///|
impl Obj with fn obj_set_property(_self, _name, _v) {
  PMissing
}

///|
impl Obj with fn obj_member_at(self, name, _stack) {
  match self.obj_property(name) {
    Some(v) => Some(v)
    None => self.obj_field(name)
  }
}

///|
impl Obj with fn obj_set_member(self, name, v) {
  self.obj_set_property(name, v)
}

///|
impl Obj with fn obj_mutate_member(_self, _name, _operation, _args) {
  PMissing
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
impl Obj with fn obj_callable(_self, _name, _ns) {
  None
}

///|
/// The stack is what an implementer may WANT; not wanting it is the common
/// case, so the default is the question asked without it.
impl Obj with fn obj_method_at(self, name, _stack) {
  self.obj_field(name)
}

///|
impl Obj with fn obj_callable_at(self, name, ns, _stack) {
  self.obj_callable(name, ns)
}

///|
impl Obj with fn obj_handler(_self, _bucket, _name) {
  None
}

///|
impl Obj with fn obj_schema(_self) {
  None
}

///|
impl Obj with fn obj_size(self) {
  match self.obj_seq_entries() {
    Some(entries) => Some(entries.length())
    None => None
  }
}

///|
impl Obj with fn obj_identity(_self) {
  None
}

///|
impl Obj with fn obj_persist_id(_self) {
  None
}

///|
/// Structural equality over the DECLARED fields, both directions.
///
/// With a schema in hand the loop belongs here, once.
///
/// Still `false` without a schema: an Obj that declares nothing has not said
/// what equality would even range over, and answering `true` for two opaque
/// values is the worse mistake.
impl Obj with fn obj_eq(self, other) {
  guard self.obj_schema() is Some(schema) else { return false }
  if self.component_id() != other.component_id() {
    return false
  }
  for f in schema.fields {
    if self.obj_field(f.name) != other.obj_field(f.name) {
      return false
    }
  }
  true
}

///|
/// `Name{field: value, …}` from the schema; `<obj>` without one.
impl Obj with fn obj_debug(self) {
  guard self.obj_schema() is Some(schema) else { return "<obj>" }
  let sb = StringBuilder()
  sb.write_string(schema.name)
  sb.write_string("{")
  let mut first = true
  for f in schema.fields {
    if !first {
      sb.write_string(", ")
    }
    first = false
    sb.write_string(f.name)
    sb.write_string(": ")
    sb.write_string(
      match self.obj_field(f.name) {
        Some(v) => v.to_repr().to_string()
        None => "_"
      },
    )
  }
  sb.write_string("}")
  sb.to_string()
}

///|
/// Structural equality; Fn values are never equal.
declare pub impl Eq for Value

///|
/// Debug rendering for tests/diagnostics; Fn renders opaquely (RFn).
declare pub impl Debug for Value

///|
/// Evaluation environment (the `stack`). Every method defaults to Null so
/// implementations (and test mocks) provide only the lookups they use.
/// lookup_method returns the RESULT of the no-arg call — the stack invokes.
/// get_handler_for returns Null when no handler is registered.
pub(open) trait Stack {
  fn lookup_name(Self, String) -> Value = _
  /// Resolve `e.<segments>` against the event being handled.
  ///
  /// Separate from `lookup_name` because it asks a different question of a
  /// different thing: a name is looked up in the value language's own scopes,
  /// and this reaches OUT of them, at the one boundary where a view touches
  /// the DOM. Keeping them apart is what stops a bind or a field from ever
  /// shadowing an event read, or the other way round.
  ///
  /// Defaults to `Null`, so a stack with no event — every test that drives a
  /// handler with plain values — answers the same thing a path that does not
  /// resolve does.
  fn lookup_event_path(Self, Array[String]) -> Value = _
  fn lookup_bind(Self, String) -> Value = _
  fn lookup_dynamic(Self, String) -> Value = _
  fn lookup_field_raw(Self, String) -> Value = _
  /// `.name` in a value position: a private-or-public virtual property first,
  /// then the raw field fallback for record-like values.
  fn lookup_member(Self, String) -> Value = _
  fn lookup_method(Self, String) -> Value = _
  fn get_handler_for(Self, String, HandlerNamespace) -> Value = _
}

///|
impl Stack with fn lookup_name(_self, _name) {
  Null
}

///|
impl Stack with fn lookup_event_path(_self, _segments) {
  Null
}

///|
impl Stack with fn lookup_bind(_self, _name) {
  Null
}

///|
impl Stack with fn lookup_dynamic(_self, _name) {
  Null
}

///|
impl Stack with fn lookup_field_raw(_self, _name) {
  Null
}

///|
impl Stack with fn lookup_member(self, name) {
  self.lookup_field_raw(name)
}

///|
impl Stack with fn lookup_method(_self, _name) {
  Null
}

///|
impl Stack with fn get_handler_for(_self, _name, _namespace) {
  Null
}

///|
/// Stand-in for `eval(null)` on values that touch no stack
pub(all) struct NullStack {}

///|
pub impl Stack for NullStack

///|
/// Evaluate this value against a stack
declare pub fn Val::eval(self : Val, stack : &Stack) -> Value

///|
/// Value in handler position: Method hands back the raw function
/// (lookup_field_raw) instead of invoking; everything else is eval.
declare pub fn Val::eval_as_handler(self : Val, stack : &Stack) -> Value

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
/// The builtin a name denotes, or None when nothing does.
declare pub fn builtin(name : String) -> Builtin?

///|
/// Every builtin name, sorted — the vocabulary a suggestion ranges over.
declare pub fn builtin_names() -> Array[String]

///|
/// size_of: Some(length) for Str/List/Map, None for unsized values
declare pub fn size_of(v : Value) -> Int?
