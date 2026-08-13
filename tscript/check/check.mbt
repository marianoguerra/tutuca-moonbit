// The checker. Implements the declares in spec.mbt.
//
// One walk per declaration, carrying an environment of what a name means here:
// the schema for `.field`, the parameters for a bare name, the block's own
// declarations for an application. Types are `@statedef.StateTy?` throughout,
// where `None` is OPAQUE and never "wrong" — the rule `check_state.mbt` states
// and this file inherits without amendment.
//
// The shape of nearly every rule is therefore the same: infer both sides, and
// report only when both are known and they disagree. A checker over a language
// with `$method`, `*dyn` and binds it cannot see has to be built that way or it
// reports mostly noise.

///|
priv struct C {
  def : @statedef.StateDef
  surface : Surface
  out : Array[Finding]
  /// The parameters of the declaration being checked.
  mut params : Map[String, @statedef.StateTy?]
  /// The declaration being checked, for a message about one of its arguments.
  mut decl_name : String
  /// Which declarations the block itself makes, by name: predicates and
  /// computes are callable, and everything else is not.
  callable : Map[String, Int]
  /// The callables a `requires` / `ensures` may name, by name and arity.
  predicate : Map[String, Int]
  /// True inside `enrich` / `enrich_scope`, the only kinds that may assign a
  /// binding.
  mut binds_assignable : Bool
  /// What `new` last put in `@cur`, on this path through the body.
  mut target : Target
}

///|
/// The active target's type, as the walk knows it.
///
/// Two states rather than one optional, because "no `new` has run" and "a
/// `new` ran and its type is opaque" are different answers: the first is a
/// mistake to report, and the second is the usual opacity to stay quiet about.
priv enum Target {
  TUnset
  TSet(@statedef.StateTy?)
}

///|
fn C::say(
  self : C,
  code : String,
  message : String,
  span : @tscript.Span,
) -> Unit {
  self.out.push({ code, message, span })
}

///|
pub fn Surface::empty() -> Surface {
  { inputs: Map([]) }
}

///|
pub fn check(
  decls : Array[@tscript.Decl],
  def : @statedef.StateDef,
  surface? : Surface = Surface::empty(),
) -> Array[Finding] {
  // Collected first, because a body may apply a predicate declared BELOW it.
  // Declaration order is only a termination proof for predicates calling
  // predicates, which is a rule for a later pass; nothing here needs order.
  let callable : Map[String, Int] = Map([])
  // The subset a contract may name. Separate rather than a flag on the map
  // above, because the two questions are different: "can a body apply this" is
  // answered by every value body, and "is this a rule" only by the two kinds
  // that declare their answer to be a yes or a no.
  let predicate : Map[String, Int] = Map([])
  for d in decls {
    if d.kind is (DPred | DCompute | DInvariant) {
      callable[d.name] = d.params.length()
    }
    if @tscript.is_predicate(d.kind) {
      predicate[d.name] = d.params.length()
    }
  }
  let c = C::{
    def,
    surface,
    out: [],
    params: Map([]),
    decl_name: "",
    callable,
    predicate,
    binds_assignable: false,
    target: TUnset,
  }
  for d in decls {
    c.decl(d)
  }
  c.out
}

// ---------------------------------------------------------------------------
// Declarations

