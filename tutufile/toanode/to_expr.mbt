// `Ex` — what the shrubbery reader produces — read straight into
// `@tutuca.Expr`, the tree everything downstream evaluates.
//
// The printer this replaces goes through tscript source: `it.n` becomes the
// text `.n`, which `@tscript.parse_text` reads back. Two grammars and a string
// in between, for a translation that is a fold over fourteen cases. Here it is
// that fold.
//
// What the string round trip actually cost is worth naming, because it is not
// only bugs: a printed expression carries no span, so every diagnostic
// downstream pointed at an offset into a synthesised attribute value rather
// than into the file the author wrote. `to_expr` takes the span it was read
// with and puts it on the node.

// The reader's tree and its error, under their own names: this package is
// where `Ex` stops being a thing to print and starts being a thing to
// translate, and qualifying every case of a fourteen-arm fold would bury the
// fold.

///|
using @lower {type Ex}

///|
using @lower {type ExError}

///|
using @lower {type Arg}

///|
using @lower {type TPart}

///|
/// Where a name is being read, which is the one thing the `Ex` tree does not
/// say on its own.
///
/// A bare name means three different things depending on position, and the old
/// path spelled the difference with sigils it printed at the last moment
/// (`bound` in `tutufile/lower/view.mbt`). It is a parameter here instead:
/// nothing is spelled, so nothing has to be re-read.
pub(all) enum NamePos {
  /// A value slot: a bare name is a binding a loop or an enricher put in
  /// scope, and reads as `@name` did.
  Bound
  /// A handler slot: a bare name is the name of the thing to run, and is not
  /// evaluated at all.
  Handler
}

///|
/// The scope a conversion runs in: what a loop renamed, and how a bare name
/// reads.
pub(all) struct ExCtx {
  /// A binder's own name to the binding the renderer answers with — `item` to
  /// `value`, `i` to `key`. The renderer's names are fixed, so this is the one
  /// place a view's own binder names exist.
  binds : Map[String, String]
  pos : NamePos
  /// Macro parameters in force, by name. A `^name` is substituted before
  /// anything becomes an `Expr` — see `subst_ex` — so by the time a conversion
  /// runs this is only what decides whether an unbound name is an error.
  params : Map[String, Ex]
}

///|
/// A value-position context with no bindings.
pub fn ExCtx::value() -> ExCtx {
  { binds: Map([]), pos: Bound, params: Map([]), }
}

///|
/// The same scope, reading names as handlers rather than as bindings.
pub fn ExCtx::as_handler(self : ExCtx) -> ExCtx {
  { binds: self.binds, pos: Handler, params: self.params, }
}

///|
/// The same scope with a macro's parameters bound to the arguments it was
/// called with.
///
/// The old path put source STRINGS in a `macro_vars` map and let the value
/// parser substitute them while reading `^name`. Here the argument is the `Ex`
/// the caller wrote, and substitution happens where the parameter is read.
pub fn ExCtx::with_params(self : ExCtx, params : Map[String, Ex]) -> ExCtx {
  { binds: self.binds, pos: self.pos, params, }
}

///|
/// The same scope with one more binder in it.
pub fn ExCtx::with_bind(self : ExCtx, name : String, as_ : String) -> ExCtx {
  let binds = Map([])
  for k, v in self.binds {
    binds[k] = v
  }
  binds[name] = as_
  { binds, pos: self.pos, params: self.params, }
}

