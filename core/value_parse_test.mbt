// Port of the parsing suites from tutuca test/value.test.js:
// string templates, kind-group acceptance/rejection, predicates, $ vs .,
// parse_field, @name.member, and handler parsing (EventHandler.parse tests
// port to parse_input_handler — the handler+args shape is identical).

///|
test "string template with interpolation" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'flex flex-col gap-3 {.foo}'", ctx)
    is Some(StrTpl(parts))
  assert_eq(parts.length(), 2)
  assert_true(parts[0] is Some(Const(lit=LStr("flex flex-col gap-3 "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "constant-only template stays a StrTplVal" {
  // A `$'…'` whose every part is constant is not folded to a Const — it stays
  // a StrTpl so the linter can flag it.
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'flex flex-col gap-3 {\\'hi\\'}'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard r.eval(@core.NullStack::{  }) is Str(s)
  assert_eq(s, "flex flex-col gap-3 hi")
}

///|
test "text with field interpolation" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'flex gap-3 {.foo}'", ctx) is Some(StrTpl(parts))
  assert_true(parts[0] is Some(Const(lit=LStr("flex gap-3 "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "multiple interpolations" {
  // Empty Const bookends are trimmed by the template parse, so the
  // leading/trailing "" segments produced by the split don't appear in parts.
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'{.a} between {.b}'", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 3)
  assert_true(parts[0] is Some(Field("a")))
  assert_true(parts[1] is Some(Const(lit=LStr(" between "), ..)))
  assert_true(parts[2] is Some(Field("b")))
}

///|
test "only interpolation, no surrounding text" {
  // After trimming, a single-placeholder template collapses to one entry —
  // this is the shape the REDUNDANT_TEMPLATE_STRING lint rule keys off.
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'{.foo}'", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 1)
  assert_true(parts[0] is Some(Field("foo")))
}

///|
test "whitespace bookends are preserved (non-empty Const)" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$' {.foo} '", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 3)
  assert_true(parts[0] is Some(Const(lit=LStr(" "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
  assert_true(parts[2] is Some(Const(lit=LStr(" "), ..)))
}

///|
test "quoted constant inside braces" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'flex {\\'gap-3\\'}'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard r.eval(@core.NullStack::{  }) is Str(s)
  assert_eq(s, "flex gap-3")
}

///|
test "numeric constant inside braces" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$'width: {42}px'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard r.eval(@core.NullStack::{  }) is Str(s)
  assert_eq(s, "width: 42px")
}

///|
test "quoted constant string with spaces" {
  // A bare multi-word run like `flex gap-3` is two tokens, not a value; a
  // single-quoted `'…'` literal carries spaces verbatim.
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_text("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "quoted single word" {
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_text("'badge'", ctx) is Some(Const(lit=LStr("badge"), ..)),
  )
}

///|
test "unquoted multi-word string returns None" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_text("flex gap-3", ctx) is None)
}

///|
test "unquoted {…} is not a template, returns None" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_text("flex {.foo}", ctx) is None)
  assert_true(@core.parse_text("{.foo}", ctx) is None)
}

///|
test "parse_bool rejects string template" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("$'flex {.foo}'", ctx) is None)
}

///|
test "parse_bool accepts a quoted constant (single literal kind)" {
  // A dynamic template is rejected in a boolean slot, but a *literal* — a
  // plain quoted string or a placeholderless `$'…'` template — is accepted:
  // all literals share the one literal kind, so any literal parses wherever
  // `true`/`false` do (a suspicious literal condition is a lint concern).
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_bool("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "parse_bool accepts a placeholderless string template" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("$'flex'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  guard r.eval(@core.NullStack::{  }) is Str(s)
  assert_eq(s, "flex")
}

///|
test "parse_sequence rejects string template" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_sequence("$'items {.foo}'", ctx) is None)
}

///|
test "parse_component rejects string template" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_component("$'child {.foo}'", ctx) is None)
}