///|
fn C::decl(self : C, d : @tscript.Decl) -> Unit {
  self.params = Map([])
  self.decl_name = d.name
  self.binds_assignable = d.kind is (DEnrich | DEnrichScope)
  // A target belongs to the body that built it and to nothing else — the same
  // rule the interpreter enforces by refusing to hand `@cur` back.
  self.target = TUnset
  // Where the parameter types come from is the whole difference between the
  // two halves of the language. A message case is DECLARED, so its payload is
  // exact; an `@on` name is not declared anywhere, so its arguments are what
  // the views wrote — and two call sites that disagreed joined to opaque long
  // before this saw them.
  match d.kind {
    DReceive | DBubble | DResponse => self.msg_params(d)
    DOn => {
      let sig = self.surface.inputs.get(d.name)
      for i, p in d.params {
        self.params[p.name] = match sig {
          Some(types) => types.get(i).unwrap_or(None)
          None => None
        }
      }
      match sig {
        Some(types) if types.length() != d.params.length() =>
          self.say(
            "ARITY",
            "`\{d.name}` takes \{d.params.length()} parameter(s) here, but the views call it with \{types.length()}",
            d.name_span,
          )
        _ => ()
      }
    }
    // A `compute` or a `pred` is called from a slot or from another body, and
    // nothing declares what it is passed. Opaque, which is the honest answer.
    _ =>
      for p in d.params {
        self.params[p.name] = None
      }
  }
  self.contract(d, d.requires_, "requires")
  self.contract(d, d.ensures_, "ensures")
  // An invariant is asked after every transition, and no two transitions carry
  // the same arguments. There is nothing that could be passed.
  if d.kind is DInvariant && !d.params.is_empty() {
    self.say(
      "INVARIANT_ARGS",
      "an `invariant` is asked after every transition, so there is nothing to pass it — drop the parameter(s), or make it a `pred` a slot calls",
      d.name_span,
    )
  }
  match d.body {
    Stmts(ss) => self.stmts(ss)
    // A `pred` answers yes or no, so its body is a CONDITION and is judged by
    // the same rule every other condition is. Not a stricter one: a string and
    // a number are boolish in tutuca — `@show=".role"` beside `@text=".role"`
    // is idiomatic — and a `pred` that invented a narrower rule than `@show`
    // follows would be a second truthiness to learn.
    Value(e) =>
      if @tscript.is_predicate(d.kind) {
        self.condition(e)
      } else {
        self.expr(e) |> ignore
      }
  }
}

///|
/// One contract clause: the `pred` it names has to exist, be a predicate, and
/// take nothing.
///
/// Nothing to pass is the rule, not an omission. A contract is a statement
/// about the component's STATE — what has to be true for a transition to
/// happen, and what has to be true where it landed — and the arguments a
/// handler was called with are already checked by the schema and by the arm's
/// own guards. A rule that needed one of them is a rule about this dispatch
/// rather than about the component, and `if` is where that is written.
fn C::contract(
  self : C,
  d : @tscript.Decl,
  clause : @tscript.Attach?,
  word : String,
) -> Unit {
  guard clause is Some(c) else { return }
  guard self.predicate.get(c.name) is Some(arity) else {
    self.say(
      "NO_PRED",
      "`\{word} \{c.name}` names no `pred` this block declares" +
      (match @statedef.nearest(c.name, self.predicate.keys().collect()) {
        Some(s) => " — did you mean `\{s}`?"
        None =>
          if self.callable.contains(c.name) {
            "; `\{c.name}` is a `compute`, and a contract names a `pred`, whose answer is declared to be a yes or a no"
          } else {
            "; declare `pred \{c.name} { … }` above `\{d.name}`"
          }
      }),
      c.span,
    )
    return
  }
  if arity != 0 {
    self.say(
      "CONTRACT_ARGS",
      "`\{c.name}` takes \{arity} parameter(s), and a contract is asked with none — a rule that needs an argument is about this dispatch rather than about the component, so guard it with `if` instead",
      c.span,
    )
  }
}

///|
/// Bind a message handler's parameters from the schema's declared payload.
fn C::msg_params(self : C, d : @tscript.Decl) -> Unit {
  let (cases, bucket) = match d.kind {
    DReceive => (self.def.receive, "receive")
    DBubble => (self.def.bubble, "bubble")
    _ => (self.def.response, "response")
  }
  let found = cases.filter(m => m.name == d.name)
  guard found.get(0) is Some(msg) else {
    // The schema is the only place these names can be declared — the views
    // never write them — so a handler for one the block does not declare is
    // answering a message nothing can send.
    self.say(
      "NO_SUCH_MESSAGE",
      "the schema declares no `\{bucket}` case `\{d.name}`" +
      (match @statedef.nearest(d.name, cases.map(m => m.name)) {
        Some(s) => " — did you mean `\{s}`?"
        None =>
          "; add it to `variant \{bucket}` in the <script type=\"tutuca/state\"> block"
      }),
      d.name_span,
    )
    for p in d.params {
      self.params[p.name] = None
    }
    return
  }
  if msg.payload.length() != d.params.length() {
    self.say(
      "ARITY",
      "`\{bucket} \{d.name}` carries \{msg.payload.length()} value(s), but this takes \{d.params.length()}",
      d.name_span,
    )
  }
  for i, p in d.params {
    self.params[p.name] = msg.payload.get(i)
  }
}

