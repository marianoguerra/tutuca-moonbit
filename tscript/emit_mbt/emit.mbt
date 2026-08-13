// The MoonBit backend. Implements the declares in spec.mbt.
//
// Every expression is emitted with the LANGUAGE type it has, and conversion
// happens where a value meets a declared type — `to_double()` on the way out
// of an integer field, `to_int()` on the way in. Doing it that way rather than
// tracking MoonBit types directly is what makes this backend agree with the
// interpreter without either consulting the other: the interpreter's `Value`
// has one number, so a language that rounds at the boundary and one that has
// only Doubles round the same expression the same way.
//
// Failure is `return None`, everywhere, for the same reason it is `no change`
// in the interpreter: it is the contract `update` already has.

///|
/// One declaration's compilation, or the reason it did not compile.
priv suberror NoWay {
  Cannot(String)
}

///|
priv struct E {
  def : @statedef.StateDef
  /// The generated state struct's name. Needed by `spread`, for the one
  /// literal that carries no `..s` to infer from.
  state_ty : String
  /// Parameter name -> its language type, or None for a raw `@tutuca.Value`.
  mut params : Map[String, @statedef.StateTy?]
  /// Statements the current one needs FIRST — a bounds check, a divisor
  /// test. They answer `Unchanged`, which is what "the arm claimed the name
  /// and there was nothing to do" means, and it is the answer the interpreter
  /// gives for the same input.
  ///
  /// Collected on the way down and flushed by `stmt`, because a guard is a
  /// statement and the thing that needs it is an expression.
  mut prelude : Array[String]
  /// Whether any arm that SURVIVED reached for `ctx`. A block of pure state
  /// transitions names the parameter `_ctx`, because a generated file must not
  /// be the thing that warns.
  mut uses_ctx : Bool
}

///|
pub fn emit(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  state_ty~ : String,
  fn_name~ : String,
  surface? : @check.Surface = @check.Surface::empty(),
) -> Emitted {
  let e = E::{ def, state_ty, params: Map([]), prelude: [], uses_ctx: false }
  let arms : Array[String] = []
  let refusals : Array[Refusal] = []
  let answers : Map[String, Array[String]] = {
    "Input": [],
    "Receive": [],
    "Bubble": [],
    "Response": [],
  }
  for d in decls {
    let bucket = match d.kind {
      DOn => "Input"
      DReceive => "Receive"
      DBubble => "Bubble"
      DResponse => "Response"
      // A `compute`, a `pred`, an `enrich`: not a transition, so not this
      // function's business. Answered elsewhere or not at all, and silently
      // skipped rather than refused — refusing would report a problem where
      // there is none.
      _ => continue
    }
    e.params = Map([])
    let before = e.uses_ctx
    let arm = e.arm(d, bucket, surface) catch {
      Cannot(why) => {
        // A refused arm is not emitted, so whatever it reached for does not
        // count towards what the function's parameters are used for.
        e.uses_ctx = before
        refusals.push({ name: d.name, why, span: d.span })
        continue
      }
    }
    arms.push(arm)
    answers.get(bucket).unwrap().push(d.name)
  }
  let source = if arms.is_empty() {
    ""
  } else {
    let b = StringBuilder::new()
    b.write_string("///|\n")
    b.write_string(
      "/// The dispatches the `<script type=\"tutuca/script\">` block answers.\n",
    )
    b.write_string("///\n")
    b.write_string(
      "/// Composed AHEAD of the author's `update~`, which stays optional and is\n",
    )
    b.write_string(
      "/// consulted only for a name this does not answer. GENERATED — edit the\n",
    )
    b.write_string("/// block, not this.\n")
    b.write_string(
      "fn \{fn_name}(\n  s : \{state_ty},\n  msg : @component.Dispatch,\n  \{if e.uses_ctx { "ctx" } else { "_ctx" }} : &@tutuca.Ctx,\n) -> @component.Update[\{state_ty}] {\n",
    )
    b.write_string("  match msg {\n")
    for a in arms {
      b.write_string(a)
    }
    // Every other name falls through, which is the documented precedence: the
    // author's `update`, then the generated mutators.
    b.write_string("    _ => Unhandled\n")
    b.write_string("  }\n}\n")
    b.to_string()
  }
  {
    source,
    answers_input: answers.get("Input").unwrap(),
    answers_receive: answers.get("Receive").unwrap(),
    answers_bubble: answers.get("Bubble").unwrap(),
    answers_response: answers.get("Response").unwrap(),
    refusals,
  }
}

