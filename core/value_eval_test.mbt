// Port of the eval-oriented tests from tutuca test/value.test.js. The JS
// tests pass ad-hoc mock stack objects; here each mock is a small struct
// implementing only the @core.Stack methods it needs (defaults cover the
// rest, returning Null).

///|
/// Mock stack backed by a field map (JS `{ lookupFieldRaw: (n) => ... }`)
priv struct FieldStack {
  fields : Map[String, @core.Value]
}

///|
impl @core.Stack for FieldStack with fn lookup_field_raw(self, name) {
  self.fields.get(name).unwrap_or(@core.Value::Null)
}

///|
/// Mock stack backed by a method-result map (the stack invokes the method
/// and hands back the result)
priv struct MethodStack {
  methods : Map[String, @core.Value]
}

///|
impl @core.Stack for MethodStack with fn lookup_method(self, name) {
  self.methods.get(name).unwrap_or(@core.Value::Null)
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
test "predicate eval applies the function" {
  let ctx = @core.ParseCtx::new()
  let stack : FieldStack = { fields: { "items": List([]), "name": Str("hi") } }
  guard @core.parse_bool("empty? .items", ctx) is Some(v1)
  assert_true(v1.eval(stack) is Bool(true))
  guard @core.parse_bool("empty? .name", ctx) is Some(v2)
  assert_true(v2.eval(stack) is Bool(false))
  guard @core.parse_bool("truthy? .name", ctx) is Some(v3)
  assert_true(v3.eval(stack) is Bool(true))
  guard @core.parse_bool("falsy? .items", ctx) is Some(v4)
  assert_true(v4.eval(stack) is Bool(true))
  guard @core.parse_bool("null? .items", ctx) is Some(v5)
  assert_true(v5.eval(stack) is Bool(false))
}

///|
test "FieldVal.eval reads the raw field without invoking" {
  let ctx = @core.ParseCtx::new()
  let stack : FieldStack = {
    fields: { "count": Num(7), "m": Fn(_args => @core.Value::Str("called")) },
  }
  guard @core.parse_text(".count", ctx) is Some(count)
  assert_true(count.eval(stack) is Num(7))
  // the function comes back raw, not invoked
  guard @core.parse_text(".m", ctx) is Some(m)
  guard m.eval(stack) is Fn(f)
  assert_true(f([]) is Str("called"))
}

///|
test "MethodVal.eval invokes the method" {
  let ctx = @core.ParseCtx::new()
  let stack : MethodStack = { methods: { "fullName": Str("Ada L") } }
  guard @core.parse_text("$fullName", ctx) is Some(v)
  assert_true(v.eval(stack) is Str("Ada L"))
}

///|
test "MethodVal.eval_as_handler hands back the raw function" {
  let ctx = @core.ParseCtx::new()
  let stack : FieldStack = {
    fields: { "inc": Fn(_args => @core.Value::Str("inc-marker")) },
  }
  guard @core.parse_text("$inc", ctx) is Some(v)
  guard v.eval_as_handler(stack) is Fn(f)
  assert_true(f([]) is Str("inc-marker"))
}

///|
test "equals? eval compares the field value against the literal" {
  let ctx = @core.ParseCtx::new()
  let stack : FieldStack = { fields: { "view": Str("detail") } }
  guard @core.parse_bool("equals? .view 'detail'", ctx) is Some(v1)
  assert_true(v1.eval(stack) is Bool(true))
  guard @core.parse_bool("equals? .view 'list'", ctx) is Some(v2)
  assert_true(v2.eval(stack) is Bool(false))
}

///|
test "bind member eval reads the member off the resolved binding" {
  // map-like binding value: member lookup with Null default (this one case
  // covers both JS paths — immutable `.get` and plain-object property access)
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
  assert_true(@core.Value::Map({}).is_truthy())
}

///|
test "Value::to_display_string follows JS interpolation" {
  assert_eq(@core.Value::Null.to_display_string(), "null")
  assert_eq(@core.Value::Bool(true).to_display_string(), "true")
  assert_eq(@core.Value::Num(42).to_display_string(), "42")
  assert_eq(@core.Value::Num(12.5).to_display_string(), "12.5")
  assert_eq(@core.Value::Str("hi").to_display_string(), "hi")
  assert_eq(@core.Value::List([Num(1), Num(2)]).to_display_string(), "1,2")
  // JS Array.join: null elements join as "", unlike top-level `${null}`
  assert_eq(
    @core.Value::List([Num(1), Null, Num(2)]).to_display_string(),
    "1,,2",
  )
}
