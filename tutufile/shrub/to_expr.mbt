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

///|

///|

///|

///|
/// Where a name is being read, which is the one thing the `Ex` tree does not
/// say on its own.
///
/// A bare name means three different things depending on position, and the old
/// path spelled the difference with sigils it printed at the last moment
/// (`bound`, in the printer this replaced). It is a parameter here instead:
/// nothing is spelled, so nothing has to be re-read.
pub(all) enum NamePos {
  /// A value slot: a bare name is a binding a loop or an enricher put in
  /// scope, and reads as `@name` did.
  Bound
  /// A handler slot: a bare name is the name of the thing to run, and is not
  /// evaluated at all.
  Handler
  /// A `logic:` body: a name the body itself bound is a binding, and anything
  /// else is a free name — a parameter, or a `compute` called with none. The
  /// two are told apart by the scope and not by the position, which is what
  /// makes this its own case rather than one of the two above.
  Local
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
  /// The HOST's table, when there is a host: what `host.name` resolves to.
  ///
  /// `None` and an empty table are different answers, and the difference is
  /// the whole reason this is an option. `None` is "nobody is loading this
  /// yet" — the ahead-of-time path, where a `host.name` stays an `EConfigVar`
  /// for a backend to refuse or a generator to write down. `Some` is a host
  /// that HAS a table, and a name missing from it is an error rather than a
  /// symbol to carry: the view would render Null against a variable the host
  /// never offered.
  config : Map[String, String]?
}

///|
/// A value-position context with no bindings.
pub fn ExCtx::value() -> ExCtx {
  { binds: Map([]), pos: Bound, params: Map([]), config: None, }
}

///|
/// A `logic:` body's scope: bound names are bindings, the rest are free.
pub fn ExCtx::in_body(binds : Map[String, String]) -> ExCtx {
  { binds, pos: Local, params: Map([]), config: None, }
}

///|
/// The same scope, reading names as handlers rather than as bindings.
pub fn ExCtx::as_handler(self : ExCtx) -> ExCtx {
  { binds: self.binds, pos: Handler, params: self.params, config: self.config, }
}

///|
/// The same scope with a macro's parameters bound to the arguments it was
/// called with.
///
/// The old path put source STRINGS in a `macro_vars` map and let the value
/// parser substitute them while reading `^name`. Here the argument is the `Ex`
/// the caller wrote, and substitution happens where the parameter is read.
pub fn ExCtx::with_params(self : ExCtx, params : Map[String, Ex]) -> ExCtx {
  { binds: self.binds, pos: self.pos, params, config: self.config, }
}

///|
/// The same scope, resolving `host.name` against a host's table.
///
/// A host that loads a card HAS a table; the ahead-of-time path does not, and
/// leaves the reference symbolic. See `ExCtx.config`.
pub fn ExCtx::with_config(self : ExCtx, config : Map[String, String]) -> ExCtx {
  {
    binds: self.binds,
    pos: self.pos,
    params: self.params,
    config: Some(config),
  }
}