///|
test "string template works in parse_macro_attr" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_macro_attr("$'flex {.foo}'", ctx) is Some(StrTpl(parts))
  assert_true(parts[0] is Some(Const(lit=LStr("flex "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "quoted constant works in parse_macro_attr" {
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_macro_attr("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "single-token value is not a predicate" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool(".items", ctx) is Some(r)
  assert_true(r is Field("items"))
  assert_true(!(r is Predicate(..)))
}

///|
test "unary predicates parse to a PredicateVal" {
  let ctx = @core.ParseCtx::new()
  for
    pair in [
      (@core.Pred::IsEmpty, "empty?"),
      (IsTruthy, "truthy?"),
      (IsFalsy, "falsy?"),
      (IsNull, "null?"),
    ] {
    let (expected, name) = pair
    guard @core.parse_bool("\{name} .items", ctx)
      is Some(Predicate(pred~, args~))
    assert_true(pred == expected)
    assert_eq(pred.name(), name)
    assert_eq(args.length(), 1)
    assert_true(args[0] is Field("items"))
  }
}

///|
test "unknown predicate returns None" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("present? .items", ctx) is None)
  // port extension: the failure is reported on the collected issues
  assert_true(
    ctx.issues ==
    [{ kind: BadValue, role: UnknownPredicate, value: "present?" }],
  )
}

///|
test "arity mismatch returns None" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("empty? .a .b", ctx) is None)
  // port extension: the arity issue carries the predicate as payload
  assert_true(
    ctx.issues ==
    [{ kind: BadValue, role: PredicateArity(IsEmpty), value: "empty? .a .b" }],
  )
}

///|
test "bad predicate arg returns None" {
  // `Foo` is a type name — not allowed in the boolean group used for args.
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("empty? Foo", ctx) is None)
}

///|
test "predicate args accept bind values" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("truthy? @flag", ctx) is Some(Predicate(args~, ..))
  assert_true(args[0] is Bind("flag"))
}

///|
test ". parses to a FieldVal" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text(".count", ctx) is Some(r)
  assert_true(r is Field("count"))
  assert_eq("\{r}", ".count")
}

///|
test "$ parses to a MethodVal" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("$fullName", ctx) is Some(r)
  assert_true(r is Method("fullName"))
  assert_eq("\{r}", "$fullName")
}

///|
test "$' is a string template, not a method" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_text("$'hi {.name}'", ctx) is Some(StrTpl(_)))
  assert_true(@core.parse_text("$name", ctx) is Some(Method("name")))
}

///|
test "$ works as a conditional-slot value" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("$canSubmit", ctx) is Some(Method(_)))
}

///|
test "$ is rejected in path-bearing slots (@each, <x render>)" {
  // A method result has no addressable path, so it cannot be iterated or
  // rendered as a child — `.field` stays valid there.
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_sequence("$items", ctx) is None)
  assert_true(@core.parse_component("$child", ctx) is None)
  assert_true(@core.parse_sequence(".items", ctx) is Some(Field(_)))
}

///|
test "$ is a method handler, a bare name is an input handler" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_input_handler("$inc", ctx) is Some(h1)
  assert_true(h1.handler is Method("inc"))
  guard @core.parse_input_handler("dec", ctx) is Some(h2)
  assert_true(h2.handler is HandlerName(name="dec", ns=Input))
}

///|
test ". cannot be used in handler position" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_input_handler(".inc", ctx) is None)
}

///|
test "$ method handler keeps its args" {
  // JS: EventHandler.parse("$setStr value") — the handler+args shape comes
  // from parse_input_handler, so the port targets it directly.
  let ctx = @core.ParseCtx::new()
  guard @core.parse_input_handler("$setStr value", ctx) is Some(h)
  assert_true(h.handler is Method("setStr"))
  assert_eq(h.args.length(), 1)
}

