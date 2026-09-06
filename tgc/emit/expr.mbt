// Expressions.
//
// Every expression compiles to a wap expression of type `tg_val?`, and a null
// means THE TRANSITION HAS NO ANSWER. That is what lets the emitters compose
// freely: a runtime operation with no answer for its arguments returns null,
// null propagates through everything above it, and the statement checks once at
// the top instead of the emitter threading a failure flag through every
// operand.
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
/// rather than a request to the host.
priv enum CurKind {
  CurNone
  /// No name, because nothing needs one: a record needs no materialization —
  /// the accumulated map IS the value — so nothing lowers differently per
  /// record type. A component's name is used, which is why that one carries it.
  CurRecord
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
/// Emit an expression as a wap node.
///
/// Under Wax this answered a STRING and wrote statements into a shared buffer as
/// a side effect, because the three short-circuiting forms — `and`, `or` and a
/// conditional — had nowhere to put an unevaluated operand except a branch, and
/// a branch is a statement. wap has `if` as an expression and a block as a
/// value, so a short circuit is a TREE and every emitter below is a function of
/// its input again.
fn emit_expr(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  e : @tutuca.Expr,
) -> @wast.Node raise Refused {
  match e {
    ELit(lit~, span~, ..) =>
      match lit {
        LNull => at(b, span, b.rt("tg_null", []))
        LBool(v) =>
          at(b, span, b.rt("tg_bool", [b.int_(if v { 1 } else { 0 })]))
        LNum(n) => at(b, span, b.rt("tg_num", [b.num(n)]))
        LStr(s) => at(b, span, b.rt("tg_str", [b.str_(s)]))
      }
    ETpl(parts~, ..) => emit_tpl(ctx, b, out, parts)
    ERead(place~, ..) => emit_read(ctx, b, out, place)
    EName(name~, ..) => emit_name(ctx, b, out, name, [])
    EApp(name~, args~, ..) => emit_name(ctx, b, out, name, args)
    EChain(family~, ops~, operands~, ..) =>
      emit_chain(ctx, b, out, family, ops, operands)
    EUnary(op~, operand~, span~) => {
      let inner = emit_expr(ctx, b, out, operand)
      let f = match op {
        UNot => "b_not"
        UNeg => "op_neg"
      }
      at(b, span, b.rt(f, [inner]))
    }
    // A conditional evaluates ONE arm, so both arms are emitted inside
    // branches rather than beside each other. A condition with no answer
    // abandons the transition rather than being read as false.
    EIf(cond~, then_~, else_~, ..) =>
      emit_branch(ctx, b, out, cond, then_, else_)
    // A handler is handed no render row, so `@binding` has nothing to mean
    // here; `$method` is answered by the render stack and a compiled handler
    // runs after one.
    EMethod(name~, ..) =>
      raise Refused(
        "`$\{name}` is answered by the render stack, and a handler runs after one",
      )
    // A `*name` is NOT a render read, even though it looks like one. The host
    // resolves this component's declared lookups before it calls in — for a
    // dispatch and for a render call alike — and hands the map over in the
    // call's fifth slot, so this is a lookup in a map that is already here.
    //
    // The exception is a property SET, whose fifth slot carries the value being
    // written; `dyn` is null there and this reads null, which is what "nothing
    // above provides one" answers anyway.
    EDyn(name~, span~) =>
      at(b, span, b.rt("member", [b.var_("dyn"), b.str_(name)]))
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
        "`host.\{name}` is a host config variable, which this backend does not carry yet",
      )
    ETypeName(name~, ..) =>
      raise Refused("`\{name}` is a type name, and a type is not a value")
  }
}

///|
/// Put the author's span on a node the emitter just built.
///
/// The node's own span is the emitter's, which points nowhere; this is the one
/// place the card's position is attached, and it is why a wap diagnostic names
/// a line the author can find. `tgc/1` had nothing to attach — it prepended the
/// preamble as text and subtracted its line count from every message afterwards.
fn at(b : B, span : @tutuca.Span, n : @wast.Node) -> @wast.Node {
  { it: n.it, span: b.at(span), }
}

