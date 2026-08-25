// Parsing suites:
// string templates, kind-group acceptance/rejection, predicates, $ vs .,
// parse_field, @name.member, and handler parsing (through
// parse_input_handler — the handler+args shape is identical).

///|
test "string template with interpolation" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'flex flex-col gap-3 {.foo}'", ctx)
    is Some(StrTpl(parts))
  assert_eq(parts.length(), 2)
  assert_true(parts[0] is Some(Const(lit=LStr("flex flex-col gap-3 "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "constant-only template stays a StrTplVal" {
  // A `$'…'` whose every part is constant is not folded to a Const — it stays
  // a StrTpl so the linter can flag it.
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'flex flex-col gap-3 {\\'hi\\'}'", ctx)
    is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard! r.eval(@tutuca.NullStack::{  }) is Str(s)
  assert_eq(s, "flex flex-col gap-3 hi")
}

///|
test "text with field interpolation" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'flex gap-3 {.foo}'", ctx) is Some(StrTpl(parts))
  assert_true(parts[0] is Some(Const(lit=LStr("flex gap-3 "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "multiple interpolations" {
  // Empty Const bookends are trimmed by the template parse, so the
  // leading/trailing "" segments produced by the split don't appear in parts.
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'{.a} between {.b}'", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 3)
  assert_true(parts[0] is Some(Field("a")))
  assert_true(parts[1] is Some(Const(lit=LStr(" between "), ..)))
  assert_true(parts[2] is Some(Field("b")))
}

///|
test "only interpolation, no surrounding text" {
  // After trimming, a single-placeholder template collapses to one entry —
  // this is the shape the REDUNDANT_TEMPLATE_STRING lint rule keys off.
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'{.foo}'", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 1)
  assert_true(parts[0] is Some(Field("foo")))
}

///|
test "whitespace bookends are preserved (non-empty Const)" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$' {.foo} '", ctx) is Some(StrTpl(parts))
  assert_eq(parts.length(), 3)
  assert_true(parts[0] is Some(Const(lit=LStr(" "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
  assert_true(parts[2] is Some(Const(lit=LStr(" "), ..)))
}

///|
test "quoted constant inside braces" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'flex {\\'gap-3\\'}'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard! r.eval(@tutuca.NullStack::{  }) is Str(s)
  assert_eq(s, "flex gap-3")
}

///|
test "numeric constant inside braces" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$'width: {42}px'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  assert_true(r.is_literal())
  guard! r.eval(@tutuca.NullStack::{  }) is Str(s)
  assert_eq(s, "width: 42px")
}

///|
test "quoted constant string with spaces" {
  // A bare multi-word run like `flex gap-3` is two tokens, not a value; a
  // single-quoted `'…'` literal carries spaces verbatim.
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_text("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "quoted single word" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_text("'badge'", ctx) is Some(Const(lit=LStr("badge"), ..)),
  )
}

///|
test "unquoted multi-word string returns None" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text("flex gap-3", ctx) is None)
}

///|
test "unquoted {…} is not a template, returns None" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text("flex {.foo}", ctx) is None)
  assert_true(@tscript.parse_text("{.foo}", ctx) is None)
}

///|
test "parse_bool rejects string template" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("$'flex {.foo}'", ctx) is None)
}

///|
test "parse_bool accepts a quoted constant (single literal kind)" {
  // A dynamic template is rejected in a boolean slot, but a *literal* — a
  // plain quoted string or a placeholderless `$'…'` template — is accepted:
  // all literals share the one literal kind, so any literal parses wherever
  // `true`/`false` do (a suspicious literal condition is a lint concern).
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_bool("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "parse_bool accepts a placeholderless string template" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("$'flex'", ctx) is Some(r)
  assert_true(r is StrTpl(_))
  guard! r.eval(@tutuca.NullStack::{  }) is Str(s)
  assert_eq(s, "flex")
}

///|
test "parse_sequence rejects string template" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_sequence("$'items {.foo}'", ctx) is None)
}

///|
test "parse_component rejects string template" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_component("$'child {.foo}'", ctx) is None)
}