///|
/// One expression, at the span it was read from.
pub fn to_expr(
  ex : Ex,
  ctx : ExCtx,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  let sp : @tutuca.Span = { start: span.start, end_: span.end(), }
  match ex {
    ENum(n) => @tutuca.Expr::lit(LNum(n), span=sp)
    EStr(s) => @tutuca.Expr::lit(LStr(s), span=sp)
    EBool(b) => @tutuca.Expr::lit(LBool(b), span=sp)
    ENone => @tutuca.Expr::lit(LNull, span=sp)
    EIt(f) => @tutuca.Expr::field(f, span=sp)
    // `it.state.n` and `it.n` name the same position: a property and the field
    // behind it are one place, and the old text spelled them apart only
    // because `state.` was how a script block reached past a property.
    EState(f) => @tutuca.Expr::field(f, span=sp)
    EDyn(n) => @tutuca.Expr::dyn_(n, span=sp)
    EName(n) => name_expr(n, ctx, sp)
    EMember(base, m) => member_expr(base, m, ctx, sp)
    EIndex(base, k) => index_expr(base, k, ctx, sp, span)
    ECall(callee, args) => call_expr(callee, args, ctx, sp, span)
    EBin(op, a, b) => bin_expr(op, a, b, ctx, sp, span)
    EUn("!", a) => EUnary(op=UNot, operand=to_expr(a, ctx, span), span=sp)
    EUn("-", a) => EUnary(op=UNeg, operand=to_expr(a, ctx, span), span=sp)
    EUn(op, _) =>
      raise @lower.ExError(
        message="`\{op}` is not a prefix operator",
        help="the prefix operators are `!` and `-`",
        span~,
      )
    EIf(c, a, b) =>
      EIf(
        cond=to_expr(c, ctx, span),
        then_=to_expr(a, ctx, span),
        else_=to_expr(b, ctx, span),
        span=sp,
      )
    ETemplate(parts) => tpl_expr(parts, ctx, sp, span)
    EList(_) | EMap(_) =>
      raise @lower.ExError(
        message="a list or map literal has no place in an expression",
        help="build a collection with the receiver methods — `it.xs.push(v)`",
        span~,
      )
  }
}

///|
/// A bare name. `true` / `false` / `null` are the literals they look like, an
/// Uppercase name is a component type, and what is left depends on position.
fn name_expr(n : String, ctx : ExCtx, sp : @tutuca.Span) -> @tutuca.Expr {
  match n {
    "true" => @tutuca.Expr::lit(LBool(true), span=sp)
    "false" => @tutuca.Expr::lit(LBool(false), span=sp)
    "null" | "none" => @tutuca.Expr::lit(LNull, span=sp)
    _ =>
      // A macro parameter is answered by the frame the CALLER opened, and it is
      // answered here rather than carried as an `EMacroVar` for the value layer
      // to resolve: the argument is already an expression, so there is nothing
      // left to resolve later.
      if ctx.params.get(n) is Some(arg) {
        from_macro(
          to_expr_unchecked(
            arg,
            { binds: ctx.binds, pos: ctx.pos, params: Map([]), },
            sp,
          ),
        )
      } else if ctx.pos is Handler {
        @tutuca.Expr::name(n, span=sp)
      } else if @tutuca.is_type_name(n) {
        @tutuca.Expr::type_name(n, span=sp)
      } else {
        @tutuca.Expr::bind(bound_name(n, ctx), span=sp)
      }
  }
}

///|
/// A constant that came from a macro argument, marked as one.
///
/// The bit is load-bearing rather than bookkeeping: it is what decides whether
/// a constant may pin a URL origin (`tgc/policy/external_url.mbt`), because the
/// caller's source and the component's own are different provenances. A
/// substitution that dropped it would widen what a guest may point at.
fn from_macro(e : @tutuca.Expr) -> @tutuca.Expr {
  match e {
    ELit(lit~, span~, ..) => ELit(lit~, from_macro=true, span~)
    ETpl(parts~, span~) =>
      ETpl(
        parts=parts.map(p => {
          match p {
            TText(text~, ..) => TText(text~, from_macro=true)
            other => other
          }
        }),
        span~,
      )
    other => other
  }
}

///|
/// A substituted macro argument, converted in the scope the CALL stands in.
///
/// It cannot fail in a way the caller can act on — the argument was read as an
/// expression at the call site, and a failure here would point at the macro's
/// body rather than at the argument — so a refusal degrades to the null the
/// slot would have read anyway, and the call site's own conversion is what
/// reports.
fn to_expr_unchecked(ex : Ex, ctx : ExCtx, sp : @tutuca.Span) -> @tutuca.Expr {
  to_expr(ex, ctx, @report.Span::of_range(sp.start, sp.end_)) catch {
    _ => @tutuca.Expr::lit(LNull, span=sp)
  }
}

///|
/// What the renderer calls this binder. A loop's own name is the author's;
/// `value` and `key` are the renderer's, and this is where the two meet.
fn bound_name(n : String, ctx : ExCtx) -> String {
  match ctx.binds.get(n) {
    Some(as_) => as_
    None => n
  }
}