///|
/// A `$'…'` template: display each part and join.
///
/// Left-folded rather than joined through a builder because the parts are known
/// at compile time and a fold of two-argument concatenations is what the
/// runtime has. A template of one literal part is that literal.
fn emit_tpl(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  parts : Array[@tutuca.TplPart],
) -> @wast.Node raise Refused {
  if parts.length() == 0 {
    return b.rt("tg_str", [b.str_("")])
  }
  let pieces : Array[@wast.Node] = []
  for p in parts {
    match p {
      TText(text~, ..) => pieces.push(b.str_(text))
      TExpr(inner) =>
        pieces.push(b.rt("display", [emit_expr(ctx, b, out, inner)]))
    }
  }
  let mut acc = pieces[0]
  for i in 1..<pieces.length() {
    acc = b.rt("concat", [acc, pieces[i]])
  }
  b.rt("tg_str", [acc])
}

///|
/// A bare name, or a name applied to arguments.
///
/// Three things it can be, in the order the language resolves them: a parameter
/// of this declaration, one of the sixteen builtins, or a `compute` / `pred` /
/// `invariant` this component declares. Nothing else — the vocabulary is
/// closed, and `tscript/script_builtin.mbt` means it.
fn emit_name(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  name : String,
  args : Array[@tutuca.Expr],
) -> @wast.Node raise Refused {
  if args.length() == 0 && ctx.params.get(name) is Some(i) {
    return b.rt("tg_arg_at", [b.var_("args"), b.int_(i)])
  }
  if builtin_call(name) is Some(fname) {
    let parts : Array[@wast.Node] = []
    for a in args {
      parts.push(emit_expr(ctx, b, out, a))
    }
    return b.rt(fname, parts)
  }
  match ctx.callable.get(name) {
    Some(kind) => {
      guard kind is (DCompute | DPred | DInvariant) else {
        raise Refused(
          "`\{name}` is a \{@tscript.kind_word(kind)}, which is not something a value position can call",
        )
      }
      // A callable reads its arguments out of a `tg_vals`, so a call with
      // arguments BUILDS one rather than spreading them: the callee's shape is
      // fixed by the vtable and cannot vary per call site. `dyn` rides through
      // unchanged — a `*name` read inside a callee is the same lookup the
      // caller resolved.
      let vals : Array[@wast.Node] = []
      for a in args {
        vals.push(emit_expr(ctx, b, out, a))
      }
      let arg_list = if vals.is_empty() {
        b.var_("args")
      } else {
        b.vals_of(vals)
      }
      b.call("\{ctx.comp.id}_\{callable_suffix(kind)}_\{mangle(name)}", [
        b.var_("f"),
        arg_list,
        b.var_("dyn"),
      ])
    }
    // The checker has already rejected a name that resolves to nothing, so
    // reaching here means it resolved to something this backend has not learned
    // — a refusal, not an error.
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
/// are emitted as a branch by `emit_chain` rather than called with both
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
  b : B,
  out : Array[@wast.Node],
  family : @tutuca.OpFamily,
  ops : Array[String],
  operands : Array[@tutuca.Expr],
) -> @wast.Node raise Refused {
  guard operands.length() >= 1 else {
    raise Refused("an operator chain with no operands")
  }
  let mut acc = emit_expr(ctx, b, out, operands[0])
  for i in 1..<operands.length() {
    let op = if i - 1 < ops.length() { ops[i - 1] } else { "" }
    // The short-circuiting three take the RIGHT OPERAND UNEVALUATED, so they
    // are handled before it is emitted. Everything else takes a value.
    if family is FLogic || family is FImplies {
      acc = emit_logic(ctx, b, out, op, acc, operands[i])
      continue
    }
    let rhs = emit_expr(ctx, b, out, operands[i])
    let f = match family {
      FLogic | FImplies => "" // unreachable: handled above
      FCompare =>
        match builtin_call(op) {
          Some(f) => f
          None => raise Refused("no comparison called `\{op}`")
        }
      FAdd =>
        match op {
          "+" => "op_add"
          "-" => "op_sub"
          _ => raise Refused("no additive operator called `\{op}`")
        }
      FMul =>
        match op {
          "*" => "op_mul"
          "/" => "op_div"
          "mod" => "op_mod"
          _ => raise Refused("no multiplicative operator called `\{op}`")
        }
    }
    acc = b.rt(f, [acc, rhs])
  }
  acc
}

///|
fn emit_root(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  root : @tutuca.PlaceRoot,
) -> @wast.Node raise Refused {
  match root {
    PState(name) =>
      match ctx.comp.field_index(name) {
        Some(i) => b.made(Index(b.var_("f"), b.int_(i)))
        None =>
          raise Refused(
            "`.\{name}` is not a declared field of \{ctx.comp.name}",
          )
      }
    PParam(name) =>
      match ctx.params.get(name) {
        Some(i) => b.rt("tg_arg_at", [b.var_("args"), b.int_(i)])
        None =>
          raise Refused("`\{name}` is not a parameter of this declaration")
      }
    // The render row arrives as ARGUMENTS, positionally, because a compiled
    // declaration has no render stack to ask. Which offsets depends on the
    // shape, which is what `bind_index` is for.
    PBind(name) =>
      match bind_index(ctx.kind, name) {
        Some(i) => b.rt("tg_arg_at", [b.var_("args"), b.int_(i)])
        None =>
          match ctx.binds {
            // A binding an enricher wrote, read back by the same enricher.
            Some(bind) => b.rt("member", [b.var_(bind), b.str_(name)])
            None =>
              raise Refused(
                "`@\{name}` is a render binding, and a \{@tscript.kind_word(ctx.kind)} is handed no row",
              )
          }
      }
    // `cur` WHOLE. For a record that is the accumulated map; for a sibling it is
    // the instance, materialized HERE — at the last moment the arguments can
    // still change and the first moment they are all in. Rebinding is what makes
    // pushing `cur` twice push one child rather than build two.
    PTarget =>
      match ctx.cur {
        CurNone =>
          raise Refused(
            "`cur` has no `new` before it, so there is nothing for it to name",
          )
        CurRecord => b.var_("cur")
        CurComp(name) => {
          // A block, because materializing is three statements and the value of
          // the whole is still `cur`. Under Wax these lines went into the
          // enclosing buffer and the expression was the bare name; the reader
          // had to find them above.
          let m = mangle(name)
          out.push(b.if_(b.is_null(b.var_("cur")), [b.ret(Some(b.null_()))]))
          out.push(
            b.if_(
              b.made(
                Bin(Ne, b.rt("kind_of", [b.force(b.var_("cur"))]), b.int_(10)),
              ),
              [
                b.set(
                  b.var_("cur"),
                  b.rt("tg_comp", [
                    b.call("\{m}_inst", [
                      b.call("\{m}_desc", []),
                      b.call("\{m}_make_fields", [b.var_("cur")]),
                    ]),
                  ]),
                ),
              ],
            ),
          )
          b.var_("cur")
        }
      }
  }
}

///|
/// `and`, `or` and `implies`, which must not evaluate their right operand
/// unless they have to.
///
/// A left operand with no answer abandons the transition. It is not read as
/// false, and that is the difference between `and` short-circuiting and `and`
/// swallowing a mistake.
///
/// Under Wax this was twenty lines of `src.depth = src.depth ± 1` around a
/// mutable `out` local, because the only way to leave an operand unevaluated
/// was to emit it inside a branch and a branch was a statement. It is the same
/// three-way decision, written once.
fn emit_logic(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  op : String,
  lhs : @wast.Node,
  rhs : @tutuca.Expr,
) -> @wast.Node raise Refused {
  // `and` continues when the left is truthy; `or` and `implies` when it is not.
  // `implies` is `(not a) or b`, which is the shape most cross-field rules take.
  let (settled, keep_going_truthy) = match op {
    "and" => (0, true)
    "or" => (1, false)
    "implies" => (1, true)
    _ => raise Refused("no logical operator called `\{op}`")
  }
  let a = ctx.temp()
  let res = ctx.temp()
  out.push(b.bind(res, b.null_(), typ=opt_val(), mutable=true))
  out.push(b.bind(a, lhs))
  // The right operand is emitted INSIDE the branch, which is the whole point:
  // it must not run when the left already settled the answer.
  let right : Array[@wast.Node] = []
  let bv = ctx.temp()
  let rv = emit_expr(ctx, b, right, rhs)
  right.push(b.bind(bv, rv))
  right.push(
    b.if_(
      b.is_null(b.var_(bv)),
      [b.set(b.var_(res), b.null_())],
      // The answer is a BOOLEAN, not the operand: `or` is not a coalescing
      // operator here, and `truthy? x` and `x` are different values.
      else_=[
        b.set(b.var_(res), b.rt("tg_bool", [b.rt("tg_truthy", [b.var_(bv)])])),
      ],
    ),
  )
  let keep_going = b.made(
    Bin(
      if keep_going_truthy {
        Ne
      } else {
        Eq
      },
      b.rt("tg_truthy", [b.var_(a)]),
      b.int_(0),
    ),
  )
  out.push(
    b.if_(b.is_null(b.var_(a)), [b.set(b.var_(res), b.null_())], else_=[
      b.if_(keep_going, right, else_=[
        b.set(b.var_(res), b.rt("tg_bool", [b.int_(settled)])),
      ]),
    ]),
  )
  b.var_(res)
}

///|
/// A conditional in a value position: one arm is evaluated, the other is not.
///
/// The arms are emitted into their OWN statement lists and spliced into the
/// branches, which is what makes "one arm is evaluated" true. A result local
/// carries the answer out, because a wap block that binds cannot itself be the
/// value of a binding — Wax's `let` scopes over the rest of its sequence, so a
/// `let` nested inside a `let`'s value is not a shape it can type. That is the
/// same reason the Wax backend before this one wrote a mutable `out` local, and
/// it survives the port.
fn emit_branch(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  cond : @tutuca.Expr,
  then_ : @tutuca.Expr,
  else_ : @tutuca.Expr,
) -> @wast.Node raise Refused {
  let cv = ctx.temp()
  let res = ctx.temp()
  let c = emit_expr(ctx, b, out, cond)
  out.push(b.bind(res, b.null_(), typ=opt_val(), mutable=true))
  out.push(b.bind(cv, c))
  let then_nodes : Array[@wast.Node] = []
  let tv = emit_expr(ctx, b, then_nodes, then_)
  then_nodes.push(b.set(b.var_(res), tv))
  let else_nodes : Array[@wast.Node] = []
  let ev = emit_expr(ctx, b, else_nodes, else_)
  else_nodes.push(b.set(b.var_(res), ev))
  out.push(
    b.if_(b.is_null(b.var_(cv)), [b.set(b.var_(res), b.null_())], else_=[
      b.if_(
        b.made(Bin(Ne, b.rt("tg_truthy", [b.var_(cv)]), b.int_(0))),
        then_nodes,
        else_=else_nodes,
      ),
    ]),
  )
  b.var_(res)
}

///|
fn emit_read(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  place : @tutuca.Place,
) -> @wast.Node raise Refused {
  let mut acc = emit_root(ctx, b, out, place.root)
  for step in place.steps {
    acc = match step {
      PField(name) => b.rt("member", [acc, b.str_(name)])
      PIndex(key) => b.rt("item", [acc, emit_expr(ctx, b, out, key)])
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