///|
test "string template works in parse_macro_attr" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_macro_attr("$'flex {.foo}'", ctx) is Some(StrTpl(parts))
  assert_true(parts[0] is Some(Const(lit=LStr("flex "), ..)))
  assert_true(parts[1] is Some(Field("foo")))
}

///|
test "quoted constant works in parse_macro_attr" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_macro_attr("'flex gap-3'", ctx)
    is Some(Const(lit=LStr("flex gap-3"), ..)),
  )
}

///|
test "single-token value is not an application" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool(".items", ctx) is Some(r)
  assert_true(r is Field("items"))
  assert_true(!(r is App(..)))
}

///|
test "unary predicates parse to a one-argument application" {
  let ctx = @tscript.ParseCtx::new()
  for pred_name in ["empty?", "truthy?", "falsy?", "null?"] {
    guard! @tscript.parse_bool("\{pred_name} .items", ctx)
      is Some(App(name~, args~))
    // The AST carries the NAME, not a constructor: that is what lets the
    // vocabulary grow without this enum growing a case.
    assert_eq(name, pred_name)
    assert_eq(args.length(), 1)
    assert_true(args[0] is Field("items"))
  }
}

///|
test "the builtin vocabulary is a table a caller can enumerate" {
  // The row is what carries the arity the parser checks against. The list is
  // ONE list for both languages — the shape predicates, the operators and the
  // reading builtins — so a name means the same thing in a `@show` and in a
  // `pred`, which is the whole reason the table stopped being an enum.
  assert_eq(@tutuca.builtin_names(), [
    "<", "<=", ">", ">=", "and", "clamp", "contains", "empty?", "has", "implies",
    "int", "is", "is not", "len", "lower", "max", "min", "not", "null?", "num", "or",
    "str", "trim", "truthy?", "upper",
  ])
  guard! @tutuca.builtin("empty?") is Some(b)
  assert_eq(b.name, "empty?")
  assert_eq(b.arity, 1)
  guard! @tutuca.builtin("is") is Some(eq)
  assert_eq(eq.arity, 2)
  assert_true(@tutuca.builtin("present?") is None)
}

///|
test "a retired name still answers, and says what to write instead" {
  // A compiled dyncomp bundle carries its view markup as a STRING inside the
  // wasm, and the host parses it at load time. Deleting a spelling would break
  // a bundle nobody can recompile, so the two that `is` and `not` replaced are
  // still rows — just not rows a suggestion ever offers.
  guard! @tutuca.builtin("equals?") is Some(eq)
  assert_eq(eq.arity, 2)
  assert_true(@tutuca.builtin("falsy?") is Some(_))
  assert_true(@tutuca.retired("equals?") is Some(_))
  assert_true(@tutuca.retired("falsy?") is Some(_))
  assert_true(@tutuca.retired("empty?") is None)
  // …and neither is in the vocabulary a "did you mean" ranges over.
  assert_false(@tutuca.builtin_names().contains("equals?"))
  assert_false(@tutuca.builtin_names().contains("falsy?"))
}

///|
test "unknown predicate returns None" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("present? .items", ctx) is None)
  // port extension: the failure is reported on the collected issues, and it
  // now says WHERE — the head token, not the whole attribute.
  assert_true(
    ctx.issues ==
    [
      {
        kind: BadValue,
        role: UnknownPredicate,
        value: "present?",
        span: { start: 0, end_: 8 },
      },
    ],
  )
}

///|
test "arity mismatch returns None" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("empty? .a .b", ctx) is None)
  // port extension: the arity issue carries the predicate as payload. The
  // whole application is what is wrong, so the span runs head-to-last-argument
  // rather than picking one of them to blame.
  assert_true(
    ctx.issues ==
    [
      {
        kind: BadValue,
        role: PredicateArity(name="empty?", want=1),
        value: "empty? .a .b",
        span: { start: 0, end_: 12 },
      },
    ],
  )
}

///|
test "bad predicate arg returns None" {
  // `Foo` is a type name — not allowed in the boolean group used for args.
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("empty? Foo", ctx) is None)
}