// ---------------------------------------------------------------------------
// Statements

///|
fn C::stmts(self : C, ss : Array[@tscript.Stmt]) -> Unit {
  for s in ss {
    self.stmt(s)
  }
}

///|
fn C::stmt(self : C, s : @tscript.Stmt) -> Unit {
  match s {
    // `@cur = expr` names the WHOLE target, so it does not read one — it makes
    // one, out of a value that is already built. Taking a copy of a row to
    // edit and push back is what it is for.
    SAssign(place~, op=ASet, value~, span~) if place.root is PBind(n) &&
      n == @tscript.target_bind &&
      place.steps.is_empty() => {
      let got = self.expr(value)
      if self.binds_assignable {
        self.say(
          "RESERVED_BIND",
          "`@\{n}` is the target `new` builds into, not a binding this `enrich` can hand a view — bind another name",
          span,
        )
      }
      self.target = TSet(got)
    }
    SAssign(place~, op~, value~, span~) => {
      let target = self.place(place, assigning=true)
      let got = self.expr(value)
      // `+=` and `-=` are arithmetic, so both sides have to be numbers — and
      // a `+=` on a string is far likelier to be a mistake than an intended
      // concatenation, which `.s = .s + x` still spells.
      if op is (AAdd | ASub) {
        match definite(target) {
          Some(t) if !is_numeric(t) =>
            self.say(
              "TYPE",
              "`\{assign_word(op)}` is arithmetic, but this place is \{t.show_source()}",
              span,
            )
          _ => ()
        }
      }
      self.assignable(target, got, span)
    }
    SMethod(place~, call~, args~, span~) => {
      let recv = self.place(place, assigning=true)
      for a in args {
        self.expr(a) |> ignore
      }
      match recv {
        Some(t) => self.method_fits(call, t, span)
        None => ()
      }
    }
    SEffect(name~, args~, span~) => {
      for a in args {
        // A `&` place is a POSITION and has no value, so it is checked as a
        // place rather than inferred as one.
        match a {
          ERef(place~, ..) => self.place(place, assigning=false) |> ignore
          _ => self.expr(a) |> ignore
        }
      }
      // The first argument of every effect but `stop` names a message, and a
      // name that is not a literal cannot be checked against anything — nor
      // routed by the generator, which needs it at generation time.
      if name != "stop" && args.get(0) is Some(a0) && !(a0 is ERef(..)) {
        if !(a0 is ELit(lit=LStr(_), ..)) {
          self.say(
            "DYNAMIC_MESSAGE",
            "`\{name}` needs a literal message name: the generator routes it, so it has to be known before anything runs",
            span,
          )
        }
      }
    }
    SIf(cond~, then_~, else_~, ..) => {
      self.condition(cond)
      let before = self.target
      self.stmts(then_)
      let after_then = self.target
      self.target = before
      self.stmts(else_)
      // What both arms agree on. Two arms that built different types leave a
      // target whose type nothing here knows, and an arm that built nothing
      // leaves no target at all — which is the answer that makes a `@cur`
      // after the branch report rather than pass.
      self.target = match (after_then, self.target) {
        (TSet(a), TSet(b)) => if a == b { TSet(a) } else { TSet(None) }
        (TUnset, _) | (_, TUnset) => TUnset
      }
    }
    SNew(ty~, ..) => self.target = TSet(self.ty_ref(ty))
  }
}

///|
pub fn resolve_ty_ref(
  def : @statedef.StateDef,
  t : @tscript.TyRef,
) -> @statedef.StateTy? {
  let args : Array[@statedef.StateTy] = []
  for a in t.args {
    // An argument that does not resolve leaves the whole reference with
    // nothing to be: `Array[Frobnicator]` is not a list of anything.
    guard resolve_ty_ref(def, a) is Some(r) else { return None }
    args.push(r)
  }
  def.resolve_ty(t.name, args)
}