///|
/// One match arm.
fn E::arm(
  self : E,
  d : @tscript.Decl,
  bucket : String,
  surface : @check.Surface,
) -> String raise NoWay {
  guard d.body is Stmts(body) else {
    raise Cannot("a value body is not a transition")
  }
  let b = StringBuilder::new()
  // `_args` when the declaration takes none: a generated file must not be the
  // thing that warns.
  let args_binder = if d.params.is_empty() { "_args" } else { "args" }
  b.write_string("    \{bucket}(\{quote(d.name)}, \{args_binder}) => {\n")
  // Parameters, decoded from the dispatch arguments by their declared or
  // inferred type. A shape that does not match is `None` — the same answer
  // every generated mutator gives when handed something it cannot use.
  // The effect queue, when the body has any. Effects go out ONLY when the
  // body FINISHED: half a transition — nothing moved but a message went out —
  // is the one outcome nobody can reason about afterwards, and it is what the
  // interpreter's `Outcome` already says by dropping them with the state. A
  // `guard … else { return Unchanged }` anywhere below leaves the queue
  // unflushed, which is the whole point of it being a queue.
  let types = self.param_types(d, surface)
  for i, p in d.params {
    let ty = types.get(i).unwrap_or(None)
    self.params[p.name] = ty
    // Bound only when the body reads it. The SHAPE is still checked either
    // way — a `setLabel 3` must refuse whether or not the body looks at the
    // argument — but a binding nobody uses is a warning, and a generated file
    // must not be the thing that warns.
    let binder = if uses_name(body, p.name) { p.name } else { "_" }
    let pat = match ty {
      Some(TInt(..)) | Some(TFloat) => "Num(\{binder})"
      Some(TText) => "Str(\{binder})"
      Some(TBool) => "Bool(\{binder})"
      // Unknown, or a shape with no pattern worth writing: the raw value.
      // Using one where a type is wanted is refused below rather than guessed.
      _ => binder
    }
    // An argument of the wrong shape is `Unchanged`, not `Unhandled`: this
    // arm DID claim the name, and letting `add 'x'` fall through to a
    // generated mutator would apply a write the block refused.
    b.write_string(
      "      guard args.get(\{i}) is Some(\{pat}) else { return Unchanged }\n",
    )
  }
  let stmts = self.stmts(body, "      ")
  if stmts.contains("effects.push(") {
    b.write_string("      let effects : Array[() -> Unit] = []\n")
    b.write_string(stmts)
    b.write_string("      for f in effects {\n        f()\n      }\n")
  } else {
    b.write_string(stmts)
  }
  b.write_string("      Next(s)\n")
  b.write_string("    }\n")
  b.to_string()
}

///|
/// Whether `name` is read anywhere in a body.
///
/// A parameter the body ignores is bound to `_`, so the arity and the shape
/// are still checked and nothing is named that nobody reads.
fn uses_name(body : Array[@tscript.Stmt], name : String) -> Bool {
  for st in body {
    if stmt_uses(st, name) {
      return true
    }
  }
  false
}

///|
fn stmt_uses(s : @tscript.Stmt, name : String) -> Bool {
  match s {
    SAssign(place~, value~, ..) =>
      place_uses(place, name) || expr_uses(value, name)
    SMethod(place~, args~, ..) =>
      place_uses(place, name) || args.iter().any(a => expr_uses(a, name))
    SEffect(args~, ..) => args.iter().any(a => expr_uses(a, name))
    SIf(cond~, then_~, else_~, ..) =>
      expr_uses(cond, name) || uses_name(then_, name) || uses_name(else_, name)
  }
}

///|
fn place_uses(p : @tscript.Place, name : String) -> Bool {
  for st in p.steps {
    if st is PIndex(e) && expr_uses(e, name) {
      return true
    }
  }
  false
}

///|
fn expr_uses(e : @tscript.Expr, name : String) -> Bool {
  match e {
    EName(name=n, ..) => n == name
    ERead(place~, ..) | ERef(place~, ..) => place_uses(place, name)
    ELit(..) | EMethod(..) | EDyn(..) => false
    ETpl(parts~, ..) =>
      parts.iter().any(p => p is TExpr(inner) && expr_uses(inner, name))
    EUnary(operand~, ..) => expr_uses(operand, name)
    EChain(operands~, ..) => operands.iter().any(o => expr_uses(o, name))
    EApp(args~, ..) => args.iter().any(a => expr_uses(a, name))
    EIf(cond~, then_~, else_~, ..) =>
      expr_uses(cond, name) || expr_uses(then_, name) || expr_uses(else_, name)
  }
}

