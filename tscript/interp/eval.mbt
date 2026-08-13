// Evaluating an expression.
//
// Every function here answers `Value?`, where None means "this could not be
// evaluated" and propagates all the way out to "the transition did not
// happen". There is no error type and no partial result, because the contract
// the framework already has is exactly that: `Path::update` returns the same
// root object for an unresolvable path, a missing handler and a handler that
// answered None, and every generated mutator answers the instance it was given
// when handed something it cannot use.

///|
pub fn Env::of_state(
  state : Map[String, @tutuca.Value],
  callables? : Map[String, @tscript.Decl] = Map([]),
  schema? : @tutuca.SchemaInfo,
  zero? : (@tscript.TyRef) -> @tutuca.Value?,
) -> Env {
  { state, params: Map([]), binds: Map([]), callables, schema, zero }
}

///|
pub fn Outcome::nothing() -> Outcome {
  { state: None, effects: [], binds: Map([]) }
}

///|
/// A depth ceiling on nested applications.
///
/// The language is total by construction — no loops, no recursion, and a
/// predicate may call only predicates declared above it — so nothing that
/// passes the checker can reach this. It is here because a `Decl` can also be
/// built by hand or decoded from somewhere, and a runtime that a malformed
/// input can hang is a runtime a host cannot load untrusted cards into.
const MAX_DEPTH = 32

///|
pub fn eval(e : @tscript.Expr, env : Env) -> @tutuca.Value? {
  eval_at(e, env, 0)
}

///|
fn eval_at(e : @tscript.Expr, env : Env, depth : Int) -> @tutuca.Value? {
  if depth > MAX_DEPTH {
    return None
  }
  match e {
    ELit(lit~, ..) =>
      Some(
        match lit {
          LNull => Null
          LBool(b) => Bool(b)
          LNum(n) => Num(n)
          LStr(s) => Str(s)
        },
      )
    ETpl(parts~, ..) => {
      let b = StringBuilder::new()
      for part in parts {
        match part {
          TText(t) => b.write_string(t)
          TExpr(inner) => {
            guard eval_at(inner, env, depth + 1) is Some(v) else { return None }
            b.write_string(v.to_display_string())
          }
        }
      }
      Some(Str(b.to_string()))
    }
    ERead(place~, ..) => read_place(place, env, depth)
    // A `$method` and a `*dyn` are resolved by the RENDER stack, which a body
    // does not have — a handler runs after the render that raised it. Reading
    // one is not a failure: it is Null, which is what a slot reading an
    // unanswered name gets. The CHECKER reports it (`RENDER_ONLY`), because a
    // silent Null in a condition is a rule that is false every time and says
    // nothing; a body calls a `compute` or a `pred` bare, which `EName` below
    // resolves.
    EMethod(..) | EDyn(..) => Some(Null)
    EName(name~, ..) => {
      if env.params.get(name) is Some(v) {
        return Some(v)
      }
      if env.binds.get(name) is Some(v) {
        return Some(v)
      }
      // A zero-argument application: a `pred` used bare is the commonest, and
      // it is how a condition slot spells one.
      apply(name, [], env, depth)
    }
    EApp(name~, args~, ..) => {
      let vals : Array[@tutuca.Value] = []
      for a in args {
        guard eval_at(a, env, depth + 1) is Some(v) else { return None }
        vals.push(v)
      }
      apply(name, vals, env, depth)
    }
    EUnary(op~, operand~, ..) => {
      guard eval_at(operand, env, depth + 1) is Some(v) else { return None }
      match op {
        UNot => Some(Bool(!v.is_truthy()))
        UNeg =>
          match v {
            Num(n) => Some(Num(-n))
            _ => None
          }
      }
    }
    EChain(family~, ops~, operands~, ..) =>
      eval_chain(family, ops, operands, env, depth)
    EIf(cond~, then_~, else_~, ..) => {
      guard eval_at(cond, env, depth + 1) is Some(c) else { return None }
      if c.is_truthy() {
        eval_at(then_, env, depth + 1)
      } else {
        eval_at(else_, env, depth + 1)
      }
    }
    // A place is not a value. `sendAt` reads it as a place, so reaching here
    // means an AST the parser did not build.
    ERef(..) => None
  }
}

