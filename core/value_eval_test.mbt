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
impl @core.Stack for FieldStack with fn lookup_field_raw(self, name) {
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
  let stack : FieldStack = { fields: { "items": List([]), "name": Str("hi") } }
  fn app(name : String, field : String) -> @core.Val {
    App(name~, args=[Field(field)])
  }

  assert_true(app("empty?", "items").eval(stack) is Bool(true))
  assert_true(app("empty?", "name").eval(stack) is Bool(false))
  assert_true(app("truthy?", "name").eval(stack) is Bool(true))
  assert_true(app("falsy?", "items").eval(stack) is Bool(true))
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
  let count : @core.Val = Field("count")
  assert_true(count.eval(stack) is Num(7))
  // the function comes back raw, not invoked
  let m : @core.Val = Field("m")
  guard! m.eval(stack) is Fn(f)
  assert_true(f([]) is Str("called"))
}

///|
test "MethodVal.eval invokes the method" {
  let stack : MethodStack = { methods: { "fullName": Str("Ada L") } }
  let v : @core.Val = Method("fullName")
  assert_true(v.eval(stack) is Str("Ada L"))
}

///|
test "MethodVal.eval_as_handler hands back the raw function" {
  let stack : FieldStack = { fields: { "inc": Fn(_args => Str("inc-marker")) } }
  let v : @core.Val = Method("inc")
  guard! v.eval_as_handler(stack) is Fn(f)
  assert_true(f([]) is Str("inc-marker"))
}

///|
test "equals? eval compares the field value against the literal" {
  let stack : FieldStack = { fields: { "view": Str("detail") } }
  fn eq(lit : String) -> @core.Val {
    App(name="equals?", args=[
      Field("view"),
      Const(lit=LStr(lit), from_macro=false),
    ])
  }

  assert_true(eq("detail").eval(stack) is Bool(true))
  assert_true(eq("list").eval(stack) is Bool(false))
}

///|
test "bind member eval reads the member off the resolved binding" {
  // map-like binding value: member lookup with Null default (covers both
  // original paths — immutable `.get` and plain-object property access)
  let im : BindStack = { bind: Map({ "title": Str("alpha") }) }
  let hit : @core.Val = BindMember(name="value", prop="title")
  assert_true(hit.eval(im) is Str("alpha"))
  let miss : @core.Val = BindMember(name="value", prop="missing")
  assert_true(miss.eval(im) is Null)
  let plain : BindStack = { bind: Map({ "color": Str("red") }) }
  let color : @core.Val = BindMember(name="meta", prop="color")
  assert_true(color.eval(plain) is Str("red"))
  let missing : @core.Val = BindMember(name="meta", prop="missing")
  assert_true(missing.eval(plain) is Null)
  // unresolved binding
  let unresolved : BindStack = { bind: Null }
  let nope : @core.Val = BindMember(name="nope", prop="x")
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
impl @core.Stack for CountingStack with fn lookup_field_raw(self, name) {
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
  fn f(n : String) -> @core.Val {
    Field(n)
  }

  fn op(name : String, args : Array[@core.Val]) -> @core.Value {
    @core.Val::App(name~, args~).eval(stack)
  }

  assert_true(op("not", [f("shut")]) is Bool(true))
  assert_true(op("not", [f("open")]) is Bool(false))
  assert_true(op("and", [f("open"), f("shut")]) is Bool(false))
  assert_true(op("or", [f("open"), f("shut")]) is Bool(true))
  assert_true(
    op("is", [f("kind"), Const(lit=LStr("a"), from_macro=false)]) is Bool(true),
  )
  assert_true(
    op("is not", [f("kind"), Const(lit=LStr("b"), from_macro=false)])
    is Bool(true),
  )
  assert_true(
    op(">", [f("n"), Const(lit=LNum(2), from_macro=false)]) is Bool(true),
  )
  assert_true(
    op("<=", [f("n"), Const(lit=LNum(3), from_macro=false)]) is Bool(true),
  )
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
  // cannot decline to look at its second one. `Val::eval` answers these two
  // ahead of the table — without which `and (truthy? .items) ($firstLabel)`
  // would call the compute on an empty list here and not in a compiled
  // handler, and the two backends would disagree.
  let stack : CountingStack = {
    fields: { "open": Bool(true), "shut": Bool(false) },
    asked: [],
  }
  let guarded : @core.Val = App(name="and", args=[Field("shut"), Method("boom")])
  assert_true(guarded.eval(stack) is Bool(false))
  assert_eq(stack.asked, [])
  // …and the other way, `or` stops once the left answers yes.
  let short : @core.Val = App(name="or", args=[Field("open"), Method("boom")])
  assert_true(short.eval(stack) is Bool(true))
  assert_eq(stack.asked, [])
  // The control: when the left does NOT decide it, the right IS asked.
  let both : @core.Val = App(name="and", args=[Field("open"), Method("fine")])
  assert_true(both.eval(stack) is Bool(true))
  assert_eq(stack.asked, ["fine"])
}
