// The builtin vocabulary: the names an application may head, each with the
// arity that makes application unambiguous and the semantics evaluation uses.
//
// This was `enum Pred` — five constructors, an arity match and an apply match,
// all of them closed. Nothing an author could write joined the set, which is
// why a predicate needed its own AST node (`Val::Predicate`), its own parse
// path and its own no-kind exception. Applying a NAME to arguments is the
// general shape, and the five become the first rows of a table.
//
// The table is data rather than an enum for one reason worth stating plainly:
// `Val::App` carries the NAME, so `Val` still derives `Eq` and `Debug` even
// though the behaviour here is a closure. An enum in the AST would have had to
// grow a case per user-declared predicate, which is exactly the thing that
// cannot work.

///|
/// Every builtin, by name. Built once: `builtin` is on the parse path and the
/// eval path, and neither wants to rebuild a six-entry map per call.
let builtin_table : Map[String, Builtin] = {
  // `empty?` is deliberately not `falsy?`: a `0` is falsy and is not empty,
  // and an unsized value is neither.
  "empty?": {
    name: "empty?",
    arity: 1,
    apply: args => Bool(args[0] is Null || size_of(args[0]) is Some(0)),
  },
  // `truthy?` / `falsy?` are `pred_truthy`, NOT `Value::is_truthy`: the
  // predicates treat an empty collection as falsy and plain truthiness does
  // not. The difference is deliberate and is the reason both exist.
  "truthy?": {
    name: "truthy?",
    arity: 1,
    apply: args => Bool(pred_truthy(args[0])),
  },
  "falsy?": {
    name: "falsy?",
    arity: 1,
    apply: args => Bool(!pred_truthy(args[0])),
  },
  "null?": { name: "null?", arity: 1, apply: args => Bool(args[0] is Null) },
  // The one binary member. `is` says this in the expression language, and
  // this spelling stays for as long as the views use it.
  "equals?": {
    name: "equals?",
    arity: 2,
    apply: args => Bool(args[0] == args[1]),
  },
}

///|
/// The builtin a name denotes, or None when nothing does.
pub fn builtin(name : String) -> Builtin? {
  builtin_table.get(name)
}

///|
/// Every builtin name in BYTE order — the vocabulary a "did you mean" search
/// ranges over, and the reason it is public rather than a private table.
///
/// Not `Array::sort`: MoonBit's `Compare for String` is length-first, which
/// would answer `null?, empty?, falsy?, equals?, truthy?`. That is still
/// deterministic, and it reads as unordered to the person the list is for.
pub fn builtin_names() -> Array[String] {
  let out : Array[String] = []
  for name, _ in builtin_table {
    out.push(name)
  }
  out.sort_by((a, b) => byte_cmp(a, b))
  out
}

///|
/// Byte order over two strings: -1, 0 or 1.
fn byte_cmp(a : String, b : String) -> Int {
  let (x, y) = (a.to_array(), b.to_array())
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] != y[i] {
      return if x[i] < y[i] { -1 } else { 1 }
    }
  }
  x.length() - y.length()
}