///|
/// Where a handler's parameter types come from — the schema for a declared
/// message, the views' call sites for an `@on` name.
fn E::param_types(
  self : E,
  d : @tscript.Decl,
  surface : @check.Surface,
) -> Array[@statedef.StateTy?] {
  match d.kind {
    DReceive | DBubble | DResponse => {
      let cases = match d.kind {
        DReceive => self.def.receive
        DBubble => self.def.bubble
        _ => self.def.response
      }
      for m in cases {
        if m.name == d.name {
          return m.payload.map(t => Some(t))
        }
      }
      d.params.map(_p => None)
    }
    _ =>
      match surface.inputs.get(d.name) {
        Some(ts) => d.params.mapi((i, _p) => ts.get(i).unwrap_or(None))
        None => d.params.map(_p => None)
      }
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn E::stmts(
  self : E,
  body : Array[@tscript.Stmt],
  pad : String,
) -> String raise NoWay {
  let b = StringBuilder::new()
  for s in body {
    b.write_string(self.stmt(s, pad))
  }
  b.to_string()
}

///|
fn E::stmt(self : E, s : @tscript.Stmt, pad : String) -> String raise NoWay {
  self.prelude = []
  let body = self.stmt_body(s, pad)
  let head = self.prelude.map(g => "\{pad}\{g}\n").join("")
  self.prelude = []
  head + body
}

///|
/// One copy-on-write rebind of `s`, with one field replaced.
///
/// `{ ..s, count: … }` on a ONE-field struct is `unused_struct_update` — the
/// spread covers nothing — and a generated file must not be the thing that
/// warns. Dropping it takes the inference the spread was supplying with it, so
/// the annotation goes back on: several examples in one package declare a
/// one-field state and MoonBit cannot pick between their record types.
///
/// A single-field state is not an edge case; it is what a counter looks like.
fn E::rebind(self : E, field : String, rhs : String, pad : String) -> String {
  if self.def.fields.length() == 1 {
    "\{pad}let s : \{self.state_ty} = { \{binding_of(field)}: \{rhs} }\n"
  } else {
    "\{pad}let s = { ..s, \{binding_of(field)}: \{rhs} }\n"
  }
}

///|
fn E::stmt_body(
  self : E,
  s : @tscript.Stmt,
  pad : String,
) -> String raise NoWay {
  match s {
    SAssign(place~, op~, value~, ..) => {
      let (field, ty) = self.root_field(place)
      let rhs = match op {
        ASet => self.at(value, ty)
        // Arithmetic, so both sides go through Double and the result comes
        // back at the field's type.
        AAdd | ASub => {
          let sign = if op is AAdd { "+" } else { "-" }
          let cur = self.read_field(place)
          let inc = self.at_num(value)
          self.to_ty("(\{cur} \{sign} \{inc})", TFloat, ty)
        }
      }
      // Copy-on-write, exactly as a hand-written arm spells it. Rebinding `s`
      // rather than accumulating one literal is what lets a later statement
      // read what an earlier one wrote.
      self.rebind(field, rhs, pad)
    }
    SMethod(place~, call~, args~, ..) => {
      let (field, ty) = self.root_field(place)
      let next = self.collection_call(call, field, ty, args)
      self.rebind(field, next, pad)
    }
    SEffect(name~, args~, ..) => self.effect(name, args, pad)
    SIf(cond~, then_~, else_~, ..) => {
      let c = self.at_bool(cond)
      let b = StringBuilder::new()
      // A branch rebinds `s`, so the shadowing has to happen in an EXPRESSION
      // that answers the state — `if … { … } else { s }` — rather than in two
      // statement blocks whose bindings would not escape.
      b.write_string("\{pad}let s = if \{c} {\n")
      b.write_string(self.stmts(then_, pad + "  "))
      b.write_string("\{pad}  s\n")
      b.write_string("\{pad}} else {\n")
      b.write_string(self.stmts(else_, pad + "  "))
      b.write_string("\{pad}  s\n")
      b.write_string("\{pad}}\n")
      b.to_string()
    }
  }
}

///|
/// The state field a place is rooted at, refusing everything this backend
/// cannot rebuild.
fn E::root_field(
  self : E,
  p : @tscript.Place,
) -> (String, @statedef.StateTy) raise NoWay {
  guard p.root is PState(name) else {
    raise Cannot(
      "a binding is written by `enrich` / `enrichScope`, which this backend does not compile yet — write the handler in MoonBit",
    )
  }
  guard self.def.field(name) is Some(f) else {
    raise Cannot("`.\{name}` is not a field of the state")
  }
  guard p.steps.is_empty() else {
    // The spine rebuild is expressible — the generator knows every type on the
    // path — and is not written yet. Saying so beats emitting something that
    // silently drops the write.
    raise Cannot(
      "writing through `.\{name}.…` needs a spine rebuild this backend does not emit yet — write the handler in MoonBit, or assign the whole field",
    )
  }
  (name, f.ty)
}

///|
/// Read the current value of a place, at its own type.
fn E::read_field(self : E, p : @tscript.Place) -> String raise NoWay {
  let (name, ty) = self.root_field(p)
  self.to_ty("s.\{binding_of(name)}", ty, TFloat)
}

///|
/// A collection method, as the new value of the field.
///
/// Every one answers an EXPRESSION, never a mutation of the receiver. A
/// MoonBit `Array` and `Map` are both mutable and a state struct is shared —
/// the previous state is still on the transactor's stack — so writing through
/// the receiver would edit a value someone else is holding. `Array` gets a
/// fresh one from a slice concatenation; `Map` gets `.copy()`.
fn E::collection_call(
  self : E,
  call : String,
  field : String,
  ty : @statedef.StateTy,
  args : Array[@tscript.Expr],
) -> String raise NoWay {
  let recv = "s.\{binding_of(field)}"
  fn arity(n : Int) -> Unit raise NoWay {
    if args.length() != n {
      raise Cannot("`\{call}` takes \{n} argument(s), not \{args.length()}")
    }
  }

  // A set is Map-backed and keyed by the member's display string — the same
  // key the generated `addIn<X>` mutator writes, so a card and a compiled
  // component put a member in the same place.
  fn set_write(value : String) -> String raise NoWay {
    let k = self.at(args[0], TText)
    "{ let m = \{recv}.copy(); m[\{k}] = \{value}; m }"
  }

  match (call, ty) {
    // -- lists --------------------------------------------------------------
    ("push", TList(elem)) => {
      arity(1)
      "(\{recv} + [\{self.at(args[0], elem)}])"
    }
    ("insertAt", TList(elem)) => {
      arity(2)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let v = self.at(args[1], elem)
      // `<=` because inserting AT the length appends, which is a real answer.
      let at = self.hoist("at", i)
      self.prelude.push(
        "guard \{at} >= 0 && \{at} <= \{recv}.length() else { return Unchanged }",
      )
      "(\{recv}[0:\{at}].to_owned() + [\{v}] + \{recv}[\{at}:].to_owned())"
    }
    ("removeAt", TList(_)) | ("deleteAt", TList(_)) => {
      arity(1)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let at = self.hoist("at", i)
      self.prelude.push(
        "guard \{at} >= 0 && \{at} < \{recv}.length() else { return Unchanged }",
      )
      "(\{recv}[0:\{at}].to_owned() + \{recv}[\{at} + 1:].to_owned())"
    }
    ("setAt", TList(elem)) => {
      arity(2)
      let i = self.at(args[0], TInt(width=32, signed=true))
      let v = self.at(args[1], elem)
      let at = self.hoist("at", i)
      self.prelude.push(
        "guard \{at} >= 0 && \{at} < \{recv}.length() else { return Unchanged }",
      )
      "{ let a = \{recv}.copy(); a[\{at}] = \{v}; a }"
    }
    ("clear", TList(elem)) => {
      arity(0)
      "([] : Array[\{elem_ty_name(elem)}])"
    }
    // -- sets ---------------------------------------------------------------
    ("add", TSet) | ("add", TFlags(_)) => {
      arity(1)
      set_write("true")
    }
    ("remove", TSet)
    | ("remove", TFlags(_))
    | ("delete", TSet)
    | ("delete", TFlags(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); m.remove(\{k}); m }"
    }
    ("toggle", TSet) | ("toggle", TFlags(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); let k = \{k}; if m.get(k) is Some(true) { m.remove(k) } else { m[k] = true }; m }"
    }
    // -- ordered maps -------------------------------------------------------
    ("set", TOMap(v)) => {
      arity(2)
      let k = self.at(args[0], TText)
      let value = self.at(args[1], v)
      "{ let m = \{recv}.copy(); m[\{k}] = \{value}; m }"
    }
    ("remove", TOMap(_)) | ("delete", TOMap(_)) => {
      arity(1)
      let k = self.at(args[0], TText)
      "{ let m = \{recv}.copy(); m.remove(\{k}); m }"
    }
    _ =>
      raise Cannot(
        "`\{call}` does not apply to `.\{field}`, which is \{ty.show_source()} — write the handler in MoonBit",
      )
  }
}