///|
/// `e.value` reads the DOM event; every other member is a binding's.
fn member_expr(
  base : Ex,
  m : String,
  ctx : ExCtx,
  sp : @tutuca.Span,
) -> @tutuca.Expr raise ExError {
  match base {
    EName("e") => @tutuca.Expr::event_path([m], span=sp)
    EMember(EName("e"), a) => @tutuca.Expr::event_path([a, m], span=sp)
    EMember(EMember(EName("e"), a), b) =>
      @tutuca.Expr::event_path([a, b, m], span=sp)
    EName(b) => @tutuca.Expr::bind_member(bound_name(b, ctx), m, span=sp)
    _ =>
      raise @lower.ExError(
        message="a member read needs a binding or the event to read it from",
        help="`it.a.b` is refused: render the child as a component, or name the value with a `compute`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// `xs[k]` — a step below whatever the base reads.
fn index_expr(
  base : Ex,
  k : Ex,
  ctx : ExCtx,
  sp : @tutuca.Span,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  let head = to_expr(base, ctx, span)
  guard head is ERead(place~, ..) else {
    raise @lower.ExError(
      message="only a place can be indexed",
      help="index a property or a binding — `it.rows[it.key]`",
      span~,
    )
  }
  let steps = []
  for s in place.steps {
    steps.push(s)
  }
  steps.push(PIndex(to_expr(k, ctx, span)))
  ERead(place={ root: place.root, steps, span: sp, }, span=sp)
}

///|
/// A call: a builtin under its own name, anything else a `compute`.
///
/// The old printer spelled a builtin as a prefix word (`empty? .items`) and a
/// compute as `$name`, then tscript read both back into `EApp` and `EMethod`.
/// The words were never the point — they were the surface the text needed —
/// so what survives here is the mapping from a method name to the builtin it
/// names, and nothing prints.
fn call_expr(
  callee : Ex,
  args : Array[Arg],
  ctx : ExCtx,
  sp : @tutuca.Span,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  let pos = positional_args(args)
  match callee {
    // `math.max(a, b)`: a namespace, because these have no receiver
    EMember(EName("math"), name) => {
      guard ["max", "min", "clamp"].contains(name) else {
        raise @lower.ExError(
          message="`math.\{name}` is not one of the builtins",
          help="the numeric builtins are `math.min`, `math.max` and `math.clamp`",
          span~,
        )
      }
      @tutuca.Expr::app(name, args_to_exprs(pos, ctx, span), span=sp)
    }
    EMember(recv, name) =>
      match builtin_name(name) {
        Some(word) => {
          let out = [to_expr(recv, ctx, span)]
          for a in args_to_exprs(pos, ctx, span) {
            out.push(a)
          }
          @tutuca.Expr::app(word, out, span=sp)
        }
        None =>
          raise @lower.ExError(
            message="`\{name}` is not a method of a value",
            help="the reading vocabulary is closed — a derivation of your own is a `compute`, called as `\{name}(…)`",
            span~,
          )
      }
    // a bare name with no arguments is this component's own `compute`
    EName(f) =>
      if pos.is_empty() {
        @tutuca.Expr::method_(f, span=sp)
      } else {
        @tutuca.Expr::app(f, args_to_exprs(pos, ctx, span), span=sp)
      }
    _ =>
      raise @lower.ExError(
        message="only a name or a method can be called",
        help="write `name(…)` for a compute, or `value.method(…)` for a builtin",
        span~,
      )
  }
}

///|
/// The builtin a receiver method names.
///
/// The same table the printer holds, read for the NAME rather than for the
/// prefix word — `empty?` was a spelling, `is_empty` is the builtin.
fn builtin_name(name : String) -> String? {
  match name {
    "is_empty" => Some("empty?")
    "is_truthy" => Some("truthy?")
    "is_null" => Some("null?")
    "length" => Some("len")
    "has" => Some("has")
    "contains" => Some("contains")
    "to_string" => Some("str")
    "to_int" => Some("int")
    "to_number" => Some("num")
    "lower" => Some("lower")
    "upper" => Some("upper")
    "trim" => Some("trim")
    _ => None
  }
}

///|
/// A binary operator, with `x == none` folded into the shape predicate — the
/// same fold the printer does, for the same reason: a comparison against null
/// is not total and the predicate is.
fn bin_expr(
  op : String,
  a : Ex,
  b : Ex,
  ctx : ExCtx,
  sp : @tutuca.Span,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  if b is ENone {
    let inner = to_expr(a, ctx, span)
    return match op {
      "==" => @tutuca.Expr::app("null?", [inner], span=sp)
      "!=" =>
        EUnary(
          op=UNot,
          operand=@tutuca.Expr::app("null?", [inner], span=sp),
          span=sp,
        )
      _ =>
        raise @lower.ExError(
          message="`none` compares with `==` and `!=` only",
          help="write `x == none` or `x != none`",
          span~,
        )
    }
  }
  if op is (":=" | "+=" | "-=" | "*=" | "/=") {
    raise @lower.ExError(
      message="a write is not a value",
      help="write to a property in an event — `~on_input: it.query := e.value` — or read one here",
      span~,
    )
  }
  let (family, word) = op_family(op, span)
  EChain(
    family~,
    ops=[word],
    operands=[to_expr(a, ctx, span), to_expr(b, ctx, span)],
    span=sp,
  )
}

///|
/// The family an operator belongs to, and the word the runtime knows it by.
///
/// Families are the reason there is no precedence table: an unparenthesized
/// chain may only mix operators of ONE family, which shrubbery already
/// enforces on the way in.
fn op_family(
  op : String,
  span : @report.Span,
) -> (@tutuca.OpFamily, String) raise ExError {
  match op {
    "==" => (FCompare, "is")
    "!=" => (FCompare, "is not")
    "<" | "<=" | ">" | ">=" => (FCompare, op)
    "&&" => (FLogic, "and")
    "||" => (FLogic, "or")
    "implies" => (FImplies, "implies")
    "+" | "-" => (FAdd, op)
    "*" | "/" | "mod" => (FMul, op)
    _ =>
      raise @lower.ExError(
        message="`\{op}` is not an operator here",
        help="the operators are the comparisons, `&&`, `||`, `implies`, `+`, `-`, `*`, `/` and `mod`",
        span~,
      )
  }
}

///|
/// `@str{…}` — text and holes, in source order.
///
/// The bookend trim matches `parse_str_tpl`: splitting on holes leaves empty
/// text at the ends, and a reader that kept them would see a different tree
/// for the same template depending on where the holes fell.
fn tpl_expr(
  parts : Array[TPart],
  ctx : ExCtx,
  sp : @tutuca.Span,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  let out : Array[@tutuca.TplPart] = []
  for p in parts {
    match p {
      TText(t) => out.push(TText(text=t, from_macro=false))
      // A hole is already a call site, so a `compute` in one is NAMED rather
      // than called — asking the render stack from inside a hole would be
      // asking it after it answered.
      THole(ECall(EName(f), args)) if positional_args(args).is_empty() =>
        out.push(TExpr(@tutuca.Expr::method_(f, span=sp)))
      THole(h) =>
        match to_expr(h, ctx, span) {
          ELit(lit=LStr(t), from_macro~, ..) =>
            out.push(TText(text=t, from_macro~))
          v => out.push(TExpr(v))
        }
    }
  }
  trim_bookends(out)
  @tutuca.Expr::tpl(out, span=sp)
}

///|
/// Drop the empty constant bookends a hole split leaves behind, keeping the
/// macro-bound ones — those are real placeholders a linter has to see.
fn trim_bookends(parts : Array[@tutuca.TplPart]) -> Unit {
  fn trimmable(p : @tutuca.TplPart) -> Bool {
    p is TText(text="", from_macro=false)
  }

  while parts.length() > 0 && trimmable(parts[parts.length() - 1]) {
    parts.pop() |> ignore
  }
  while parts.length() > 0 && trimmable(parts[0]) {
    parts.remove(0) |> ignore
  }
}

///|
/// The positional arguments of a call. A keyword one has no place in a value
/// position, and is dropped here the way the printer dropped it.
fn positional_args(args : Array[Arg]) -> Array[Ex] {
  let out = []
  for a in args {
    if a is APos(e) {
      out.push(e)
    }
  }
  out
}

///|
fn args_to_exprs(
  args : Array[Ex],
  ctx : ExCtx,
  span : @report.Span,
) -> Array[@tutuca.Expr] raise ExError {
  let out = []
  for a in args {
    out.push(to_expr(a, ctx, span))
  }
  out
}