///|
test "predicate args accept bind values" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("truthy? @flag", ctx) is Some(App(args~, ..))
  assert_true(args[0] is Bind("flag"))
}

///|
test ". parses to a FieldVal" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text(".count", ctx) is Some(r)
  assert_true(r is Field("count"))
  assert_eq("\{r}", ".count")
}

///|
test "$ parses to a MethodVal" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("$fullName", ctx) is Some(r)
  assert_true(r is Method("fullName"))
  assert_eq("\{r}", "$fullName")
}

///|
test "$' is a string template, not a method" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text("$'hi {.name}'", ctx) is Some(StrTpl(_)))
  assert_true(@tscript.parse_text("$name", ctx) is Some(Method("name")))
}

///|
test "$ works as a conditional-slot value" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("$canSubmit", ctx) is Some(Method(_)))
}

///|
test "$ is rejected in path-bearing slots (@each, <x render>)" {
  // A method result has no addressable path, so it cannot be iterated or
  // rendered as a child — `.field` stays valid there.
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_sequence("$items", ctx) is None)
  assert_true(@tscript.parse_component("$child", ctx) is None)
  assert_true(@tscript.parse_sequence(".items", ctx) is Some(Field(_)))
}

///|
test "$ is a method handler, a bare name is an input handler" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_input_handler("$inc", ctx) is Some(h1)
  assert_true(h1.handler is Method("inc"))
  guard! @tscript.parse_input_handler("dec", ctx) is Some(h2)
  assert_true(h2.handler is HandlerName(name="dec", ns=Receive))
}

///|
test ". cannot be used in handler position" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_input_handler(".inc", ctx) is None)
}

///|
test "$ method handler keeps its args" {
  // JS: EventHandler.parse("$setStr value") — the handler+args shape comes
  // from parse_input_handler, so the port targets it directly.
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_input_handler("$setStr value", ctx) is Some(h)
  assert_true(h.handler is Method("setStr"))
  assert_eq(h.args.length(), 1)
}

///|
test "equals? parses to a two-argument application with a Const string arg" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("equals? .view 'detail'", ctx)
    is Some(App(name~, args~))
  assert_eq(name, "equals?")
  assert_eq(args.length(), 2)
  assert_true(args[0] is Field("view"))
  assert_true(args[1] is Const(lit=LStr("detail"), ..))
}

///|
test "string literal arg preserves interior spaces" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("equals? .name 'John Doe'", ctx)
    is Some(App(args~, ..))
  assert_eq(args.length(), 2)
  assert_true(args[1] is Const(lit=LStr("John Doe"), ..))
}

///|
test "escaped quote in a string literal arg" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("equals? .name 'it\\'s'", ctx)
    is Some(App(args~, ..))
  assert_true(args[1] is Const(lit=LStr("it's"), ..))
}

///|
test "equals? arity mismatch returns None" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("equals? .view", ctx) is None)
}

///|
test "to_string round-trips a quoted literal" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_bool("equals? .view 'detail'", ctx) is Some(r)
  assert_eq("\{r}", "equals? .view 'detail'")
}

///|
test "bare string literal in parse_bool parses as a literal" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_bool("'detail'", ctx) is Some(Const(lit=LStr("detail"), ..)),
  )
}

///|
test "parse_field accepts a field reference" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_field(".color", ctx) is Some(Field(_)))
}

///|
test "parse_field accepts a method reference" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_field("$color", ctx) is Some(Method(_)))
}

///|
test "parse_field accepts a string-literal constant (dynamic alias default)" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_field("'gray'", ctx) is Some(Const(lit=LStr("gray"), ..)),
  )
}

///|
test "parse_field accepts a numeric constant" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_field("42", ctx) is Some(Const(lit=LNum(n), ..))
  assert_eq(n, 42)
}

///|
test "parse_field accepts a .seq[.key] seq-access" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(
    @tscript.parse_field(".sheets[.selId]", ctx)
    is Some(SeqAccess(seq="sheets", key="selId")),
  )
}

///|
test "seq-access to_path_item yields a SeqAccessStep" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_field(".sheets[.selId]", ctx) is Some(r)
  assert_true(
    r.to_path_item()
    is Some(SeqAccessStep(seq_field="sheets", key_field="selId")),
  )
}