///|
/// Bind an expression once when it is not already a simple name.
///
/// A guard tests it and the code after reads it again; evaluating a call twice
/// would be wrong the moment it stopped being pure, and unreadable either way.
fn E::hoist(self : E, name : String, expr : String) -> String {
  if is_simple(expr) {
    return expr
  }
  self.prelude.push("let \{name} = \{expr}")
  name
}

///|
/// Whether an expression is a bare name or an integer literal.
fn is_simple(e : String) -> Bool {
  let cs = e.to_array()
  if cs.is_empty() {
    return false
  }
  for c in cs {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_') {
      return false
    }
  }
  true
}

///|
/// The MoonBit spelling of a list's element type, for the one place an empty
/// literal has to be annotated.
fn elem_ty_name(t : @statedef.StateTy) -> String raise NoWay {
  match t {
    TBool => "Bool"
    TInt(width=32, signed=true) => "Int"
    TFloat => "Double"
    TText => "String"
    TAny => "@tutuca.Value"
    _ =>
      raise Cannot(
        "clearing a list of \{t.show_source()} needs a type annotation this backend does not spell yet — assign `[]` to the whole field instead",
      )
  }
}

///|
/// An effect, straight through to the `ctx` the function already holds.
fn E::effect(
  self : E,
  name : String,
  args : Array[@tscript.Expr],
  pad : String,
) -> String raise NoWay {
  self.uses_ctx = true
  if name == "stop" {
    return "\{pad}effects.push(() => ctx.stop_propagation())\n"
  }
  guard args.get(0) is Some(ELit(lit=LStr(msg), ..)) else {
    raise Cannot("`\{name}` needs a literal message name")
  }
  // Every payload crosses as a `@tutuca.Value`, which is what the channel
  // carries — so this is the one place a typed expression goes back to the
  // dynamic representation.
  let rest : Array[String] = []
  for i in 1..<args.length() {
    rest.push(self.as_value(args[i]))
  }
  let payload = "[" + rest.join(", ") + "]"
  match name {
    "send" => "\{pad}effects.push(() => ctx.send(\{quote(msg)}, \{payload}))\n"
    "bubble" =>
      "\{pad}effects.push(() => ctx.bubble(\{quote(msg)}, \{payload}))\n"
    "request" =>
      "\{pad}effects.push(() => ctx.request(\{quote(msg)}, \{payload}, @tutuca.RequestOpts::new()))\n"
    _ =>
      raise Cannot(
        "`\{name}` addresses a position, which this backend does not emit yet — write the handler in MoonBit",
      )
  }
}