///|
/// Resolve the type a `new` names, reporting a name that resolves to nothing
/// so that nothing below it reports again.
fn C::ty_ref(self : C, t : @tscript.TyRef) -> @statedef.StateTy? {
  match resolve_ty_ref(self.def, t) {
    Some(r) => Some(r)
    None => {
      self.say(
        "NO_TYPE",
        "`\{t.to_source()}` is not a type the \{self.def.component} state declares" +
        (match
          @statedef.nearest(t.name, self.def.types.map(u => u.source_name)) {
          Some(s) => " — did you mean `\{s}`?"
          None =>
            "; declare it in the <script type=\"tutuca/state\"> block, or write a built-in type"
        }),
        t.span,
      )
      None
    }
  }
}

///|
/// A condition, checked for being answerable as a boolean at all.
fn C::condition(self : C, e : @tscript.Expr) -> Unit {
  match definite(self.expr(e)) {
    Some(t) =>
      if !is_boolish(t) {
        // The same finding `AlwaysTruthy` makes about a `@show` over a
        // container: `Value::is_truthy` answers true for a List, a Map and an
        // Obj unconditionally, so the test cannot fail.
        self.say(
          "ALWAYS_TRUE",
          "\{t.show_source()} is always truthy, so this condition never decides anything — test `empty?` of it, or a field of it",
          expr_span(e),
        )
      }
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Places

///|
/// Resolve a place to the type it addresses, or None when opaque.
fn C::place(
  self : C,
  p : @tscript.Place,
  assigning~ : Bool,
) -> @statedef.StateTy? {
  let mut ty : @statedef.StateTy? = match p.root {
    PState(name) =>
      match self.def.field(name) {
        Some(f) => Some(f.ty)
        None => {
          self.say(
            "NO_FIELD",
            "`.\{name}` is not a field of the \{self.def.component} state" +
            (match @statedef.nearest(name, self.def.fields.map(f => f.name)) {
              Some(s) => " — did you mean `.\{s}`?"
              None => "; declare it in the <script type=\"tutuca/state\"> block"
            }),
            p.span,
          )
          return None
        }
      }
    // The target: the one binding this block makes for itself, so the one
    // binding whose type is known here.
    PBind(name) if name == @tscript.target_bind =>
      match self.target {
        TSet(t) => t
        TUnset => {
          self.say(
            "NO_TARGET",
            "`@\{name}` holds what a `new` built, and no `new` has run here — write `new <Type>` above this",
            p.span,
          )
          return None
        }
      }
    PBind(name) => {
      if assigning && !self.binds_assignable {
        self.say(
          "BIND_ASSIGN",
          "`@\{name}` is a binding, and only `enrich` and `enrichScope` produce bindings — a handler assigns state, and `new` builds a value in `@\{@tscript.target_bind}`",
          p.span,
        )
      }
      // A binding comes from the SLOT that uses this declaration, which the
      // block cannot see. Opaque, and everything below it too.
      None
    }
    // A path into an argument. The root has to BE a parameter — a bare name
    // followed by an attached `.` is a path and nothing else, so a name that
    // is not one is a mistake rather than a call.
    PParam(name) => {
      // Unreachable through the parser, which refuses a statement that starts
      // with a path into an argument and says why. Kept because `Place` is one
      // type for reads and writes, and answering "not a place" is the only
      // honest thing this can say if some other producer builds one.
      if assigning {
        self.say(
          "PARAM_ASSIGN",
          "`\{name}` is a parameter — an argument is a value the caller handed over, not a place this component owns; assign to a `.field` instead",
          p.span,
        )
        return None
      }
      if !self.params.contains(name) {
        self.say(
          "NO_PARAM",
          "`\{name}` is not a parameter of `\{self.decl_name}`" +
          (match @statedef.nearest(name, self.params.keys().collect()) {
            Some(s) => " — did you mean `\{s}`?"
            None =>
              "; a path is only written on an argument, and `.\{name}` is how a state field is read"
          }),
          p.span,
        )
        return None
      }
      self.params.get(name).unwrap_or(None)
    }
  }
  for st in p.steps {
    match st {
      PField(name) =>
        ty = match ty {
          Some(t) =>
            match self.def.field_of(t, name) {
              Some(inner) => Some(inner)
              None => {
                self.say(
                  "NO_FIELD",
                  "`\{t.show_source()}` has no field `\{name}`",
                  p.span,
                )
                return None
              }
            }
          None => None
        }
      PIndex(key) => {
        self.expr(key) |> ignore
        ty = match ty {
          Some(t) =>
            match t.elem() {
              Some(inner) => Some(inner)
              None => {
                self.say(
                  "NOT_INDEXABLE",
                  "`\{t.show_source()}` is not a collection, so it has nothing to index",
                  p.span,
                )
                return None
              }
            }
          None => None
        }
      }
    }
  }
  ty
}

// ---------------------------------------------------------------------------
// Expressions

///|
fn C::expr(self : C, e : @tscript.Expr) -> @statedef.StateTy? {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LNull => None
        LBool(_) => Some(TBool)
        LNum(_) => Some(TFloat)
        LStr(_) => Some(TText)
      }
    ETpl(parts~, ..) => {
      for part in parts {
        match part {
          TExpr(inner) => self.expr(inner) |> ignore
          TText(_) => ()
        }
      }
      Some(TText)
    }
    ERead(place~, ..) => self.place(place, assigning=false)
    // Opaque, and REPORTED — the two are not the same thing.
    //
    // Their TYPE is unknown, which is never wrong; their value in a body is
    // Null, which almost always is. Both sigils are answered by the render
    // stack, and a body runs after one — so `if $over { … }` takes the else
    // arm every time and says nothing, which is the worst way for a rule to be
    // false. The ahead-of-time backend refuses both by name
    // (`tscript/emit_mbt/emit.mbt`); this is the same refusal for the path
    // that has no compiler to do it.
    EMethod(name~, span~) => {
      self.render_only(name, sigil="$", span)
      None
    }
    EDyn(name~, span~) => {
      self.render_only(name, sigil="*", span)
      None
    }
    EName(name~, span~) => self.name(name, [], span)
    EApp(name~, args~, span~) => self.name(name, args, span)
    EUnary(op~, operand~, span~) =>
      match op {
        UNot => {
          self.condition(operand)
          Some(TBool)
        }
        UNeg => {
          let t = self.expr(operand)
          match definite(t) {
            Some(inner) if !is_numeric(inner) =>
              self.say(
                "TYPE",
                "`-` negates a number, but this is \{inner.show_source()}",
                span,
              )
            _ => ()
          }
          t
        }
      }
    EChain(family~, operands~, span~, ..) => self.chain(family, operands, span)
    EIf(cond~, then_~, else_~, ..) => {
      self.condition(cond)
      let a = self.expr(then_)
      let b = self.expr(else_)
      // Both arms known and different: the value has no one type, so nothing
      // reading it can be checked. Reported rather than joined to opaque,
      // because an author who wrote two shapes meant one of them.
      match (a, b) {
        (Some(x), Some(y)) =>
          if x == y {
            a
          } else {
            self.say(
              "TYPE",
              "the two branches are \{x.show_source()} and \{y.show_source()}",
              expr_span(else_),
            )
            None
          }
        _ => None
      }
    }
    // A place is not a value, and the parser has already confined it to
    // `sendAt`'s first argument. Reaching here means an AST built by hand.
    ERef(..) => None
  }
}