///|
test "one-level member read parses where bindings are accepted" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_text("@value.title", ctx) is Some(r)
  assert_true(r is BindMember(name="value", prop="title"))
  assert_eq("\{r}", "@value.title")
  // any binding name, not just `value`; predicate-style `?` members parse too
  assert_true(@tscript.parse_bool("@item.done?", ctx) is Some(BindMember(..)))
}

///|
test "two or more members fail to parse" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text("@value.a.b", ctx) is None)
  assert_true(@tscript.parse_bool("@value.a.b.c", ctx) is None)
}

///|
test "dotted field reads still fail to parse" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text(".a.b", ctx) is None)
  assert_true(@tscript.parse_bool(".a.b", ctx) is None)
}

///|
test "member reads are not addressable: no path item, no path-bearing slots" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_component("@value.child", ctx) is None)
  assert_true(@tscript.parse_sequence("@value.items", ctx) is None)
  guard! @tscript.parse_text("@value.title", ctx) is Some(r)
  assert_true(r.to_path_item() is None)
}

///|
test "handler arg accepts a quoted literal with spaces" {
  // The handler+args case, driven through
  // parse_input_handler.
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_input_handler("showView 'detail mode'", ctx) is Some(h)
  assert_true(h.handler is HandlerName(name="showView", ns=Receive))
  assert_eq(h.args.length(), 1)
  assert_true(h.args[0] is Const(lit=LStr("detail mode"), ..))
}

// -- positions --------------------------------------------------------------

///|
test "a bad argument is blamed on the argument, not on the attribute" {
  // The reason the parser left `core`. Before this the whole value language
  // had no position anywhere in it: `Issue` was `{kind, role, value}`, and
  // `anode` could add only the name of the enclosing TAG. A slot value can now
  // say which of its operands was wrong.
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("empty? Foo", ctx) is None)
  assert_eq(ctx.issues.length(), 1)
  assert_eq(ctx.issues[0].role, BadPredicateArg)
  assert_eq(ctx.issues[0].value, "Foo")
  // `Foo` starts at column 7 of the attribute value.
  assert_eq(ctx.issues[0].span, { start: 7, end_: 10 })
}

///|
test "a handler argument is blamed on the argument that failed" {
  let ctx = @tscript.ParseCtx::new()
  guard! @tscript.parse_input_handler("setLabel value {bad}", ctx) is Some(h)
  // The argument still occupies its position — it becomes the null sentinel,
  // so the arguments after it do not shift — and the issue says where.
  assert_eq(h.args.length(), 2)
  assert_true(h.args[1] is Const(lit=LNull, ..))
  assert_eq(ctx.issues.length(), 1)
  assert_eq(ctx.issues[0].role, BadHandlerArg)
  assert_eq(ctx.issues[0].span, { start: 15, end_: 20 })
}

///|
test "a span indexes the string handed to the parser, untrimmed" {
  // Whoever holds the file rebases it: `@viewfile.Block` carries the offset
  // that turns a block-relative span into a file-relative one.
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("  present? .x", ctx) is None)
  assert_eq(ctx.issues[0].span, { start: 2, end_: 10 })
}

///|
test "a $$name config variable is the host's literal, and it pins" {
  // The mirror of `^name`, and the marking is the difference: a config value
  // is the HOST's string, so the Const it becomes is not from_macro and the
  // template around it stays literal enough to pin a URL origin.
  let ctx = @tscript.ParseCtx::new(config_vars={
    "mediaOrigin": "https://files.hachyderm.io/",
  })
  guard! @tscript.parse_text("$'{$$mediaOrigin}{.avatarPath}'", ctx)
    is Some(StrTpl(parts))
  // Three, not two: the split leaves an empty text part BETWEEN the two
  // placeholders, and only the bookends are trimmed. What matters is that
  // parts[0] is the host's literal, which is what `pinned_prefix` reads.
  assert_eq(parts.length(), 3)
  assert_true(
    parts[0]
    is Some(Const(lit=LStr("https://files.hachyderm.io/"), from_macro=false)),
  )
  assert_true(parts[1] is Some(Const(lit=LStr(""), ..)))
  assert_true(parts[2] is Some(Field("avatarPath")))
  assert_eq(ctx.issues.length(), 0)
}