///|
/// The same scope with one more binder in it.
pub fn ExCtx::with_bind(self : ExCtx, name : String, as_ : String) -> ExCtx {
  let binds = Map([])
  for k, v in self.binds {
    binds[k] = v
  }
  binds[name] = as_
  { binds, pos: self.pos, params: self.params, config: self.config, }
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
    EMember(base, m) => member_expr(base, m, ctx, sp, span)
    EIndex(base, k) => index_expr(base, k, ctx, sp, span)
    ECall(callee, args) => call_expr(callee, args, ctx, sp, span)
    EBin(op, a, b) => bin_expr(op, a, b, ctx, sp, span)
    EUn("!", a) => EUnary(op=UNot, operand=to_expr(a, ctx, span), span=sp)
    EUn("-", a) => EUnary(op=UNeg, operand=to_expr(a, ctx, span), span=sp)
    EUn(op, _) =>
      raise ExError(
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
      raise ExError(
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
            {
              binds: ctx.binds,
              pos: ctx.pos,
              params: Map([]),
              config: ctx.config,
            },
            sp,
          ),
        )
      } else if ctx.pos is Handler {
        @tutuca.Expr::name(n, span=sp)
      } else if ctx.pos is Local {
        if ctx.binds.get(n) is Some(as_) {
          @tutuca.Expr::bind(as_, span=sp)
        } else {
          @tutuca.Expr::name(n, span=sp)
        }
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
pub fn from_macro(e : @tutuca.Expr) -> @tutuca.Expr {
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
/// The `PParam` root this name is, when a path attached to it is a path into a
/// handler's argument.
///
/// Only in a `logic:` body, and only for a name the body did not bind: a
/// binding shadows a parameter for the same reason a `let` shadows anything,
/// and outside a body there are no parameters to read. `None` everywhere else
/// leaves the name to the arms that already handle it.
fn param_root(n : String, ctx : ExCtx) -> @tutuca.PlaceRoot? {
  guard ctx.pos is Local else { return None }
  guard ctx.binds.get(n) is None else { return None }
  guard ctx.params.get(n) is None else { return None }
  Some(PParam(n))
}

///|
/// `e.value` reads the DOM event; every other member is a binding's.
fn member_expr(
  base : Ex,
  m : String,
  ctx : ExCtx,
  sp : @tutuca.Span,
  span : @report.Span,
) -> @tutuca.Expr raise ExError {
  match base {
    // `host.name` is the HOST's, not a binding's. It is matched before
    // `EName(b)` below because that arm would otherwise read it as a binding
    // called `host` — which is not a name error anywhere, so it would render
    // Null and pin nothing, and `tgc/policy` would judge a host-supplied
    // origin as if the component had made it up.
    EName("host") => config_expr(m, ctx, sp)
    // `e.a.b.c…`, to any depth. Three levels were spelled out here and the
    // fourth fell through to the binding arm, so
    // `e.target.ownerDocument.defaultView.localStorage.length` — the exact
    // shape the event-path allowlist exists to advise about — was refused as a
    // member read instead of reaching the rule. WHICH steps are allowed is
    // `@eventpath`'s question, and it needs the path to ask it about.
    _ if event_root(base) is Some(head) => {
      head.push(m)
      @tutuca.Expr::event_path(head, span=sp)
    }
    // `t.iso` where `t` is the handler's own parameter. A body's free name is
    // a parameter, so a path attached to one is a path into the argument the
    // caller handed over — which `PParam` is the root for, and which
    // `tscript/check` already answers `NO_PARAM` about when the name is not
    // one. Matched before the binding arm below, because that arm reads every
    // bare name as a binding: a card taking `{ms, iso, …}` from a host and
    // reading `.iso` off it was told `@t` is a binding a handler does not
    // have, and the handler was refused.
    EName(b) if param_root(b, ctx) is Some(root) =>
      ERead(place={ root, steps: [PField(m)], span: sp, }, span=sp)
    EName(b) => @tutuca.Expr::bind_member(bound_name(b, ctx), m, span=sp)
    // `it.a.b` in a `logic:` BODY is a step below a step, and legal: a body is
    // checked code and the generator knows every type along the path. In a
    // view it is not — a slot's name lookup stays one level because nothing
    // checks it — which is why the position decides and not the shape.
    _ if ctx.pos is Local => {
      let head = to_expr(base, ctx, span)
      guard head is ERead(place~, ..) else {
        raise ExError(
          message="only a place has members",
          help="write `it.<field>.<member>`, or name the value with a `compute`",
          span~,
        )
      }
      let steps = []
      for s in place.steps {
        steps.push(s)
      }
      steps.push(PField(m))
      ERead(place={ root: place.root, steps, span: sp, }, span=sp)
    }
    _ =>
      raise ExError(
        message="a member read needs a binding or the event to read it from",
        help="`it.a.b` is refused in a view: render the child as a component, or name the value with a `compute`",
        span~,
      )
  }
}

///|
/// `host.name`, against the table the loader supplied — or symbolic.
///
/// The value is SUBSTITUTED rather than re-read as source: it is text the host
/// decided, and reading it back as an expression would let a host's table
/// smuggle in an expression nobody asked for.
fn config_expr(
  name : String,
  ctx : ExCtx,
  sp : @tutuca.Span,
) -> @tutuca.Expr raise ExError {
  match ctx.config {
    None => EConfigVar(name~, span=sp)
    Some(table) =>
      match table.get(name) {
        Some(v) => @tutuca.Expr::lit(LStr(v), span=sp)
        None =>
          raise ExError(
            message="the host offers no `host.\{name}`",
            help="a host names what a view may read; write one it configured, or ask for `\{name}` to be added",
            span=@report.Span::of_range(sp.start, sp.end_),
          )
      }
  }
}

///|
/// The segments under `e`, when this expression is rooted at the event.
///
/// `None` for anything else, which is what keeps a binding called `e` from
/// being read as one — the root has to be the bare name.
fn event_root(base : Ex) -> Array[String]? {
  match base {
    EName("e") => Some([])
    EMember(inner, seg) =>
      match event_root(inner) {
        Some(head) => {
          head.push(seg)
          Some(head)
        }
        None => None
      }
    _ => None
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
  // A parameter is a place when something is attached to it, and only then:
  // a bare `t` stays the free name the backend resolves. Same seam as
  // `member_expr`, so `f.items` and `f[0]` agree about what `f` is.
  let head = match base {
    EName(b) if param_root(b, ctx) is Some(root) =>
      @tutuca.Expr::ERead(place={ root, steps: [], span: sp, }, span=sp)
    _ => to_expr(base, ctx, span)
  }
  guard head is ERead(place~, ..) else {
    raise ExError(
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
        raise ExError(
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
          raise ExError(
            message="`\{name}` is not a method of a value",
            help="the reading vocabulary is closed — a derivation of your own is a `compute`, called as `\{name}(…)`",
            span~,
          )
      }
    // a bare name with no arguments is this component's own `compute`
    //
    // …in a VIEW. In a `logic:` body it is a plain name, and the difference is
    // not cosmetic: an `EMethod` is answered by the RENDER STACK, and a body
    // runs after one has finished, so `mode()` written in a body read Null.
    // The two are one call in the notation and the position decides which
    // form it takes — which is what the checker's own repair says to do.
    EName(f) =>
      if pos.is_empty() {
        // An UPPERCASE name is a component or a record being built — `Hole()`
        // in `it.children.push(Hole())` — and a body reaches one the same way
        // a view does, which is why the position does not decide for it.
        if ctx.pos is Local && !@tutuca.is_type_name(f) {
          @tutuca.Expr::name(f, span=sp)
        } else {
          @tutuca.Expr::method_(f, span=sp)
        }
      } else {
        @tutuca.Expr::app(f, args_to_exprs(pos, ctx, span), span=sp)
      }
    _ =>
      raise ExError(
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
        raise ExError(
          message="`none` compares with `==` and `!=` only",
          help="write `x == none` or `x != none`",
          span~,
        )
    }
  }
  if op is (":=" | "+=" | "-=" | "*=" | "/=") {
    raise ExError(
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
      raise ExError(
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
      // A hole is an ordinary expression slot: `call_expr` decides what
      // `mode()` becomes, and the POSITION is what decides it — the render
      // stack's `$name` in a view, a plain call in a `logic:` body. This arm
      // used to force the first form here, so a `compute` called inside a
      // template inside another compute's body read Null.
      THole(h) =>
        match to_expr(h, ctx, span) {
          ELit(lit=LStr(t), from_macro~, ..) =>
            out.push(TText(text=t, from_macro~))
          v => out.push(TExpr(v))
        }
    }
  }
  trim_bookends(out)
  // A template with no holes left in it IS a string, and folding it here is
  // what makes every consumer agree about one. `~format: @str{a sentence}`
  // read back as a one-part template, and the two places that show a rule's
  // sentence — a broken invariant's report, a declined transition's log —
  // print a literal and print nothing for a template, so the author's words
  // came out as the rule's NAME.
  let mut all_text = true
  let text = StringBuilder()
  let mut from_macro = false
  for p in out {
    match p {
      TText(text=t, from_macro=fm) => {
        text.write_string(t)
        if fm {
          from_macro = true
        }
      }
      TExpr(_) => all_text = false
    }
  }
  if all_text {
    return ELit(lit=LStr(text.to_string()), from_macro~, span=sp)
  }
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
pub fn positional_args(args : Array[Arg]) -> Array[Ex] {
  let out = []
  for a in args {
    if a is APos(e) {
      out.push(e)
    }
  }
  out
}

///|
pub fn args_to_exprs(
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