///|
/// A `$name` or a `*name` written inside a body.
///
/// One rule with two messages, because the fixes differ. A `compute` or a
/// `pred` IS callable from a body — bare, the way a condition slot spells one
/// — so the finding names the spelling that works. A dynamic binding has no
/// spelling that works: it belongs to the render stack, and a body has none.
fn C::render_only(
  self : C,
  name : String,
  sigil~ : String,
  span : @tscript.Span,
) -> Unit {
  let head = "`\{sigil}\{name}` is answered by the render stack, and a body runs after one, so it reads Null here"
  if sigil == "$" {
    self.say(
      "RENDER_ONLY",
      head +
      (if self.callable.contains(name) {
        " — this block declares `\{name}`, so call it bare: `\{name}`"
      } else {
        match @statedef.nearest(name, self.callable.keys().collect()) {
          Some(s) =>
            " — did you mean the `pred` or `compute` `\{s}`, called bare?"
          None =>
            "; a `pred` or a `compute` is called bare from a body, and nothing here declares one by that name"
        }
      }),
      span,
    )
  } else {
    self.say(
      "RENDER_ONLY",
      head + "; a body cannot read a dynamic binding at all",
      span,
    )
  }
}

///|
/// A bare name, or a name applied to arguments.
fn C::name(
  self : C,
  name : String,
  args : Array[@tscript.Expr],
  span : @tscript.Span,
) -> @statedef.StateTy? {
  for a in args {
    self.expr(a) |> ignore
  }
  // A parameter, and it takes no arguments — applying one is what a reader
  // would otherwise have to work out from the arity table.
  if self.params.contains(name) {
    if !args.is_empty() {
      self.say(
        "NOT_CALLABLE",
        "`\{name}` is a parameter, so it takes no arguments",
        span,
      )
      return None
    }
    return self.params.get(name).unwrap_or(None)
  }
  // A builtin: arity is checked, and the result type is what the vocabulary
  // says it is.
  if @tscript.script_builtin(name) is Some(arity) {
    if args.length() != arity {
      self.say(
        "ARITY",
        "`\{name}` takes \{arity} argument(s), not \{args.length()}",
        span,
      )
      return None
    }
    return builtin_result(name)
  }
  // A predicate or a compute this block declares.
  if self.callable.get(name) is Some(want) {
    if args.length() != want {
      self.say(
        "ARITY",
        "`\{name}` takes \{want} argument(s), not \{args.length()}",
        span,
      )
    }
    // A `pred` answers Bool; a `compute` answers whatever its body does, and
    // asking would mean ordering the declarations. Opaque is the honest
    // answer and costs nothing, since nothing downstream needs it yet.
    return None
  }
  let mut choices = self.params.keys().collect()
  choices = choices +
    @tscript.script_builtin_names() +
    self.callable.keys().collect()
  self.say(
    "NO_NAME",
    "nothing here is called `\{name}`" +
    (match @statedef.nearest(name, choices) {
      Some(s) => " — did you mean `\{s}`?"
      None =>
        "; a bare name is a parameter, a builtin, or a `pred` or `compute` this block declares"
    }),
    span,
  )
  None
}

