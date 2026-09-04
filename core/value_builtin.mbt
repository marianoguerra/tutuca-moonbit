// The builtin vocabulary: the names an application may head, each with the
// arity that makes application unambiguous and the semantics evaluation uses.
//
// This was `enum Pred` — five constructors, an arity match and an apply match,
// all of them closed. Nothing an author could write joined the set, which is
// why a predicate needed its own AST node (`Expr::Predicate`), its own parse
// path and its own no-kind exception. Applying a NAME to arguments is the
// general shape, and the five become the first rows of a table.
//
// The table is data rather than an enum for one reason worth stating plainly:
// `Expr::App` carries the NAME, so `Expr` still derives `Eq` and `Debug` even
// though the behaviour here is a closure. An enum in the AST would have had to
// grow a case per user-declared predicate, which is exactly the thing that
// cannot work.
//
// It is ONE table for both languages. A conditional slot and a block body ask
// the same names of the same implementations, so `truthy? .items` cannot mean
// one thing in a `@show` and another in a `pred`. The operators are here for
// the same reason: `and` in a slot is `and` in a block, not a second spelling
// that happens to agree today. `tscript/script_builtin.mbt` is the block's
// view of this list and re-exports rather than restates it.
//
// TWO ROWS DO NOT EVALUATE HERE. `and` and `or` short-circuit, and `apply`
// takes ARGUMENTS THAT ARE ALREADY EVALUATED, so they cannot. `Expr::eval`
// answers them ahead of the generic path; the rows exist so the name resolves
// and the arity is checked in one place with everything else.

///|
/// Truthiness, for the operators. `Value::is_truthy` and NOT `pred_truthy`:
/// the block coerces a condition the same way (`tscript/emit_mbt/emit.mbt`'s
/// `at_bool`, which says so out loud), and the two backends have to agree
/// about `@show=".count"`.
fn op_truthy(v : Value) -> Bool {
  v.is_truthy()
}

///|
/// Every builtin, by name. Built once: `builtin` is on the parse path and the
/// eval path, and neither wants to rebuild the map per call.
let builtin_table : Map[String, Builtin] = {
  // -- The shape predicates ------------------------------------------------
  //
  // These are the ones no operator says, which is why they keep the `?` and
  // why both languages keep all four. `empty?` is total over any value where
  // `(len x) is 0` is not, and `truthy?` differs from plain truthiness ON
  // PURPOSE — see `pred_truthy`.

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
  "null?": { name: "null?", arity: 1, apply: args => Bool(args[0] is Null), },

  // -- Logic ---------------------------------------------------------------
  //
  // `not` evaluates here; `and` / `or` do not — `Expr::eval` short-circuits
  // them, because `apply` is handed evaluated arguments and a guard like
  // `and (truthy? .items) ($firstLabel)` has to be able to stop.
  "not": { name: "not", arity: 1, apply: args => Bool(!op_truthy(args[0])), },
  "and": {
    name: "and",
    arity: 2,
    apply: args => Bool(op_truthy(args[0]) && op_truthy(args[1])),
  },
  "or": {
    name: "or",
    arity: 2,
    apply: args => Bool(op_truthy(args[0]) || op_truthy(args[1])),
  },
  // `a implies b` is `(not a) or b`, the shape most cross-field rules take.
  "implies": {
    name: "implies",
    arity: 2,
    apply: args => Bool(!op_truthy(args[0]) || op_truthy(args[1])),
  },

  // -- Comparison ----------------------------------------------------------
  //
  // `is` is STRUCTURAL, through `Eq for Value`, so two lists with equal
  // contents compare equal here as they do in a compiled handler. The ordering
  // four read both sides as numbers, which a non-number answers 0 for —
  // the interpreter's analogue of the type error the compiled backend raises.
  "is": { name: "is", arity: 2, apply: args => Bool(args[0] == args[1]), },
  "is not": {
    name: "is not",
    arity: 2,
    apply: args => Bool(args[0] != args[1]),
  },
  "<": {
    name: "<",
    arity: 2,
    apply: args => Bool(args[0].num() < args[1].num()),
  },
  "<=": {
    name: "<=",
    arity: 2,
    apply: args => Bool(args[0].num() <= args[1].num()),
  },
  ">": {
    name: ">",
    arity: 2,
    apply: args => Bool(args[0].num() > args[1].num()),
  },
  ">=": {
    name: ">=",
    arity: 2,
    apply: args => Bool(args[0].num() >= args[1].num()),
  },

  // -- Reading -------------------------------------------------------------
  //
  // The block's list, which is here because the block's list IS this list.
  // Each of them is in it because the census found it hand-written; they are
  // not a general standard library and should not become one.
  "len": {
    name: "len",
    arity: 1,
    apply: args => {
      match size_of(args[0]) {
        Some(n) => Num(n.to_double())
        None => Null
      }
    },
  },
  // A KEY in a set or map, a VALUE in a list. The keyed case keys on the
  // DISPLAY string, which is the key the generated `hasIn<X>` mutator looks up.
  "has": {
    name: "has",
    arity: 2,
    apply: args => {
      match args[0] {
        Map(m) => Bool(m.contains(args[1].to_display_string()))
        List(a) => Bool(a.iter().any(v => v == args[1]))
        // A custom collection answers both halves at once: it is asked by KEY
        // like a map and by VALUE like a list, because nothing here knows which
        // of the two shapes it meant to be.
        Obj(o) =>
          Bool(
            o
            .seq_entries()
            .unwrap_or([])
            .iter()
            .any(e => {
              let (k, v) = e
              k.to_label() == args[1].to_display_string() || v == args[1]
            }),
          )
        _ => Bool(false)
      }
    },
  },
  "contains": {
    name: "contains",
    arity: 2,
    apply: args => Bool(args[0].str().contains(args[1].str())),
  },
  "min": {
    name: "min",
    arity: 2,
    apply: args => {
      let (a, b) = (args[0].num(), args[1].num())
      Num(if a < b { a } else { b })
    },
  },
  "max": {
    name: "max",
    arity: 2,
    apply: args => {
      let (a, b) = (args[0].num(), args[1].num())
      Num(if a > b { a } else { b })
    },
  },
  // The empty-range answer is `lo`, matching the compiled backend: an empty
  // list makes `hi` -1 and a negative index is not an honest result.
  "clamp": {
    name: "clamp",
    arity: 3,
    apply: args => {
      let (v, lo, hi) = (args[0].num(), args[1].num(), args[2].num())
      Num(
        if hi < lo {
          lo
        } else if v < lo {
          lo
        } else if v > hi {
          hi
        } else {
          v
        },
      )
    },
  },
  "int": {
    name: "int",
    arity: 1,
    apply: args => Num(args[0].num().to_int().to_double()),
  },
  "num": { name: "num", arity: 1, apply: args => Num(args[0].num()), },
  "str": {
    name: "str",
    arity: 1,
    apply: args => Str(args[0].to_display_string()),
  },
  "lower": {
    name: "lower",
    arity: 1,
    apply: args => Str(args[0].str().to_lower()),
  },
  "upper": {
    name: "upper",
    arity: 1,
    apply: args => Str(args[0].str().to_upper()),
  },
  "trim": {
    name: "trim",
    arity: 1,
    apply: args => Str(args[0].str().trim(chars=" \t\n\r").to_owned()),
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
  out.sort_by((a, b) => a.lexical_compare(b))
  out
}
