// Val evaluation and Value runtime semantics (eval side +
// PREDICATES table + immutable `is`). Implements the declares in spec.mbt.

///|
/// Structural equality over our Value shapes. NaN equals
/// NaN (Object.is); Fn values compare by reference.
///
/// The identity fast path is not just an optimization of the common case: the
/// runtime shares structure aggressively (copy-on-write spines, the value
/// stash restoring Obj/Fn by reference), so most comparisons of a rebuilt
/// tree against its predecessor meet the SAME object a level or two down.
/// Answering those in O(1) is what keeps an equality check over a 1000-item
/// list proportional to what actually changed. It agrees with the arms below
/// everywhere, NaN included.
pub impl Eq for Value with fn equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  match (self, other) {
    (Null, Null) => true
    (Bool(a), Bool(b)) => a == b
    (Num(a), Num(b)) => a == b || (a != a && b != b)
    (Str(a), Str(b)) => a == b
    (List(a), List(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !(a[i] == b[i]) {
          return false
        }
      }
      true
    }
    (Map(a), Map(b)) => {
      if a.length() != b.length() {
        return false
      }
      for k, v in a {
        match b.get(k) {
          Some(v2) => if !(v == v2) { return false }
          None => return false
        }
      }
      true
    }
    (Fn(a), Fn(b)) => physical_equal(a, b)
    (Obj(a), Obj(b)) => a.obj_eq(b)
    _ => false
  }
}

///|
/// size_of: `.size` (immutable collections) or `.length` (string/array).
///
/// A custom collection answers too, through `obj_size`. An
/// instance that is NOT a sequence still answers None, which is the honest
/// reading: a component has fields, not a size.
pub fn size_of(v : Value) -> Int? {
  match v {
    Str(s) => Some(s.length())
    List(a) => Some(a.length())
    Map(m) => Some(m.length())
    Obj(o) => o.obj_size()
    _ => None
  }
}

///|
/// Truthiness for unsized values; sized values are truthy when non-empty.
fn pred_truthy(v : Value) -> Bool {
  match size_of(v) {
    Some(n) => n > 0
    None =>
      match v {
        Null => false
        Bool(b) => b
        Num(n) => n != 0.0 && n == n
        Fn(_) => true
        // Str/List/Map are sized and handled above.
        _ => true
      }
  }
}

///|
/// Truthiness: Null/false/0/NaN/"" are false; lists, maps and functions
/// are always true. The `truthy?` predicate differs on
/// purpose: it treats empty collections as falsy (see `pred_truthy`).
pub fn Value::is_truthy(self : Value) -> Bool {
  match self {
    Null => false
    Bool(b) => b
    Num(n) => n != 0.0 && n == n // 0 and NaN are falsy
    Str(s) => s != ""
    List(_) | Map(_) | Fn(_) | Obj(_) => true
  }
}

///|
/// `${v}` template-interpolation semantics. Approximations: List joins
/// elements with ","; Map and Fn render as opaque markers
/// ("[object Object]" / function source are not worth mirroring).
pub fn Value::to_display_string(self : Value) -> String {
  match self {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Num(n) => num_source(n)
    Str(s) => s
    // Join semantics: null elements become "", the rest String()-coerce.
    List(items) => items.map(i => tpl_piece(i)).join(",")
    Map(_) => "[object]"
    Fn(_) => "[function]"
    Obj(o) => o.obj_debug()
  }
}

///|
fn lit_value(lit : Lit) -> Value {
  match lit {
    LNull => Null
    LBool(b) => Bool(b)
    LNum(n) => Num(n)
    LStr(s) => Str(s)
  }
}

///|
/// Number formatting for `${n}` / toString: integral doubles print with
/// no fractional part.
fn num_source(n : Double) -> String {
  if n != n {
    return "NaN"
  }
  if n == n.floor() && n.abs() < 9.0e15 {
    n.to_int64().to_string()
  } else {
    n.to_string()
  }
}

///|
/// One template piece in StrTpl.eval's join: null turns
/// into "" and String()-coercion applies to the rest.
fn tpl_piece(v : Value) -> String {
  match v {
    Null => ""
    _ => v.to_display_string()
  }
}