///|
/// A chain of operands joined by one family's operators.
fn C::chain(
  self : C,
  family : @tscript.OpFamily,
  operands : Array[@tscript.Expr],
  span : @tscript.Span,
) -> @statedef.StateTy? {
  let types = operands.map(o => self.expr(o))
  match family {
    FLogic | FImplies => {
      for i, t in types {
        match definite(t) {
          Some(ty) if !is_boolish(ty) =>
            self.say(
              "ALWAYS_TRUE",
              "\{ty.show_source()} is always truthy, so this operand never decides anything",
              expr_span(operands[i]),
            )
          _ => ()
        }
      }
      Some(TBool)
    }
    FCompare => {
      // Both sides known and different: comparing them can only ever answer
      // one way, which is not what the author wrote it for.
      match
        (
          definite(types.get(0).unwrap_or(None)),
          definite(types.get(1).unwrap_or(None)),
        ) {
        (Some(a), Some(b)) =>
          if !comparable(a, b) {
            self.say(
              "TYPE",
              "\{a.show_source()} and \{b.show_source()} are never equal, so this comparison has one answer",
              span,
            )
          }
        _ => ()
      }
      Some(TBool)
    }
    FAdd | FMul => {
      // `+` concatenates two strings and adds two numbers; the operands'
      // static types decide, and a mixed pair is an error rather than a
      // coercion. Everything else is arithmetic only.
      let all_text = types.iter().all(t => t is Some(TText))
      if family is FAdd && all_text && !types.is_empty() {
        return Some(TText)
      }
      for i, t in types {
        match definite(t) {
          Some(ty) if !is_numeric(ty) =>
            self.say(
              "TYPE",
              "arithmetic needs a number, but this is \{ty.show_source()}",
              expr_span(operands[i]),
            )
          _ => ()
        }
      }
      Some(TFloat)
    }
  }
}

// ---------------------------------------------------------------------------
// The type rules

///|
/// The result of a reading builtin. `None` where the vocabulary genuinely
/// cannot say — `min`/`max`/`clamp` answer whatever they were given, and
/// pretending they answer `f64` would make `int .n` look like a widening.
fn builtin_result(name : String) -> @statedef.StateTy? {
  match name {
    "empty?" | "truthy?" | "falsy?" | "null?" | "has" | "contains" =>
      Some(TBool)
    "len" | "int" => Some(TInt(width=32, signed=true))
    "num" => Some(TFloat)
    "str" | "lower" | "upper" | "trim" => Some(TText)
    _ => None
  }
}

