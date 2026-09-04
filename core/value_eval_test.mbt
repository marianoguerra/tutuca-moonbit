// Eval-oriented tests. The originals pass ad-hoc mock stack objects; here each
// mock is a small struct
// implementing only the @core.Stack methods it needs (defaults cover the
// rest, returning Null).

///|
/// Mock stack backed by a field map
priv struct FieldStack {
  fields : Map[String, @core.Value]
}

///|
impl @core.Stack for FieldStack with fn lookup_storage(self, name) {
  self.fields.get(name).unwrap_or(Null)
}

///|
/// Mock stack backed by a method-result map (the stack invokes the method
/// and hands back the result)
priv struct MethodStack {
  methods : Map[String, @core.Value]
}

///|
impl @core.Stack for MethodStack with fn lookup_method(self, name) {
  self.methods.get(name).unwrap_or(Null)
}

///|
/// Mock stack resolving a single binding name
priv struct BindStack {
  bind : @core.Value
}

///|
impl @core.Stack for BindStack with fn lookup_bind(self, _name) {
  self.bind
}

///|
test "an application resolves its name and applies the builtin" {
  // Built rather than parsed: the parser lives one package UP now (core
  // cannot import it), and what this is about is evaluation anyway.
  let stack : FieldStack = { fields: { "items": List([]), "name": Str("hi") }, }
  fn app(name : String, field : String) -> @core.Expr {
    Expr::app(name, [Expr::field(field)])
  }

  assert_true(app("empty?", "items").eval(stack) is Bool(true))
  assert_true(app("empty?", "name").eval(stack) is Bool(false))
  assert_true(app("truthy?", "name").eval(stack) is Bool(true))
  assert_true(app("empty?", "items").eval(stack) is Bool(true))
  assert_true(app("null?", "items").eval(stack) is Bool(false))
  // A name nothing answers evaluates to Null rather than failing: the parser
  // refuses one, so reaching here means an App built by hand or decoded from
  // an IR module an older generator wrote.
  assert_true(app("present?", "items").eval(stack) is Null)
}

///|
test "FieldVal.eval reads the raw field without invoking" {
  let stack : FieldStack = {
    fields: { "count": Num(7), "m": Fn(_args => Str("called")) },
  }
  let count : @core.Expr = Expr::field("count")
  assert_true(count.eval(stack) is Num(7))
  // the function comes back raw, not invoked
  let m : @core.Expr = Expr::field("m")
  guard! m.eval(stack) is Fn(f)
  assert_true(f([]) is Str("called"))
}

///|
test "MethodVal.eval invokes the method" {
  let stack : MethodStack = { methods: { "fullName": Str("Ada L") }, }
  let v : @core.Expr = Expr::method_("fullName")
  assert_true(v.eval(stack) is Str("Ada L"))
}

///|
test "MethodVal.eval_as_handler hands back the raw function" {
  let stack : FieldStack = {
    fields: { "inc": Fn(_args => Str("inc-marker")) },
  }
  let v : @core.Expr = Expr::method_("inc")
  guard! v.eval_as_handler(stack) is Fn(f)
  assert_true(f([]) is Str("inc-marker"))
}

///|
test "is eval compares the field value against the literal" {
  let stack : FieldStack = { fields: { "view": Str("detail") }, }
  fn eq(lit : String) -> @core.Expr {
    Expr::app("is", [Expr::field("view"), Expr::lit(LStr(lit))])
  }

  assert_true(eq("detail").eval(stack) is Bool(true))
  assert_true(eq("list").eval(stack) is Bool(false))
}

///|
test "bind member eval reads the member off the resolved binding" {
  // map-like binding value: member lookup with Null default (covers both
  // original paths — immutable `.get` and plain-object property access)
  let im : BindStack = { bind: Map({ "title": Str("alpha") }), }
  let hit : @core.Expr = Expr::bind_member("value", "title")
  assert_true(hit.eval(im) is Str("alpha"))
  let miss : @core.Expr = Expr::bind_member("value", "missing")
  assert_true(miss.eval(im) is Null)
  let plain : BindStack = { bind: Map({ "color": Str("red") }), }
  let color : @core.Expr = Expr::bind_member("meta", "color")
  assert_true(color.eval(plain) is Str("red"))
  let missing : @core.Expr = Expr::bind_member("meta", "missing")
  assert_true(missing.eval(plain) is Null)
  // unresolved binding
  let unresolved : BindStack = { bind: Null, }
  let nope : @core.Expr = Expr::bind_member("nope", "x")
  assert_true(nope.eval(unresolved) is Null)
}