///|
test "a $$name nothing was bound to is an issue, not a silent empty string" {
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_text("$$mediaOrigin", ctx) is None)
  assert_eq(ctx.issues.length(), 1)
  assert_eq(ctx.issues[0].role, BadConfigVar)
  assert_eq(ctx.issues[0].value, "$$mediaOrigin")
}

///|
test "a config value is substituted, not re-parsed" {
  // `^name` re-tokenizes what it is bound to, because that is a macro
  // argument: source the CALLER wrote. A config value is text the host
  // decided, so it lands as text — a bound value that looks like an
  // expression is that expression's characters, not that expression.
  let ctx = @tscript.ParseCtx::new(config_vars={ "who": ".secret" })
  guard! @tscript.parse_text("$$who", ctx) is Some(v)
  assert_true(v is Const(lit=LStr(".secret"), from_macro=false))
}

///|
test "$ and $$ stay apart" {
  let ctx = @tscript.ParseCtx::new(config_vars={ "total": "9" })
  assert_true(@tscript.parse_text("$total", ctx) is Some(Method("total")))
  guard! @tscript.parse_text("$$total", ctx) is Some(v)
  assert_true(v is Const(lit=LStr("9"), ..))
}

///|
/// The last link: a config template does not merely PARSE to a pinned literal,
/// it evaluates to the url the browser fetches. This is what
/// `<img :src="$'{$$mediaOrigin}{.avatarPath}'">` actually puts in the DOM.
priv struct AvatarStack {
  fields : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Stack for AvatarStack with fn lookup_field_raw(self, name) {
  self.fields.get(name).unwrap_or(Null)
}

///|
test "a config origin template renders the url the host pointed at" {
  let tpl = "$'{$$mediaOrigin}{.avatarPath}'"
  let stack = AvatarStack::{
    fields: { "avatarPath": Str("accounts/avatars/000/111/aa.png") },
  }
  // The same view, the same record, two servers — which is the whole claim.
  for
    pair in [
      (
        "https://files.hachyderm.io/", "https://files.hachyderm.io/accounts/avatars/000/111/aa.png",
      ),
      (
        "https://files.mastodon.social/", "https://files.mastodon.social/accounts/avatars/000/111/aa.png",
      ),
    ] {
    let (origin, want) = pair
    let ctx = @tscript.ParseCtx::new(config_vars={ "mediaOrigin": origin })
    guard! @tscript.parse_text(tpl, ctx) is Some(v)
    guard! v.eval(stack) is Str(got)
    assert_eq(got, want)
  }
}

// -- one language ------------------------------------------------------------

///|
/// The sentence a conditional slot answers with, or "" when it parsed.
fn slot_err(src : String) -> String {
  let ctx = @tscript.ParseCtx::new()
  @tscript.parse_bool(src, ctx) |> ignore
  match ctx.issues.get(0) {
    Some({ role: BadExpression(why~), .. }) => why
    Some(_) => "issue"
    None => ""
  }
}

///|
/// The sentence a BLOCK answers with for the same expression, or "".
fn block_err(src : String) -> String {
  try {
    @tscript.parse_script("pred p { \{src} }") |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "a slot and a block are one grammar, and refuse alike" {
  // The property this whole change exists for. Each source is put through BOTH
  // front ends, and they have to agree — not merely both fail, but fail with
  // the SAME sentence, because there is one grammar and one set of rules about
  // where parentheses go.
  //
  // A case that stops agreeing here is the two languages drifting apart again,
  // and the answer is to lift more of the block's parser rather than to
  // special-case the slot.
  //
  // `^name` and `$$name` are deliberately NOT in this corpus. They parse in
  // both front ends — one grammar — and are refused in only one of them,
  // because the difference is not grammatical: a slot stands in a macro frame
  // with a host attached and a block does not. `block_err` only parses, so it
  // would report the checker's refusal as agreement-by-silence. The two
  // refusals are pinned where they belong, in `tscript/check`.
  for
    src in [
      // the family rules
      "(not .busy) and (.n > 0)", ".a and .b and .c", ".a is 'x'", ".a is not 'x'",
      ".a >= .b", ".published implies .title", "not .busy", "not (empty? .kind)",
      "(len .items) is 1", "len .items is 1", "contains (lower .title) 'x'",
      // …and the refusals, which are the half worth pinning
       ".a and .b or .c", "(not .busy) and .n > 0", ".a < .b < .c", ".a implies .b implies .c",
      ".a + .b * .c",
    ] {
    assert_eq((src, slot_err(src)), (src, block_err(src)))
  }
}

///|
test "a slot refuses what only a body can hold, and names the way out" {
  // `Val` is span-free and flat because it rides inside `Step` and into the
  // checked-in IR modules. The half of `Expr` it cannot hold stops at the
  // lowering — with a sentence, never with silence, which is what the old
  // `bad value 'not' in unknown predicate` failed to give.
  fn says(src : String, needle : String) -> Unit raise {
    let why = slot_err(src)
    assert_true(why.contains(needle))
  }

  says("if .a { .b } else { .c }", "a slot has no `if`")
  says("empty? .a.b", "a slot reads one level")
  says("(len .items) is (-.n)", "a slot has no arithmetic")
}

///|
test "a substituted value is an operand, and keeps the mark that decides an origin" {
  // The regression this covers: unifying the slot with the block's grammar
  // pre-scanned for `^` and `$$` and refused the whole expression, so
  // `@hide="empty? ^label"` — which parsed at 0.28.1, through the old
  // predicate-application path — stopped parsing.
  //
  // A `^name` expansion is required to be exactly ONE token, so splicing it
  // where an operand goes cannot regroup the expression around it. And
  // `from_macro` rides on the `Const` rather than on the shape above it, which
  // is the half that matters: an operator over one does not lose the mark.
  let ctx = @tscript.ParseCtx::new(macro_vars={ "label": "'x'" }, config_vars={
    "origin": "https://files.example/",
  })
  guard! @tscript.parse_bool("empty? ^label", ctx)
    is Some(App(name="empty?", args~))
  assert_eq(args.length(), 1)
  assert_true(args[0] is Const(lit=LStr("x"), from_macro=true))
  // The whole grammar, not just the shape 0.28.1 happened to accept.
  assert_true(
    @tscript.parse_bool("not ^label", ctx) is Some(App(name="not", ..)),
  )
  assert_true(
    @tscript.parse_bool("^label is 'x'", ctx) is Some(App(name="is", ..)),
  )
  assert_true(
    @tscript.parse_bool("(empty? ^label) and (empty? $$origin)", ctx)
    is Some(App(name="and", ..)),
  )
  assert_eq(ctx.issues.length(), 0)
}

///|
test "a host's value nested under an operator is still the host's" {
  // The concern the refusal was written for, pinned rather than avoided: the
  // origin rule reads a Const's own `from_macro`, so nesting cannot launder a
  // caller's string into a host's or the other way round.
  let ctx = @tscript.ParseCtx::new(
    macro_vars={ "u": "'https://evil.example/'" },
    config_vars={ "origin": "https://files.example/" },
  )
  guard! @tscript.parse_bool("$$origin is ^u", ctx) is Some(App(args~, ..))
  assert_true(args[0] is Const(from_macro=false, ..))
  assert_true(args[1] is Const(from_macro=true, ..))
}

///|
test "a `^` nothing is bound to is an issue inside an expression too" {
  // Same role, same span discipline as the single-token path — the resolver is
  // literally the same function.
  let ctx = @tscript.ParseCtx::new()
  assert_true(@tscript.parse_bool("empty? ^label", ctx) is None)
  assert_eq(ctx.issues.length(), 1)
  assert_eq(ctx.issues[0].role, BadMacroVar)
  assert_eq(ctx.issues[0].value, "^label")
  assert_eq(ctx.issues[0].span, { start: 7, end_: 13 })
}