// ---------------------------------------------------------------------------
// Expressions

///|
/// Emit an expression at a wanted type.
///
/// A WHOLE numeric literal is spelled at the wanted type directly rather than
/// converted into it. `.count = 1` reads `1`, not `1.0.to_int()`, and the two
/// are the same number — the conversion exists for values whose type is only
/// known at run time, and a literal's is known here.
///
/// A FRACTIONAL one is not refused. It goes through the ordinary `.to_int()`,
/// which truncates, because that is what the interpreter does with the same
/// expression — `Value` has one number and the generated codec's decode
/// truncates too. Refusing it here would make `.count = 2.7` an error while
/// `.count = .ratio` quietly truncated, which is two rules for one idea.
/// Whether a fractional literal in an integer place deserves a DIAGNOSTIC is
/// the checker's question, not the emitter's.
fn E::at(
  self : E,
  e : @tscript.Expr,
  want : @statedef.StateTy,
) -> String raise NoWay {
  if e is ELit(lit=LNum(n), ..) &&
    want is TInt(..) &&
    n == n.to_int().to_double() {
    return n.to_int().to_string()
  }
  let (src, got) = self.expr(e)
  self.to_ty(src, got, want)
}

///|
fn E::at_num(self : E, e : @tscript.Expr) -> String raise NoWay {
  self.at(e, TFloat)
}

///|
fn E::at_bool(self : E, e : @tscript.Expr) -> String raise NoWay {
  let (src, got) = self.expr(e)
  match got {
    TBool => src
    // Everything else answers a yes/no question by tutuca's own truthiness,
    // which is `Value::is_truthy` — so the conversion is through a Value
    // rather than a MoonBit `!= 0`, or the two backends would disagree about
    // `@show=".count"`.
    _ => "\{self.value_of(src, got)}.is_truthy()"
  }
}

