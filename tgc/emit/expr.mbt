// Expressions.
//
// Every expression compiles to a Wax expression of type `&?tg_val`, and
// `ref.null` means THE TRANSITION HAS NO ANSWER. That is what lets the
// emitters compose freely: a runtime operation with no answer for its arguments
// returns null, null propagates through everything above it, and the statement
// checks once at the top instead of the emitter threading a failure flag
// through every operand.
//
// The null VALUE is `kind 0` and is an ordinary thing to compute with. Keeping
// the two apart is why `.note is null` is a real question and `len true` is not
// an answer of `false`.

///|
/// One declaration being emitted.
priv struct Ctx {
  comp : Comp
  /// Which body this is. Two effects mean different things in a `receive` and
  /// in an `answer`, and the body is the only thing that says which — and the
  /// render row arrives at different offsets in a `pred` and in an `enrich`.
  kind : @tscript.DeclKind
  /// The rules whose `format` sentence lowered, so a guard knows whether there
  /// is one to say.
  formats : @set.Set[String]
  /// Every invariant this component declares. Checked after each transition,
  /// because an invariant is the rule nothing has to mention.
  invariants : Array[String]
  /// What `cur` currently holds, if a `new` has run.
  ///
  /// A `new` names a type at COMPILE time, and the checker guarantees the two
  /// arms of an `if` agree about it (`C::stmts` merges the target and keeps
  /// only what both said, so reading `cur` after a one-armed `new` is
  /// `NO_TARGET`). So one mutable field, walked in statement order, is enough
  /// — and it is what decides whether reading `cur` yields a map or builds a
  /// component.
  mut cur : CurKind
  /// The local holding the bindings an enricher is accumulating, if this is one.
  ///
  /// An enricher ANSWERS the map rather than writing into one, which is the
  /// single place the compiled shape has to differ from the interpreted one: the
  /// renderer reads the map it PASSED IN, and a guest cannot mutate a host's
  /// map. So it returns one and the host merges it back.
  binds : String?
  /// The declaration's parameters, by name, in order.
  params : Map[String, Int]
  /// Which callables this component actually has, so a call to a refused one is
  /// itself a refusal rather than a call to a function that is not there.
  callable : Map[String, @tscript.DeclKind]
  mut temps : Int
}

///|
/// What `new` opened.
///
/// A RECORD is a map and stays one — `core.Value` has no record, and
/// `struct Label { text: String }` decodes to a `Map`. A sibling COMPONENT is
/// an instance, and building one is a call to this module's own `tgc.make`
/// rather than a request to the host: the old contract had to ask, because
/// `control.make-instance` was the only way a guest could name one, and the
/// Component Model forbade re-entering the module while a call was active.
/// Neither is true here.
priv enum CurKind {
  CurNone
  CurRecord(String)
  CurComp(String)
}

///|
/// This declaration cannot be lowered. Caught per declaration: the rest of the
/// card still compiles and the host hears `unhandled` for this name.
priv suberror Refused {
  Refused(String)
}

///|
fn Ctx::temp(self : Ctx) -> String {
  self.temps = self.temps + 1
  "t\{self.temps}"
}

///|
/// Emit an expression, and answer the Wax expression that reads its value.
///
/// It takes the source buffer because three forms have to SHORT-CIRCUIT — `and`,
/// `or` and a conditional — and Wax has no macros, so the only way to leave an
/// operand unevaluated is to emit it inside a branch. Everything else could
/// have been a pure string; making them all take `src` is what keeps one rule.
fn emit_expr(ctx : Ctx, src : Src, e : @tutuca.Expr) -> String raise Refused {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LNull => "tg_null()"
        LBool(b) => "tg_bool(\{if b { 1 } else { 0 }})"
        LNum(n) => "tg_num(\{wax_num(n)})"
        LStr(s) => "tg_str(\{wax_str(s)})"
      }
    ETpl(parts~, ..) => emit_tpl(ctx, src, parts)
    ERead(place~, ..) => emit_read(ctx, src, place)
    EName(name~, ..) => emit_name(ctx, src, name, [])
    EApp(name~, args~, ..) => emit_name(ctx, src, name, args)
    EChain(family~, ops~, operands~, ..) =>
      emit_chain(ctx, src, family, ops, operands)
    EUnary(op~, operand~, ..) => {
      let inner = emit_expr(ctx, src, operand)
      match op {
        UNot => "b_not(\{inner})"
        UNeg => "op_neg(\{inner})"
      }
    }
    // A conditional evaluates ONE arm, so both arms are emitted inside
    // branches rather than beside each other. A condition with no answer
    // abandons the transition rather than being read as false.
    EIf(cond~, then_~, else_~, ..) =>
      emit_branch(ctx, src, cond, () => then_, () => else_)
    // A handler is handed no render row, so `@binding` has nothing to mean
    // here; `$method` and `*dyn` are answered by the render stack and a
    // compiled handler runs after one.
    EMethod(name~, ..) =>
      raise Refused(
        "`$\{name}` is answered by the render stack, and a handler runs after one",
      )
    EDyn(name~, ..) =>
      raise Refused(
        "`*\{name}` is a dynamic lookup, which this backend does not carry yet",
      )
    EEventPath(segments~, ..) =>
      raise Refused(
        "`e.\{segments.join(".")}` is DOM event data, named in the view and passed as an argument",
      )
    ERef(..) =>
      raise Refused(
        "a `&.place` is only an address, and only `sendAt` takes one",
      )
    EMacroVar(name~, ..) =>
      raise Refused(
        "`^\{name}` is a macro variable, resolved when a view is parsed",
      )
    EConfigVar(name~, ..) =>
      raise Refused(
        "`$$\{name}` is a host config variable, which this backend does not carry yet",
      )
    ETypeName(name~, ..) =>
      raise Refused("`\{name}` is a type name, and a type is not a value")
  }
}

