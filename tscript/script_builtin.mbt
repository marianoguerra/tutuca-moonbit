// The block language's reading vocabulary.
//
// Each of these is here because the census found it hand-written: `clamp` for
// the 42 `prev`/`next` call sites, `int`/`num` for the `Num(Double)` ⇄ `s32`
// seam, `lower`/`trim`/`contains` for the filter predicate that every list
// component grows. They are not a general standard library and should not
// become one — the language is total because its vocabulary is closed, and
// every addition is a claim that the corpus needs it.
//
// The four shape predicates come from `core`'s table rather than being
// restated, so a `truthy?` in a `@show` and a `truthy?` in a `pred` cannot
// drift apart. `equals?` is deliberately NOT re-exported into the block: `is`
// says it, and one meaning keeps one spelling.
//
// Arity lives here rather than in the checker because the INTERPRETER needs it
// too, and neither of those packages sees the other.

///|
/// The arity of a reading builtin, or None when the name is not one.
///
/// The parser does not consult this: juxtaposition binds an argument list
/// greedily over ATOMS, so a wrong count is a type error rather than a syntax
/// error, and it is reported with the rest of them.
pub fn script_builtin(name : String) -> Int? {
  match name {
    // Shape predicates — the same four `core.builtin` answers for a slot.
    "empty?" | "truthy?" | "falsy?" | "null?" => Some(1)
    // Collections
    "len" => Some(1)
    "has" | "contains" => Some(2)
    // Numbers
    "min" | "max" => Some(2)
    "clamp" => Some(3)
    "int" | "num" => Some(1)
    // Text
    "str" | "lower" | "upper" | "trim" => Some(1)
    _ => None
  }
}

///|
/// Every reading builtin, in byte order — the vocabulary a "did you mean"
/// search ranges over.
pub fn script_builtin_names() -> Array[String] {
  let out = [
    "clamp", "contains", "empty?", "falsy?", "has", "int", "len", "lower", "max",
    "min", "null?", "num", "str", "trim", "truthy?", "upper",
  ]
  out
}