///|
/// Narrow a type to one worth checking against.
///
/// `any` is a DECLARED type and an opaque value at the same time — it is the
/// dynamic escape hatch inside a typed struct — so every rule below has to
/// treat it the way it treats a `$method` result. Doing that here rather than
/// in each rule is what stops one of them from forgetting.
fn definite(t : @statedef.StateTy?) -> @statedef.StateTy? {
  match t {
    Some(TAny) => None
    other => other
  }
}

///|
fn is_numeric(t : @statedef.StateTy) -> Bool {
  t is (TInt(..) | TFloat)
}

///|
/// Whether a value of this type can answer a yes/no question usefully.
///
/// The same rule `StateTy::is_boolish` states, and reached through it so the
/// two cannot drift: a List, a Map and an Obj are truthy unconditionally, so a
/// condition over one never decides anything. Strings and numbers stay
/// boolish on purpose — `@show=".role"` beside `@text=".role"` is idiomatic.
fn is_boolish(t : @statedef.StateTy) -> Bool {
  t.is_boolish()
}

///|
/// Whether two types can hold equal values.
///
/// The integer/float pair is deliberately comparable: `Value` has one
/// `Num(Double)`, so an `s32` and an `f64` are the same runtime shape and
/// `.count is 2` must not be a type error.
fn comparable(a : @statedef.StateTy, b : @statedef.StateTy) -> Bool {
  if a == b {
    return true
  }
  if is_numeric(a) && is_numeric(b) {
    return true
  }
  // An `any` field holds whatever it was given, and an enum is a string at
  // runtime, so both compare against anything the author means them to.
  a is (TAny | TEnum(_)) || b is (TAny | TEnum(_))
}

///|
/// Whether `got` may be written where `want` is expected.
fn C::assignable(
  self : C,
  want : @statedef.StateTy?,
  got : @statedef.StateTy?,
  span : @tscript.Span,
) -> Unit {
  guard definite(want) is Some(w) && definite(got) is Some(g) else { return }
  let ok = match (w, g) {
    // One numeric surface: assigning into an `s32` truncates and range-checks
    // against the same bounds the generated decode already applies, and fails
    // — no change — outside them. That is a runtime answer, not a type error.
    (TInt(..) | TFloat, TInt(..) | TFloat) => true
    // An enum is a string at runtime, so a computed string can name a case.
    (TEnum(_), TText) => true
    _ => w == g
  }
  if !ok {
    self.say(
      "TYPE",
      "this place is \{w.show_source()}, but the value is \{g.show_source()}",
      span,
    )
  }
}

///|
/// Whether a collection method fits the field it is called on.
fn C::method_fits(
  self : C,
  call : String,
  t : @statedef.StateTy,
  span : @tscript.Span,
) -> Unit {
  guard definite(Some(t)) is Some(t) else { return }
  let ok = match call {
    // The set operations, over open and closed membership alike.
    "add" | "remove" | "toggle" => t is (TSet | TFlags(_))
    // The sequence operations. A map is keyed rather than ordered, so it takes
    // the keyed half and not `push`.
    "push" | "insertAt" => t is TList(_)
    "setAt" | "deleteAt" => t is (TList(_) | TOMap(_))
    _ => true
  }
  if !ok {
    self.say(
      "NO_METHOD",
      "`\{call}` does not apply to \{t.show_source()}",
      span,
    )
  }
}

///|
fn assign_word(op : @tscript.AssignOp) -> String {
  op.word()
}

///|
/// Where an expression is, for a finding about it.
fn expr_span(e : @tscript.Expr) -> @tscript.Span {
  match e {
    ELit(span~, ..)
    | ETpl(span~, ..)
    | ERead(span~, ..)
    | EMethod(span~, ..)
    | EDyn(span~, ..)
    | EName(span~, ..)
    | EApp(span~, ..)
    | EChain(span~, ..)
    | EUnary(span~, ..)
    | EIf(span~, ..)
    | ERef(span~, ..) => span
  }
}