///|
/// Emit an expression as a `@tutuca.Value`, for a channel payload.
fn E::as_value(self : E, e : @tscript.Expr) -> String raise NoWay {
  let (src, got) = self.expr(e)
  self.value_of(src, got)
}

///|
fn E::value_of(self : E, src : String, ty : @statedef.StateTy) -> String {
  // The schema's own projection, which the generated codec is written from
  // too. A set, a list of records and a tuple all need real conversion, and
  // this used to pass them through as if they were already Values — which
  // compiled for the four scalars and for nothing else.
  let e = self.def.to_value_src(ty, src)
  // Annotated for the scalars, whose constructors are ambiguous in an
  // argument position; the compound forms carry their own annotation.
  match ty {
    TBool | TText | TInt(..) | TFloat => "(\{e} : @tutuca.Value)"
    _ => e
  }
}

///|
/// Insert whatever conversion `from` -> `to` needs, or refuse the pair.
fn E::to_ty(
  self : E,
  src : String,
  from : @statedef.StateTy,
  to : @statedef.StateTy,
) -> String raise NoWay {
  if from == to {
    return src
  }
  match (from, to) {
    // Widening into `Any`, which IS `@tutuca.Value` — the one direction that
    // needs no guess, because every language type has a Value spelling and the
    // codec already writes it. The other direction is refused where a raw
    // parameter is read: a Value could be anything, and picking one is the
    // guess this backend does not make.
    (_, TAny) => self.value_of(src, from)
    // The one numeric surface, made explicit. Truncating into an integer field
    // is what the generated codec's decode does with the same value.
    (TInt(..), TFloat) => "\{src}.to_double()"
    // A bare integer read that goes straight back into an integer place: the
    // normalization and its undoing cancel, and `s.count.to_double().to_int()`
    // is the same number spelled twice. Only the suffix WE wrote is peeled —
    // an arithmetic expression ends in `)`, so it never matches.
    (TFloat, TInt(..)) if src.has_suffix(".to_double()") =>
      src[0:src.length() - ".to_double()".length()].to_owned()
    (TFloat, TInt(..)) => "\{src}.to_int()"
    (TInt(..), TInt(..)) => src
    // An enum is a string at runtime, so a computed string can name a case —
    // but naming which case needs the generated enum's constructor, which this
    // does not build.
    (TText, TEnum(n)) =>
      raise Cannot(
        "assigning a computed string into the `\{n}` enum is not compiled yet",
      )
    _ =>
      raise Cannot(
        "a `\{from.show_source()}` does not fit where a `\{to.show_source()}` is wanted",
      )
  }
}

///|
/// Emit an expression, answering its source and its language type.
fn E::expr(
  self : E,
  e : @tscript.Expr,
) -> (String, @statedef.StateTy) raise NoWay {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LBool(b) => (if b { "true" } else { "false" }, TBool)
        LStr(s) => (quote(s), TText)
        // Every literal number is a Double, because every arithmetic
        // expression is. The conversion happens where it meets a field.
        LNum(n) => (double_lit(n), TFloat)
        LNull => raise Cannot("`null` has no typed spelling here")
      }
    ETpl(parts~, ..) => {
      let b = StringBuilder::new()
      b.write_string("(")
      let mut first = true
      for part in parts {
        if !first {
          b.write_string(" + ")
        }
        first = false
        match part {
          TText(t) => b.write_string(quote(t))
          // Through `to_display_string`, not MoonBit's `Show`: a template in a
          // slot renders JS-style (`3`, not `3.0`), and a card and a compiled
          // component have to agree about what the same template says.
          TExpr(inner) => {
            let (src, ty) = self.expr(inner)
            b.write_string("\{self.value_of(src, ty)}.to_display_string()")
          }
        }
      }
      b.write_string(")")
      (b.to_string(), TText)
    }
    ERead(place~, ..) => self.read(place)
    EName(name~, ..) => {
      guard self.params.get(name) is Some(ty) else {
        raise Cannot("`\{name}` is not a parameter of this handler")
      }
      guard ty is Some(t) else {
        raise Cannot(
          "`\{name}`'s type is not known from the call sites, so it arrives as a raw value — annotate it by calling the handler consistently, or write the handler in MoonBit",
        )
      }
      // A parameter arrives as the type its pattern bound: a number is a
      // Double, which is the arithmetic surface.
      match t {
        TInt(..) => (name, TFloat)
        _ => (name, t)
      }
    }
    EUnary(op~, operand~, ..) =>
      match op {
        // `!expr`, not `not(expr)`: moonc deprecates the second, so a block
        // with a `not` in it made every generated module warn — and a strict
        // build (--deny-warn) reject a file whose author wrote nothing wrong.
        UNot => ("(!\{self.at_bool(operand)})", TBool)
        UNeg => ("(-\{self.at_num(operand)})", TFloat)
      }
    EChain(family~, ops~, operands~, ..) => self.chain(family, ops, operands)
    EIf(cond~, then_~, else_~, ..) => {
      let c = self.at_bool(cond)
      let (a, ta) = self.expr(then_)
      let bsrc = self.at(else_, ta)
      ("(if \{c} { \{a} } else { \{bsrc} })", ta)
    }
    EApp(name~, args~, ..) => self.app(name, args)
    EMethod(name~, ..) =>
      raise Cannot(
        "`$\{name}` is a `compute`, which a handler cannot call: it is answered by the render stack and a handler runs after one",
      )
    EDyn(name~, ..) =>
      raise Cannot(
        "`*\{name}` is a dynamic binding, which a handler cannot read",
      )
    ERef(..) => raise Cannot("a place is not a value")
  }
}