///|
/// A `$'…'` template: display each part and join.
///
/// Left-folded rather than joined through a builder because the parts are known
/// at compile time and a fold of two-argument concatenations is what the
/// runtime has. A template of one literal part is that literal.
fn emit_tpl(
  ctx : Ctx,
  src : Src,
  parts : Array[@tutuca.TplPart],
) -> String raise Refused {
  if parts.length() == 0 {
    return "tg_str(\"\")"
  }
  let pieces = []
  for p in parts {
    match p {
      TText(text~, ..) => pieces.push(wax_str(text))
      TExpr(inner) => pieces.push("display(\{emit_expr(ctx, src, inner)})")
    }
  }
  let mut acc = pieces[0]
  for i in 1..<pieces.length() {
    acc = "concat(\{acc}, \{pieces[i]})"
  }
  "tg_str(\{acc})"
}

///|
/// A bare name, or a name applied to arguments.
///
/// Three things it can be, in the order the language resolves them: a
/// parameter of this declaration, one of the sixteen builtins, or a `compute` /
/// `pred` / `invariant` this component declares. Nothing else — the vocabulary
/// is closed, and `tscript/script_builtin.mbt` means it.
fn emit_name(
  ctx : Ctx,
  src : Src,
  name : String,
  args : Array[@tutuca.Expr],
) -> String raise Refused {
  if args.length() == 0 && ctx.params.get(name) is Some(i) {
    return "tg_arg_at(args, \{i})"
  }
  if builtin_call(name) is Some(fname) {
    let parts = []
    for a in args {
      parts.push(emit_expr(ctx, src, a))
    }
    return "\{fname}(" + parts.join(", ") + ")"
  }
  match ctx.callable.get(name) {
    Some(kind) => {
      guard kind is (DCompute | DPred | DInvariant) else {
        raise Refused(
          "`\{name}` is a \{@tscript.kind_word(kind)}, which is not something a value position can call",
        )
      }
      let parts = ["f", "args"]
      for a in args {
        parts.push(emit_expr(ctx, src, a))
      }
      "\{ctx.comp.id}_\{callable_suffix(kind)}_\{mangle(name)}(" +
      parts.join(", ") +
      ")"
    }
    // The checker has already rejected a name that resolves to nothing, so
    // reaching here means it resolved to something this backend has not
    // learned — a refusal, not an error.
    None => raise Refused("nothing this backend compiles is called `\{name}`")
  }
}

///|
fn callable_suffix(kind : @tscript.DeclKind) -> String {
  match kind {
    DCompute => "compute"
    DPred => "pred"
    DInvariant => "invariant"
    _ => "callable"
  }
}