///|
test "Value::is_truthy follows JS truthiness" {
  assert_true(!@core.Value::Null.is_truthy())
  assert_true(!@core.Value::Bool(false).is_truthy())
  assert_true(!@core.Value::Num(0).is_truthy())
  assert_true(!@core.Value::Str("").is_truthy())
  assert_true(@core.Value::Str("0").is_truthy()) // non-empty string
  assert_true(@core.Value::Num(-1).is_truthy())
  assert_true(@core.Value::List([]).is_truthy()) // objects always truthy
  assert_true(@core.Value::Map(Map([])).is_truthy())
}

///|
test "Value::to_display_string follows JS interpolation" {
  assert_eq(@core.Value::Null.to_display_string(), "null")
  assert_eq(@core.Value::Bool(true).to_display_string(), "true")
  assert_eq(@core.Value::Num(42).to_display_string(), "42")
  assert_eq(@core.Value::Num(12.5).to_display_string(), "12.5")
  assert_eq(@core.Value::Str("hi").to_display_string(), "hi")
  assert_eq(@core.Value::List([Num(1), Num(2)]).to_display_string(), "1,2")
  // Array.join semantics: null elements join as "", unlike top-level `${null}`
  assert_eq(
    @core.Value::List([Num(1), Null, Num(2)]).to_display_string(),
    "1,,2",
  )
}

///|
/// A stack that COUNTS the methods it is asked for — the only way to observe
/// that a short-circuit actually stopped.
priv struct CountingStack {
  fields : Map[String, @core.Value]
  asked : Array[String]
}

///|
impl @core.Stack for CountingStack with fn lookup_storage(self, name) {
  self.fields.get(name).unwrap_or(Null)
}

///|
impl @core.Stack for CountingStack with fn lookup_method(self, name) {
  self.asked.push(name)
  Bool(true)
}

///|
test "the operators evaluate through the same table the shape predicates do" {
  let stack : FieldStack = {
    fields: {
      "open": Bool(true),
      "shut": Bool(false),
      "items": List([]),
      "kind": Str("a"),
      "n": Num(3),
    },
  }
  fn f(n : String) -> @core.Expr {
    Expr::field(n)
  }

  fn op(name : String, args : Array[@core.Expr]) -> @core.Value {
    Expr::app(name, args).eval(stack)
  }

  assert_true(op("not", [f("shut")]) is Bool(true))
  assert_true(op("not", [f("open")]) is Bool(false))
  assert_true(op("and", [f("open"), f("shut")]) is Bool(false))
  assert_true(op("or", [f("open"), f("shut")]) is Bool(true))
  assert_true(op("is", [f("kind"), Expr::lit(LStr("a"))]) is Bool(true))
  assert_true(op("is not", [f("kind"), Expr::lit(LStr("b"))]) is Bool(true))
  assert_true(op(">", [f("n"), Expr::lit(LNum(2))]) is Bool(true))
  assert_true(op("<=", [f("n"), Expr::lit(LNum(3))]) is Bool(true))
  assert_true(op("implies", [f("shut"), f("open")]) is Bool(true))
  assert_true(op("len", [f("items")]) is Num(0))
  // `and` / `or` coerce with `Value::is_truthy` and NOT `pred_truthy` — the
  // same coercion the compiled backend's `at_bool` uses — so an EMPTY LIST is
  // truthy to an operator and falsy to `truthy?`. Both are deliberate, and
  // this is the pair that says so.
  assert_true(op("and", [f("items"), f("open")]) is Bool(true))
  assert_true(op("truthy?", [f("items")]) is Bool(false))
}

///|
test "`and` and `or` stop early, so a slot can guard a compute" {
  // `Builtin::apply` is handed ALREADY-EVALUATED arguments, so a table row
  // cannot decline to look at its second one. `Expr::eval` answers these two
  // ahead of the table — without which `and (truthy? .items) ($firstLabel)`
  // would call the compute on an empty list here and not in a compiled
  // handler, and the two backends would disagree.
  let stack : CountingStack = {
    fields: { "open": Bool(true), "shut": Bool(false) },
    asked: [],
  }
  let guarded : @core.Expr = Expr::app("and", [
    Expr::field("shut"),
    Expr::method_("boom"),
  ])
  assert_true(guarded.eval(stack) is Bool(false))
  assert_eq(stack.asked, [])
  // …and the other way, `or` stops once the left answers yes.
  let short : @core.Expr = Expr::app("or", [
    Expr::field("open"),
    Expr::method_("boom"),
  ])
  assert_true(short.eval(stack) is Bool(true))
  assert_eq(stack.asked, [])
  // The control: when the left does NOT decide it, the right IS asked.
  let both : @core.Expr = Expr::app("and", [
    Expr::field("open"),
    Expr::method_("fine"),
  ])
  assert_true(both.eval(stack) is Bool(true))
  assert_eq(stack.asked, ["fine"])
}

