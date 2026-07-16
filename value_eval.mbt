// Val evaluation and Value runtime semantics (src/value.js eval side +
// PREDICATES table + immutable `is`). Implements the declares in spec.mbt.

///|
/// Structural equality (immutable.js `is` over our Value shapes). NaN equals
/// NaN (Object.is); Fn values compare by reference.
pub impl Eq for Value with fn equal(self, other) {
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
/// JS sizeOf: `.size` (immutable collections) or `.length` (string/array).
pub fn size_of(v : Value) -> Int? {
  match v {
    Str(s) => Some(s.length())
    List(a) => Some(a.length())
    Map(m) => Some(m.length())
    _ => None
  }
}

///|
/// JS truthiness for unsized values; sized values are truthy when non-empty.
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
/// JS truthiness: Null/false/0/NaN/"" are false; lists, maps and functions
/// are always true (like JS objects). The `truthy?` predicate differs on
/// purpose: it treats empty collections as falsy (see `pred_truthy`).
pub fn Value::is_truthy(self : Value) -> Bool {
  match self {
    Null => false
    Bool(b) => b
    Num(n) => n != 0.0 && n == n // 0 and NaN are falsy
    Str(s) => s != ""
    List(_) | Map(_) | Fn(_) | Obj(_) => true // JS objects are always truthy
  }
}

///|
/// JS `${v}` template-interpolation semantics. Approximations: List joins
/// elements with ","; Map and Fn render as opaque markers (JS
/// "[object Object]" / function source are not worth mirroring).
pub fn Value::to_display_string(self : Value) -> String {
  match self {
    Null => "null" // JS `${null}`
    Bool(b) => if b { "true" } else { "false" }
    Num(n) => num_source(n)
    Str(s) => s
    // JS Array.join: null elements become "", the rest String()-coerce.
    List(items) => items.map(i => tpl_piece(i)).join(",")
    Map(_) => "[object]"
    Fn(_) => "[function]"
    Obj(o) => o.obj_debug()
  }
}

///|
pub fn Pred::of_name(name : String) -> Pred? {
  match name {
    "empty?" => Some(IsEmpty)
    "truthy?" => Some(IsTruthy)
    "falsy?" => Some(IsFalsy)
    "null?" => Some(IsNull)
    "equals?" => Some(Equals)
    _ => None
  }
}

///|
pub fn Pred::name(self : Pred) -> String {
  match self {
    IsEmpty => "empty?"
    IsTruthy => "truthy?"
    IsFalsy => "falsy?"
    IsNull => "null?"
    Equals => "equals?"
  }
}

///|
pub fn Pred::arity(self : Pred) -> Int {
  match self {
    Equals => 2
    _ => 1
  }
}

///|
pub fn Pred::apply(self : Pred, args : Array[Value]) -> Bool {
  match self {
    IsEmpty => args[0] is Null || size_of(args[0]) is Some(0)
    IsTruthy => pred_truthy(args[0])
    IsFalsy => !pred_truthy(args[0])
    IsNull => args[0] is Null
    Equals => args[0] == args[1]
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
/// JS number formatting for `${n}` / toString: integral doubles print with
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
/// One template piece in StrTpl.eval's join: JS Array.join turns
/// null/undefined into "" and String()-coerces the rest.
fn tpl_piece(v : Value) -> String {
  match v {
    Null => ""
    _ => v.to_display_string()
  }
}

///|
/// JS mk404Handler: a warn-and-return-this function for unresolved handler
/// names (our Fn convention: element 0 is `this`).
fn mk_404_handler(ns : HandlerNamespace, name : String) -> Value {
  Fn(args => {
    println("handler not found \{to_repr((ns, name))}")
    args.get(0).unwrap_or(Null)
  })
}

///|
pub fn Val::eval(self : Val, stack : &Stack) -> Value {
  match self {
    Const(lit~, ..) => lit_value(lit)
    StrTpl(parts) => {
      let buf = StringBuilder::new()
      for part in parts {
        match part {
          Some(v) => buf.write_string(tpl_piece(v.eval(stack)))
          None => () // failed placeholder: JS join turns null into ""
        }
      }
      Str(buf.to_string())
    }
    Predicate(pred~, args~) => Bool(pred.apply(args.map(a => a.eval(stack))))
    Name(name) => stack.lookup_name(name)
    HandlerName(name~, ns~) =>
      match stack.get_handler_for(name, ns) {
        Null => mk_404_handler(ns, name)
        handler => handler
      }
    TypeName(name) => stack.lookup_type(name)
    Bind(name) => stack.lookup_bind(name)
    BindMember(name~, prop~) =>
      // Bindings hold maps (`@value`), component instances (iterating a seq of
      // components, e.g. `@text="@value.title"` in docs/examples/seq-item-access.js),
      // or whatever @enrich-with set. A member read off anything else is Null
      // (JS get/property fallback).
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
    SeqAccess(seq~, key~) => {
      let key_v = stack.lookup_field_raw(key)
      match (stack.lookup_field_raw(seq), key_v) {
        (Map(m), Str(k)) => m.get(k).unwrap_or(Null)
        (List(a), Num(n)) => a.get(n.to_int()).unwrap_or(Null)
        _ => Null
      }
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
pub fn Val::render(self : Val, stack : &Stack) -> Value? {
  match self {
    // JS BaseVal.render is undefined for these; everything else renders as
    // its eval.
    Name(_) | HandlerName(..) | TypeName(_) | Predicate(..) => None
    _ => Some(self.eval(stack))
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
