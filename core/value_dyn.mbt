// Generic access to a value whose shape is not known at the call site: read a
// field or an item, coerce a scalar, write one back, ask how big a sequence is,
// iterate it, call a method, name the fields.
//
// These are FREE FUNCTIONS over the `Obj` primitives, not trait methods. A
// trait method has to be implemented once per type; a function over the
// primitives is written once and every implementor gets it — which is what
// keeps the implementation side at "answer `obj_field`, and `obj_schema` if
// you have one".
//
// The container triple — `(List, KInt) | (Map, KStr) | (Obj, obj_item)` — used
// to be written out at each call site: the renderer's keyed lookup, the stack
// rebuild, the path traversal, the seq-access evaluator. The evaluator's copy
// had already lost its `Obj` arm, so `.songs[.currentKey]` returned Null on a
// custom collection while `@each` iterated it fine. It lives here now.
//
// EVERY accessor comes in two forms, and the `_opt` one is the primitive: the
// total form is `_opt(...).unwrap_or(default)`, never a second match over the
// same shapes. The two used to live in two files (this one and
// value_access.mbt) as independent matches — the exact arrangement whose
// drift the paragraph above is about. Use `_opt` when absent has to be told
// apart from present-but-empty, the total form when it does not, and a `match`
// when the shape distinction is the point.

///|
/// A field, or None when there is no such field. `Map` and `Obj` answer,
/// anything else has no fields.
pub fn Value::field_opt(self : Value, name : String) -> Value? {
  match self {
    Map(m) => m.get(name)
    Obj(o) => o.obj_field(name)
    _ => None
  }
}

///|
/// Field access that works on Map values and Obj instances alike; Null for
/// anything else (including missing fields).
pub fn Value::field(self : Value, name : String) -> Value {
  self.field_opt(name).unwrap_or(Null)
}

///|
/// An item by key: a list index, a map key, or whatever a custom collection
/// resolves through `obj_item`. None when there is no such item.
pub fn Value::item_opt(self : Value, key : PathKey) -> Value? {
  match (self, key) {
    (List(a), KInt(i)) =>
      if i >= 0 && i < a.length() {
        Some(a[i])
      } else {
        None
      }
    (Map(m), KStr(s)) => m.get(s)
    (Obj(o), k) => o.obj_item(k)
    _ => None
  }
}

///|
/// An item by key, or the default.
pub fn Value::item(
  self : Value,
  key : PathKey,
  default? : Value = Null,
) -> Value {
  self.item_opt(key).unwrap_or(default)
}