///|
test "equals? parses to a PredicateVal with a Const string arg" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("equals? .view 'detail'", ctx)
    is Some(Predicate(pred~, args~))
  assert_true(pred == Equals)
  assert_eq(pred.name(), "equals?")
  assert_eq(args.length(), 2)
  assert_true(args[0] is Field("view"))
  assert_true(args[1] is Const(lit=LStr("detail"), ..))
}

///|
test "string literal arg preserves interior spaces" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("equals? .name 'John Doe'", ctx)
    is Some(Predicate(args~, ..))
  assert_eq(args.length(), 2)
  assert_true(args[1] is Const(lit=LStr("John Doe"), ..))
}

///|
test "escaped quote in a string literal arg" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("equals? .name 'it\\'s'", ctx)
    is Some(Predicate(args~, ..))
  assert_true(args[1] is Const(lit=LStr("it's"), ..))
}

///|
test "equals? arity mismatch returns None" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_bool("equals? .view", ctx) is None)
}

///|
test "to_string round-trips a quoted literal" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_bool("equals? .view 'detail'", ctx) is Some(r)
  assert_eq("\{r}", "equals? .view 'detail'")
}

///|
test "bare string literal in parse_bool parses as a literal" {
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_bool("'detail'", ctx) is Some(Const(lit=LStr("detail"), ..)),
  )
}

///|
test "parse_field accepts a field reference" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_field(".color", ctx) is Some(Field(_)))
}

///|
test "parse_field accepts a method reference" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_field("$color", ctx) is Some(Method(_)))
}

///|
test "parse_field accepts a string-literal constant (dynamic alias default)" {
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_field("'gray'", ctx) is Some(Const(lit=LStr("gray"), ..)),
  )
}

///|
test "parse_field accepts a numeric constant" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_field("42", ctx) is Some(Const(lit=LNum(n), ..))
  assert_eq(n, 42)
}

///|
test "parse_field accepts a .seq[.key] seq-access" {
  let ctx = @core.ParseCtx::new()
  assert_true(
    @core.parse_field(".sheets[.selId]", ctx)
    is Some(SeqAccess(seq="sheets", key="selId")),
  )
}

///|
test "seq-access to_path_item yields a SeqAccessStep" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_field(".sheets[.selId]", ctx) is Some(r)
  assert_true(
    r.to_path_item()
    is Some(SeqAccessStep(seq_field="sheets", key_field="selId")),
  )
}

///|
test "one-level member read parses where bindings are accepted" {
  let ctx = @core.ParseCtx::new()
  guard @core.parse_text("@value.title", ctx) is Some(r)
  assert_true(r is BindMember(name="value", prop="title"))
  assert_eq("\{r}", "@value.title")
  // any binding name, not just `value`; predicate-style `?` members parse too
  assert_true(@core.parse_bool("@item.done?", ctx) is Some(BindMember(..)))
}

///|
test "two or more members fail to parse" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_text("@value.a.b", ctx) is None)
  assert_true(@core.parse_bool("@value.a.b.c", ctx) is None)
}

///|
test "dotted field reads still fail to parse" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_text(".a.b", ctx) is None)
  assert_true(@core.parse_bool(".a.b", ctx) is None)
}

///|
test "member reads are not addressable: no path item, no path-bearing slots" {
  let ctx = @core.ParseCtx::new()
  assert_true(@core.parse_component("@value.child", ctx) is None)
  assert_true(@core.parse_sequence("@value.items", ctx) is None)
  guard @core.parse_text("@value.title", ctx) is Some(r)
  assert_true(r.to_path_item() is None)
}

///|
test "handler arg accepts a quoted literal with spaces" {
  // JS: EventHandler.parse("showView 'detail mode'") — ported to
  // parse_input_handler (EventHandler lives in attribute.js, out of scope).
  let ctx = @core.ParseCtx::new()
  guard @core.parse_input_handler("showView 'detail mode'", ctx) is Some(h)
  assert_true(h.handler is HandlerName(name="showView", ns=Input))
  assert_eq(h.args.length(), 1)
  assert_true(h.args[0] is Const(lit=LStr("detail mode"), ..))
}