///|
/// The sixteen, plus the operator spellings that share the table.
///
/// `and` / `or` / `implies` are absent on purpose: they SHORT-CIRCUIT, so they
/// are emitted as control flow by `emit_chain` rather than called with both
/// arguments already evaluated.
fn builtin_call(name : String) -> String? {
  match name {
    "empty?" => Some("b_empty")
    "truthy?" => Some("b_truthy")
    "falsy?" => Some("b_falsy")
    "null?" => Some("b_null")
    "not" => Some("b_not")
    "is" => Some("op_is")
    "is not" => Some("op_is_not")
    "<" => Some("op_lt")
    "<=" => Some("op_le")
    ">" => Some("op_gt")
    ">=" => Some("op_ge")
    "len" => Some("b_len")
    "has" => Some("b_has")
    "contains" => Some("b_contains")
    "min" => Some("b_min")
    "max" => Some("b_max")
    "clamp" => Some("b_clamp")
    "int" => Some("b_int")
    "num" => Some("b_num")
    "str" => Some("b_str")
    "lower" => Some("b_lower")
    "upper" => Some("b_upper")
    "trim" => Some("b_trim")
    _ => None
  }
}

///|
/// An operator chain.
///
/// `tscript` groups a chain by FAMILY and forbids mixing them, so each of these
/// is a left fold over one operator kind. The logic family is the exception and
/// the reason the split exists: `and` and `or` must stop, and a fold of calls
/// cannot.
fn emit_chain(
  ctx : Ctx,
  src : Src,
  family : @tutuca.OpFamily,
  ops : Array[String],
  operands : Array[@tutuca.Expr],
) -> String raise Refused {
  guard operands.length() >= 1 else {
    raise Refused("an operator chain with no operands")
  }
  let mut acc = emit_expr(ctx, src, operands[0])
  for i in 1..<operands.length() {
    let op = if i - 1 < ops.length() { ops[i - 1] } else { "" }
    // The short-circuiting three take the RIGHT OPERAND UNEVALUATED, so they
    // are handled before it is emitted. Everything else takes a value.
    if family is FLogic || family is FImplies {
      acc = emit_logic(ctx, src, op, acc, operands[i])
      continue
    }
    let rhs = emit_expr(ctx, src, operands[i])
    acc = match family {
      FLogic | FImplies => acc
      FCompare =>
        match builtin_call(op) {
          Some(f) => "\{f}(\{acc}, \{rhs})"
          None => raise Refused("no comparison called `\{op}`")
        }
      FAdd =>
        match op {
          "+" => "op_add(\{acc}, \{rhs})"
          "-" => "op_sub(\{acc}, \{rhs})"
          _ => raise Refused("no additive operator called `\{op}`")
        }
      FMul =>
        match op {
          "*" => "op_mul(\{acc}, \{rhs})"
          "/" => "op_div(\{acc}, \{rhs})"
          "mod" => "op_mod(\{acc}, \{rhs})"
          _ => raise Refused("no multiplicative operator called `\{op}`")
        }
    }
  }
  acc
}

///|
fn emit_root(
  ctx : Ctx,
  src : Src,
  root : @tutuca.PlaceRoot,
) -> String raise Refused {
  match root {
    PState(name) =>
      match ctx.comp.field_index(name) {
        Some(i) => "f[\{i}]"
        None =>
          raise Refused(
            "`.\{name}` is not a declared field of \{ctx.comp.name}",
          )
      }
    PParam(name) =>
      match ctx.params.get(name) {
        Some(i) => "tg_arg_at(args, \{i})"
        None =>
          raise Refused("`\{name}` is not a parameter of this declaration")
      }
    // The render row arrives as ARGUMENTS, positionally, because a compiled
    // declaration has no render stack to ask. Which offsets depends on the
    // shape, which is what `bind_index` is for.
    PBind(name) =>
      match bind_index(ctx.kind, name) {
        Some(i) => "tg_arg_at(args, \{i})"
        None =>
          match ctx.binds {
            // A binding an enricher wrote, read back by the same enricher.
            Some(b) => "member(\{b}, \{wax_str(name)})"
            None =>
              raise Refused(
                "`@\{name}` is a render binding, and a \{@tscript.kind_word(ctx.kind)} is handed no row",
              )
          }
      }
    // `cur` WHOLE. For a record that is the accumulated map; for a sibling it
    // is the instance, materialized HERE — at the last moment the arguments
    // can still change and the first moment they are all in. Rebinding is what
    // makes pushing `cur` twice push one child rather than build two.
    PTarget =>
      match ctx.cur {
        CurNone =>
          raise Refused(
            "`cur` has no `new` before it, so there is nothing for it to name",
          )
        CurRecord(_) => "cur"
        CurComp(name) => {
          src.line("if cur == null { return null; }")
          src.open("if kind_of(cur!) != 10 {")
          src.line(
            "cur = tg_comp(\{mangle(name)}_inst(\{mangle(name)}_desc(), \{mangle(name)}_make_fields(cur)));",
          )
          src.close("}")
          "cur"
        }
      }
  }
}