///|
/// The forms a SLOT refuses and a body writes, evaluated.
///
/// They are reachable here because there is one AST: a `Step` can carry any of
/// them, and an IR module written by hand can spell one. `eval` answers rather
/// than falls through, and what it answers is what the compiled backend
/// answers for the same expression — which is the property the conformance
/// corpus exists to hold the two to.
test "a chain, a unary and an `if` evaluate" {
  let stack : FieldStack = {
    fields: { "open": Bool(true), "shut": Bool(false), "n": Num(3.0) },
  }
  fn f(name : String) -> @core.Expr {
    @core.Expr::field(name)
  }

  fn chain(op : String, a : @core.Expr, b : @core.Expr) -> @core.Expr {
    EChain(family=FLogic, ops=[op], operands=[a, b], span=@core.no_span)
  }

  // A chain folds LEFT into applications of the operator's own name, which is
  // the grouping `&&` gives it in the compiled backend.
  assert_true(chain("and", f("open"), f("open")).eval(stack) is Bool(true))
  assert_true(chain("and", f("shut"), f("open")).eval(stack) is Bool(false))
  assert_true(chain("or", f("shut"), f("open")).eval(stack) is Bool(true))
  // Three operands, one chain: `a and b and c`.
  let three : @core.Expr = EChain(
    family=FLogic,
    ops=["and", "and"],
    operands=[f("open"), f("open"), f("shut")],
    span=@core.no_span,
  )
  assert_true(three.eval(stack) is Bool(false))
  // Arithmetic has no builtin, so it answers Null — the same answer every
  // unresolved name gives. The slot vocabulary is what evaluates.
  let sum : @core.Expr = EChain(
    family=FAdd,
    ops=["+"],
    operands=[f("n"), f("n")],
    span=@core.no_span,
  )
  assert_true(sum.eval(stack) is Null)
  // `not` is the vocabulary's; negation is a fact about the number.
  let negated : @core.Expr = EUnary(
    op=UNot,
    operand=f("shut"),
    span=@core.no_span,
  )
  assert_true(negated.eval(stack) is Bool(true))
  let minus : @core.Expr = EUnary(op=UNeg, operand=f("n"), span=@core.no_span)
  assert_eq(minus.eval(stack), Num(-3.0))
  let bad : @core.Expr = EUnary(op=UNeg, operand=f("open"), span=@core.no_span)
  assert_true(bad.eval(stack) is Null)
  // An `if` picks an arm and evaluates only that one.
  let taken : @core.Expr = EIf(
    cond=f("open"),
    then_=f("n"),
    else_=f("shut"),
    span=@core.no_span,
  )
  assert_eq(taken.eval(stack), Num(3.0))
  let other : @core.Expr = EIf(
    cond=f("shut"),
    then_=f("n"),
    else_=f("open"),
    span=@core.no_span,
  )
  assert_eq(other.eval(stack), Bool(true))
}

///|
test "a place deeper than a slot can write still reads" {
  // `.a.b` is refused in a slot (`Position`), which is a rule about what may
  // be WRITTEN. The tree can hold one — a block body writes them — and the
  // reader walks it rather than answering nothing.
  let stack : FieldStack = {
    fields: { "row": Map({ "title": Str("hi") }), "n": Num(1.0) },
  }
  let deep : @core.Expr = ERead(
    place={
      root: PState("row"),
      steps: [PField("title")],
      span: @core.no_span,
    },
    span=@core.no_span,
  )
  assert_eq(deep.eval(stack), Str("hi"))
  // A parameter has no answer on a render stack: a body runs after one.
  let param : @core.Expr = ERead(
    place={ root: PParam("p"), steps: [], span: @core.no_span, },
    span=@core.no_span,
  )
  assert_true(param.eval(stack) is Null)
}