///|
/// A handler nothing answers: warn and hand back `this` unchanged.
///
/// A view's `@when` / `@enrich-with` /
/// `@loop-with` names are generated into an enum the author matches
/// exhaustively, so a name NOBODY wired is a build error now. What is left is
/// the case the enum cannot rule out — an arm that answers `None`, meaning
/// "another bucket serves this", where no other bucket does. That is a real
/// mistake worth reporting rather than a shape the engine has to tolerate.
fn mk_404_handler(ns : HandlerNamespace, name : String) -> Value {
  Fn(args => {
    // The same silence `Path::update` reports for a dispatch, one layer out: a
    // name a view wrote and no bucket answers. There is no state in hand here —
    // a 404 is built where the name resolves, which is before anything is asked
    // of a component — so the record says `Null` rather than inventing one.
    if refusing() {
      refuse({
        code: NoHandler,
        asked: name,
        rule: "",
        sentence: "",
        state: Null,
        path: Path::new(),
      })
    } else {
      warn("handler not found \{Repr((ns, name))}")
    }
    args.get(0).unwrap_or(Null)
  })
}

///|
pub fn Val::eval(self : Val, stack : &Stack) -> Value {
  match self {
    Const(lit~, ..) => lit_value(lit)
    // The one case that reads something outside the value language. The stack
    // decides what a segment means; this only says which segments were written.
    EventPath(segments) => stack.lookup_event_path(segments)
    StrTpl(parts) => {
      let buf = StringBuilder::new()
      for part in parts {
        match part {
          Some(v) => buf.write_string(tpl_piece(v.eval(stack)))
          None => () // failed placeholder: joins as the empty string
        }
      }
      Str(buf.to_string())
    }
    // The parser only builds an `App` whose name resolves and whose argument
    // count matches, so the lookup here cannot fail on anything it produced.
    // It can still miss for an `App` built by hand or decoded from an IR
    // module written by an older generator, and `Null` is the honest answer
    // there — the same one an unresolved name gives everywhere else.
    App(name~, args~) =>
      match builtin(name) {
        Some(b) => (b.apply)(args.map(a => a.eval(stack)))
        None => Null
      }
    Name(name) => stack.lookup_name(name)
    HandlerName(name~, ns~) =>
      match stack.get_handler_for(name, ns) {
        Null => mk_404_handler(ns, name)
        handler => handler
      }
    // An Uppercase name parses (a handler arg may be written as one, and the
    // linter reads them) but resolves to nothing: a type is not a Value, so
    // there is nothing for a stack to hand back.
    TypeName(_) => Null
    Bind(name) => stack.lookup_bind(name)
    BindMember(name~, prop~) =>
      // Bindings hold maps (`@value`), component instances (iterating a seq of
      // components, e.g. `@text="@value.title"` on a seq of components),
      // or whatever @enrich-with set. A member read off anything else is Null
      // (get/property fallback).
      match stack.lookup_bind(name) {
        Map(m) => m.get(prop).unwrap_or(Null)
        Obj(o) => o.obj_field(prop).unwrap_or(Null)
        _ => Null
      }
    Dyn(name) => stack.lookup_dynamic(name)
    // `.name` never invokes: a function field comes back raw.
    Field(name) => stack.lookup_field_raw(name)
    // `$name` in a value slot: the stack invokes and returns the result.
    Method(name) => stack.lookup_method(name)
    // `.seq[.key]`. Through the shared item lookup, which is what makes a
    // custom collection readable here.
    SeqAccess(seq~, key~) =>
      match stack.lookup_field_raw(key).as_key() {
        Some(k) => stack.lookup_field_raw(seq).item(k)
        None => Null
      }
  }
}

///|
pub fn Val::eval_as_handler(self : Val, stack : &Stack) -> Value {
  match self {
    // Handler position hands back the raw function for the dispatch
    // machinery to call with event args.
    Method(name) => stack.lookup_field_raw(name)
    _ => self.eval(stack)
  }
}

///|
pub fn Val::to_path_item(self : Val) -> Step? {
  match self {
    Field(name) => Some(FieldStep(name))
    SeqAccess(seq~, key~) => Some(SeqAccessStep(seq_field=seq, key_field=key))
    _ => None
  }
}

///|
pub fn Val::is_literal(self : Val) -> Bool {
  match self {
    Const(..) => true
    // Every part a plain constant, none bound from a macro variable (the
    // macro placeholder is real in the body even when it resolved constant).
    StrTpl(parts) =>
      parts.iter().all(p => p is Some(Const(from_macro=false, ..)))
    _ => false
  }
}