///|
/// `and`, `or` and `implies`, which must not evaluate their right operand
/// unless they have to.
///
/// Wax has no macros, so the only way to leave an operand unevaluated is to
/// emit it inside a branch — which is why every expression emitter takes the
/// source buffer.
///
/// A left operand with no answer abandons the transition. It is not read as
/// false, and that is the difference between `and` short-circuiting and `and`
/// swallowing a mistake.
fn emit_logic(
  ctx : Ctx,
  src : Src,
  op : String,
  lhs : String,
  rhs : @tutuca.Expr,
) -> String raise Refused {
  let a = ctx.temp()
  let out = ctx.temp()
  src.line("let \{a} = \{lhs};")
  src.line("let \{out}: &?tg_val = null;")
  src.open("if \{a} == null {")
  src.line("\{out} = null;")
  src.close("} else {")
  src.depth = src.depth + 1
  // `and` continues when the left is truthy; `or` and `implies` when it is not.
  // `implies` is `(not a) or b`, which is the shape most cross-field rules take.
  let (settled, keep_going) = match op {
    "and" => ("tg_bool(0)", "!= 0")
    "or" => ("tg_bool(1)", "== 0")
    "implies" => ("tg_bool(1)", "!= 0")
    _ => raise Refused("no logical operator called `\{op}`")
  }
  src.open("if tg_truthy(\{a}) \{keep_going} {")
  let b = emit_expr(ctx, src, rhs)
  let bv = ctx.temp()
  src.line("let \{bv} = \{b};")
  src.open("if \{bv} == null {")
  src.line("\{out} = null;")
  src.close("} else {")
  src.depth = src.depth + 1
  // The answer is a BOOLEAN, not the operand: `or` is not a coalescing
  // operator here, and `truthy? x` and `x` are different values.
  src.line("\{out} = tg_bool(tg_truthy(\{bv}));")
  src.depth = src.depth - 1
  src.line("}")
  src.close("} else {")
  src.depth = src.depth + 1
  src.line("\{out} = \{settled};")
  src.depth = src.depth - 1
  src.line("}")
  src.depth = src.depth - 1
  src.line("}")
  out
}

///|
/// A conditional in a value position: one arm is evaluated, the other is not.
fn emit_branch(
  ctx : Ctx,
  src : Src,
  cond : @tutuca.Expr,
  then_ : () -> @tutuca.Expr,
  else_ : () -> @tutuca.Expr,
) -> String raise Refused {
  let c = emit_expr(ctx, src, cond)
  let cv = ctx.temp()
  let out = ctx.temp()
  src.line("let \{cv} = \{c};")
  src.line("let \{out}: &?tg_val = null;")
  src.open("if \{cv} == null {")
  src.line("\{out} = null;")
  src.close("} else {")
  src.depth = src.depth + 1
  src.open("if tg_truthy(\{cv}) != 0 {")
  let t = emit_expr(ctx, src, then_())
  src.line("\{out} = \{t};")
  src.close("} else {")
  src.depth = src.depth + 1
  let f = emit_expr(ctx, src, else_())
  src.line("\{out} = \{f};")
  src.depth = src.depth - 1
  src.line("}")
  src.depth = src.depth - 1
  src.line("}")
  out
}

///|
fn emit_read(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
) -> String raise Refused {
  let mut acc = emit_root(ctx, src, place.root)
  for step in place.steps {
    acc = match step {
      PField(name) => "member(\{acc}, \{wax_str(name)})"
      PIndex(key) => "item(\{acc}, \{emit_expr(ctx, src, key)})"
    }
  }
  acc
}

///|
/// Where the render row lands in a declaration's arguments.
///
/// A compiled declaration runs after the render stack rather than inside it, so
/// `@key`, `@value` and `@iter` cannot be looked up — they are handed over. The
/// offsets differ by shape, and this table is the whole of that difference:
///
/// | | handed | answers |
/// |---|---|---|
/// | `pred` through `@when` | `(key, value, iter)` | a yes or a no |
/// | `enrich` | `(binds, key, value, iter)` | the whole binding map |
/// | `bindWith` | `()` | the whole binding map |
fn bind_index(kind : @tscript.DeclKind, name : String) -> Int? {
  let base = match kind {
    DPred | DInvariant => 0
    DEnrich => 1
    _ => return None
  }
  match name {
    "key" => Some(base)
    "value" => Some(base + 1)
    "iter" => Some(base + 2)
    _ => None
  }
}