///|
/// Read a place. Top-level fields and one level of record field; anything
/// indexed is a read this backend does not emit yet.
fn E::read(
  self : E,
  p : @tscript.Place,
) -> (String, @statedef.StateTy) raise NoWay {
  guard p.root is PState(name) else {
    raise Cannot("a binding is not readable from a handler")
  }
  guard self.def.field(name) is Some(f) else {
    raise Cannot("`.\{name}` is not a field of the state")
  }
  let mut src = "s.\{binding_of(name)}"
  let mut ty = f.ty
  for st in p.steps {
    match st {
      PField(sub) => {
        guard self.def.field_of(ty, sub) is Some(inner) else {
          raise Cannot("`\{ty.show_source()}` has no field `\{sub}`")
        }
        src = "\{src}.\{binding_of(sub)}"
        ty = inner
      }
      PIndex(_) =>
        raise Cannot(
          "reading through an index needs a bounds check this backend does not emit yet — write the handler in MoonBit",
        )
    }
  }
  // An integer field is read at the arithmetic surface, like everything else.
  match ty {
    TInt(..) => (src + ".to_double()", TFloat)
    _ => (src, ty)
  }
}

///|
fn E::chain(
  self : E,
  family : @tscript.OpFamily,
  ops : Array[String],
  operands : Array[@tscript.Expr],
) -> (String, @statedef.StateTy) raise NoWay {
  match family {
    FLogic => {
      let b = StringBuilder::new()
      b.write_string("(\{self.at_bool(operands[0])}")
      for i, op in ops {
        b.write_string(if op == "and" { " && " } else { " || " })
        b.write_string(self.at_bool(operands[i + 1]))
      }
      b.write_string(")")
      (b.to_string(), TBool)
    }
    FImplies => {
      let a = self.at_bool(operands[0])
      let c = self.at_bool(operands[1])
      ("((!\{a}) || \{c})", TBool)
    }
    FCompare => {
      let (a, ta) = self.expr(operands[0])
      match ops[0] {
        // Structural equality, through `Value` — the same `Eq for Value`
        // everything else compares with, so two lists with equal contents
        // compare equal here as they do in a card.
        "is" | "is not" => {
          let (bsrc, tb) = self.expr(operands[1])
          let cmp = "(\{self.value_of(a, ta)} == \{self.value_of(bsrc, tb)})"
          // `!(a == b)` rather than `not(a == b)`, for the reason above.
          (if ops[0] == "is" { cmp } else { "(!\{cmp})" }, TBool)
        }
        op => {
          let x = self.to_ty(a, ta, TFloat)
          let y = self.at_num(operands[1])
          ("(\{x} \{op} \{y})", TBool)
        }
      }
    }
    FAdd | FMul => {
      // Two strings concatenate; everything else is arithmetic. The operands'
      // static types decide, exactly as the checker says.
      let (first, tf) = self.expr(operands[0])
      if family is FAdd && tf is TText {
        let b = StringBuilder::new()
        b.write_string("(\{first}")
        for i, _op in ops {
          b.write_string(" + \{self.at(operands[i + 1], TText)}")
        }
        b.write_string(")")
        return (b.to_string(), TText)
      }
      // Folded rather than appended, because `mod` WRAPS what came before it
      // instead of extending it: `a mod b` is a round trip through Int, and
      // the accumulated left-hand side has to be inside that trip. Growing one
      // string left to right cannot express an operator that reaches backwards.
      let mut acc = self.to_ty(first, tf, TFloat)
      for i, op in ops {
        // A zero divisor is "no change", which is what the interpreter
        // answers. MoonBit's Double division answers Infinity instead, and
        // `.to_int()` then saturates to 2^31-1 — a number, silently, where the
        // other backend said the transition did not happen.
        let rhs = if op == "/" || op == "mod" {
          let d = self.hoist("d\{i}", self.at_num(operands[i + 1]))
          self.prelude.push("guard \{d} != 0.0 else { return Unchanged }")
          d
        } else {
          self.at_num(operands[i + 1])
        }
        acc = match op {
          // MoonBit has no `%` on Double, and the language's `mod` is over
          // whole numbers anyway — the interpreter truncates both sides too.
          "mod" => "((\{acc}).to_int() % (\{rhs}).to_int()).to_double()"
          _ => "(\{acc} \{op} \{rhs})"
        }
      }
      (acc, TFloat)
    }
  }
}