///|
/// Read what is at a place.
fn read_place(p : @tscript.Place, env : Env, depth : Int) -> @tutuca.Value? {
  let mut cur : @tutuca.Value = match p.root {
    PState(name) =>
      match env.state.get(name) {
        Some(v) => v
        // A field the state does not hold reads Null rather than failing: the
        // checker names an undeclared one, and a schema-less card is allowed
        // to grow a field the map has not seen yet.
        None => Null
      }
    // A missing binding reads Null — it comes from a slot this block cannot
    // see, and absent is a normal answer there. The target is the exception:
    // it comes from a `new` in this very body, so its absence is a mistake and
    // reading it as Null would bury one.
    PBind(name) =>
      match env.binds.get(name) {
        Some(v) => v
        None => if name == @tscript.target_bind { return None } else { Null }
      }
  }
  for st in p.steps {
    match st {
      PField(name) =>
        cur = match cur.field_opt(name) {
          Some(v) => v
          None => Null
        }
      PIndex(key) => {
        guard eval_at(key, env, depth + 1) is Some(kv) else { return None }
        guard kv.as_key() is Some(k) else { return None }
        // A key that is not there is a FAILURE, not a Null: reading past the
        // end of a list is the case "failure is no change" exists for, and a
        // handler that quietly worked on Null would write it back.
        guard cur.item_opt(k) is Some(v) else { return None }
        cur = v
      }
    }
  }
  Some(cur)
}

///|
/// Apply a name to already-evaluated arguments.
fn apply(
  name : String,
  args : Array[@tutuca.Value],
  env : Env,
  depth : Int,
) -> @tutuca.Value? {
  // `core`'s table first, so `empty?` and `truthy?` mean in a body exactly
  // what they mean in a `@show`. One table, one meaning.
  if @tutuca.builtin(name) is Some(b) {
    return if args.length() == b.arity { Some((b.apply)(args)) } else { None }
  }
  if script_builtin_apply(name, args) is Some(v) {
    return Some(v)
  }
  // A `pred` or a `compute` the block declares.
  if env.callables.get(name) is Some(d) {
    guard d.body is Value(body) else { return None }
    let params : Map[String, @tutuca.Value] = Map([])
    for i, p in d.params {
      params[p.name] = args.get(i).unwrap_or(Null)
    }
    return eval_at(body, { ..env, params, }, depth + 1)
  }
  None
}

///|
/// A chain of operands joined by one family's operators.
///
/// Evaluated left to right and short-circuiting for `and` / `or`, which is
/// what a reader expects and what keeps `(not .busy) and (.items.len > 0)`
/// from evaluating the second half when the first already decided.
fn eval_chain(
  family : @tscript.OpFamily,
  ops : Array[String],
  operands : Array[@tscript.Expr],
  env : Env,
  depth : Int,
) -> @tutuca.Value? {
  match family {
    FLogic => {
      guard eval_at(operands[0], env, depth + 1) is Some(first) else {
        return None
      }
      let mut acc = first.is_truthy()
      for i, op in ops {
        if op == "and" && !acc {
          return Some(Bool(false))
        }
        if op == "or" && acc {
          return Some(Bool(true))
        }
        guard eval_at(operands[i + 1], env, depth + 1) is Some(v) else {
          return None
        }
        acc = v.is_truthy()
      }
      Some(Bool(acc))
    }
    // `a implies b` is `(not a) or b`, so a false antecedent decides without
    // evaluating the consequent — which is what makes an implication over a
    // field that is not there safe to write.
    FImplies => {
      guard eval_at(operands[0], env, depth + 1) is Some(a) else { return None }
      if !a.is_truthy() {
        return Some(Bool(true))
      }
      guard eval_at(operands[1], env, depth + 1) is Some(b) else { return None }
      Some(Bool(b.is_truthy()))
    }
    FCompare => {
      guard eval_at(operands[0], env, depth + 1) is Some(a) else { return None }
      guard eval_at(operands[1], env, depth + 1) is Some(b) else { return None }
      compare_op(ops[0], a, b)
    }
    FAdd | FMul => {
      guard eval_at(operands[0], env, depth + 1) is Some(first) else {
        return None
      }
      let mut acc = first
      for i, op in ops {
        guard eval_at(operands[i + 1], env, depth + 1) is Some(v) else {
          return None
        }
        guard arith(op, acc, v) is Some(next) else { return None }
        acc = next
      }
      Some(acc)
    }
  }
}