///|
/// This value AS a sequence key: a string keys a map, an integral number
/// indexes a list. None for everything else — including a non-integral number,
/// which is not an index and must not be rounded into one.
///
/// The bridge between the value world and the addressing world: it is how a
/// `.seq[.key]` read turns the key FIELD into the key it looks up, and how the
/// renderer names an iterated item in its `§Each§` breadcrumb.
pub fn Value::as_key(self : Value) -> PathKey? {
  match self {
    Str(s) => Some(KStr(s))
    Num(n) => {
      let i = n.to_int()
      if i.to_double() == n {
        Some(KInt(i))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// `v.index(2)` — an item by position.
pub fn Value::index(self : Value, i : Int, default? : Value = Null) -> Value {
  self.item(KInt(i), default~)
}

///|
/// `v.key("id")` — an item by name. Distinct from `field`: a `Map` answers
/// both, but a component instance keys its SEQUENCE here and its FIELDS there.
pub fn Value::key(self : Value, k : String, default? : Value = Null) -> Value {
  self.item(KStr(k), default~)
}

///|
// ---------------------------------------------------------------------------
// Scalar coercion
// ---------------------------------------------------------------------------
//
// The `_opt` form is the one that carries the shape test. `int(default=0)`
// cannot say whether the 0 was stored or invented, and a caller assembling an
// Option — an optional slice bound, a key list that may be absent — needs to;
// a caller reading a handler arg does not, and takes the total form.

///|
pub fn Value::int_opt(self : Value) -> Int? {
  match self {
    Num(n) => Some(n.to_int())
    _ => None
  }
}

///|
pub fn Value::int(self : Value, default? : Int = 0) -> Int {
  self.int_opt().unwrap_or(default)
}

///|
pub fn Value::num_opt(self : Value) -> Double? {
  match self {
    Num(n) => Some(n)
    _ => None
  }
}

///|
pub fn Value::num(self : Value, default? : Double = 0) -> Double {
  self.num_opt().unwrap_or(default)
}

///|
pub fn Value::str_opt(self : Value) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
pub fn Value::str(self : Value, default? : String = "") -> String {
  self.str_opt().unwrap_or(default)
}

///|
pub fn Value::bool_opt(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
pub fn Value::bool(self : Value, default? : Bool = false) -> Bool {
  self.bool_opt().unwrap_or(default)
}

///|
pub fn Value::list_opt(self : Value) -> Array[Value]? {
  match self {
    List(a) => Some(a)
    _ => None
  }
}

///|
/// The list payload; [] for non-lists (shared empty NOT returned — fresh).
pub fn Value::list(self : Value) -> Array[Value] {
  self.list_opt().unwrap_or([])
}

///|
pub fn Value::map_opt(self : Value) -> Map[String, Value]? {
  match self {
    Map(m) => Some(m)
    _ => None
  }
}

///|
/// The map payload; empty for non-maps (fresh, like `Value::list`).
pub fn Value::map(self : Value) -> Map[String, Value] {
  self.map_opt().unwrap_or(Map([]))
}

// ---------------------------------------------------------------------------
// Copy-on-write writes
// ---------------------------------------------------------------------------
//
// Writing back a value physically identical to the one already stored hands
// back THIS value, not a copy. Identity is what the transactor reads as
// "nothing happened", and it is what lets the spine rebuild above a write
// collapse level by level, so an accessor must not be the thing that breaks
// it.

///|
/// Copy-on-write field write; None when there is no such field to write (no
/// such field on an instance, not a container at all). The partial form is
/// what `step_put` needs: a step that cannot be addressed must leave the whole
/// tree untouched rather than silently write nothing.
pub fn Value::with_field_opt(self : Value, name : String, v : Value) -> Value? {
  match self {
    Map(m) => {
      if m.get(name) is Some(old) && physical_equal(old, v) {
        return Some(self)
      }
      let out = m.copy()
      out[name] = v
      Some(Map(out))
    }
    Obj(o) => o.obj_with_field(name, v)
    _ => None
  }
}

///|
/// Copy-on-write field write, total: the value unchanged when the field cannot
/// be written.
pub fn Value::with_field(self : Value, name : String, v : Value) -> Value {
  self.with_field_opt(name, v).unwrap_or(self)
}

///|
/// Copy-on-write item write; None when the key addresses no item (an index out
/// of range, a key of the wrong kind for the container).
pub fn Value::with_item_opt(self : Value, key : PathKey, v : Value) -> Value? {
  match (self, key) {
    (List(a), KInt(i)) => {
      if i < 0 || i >= a.length() {
        return None
      }
      if physical_equal(a[i], v) {
        return Some(self)
      }
      let out = a.copy()
      out[i] = v
      Some(List(out))
    }
    (Map(m), KStr(s)) => {
      if m.get(s) is Some(old) && physical_equal(old, v) {
        return Some(self)
      }
      let out = m.copy()
      out[s] = v
      Some(Map(out))
    }
    (Obj(o), k) => o.obj_with_item(k, v)
    _ => None
  }
}

///|
/// Copy-on-write item write, total. Same identity contract as `with_field`.
pub fn Value::with_item(self : Value, key : PathKey, v : Value) -> Value {
  self.with_item_opt(key, v).unwrap_or(self)
}

// ---------------------------------------------------------------------------
// Sequences
// ---------------------------------------------------------------------------

///|
/// How many items, or 0. The total form of `size_of`.
pub fn Value::size(self : Value, default? : Int = 0) -> Int {
  size_of(self).unwrap_or(default)
}

///|
/// The ordered (key, value) entries of any container: a list keyed by index, a
/// map by name, a custom collection by whatever `obj_seq_entries` says. Empty
/// for anything that is not one (the JS unkIter default).
///
/// TOOLING and one-off use: this materializes. The renderer's `@each` keeps
/// indexing `List` and `Map` directly, because allocating a tuple per item on
/// every render is not what a convenience is for.
pub fn Value::entries(self : Value) -> Array[(PathKey, Value)] {
  match self {
    List(a) => {
      let out : Array[(PathKey, Value)] = []
      for i, v in a {
        out.push((KInt(i), v))
      }
      out
    }
    Map(m) => {
      let out : Array[(PathKey, Value)] = []
      for k, v in m {
        out.push((KStr(k), v))
      }
      out
    }
    Obj(o) => o.obj_seq_entries().unwrap_or([])
    _ => []
  }
}

// ---------------------------------------------------------------------------
// Calling
// ---------------------------------------------------------------------------

///|
/// Call a function value under the Fn convention: element 0 of the argument
/// array is the `this` slot, which self-pre-bound callees ignore. Null for a
/// non-function.
///
/// The convention was hand-rolled at every call site — `match v { Fn(f) =>
/// f([Null, x]) ... }` — with the dummy slot spelled out each time.
pub fn Value::call(
  self : Value,
  args : Array[Value],
  this? : Value = Null,
) -> Value {
  match self {
    Fn(f) => {
      let full = [this]
      full.append(args)
      f(full)
    }
    _ => Null
  }
}

///|
/// Call a method OF this value, with this value in the `this` slot: the
/// `$name` read followed by the invocation, which is how a view calls one and
/// how a handler filters a list of instances it cannot downcast.
pub fn Value::call_field(
  self : Value,
  name : String,
  args : Array[Value],
) -> Value {
  self.field(name).call(args, this=self)
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

///|
/// What this value DECLARES, when it is a component instance that says.
pub fn Value::schema(self : Value) -> SchemaInfo? {
  match self {
    Obj(o) => o.obj_schema()
    _ => None
  }
}

///|
/// The declared description of one field.
pub fn Value::field_info(self : Value, name : String) -> FieldInfo? {
  match self.schema() {
    Some(s) => s.field(name)
    None => None
  }
}

///|
/// Every field name: declaration order for a described instance, key order for
/// a Map, empty for anything else (including an instance that declares
/// nothing — "no schema" is not "no fields", and guessing is what the schema
/// work removed).
pub fn Value::field_names(self : Value) -> Array[String] {
  match self {
    Obj(o) =>
      match o.obj_schema() {
        Some(s) => s.field_names()
        None => []
      }
    Map(m) => {
      let out : Array[String] = []
      for k, _ in m {
        out.push(k)
      }
      out
    }
    _ => []
  }
}

///|
/// name -> value for every declared field, in declaration order.
///
/// What every consumer that wanted to SHOW an instance had been faking: the
/// inspector read the names off a `Components` registry, the example builder
/// took them as a parameter, the dyncomp host parsed them out of a JSON
/// projection.
pub fn Value::snapshot(self : Value) -> Map[String, Value] {
  let out : Map[String, Value] = Map([])
  for name in self.field_names() {
    out[name] = self.field(name)
  }
  out
}

// ---------------------------------------------------------------------------
// By path
// ---------------------------------------------------------------------------

///|
/// The value at a path, or Null at the first step that does not resolve.
///
/// This is the composition, not a new primitive: one-hop reads stay
/// `field`/`item`, because building a one-element Path to replace a match
/// costs three allocations. Reach for a Path when the ADDRESS is the thing
/// being passed around — a transaction target, an observed change, a test's
/// assertion site.
pub fn Value::at(self : Value, p : Path) -> Value {
  self.at_opt(p).unwrap_or(Null)
}

///|
/// The value at a path, distinguishing "no such place" from a Null stored
/// there — the one distinction `at` cannot express and no coercer can recover.
pub fn Value::at_opt(self : Value, p : Path) -> Value? {
  p.lookup(self)
}

///|
/// Copy-on-write write at a path, total: the SAME value back when the path
/// does not resolve (`Path::set_value`'s own contract).
pub fn Value::with_at(self : Value, p : Path, v : Value) -> Value {
  p.set_value(self, v)
}