///|
/// A builtin applied to arguments.
fn E::app(
  self : E,
  name : String,
  args : Array[@tscript.Expr],
) -> (String, @statedef.StateTy) raise NoWay {
  match (name, args.length()) {
    ("len", 1) => {
      let (src, ty) = self.expr(args[0])
      guard ty is (TList(_) | TText | TSet | TFlags(_) | TOMap(_)) else {
        raise Cannot("`len` needs a sized value, not `\{ty.show_source()}`")
      }
      ("\{src}.length().to_double()", TFloat)
    }
    ("min", 2) | ("max", 2) => {
      let a = self.at_num(args[0])
      let b = self.at_num(args[1])
      let cmp = if name == "min" { "<" } else { ">" }
      ("(if \{a} \{cmp} \{b} { \{a} } else { \{b} })", TFloat)
    }
    ("clamp", 3) => {
      let v = self.at_num(args[0])
      let lo = self.at_num(args[1])
      let hi = self.at_num(args[2])
      // The empty-range answer is `lo`, matching the interpreter: an empty
      // list makes `hi` -1 and a negative index is not an honest result.
      (
        "(if \{hi} < \{lo} { \{lo} } else if \{v} < \{lo} { \{lo} } else if \{v} > \{hi} { \{hi} } else { \{v} })",
        TFloat,
      )
    }
    ("int", 1) => ("\{self.at_num(args[0])}.to_int().to_double()", TFloat)
    ("num", 1) => (self.at_num(args[0]), TFloat)
    ("str", 1) => {
      let (src, ty) = self.expr(args[0])
      ("\{self.value_of(src, ty)}.to_display_string()", TText)
    }
    ("lower", 1) => ("\{self.at(args[0], TText)}.to_lower()", TText)
    ("trim", 1) =>
      (
        "\{self.at(args[0], TText)}.trim(chars=\" \\t\\n\\r\").to_owned()",
        TText,
      )
    ("contains", 2) => {
      let hay = self.at(args[0], TText)
      let needle = self.at(args[1], TText)
      ("\{hay}.contains(\{needle})", TBool)
    }
    ("empty?", 1) => {
      let (src, ty) = self.expr(args[0])
      (
        "(\{self.value_of(src, ty)} is Null || @tutuca.size_of(\{self.value_of(src, ty)}) is Some(0))",
        TBool,
      )
    }
    ("truthy?", 1) | ("falsy?", 1) | ("null?", 1) => {
      let (src, ty) = self.expr(args[0])
      let v = self.value_of(src, ty)
      // Through `core`'s own table, so the four mean in a compiled handler
      // exactly what they mean in a `@show`. One table, one meaning.
      let call = "(match @tutuca.builtin(\{quote(name)}) { Some(b) => (b.apply)([\{v}]).is_truthy(); None => false })"
      (call, TBool)
    }
    _ =>
      raise Cannot(
        "`\{name}` applied to \{args.length()} argument(s) is not compiled yet — write the handler in MoonBit",
      )
  }
}

// ---------------------------------------------------------------------------
// Spelling

///|
/// The MoonBit binding for a runtime field name — the same escape
/// `statedef/names.mbt` applies, reached through it so the two cannot drift.
fn binding_of(name : String) -> String {
  @statedef.binding_name(name)
}

///|
/// Both reached through `@statedef` for the same reason `binding_of` is.
fn quote(s : String) -> String {
  @statedef.quote(s)
}

///|
fn double_lit(d : Double) -> String {
  @statedef.double_lit(d)
}