///|
fn compare_op(
  op : String,
  a : @tutuca.Value,
  b : @tutuca.Value,
) -> @tutuca.Value? {
  match op {
    // Structural equality, the same `Eq for Value` everything else compares
    // with — so two lists with equal contents are equal here too.
    "is" => Some(Bool(a == b))
    "is not" => Some(Bool(a != b))
    _ => {
      // The ordered comparisons are numeric. Comparing two strings by order
      // is a thing a language could offer and this one does not: locale makes
      // it a decision rather than an operation, and nothing in the corpus
      // asked.
      guard a is Num(x) && b is Num(y) else { return None }
      Some(
        Bool(
          match op {
            "<" => x < y
            "<=" => x <= y
            ">" => x > y
            _ => x >= y
          },
        ),
      )
    }
  }
}

///|
/// `+` over two strings concatenates and over two numbers adds; everything
/// else is arithmetic over numbers. A mixed pair fails rather than coercing,
/// which is the rule the checker states statically and this enforces when the
/// types were not known.
fn arith(op : String, a : @tutuca.Value, b : @tutuca.Value) -> @tutuca.Value? {
  if op == "+" && a is Str(x) && b is Str(y) {
    return Some(Str(x + y))
  }
  guard a is Num(x) && b is Num(y) else { return None }
  match op {
    "+" => Some(Num(x + y))
    "-" => Some(Num(x - y))
    "*" => Some(Num(x * y))
    "/" => if y == 0.0 { None } else { Some(Num(x / y)) }
    "mod" =>
      if y == 0.0 {
        None
      } else {
        Some(Num((x.to_int() % y.to_int()).to_double()))
      }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// The reading builtins

///|
/// The block's own vocabulary. The four shape predicates are NOT here: they
/// come from `core`'s table, so a `truthy?` in a body and a `truthy?` in a
/// `@show` cannot drift apart.
fn script_builtin_apply(
  name : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value? {
  guard @tscript.script_builtin(name) is Some(arity) else { return None }
  guard args.length() == arity else { return None }
  match name {
    "len" =>
      match @tutuca.size_of(args[0]) {
        Some(n) => Some(Num(n.to_double()))
        None => None
      }
    "min" | "max" => {
      guard args[0] is Num(a) && args[1] is Num(b) else { return None }
      let pick = if name == "min" {
        if a < b {
          a
        } else {
          b
        }
      } else if a > b {
        a
      } else {
        b
      }
      Some(Num(pick))
    }
    "clamp" => {
      guard args[0] is Num(v) && args[1] is Num(lo) && args[2] is Num(hi) else {
        return None
      }
      // A `hi` below `lo` has no answer that is not a guess, and this is the
      // 42-call-site `prev`/`next` builtin — an empty list makes `hi` -1 and
      // the honest result is `lo`, not a negative index.
      Some(
        Num(
          if v < lo {
            lo
          } else if v > hi && hi >= lo {
            hi
          } else if hi < lo {
            lo
          } else {
            v
          },
        ),
      )
    }
    "int" =>
      match args[0] {
        Num(n) => Some(Num(n.to_int().to_double()))
        Str(s) => {
          let v : Double = @string.from_str(s) catch { _ => return None }
          Some(Num(v.to_int().to_double()))
        }
        _ => None
      }
    "num" =>
      match args[0] {
        Num(n) => Some(Num(n))
        Str(s) => {
          let v : Double = @string.from_str(s) catch { _ => return None }
          Some(Num(v))
        }
        _ => None
      }
    "str" => Some(Str(args[0].to_display_string()))
    "lower" | "upper" =>
      match args[0] {
        Str(s) => {
          let down = name == "lower"
          let b = StringBuilder::new()
          for c in s {
            b.write_char(
              if down && c >= 'A' && c <= 'Z' {
                Int::unsafe_to_char(c.to_int() + 32)
              } else if !down && c >= 'a' && c <= 'z' {
                Int::unsafe_to_char(c.to_int() - 32)
              } else {
                c
              },
            )
          }
          Some(Str(b.to_string()))
        }
        _ => None
      }
    "trim" =>
      match args[0] {
        Str(s) => Some(Str(s.trim(chars=" \t\n\r").to_owned()))
        _ => None
      }
    "contains" => {
      guard args[0] is Str(hay) && args[1] is Str(needle) else { return None }
      Some(Bool(hay.contains(needle)))
    }
    // Membership in a set or a map, keyed by the member's display string —
    // the same key the generated `hasIn<X>` mutator uses.
    "has" =>
      match args[0] {
        Map(m) => Some(Bool(m.contains(args[1].to_display_string())))
        List(xs) => Some(Bool(xs.iter().any(x => x == args[1])))
        _ => None
      }
    _ => None
  }
}
