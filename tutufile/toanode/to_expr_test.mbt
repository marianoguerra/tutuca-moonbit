// The expression translation, checked the only way that means anything: against
// the path it replaces.
//
// The oracle is `print_ex` + `@tscript.parse_text` — shrubbery printed as the
// old notation and read by the parser that has always read it. Where the two
// agree, going direct changed nothing; where they cannot agree, the test says
// so in its own name rather than being quietly absent.
//
// Spans are why `Expr`'s `Eq` ignores them (see `core/expr_spec.mbt`): the
// printed text has different offsets from the file, so the two trees can only
// be compared modulo position. That is exactly what `Eq` here does, and it is
// the reason the comparison is possible at all.

///|
/// Read one group of shrubbery as an `Ex`.
fn read_one_ex(src : String) -> @lower.Ex? {
  let parsed = @shrub.parse(src + "\n") catch { _ => return None }
  guard parsed.root().it is Multi(gs) && gs.length() == 1 else { return None }
  Some(@lower.read_group(gs[0]) catch { _ => return None })
}

///|
/// The direct translation.
fn direct(src : String) -> @tutuca.Expr? {
  let ex = read_one_ex(src)
  guard ex is Some(ex) else { return None }
  Some(
    to_expr(ex, ExCtx::value(), @report.Span::at(0)) catch {
      _ => return None
    },
  )
}

///|
/// The translation the printer path produces, for the same source, read by the
/// parser the slot at `pos` would have used.
///
/// There is a parser per POSITION on the old path — `parse_text` for an
/// attribute value, `parse_bool` for a condition, `parse_sequence` for an
/// `@each` — and each admits a different part of the grammar. That split is why
/// the oracle takes one: `(.a is 'x')` is not a text value and `parse_text`
/// rightly refuses it, so comparing everything against one parser would compare
/// half of it against a refusal.
///
/// Going direct does not need the split. One translation builds the expression
/// and `Expr::admitted_in` asks the position question afterwards, which is the
/// same rule in one place instead of eleven parsers.
fn printed(
  src : String,
  parser : (String, @tscript.ParseCtx) -> @tutuca.Expr?,
) -> @tutuca.Expr? {
  let ex = read_one_ex(src)
  guard ex is Some(ex) else { return None }
  let text = @lower.print_ex(ex) catch { _ => return None }
  parser(text, @tscript.ParseCtx::new())
}

///|
/// The two paths spell an operator differently, and this is the reduction that
/// says they mean the same thing.
///
/// The SLOT parsers read `(.a is 'x')` as an application — the prefix form the
/// old attribute text was written in — while the BLOCK parser reads `a == b` as
/// an `EChain` carrying its family. Both evaluate identically: `eval_chain`
/// (`core/value_eval.mbt`) reduces a chain to exactly this nest of `EApp`
/// before evaluating it, and `Position`'s table gives `EApp`, `EChain` and
/// `EUnary` one kind (`KApp`), so no position tells them apart either.
///
/// Going direct produces the CHAIN, because a body and a slot are one language
/// and one of the two spellings had to go. This function is where the choice is
/// written down rather than assumed.
fn flatten(e : @tutuca.Expr) -> @tutuca.Expr {
  match e {
    EChain(ops~, operands~, span~, ..) => {
      let mut acc = flatten(operands[0])
      for i, op in ops {
        acc = EApp(name=op, args=[acc, flatten(operands[i + 1])], span~)
      }
      acc
    }
    EUnary(op=UNot, operand~, span~) =>
      EApp(name="not", args=[flatten(operand)], span~)
    EApp(name~, args~, span~) => EApp(name~, args=args.map(flatten), span~)
    ETpl(parts~, span~) =>
      ETpl(
        parts=parts.map(p => {
          match p {
            TExpr(v) => TExpr(flatten(v))
            other => other
          }
        }),
        span~,
      )
    EIf(cond~, then_~, else_~, span~) =>
      EIf(cond=flatten(cond), then_=flatten(then_), else_=flatten(else_), span~)
    other => other
  }
}

///|
/// Both paths, as one assertion.
fn agree(
  src : String,
  parser? : (String, @tscript.ParseCtx) -> @tutuca.Expr? = @tscript.parse_text,
) -> Unit raise {
  let a = direct(src)
  let b = printed(src, parser)
  assert_true(b is Some(_))
  @debug.assert_eq(a.map(flatten), b.map(flatten))
}

///|
test "a literal is the same literal either way" {
  agree("42")
  agree("1.5")
  agree("\"text\"")
  agree("true")
  agree("false")
}

///|
test "a property and a dynamic binding" {
  agree("it.count")
  agree("dyn.theme")
}

///|
/// `it.state.count` — the raw field behind a property — is a form the printer
/// path emits and the slot parser then REFUSES: `state.` is a script-block root,
/// so `parse_text` answers None and the attribute silently carries a parse
/// issue instead of a value.
///
/// Going direct there is nothing to refuse. Both spellings name one position,
/// which is what `tscript` itself concludes — `.count` and `state.count` both
/// parse to `PState("count")` in a body — so the view gets the same answer a
/// body has always got.
test "the raw field behind a property, which the printer path could not carry" {
  assert_true(printed("it.state.count", @tscript.parse_text) is None)
  @debug.assert_eq(direct("it.state.count"), Some(@tutuca.Expr::field("count")))
  @debug.assert_eq(direct("it.state.count"), direct("it.count"))
}

///|
/// Conditions go through `parse_bool`, which is the position they stand in:
/// `@show`, `@when`, `@if.<attr>` and a `pred` body all ask a yes/no question.
test "every operator family lands in the family the runtime knows" {
  agree("it.a == \"x\"", parser=@tscript.parse_bool)
  agree("it.a != \"x\"", parser=@tscript.parse_bool)
  agree("it.a && it.b", parser=@tscript.parse_bool)
  agree("it.a || it.b", parser=@tscript.parse_bool)
  agree("!it.open", parser=@tscript.parse_bool)
  agree("(it.n > 0) && it.open", parser=@tscript.parse_bool)
  agree("it.a implies it.b", parser=@tscript.parse_bool)
}

///|
/// Arithmetic is body grammar, not slot grammar: no view position admits a
/// product, so the oracle is the block parser rather than a slot's.
test "arithmetic reaches the same chain the block parser builds" {
  agree("it.qty * it.price", parser=body_parser)
  agree("it.qty + 1", parser=body_parser)
  agree("it.n - 1", parser=body_parser)
}

///|
/// The whole grammar, as a slot-parser-shaped function so the oracle above can
/// take it like any other.
fn body_parser(s : String, _ctx : @tscript.ParseCtx) -> @tutuca.Expr? {
  Some(@tscript.parse_expr_source(s) catch { _ => return None })
}

///|
test "a builtin call reaches the same application" {
  agree("it.items.is_empty()", parser=@tscript.parse_bool)
  agree("it.items.length()", parser=@tscript.parse_bool)
  agree("it.title.lower().contains(\"a\")", parser=@tscript.parse_bool)
  agree("it.n.to_string()", parser=@tscript.parse_bool)
  agree("math.clamp(it.page, 0, 9)", parser=@tscript.parse_bool)
  // nested arithmetic in an argument makes the whole call body grammar
  agree("math.max(0, it.qty - 1)", parser=body_parser)
}

///|
test "a compute with no arguments is named" {
  agree("label()")
}

///|
/// A compute WITH arguments is the second thing the printer path emits and
/// nothing reads. `compute name(args…)` is a declared construct
/// (`skill/tutuca/schema.md`), the printer spells the call `$unfinished .rows`,
/// and no parser in the system accepts that: `$name` always parses as a
/// zero-argument `EMethod`, with nowhere to put an argument.
///
/// The body grammar spells the same call `unfinished .rows` — a bare name
/// applied to arguments, which is `EApp` — so that is what going direct builds.
/// The construct works now; it did not before.
test "a compute with arguments, which the printer path spelled unreadably" {
  assert_true(printed("unfinished(it.rows)", body_parser) is None)
  @debug.assert_eq(
    direct("unfinished(it.rows)").map(flatten),
    body_parser("unfinished .rows", @tscript.ParseCtx::new()).map(flatten),
  )
}

///|
test "`x == none` folds into the shape predicate, both ways" {
  agree("it.child == none", parser=@tscript.parse_bool)
  agree("it.child != none", parser=@tscript.parse_bool)
}

///|
/// An `if` in a VALUE has no spelling on the old path at all — the printer
/// splits it into `@if.<attr>` / `@then` / `@else`, three attributes, because
/// HTML has nowhere to put a conditional value. So there is no text to compare
/// against, and the shape is pinned instead.
test "a conditional value is one expression, which the old notation could not hold" {
  let out = direct("if it.on | \"a\" | \"b\"").unwrap()
  assert_true(out is EIf(_))
}

///|
/// `e.<path>` stands in exactly one position — an `@on` argument — and reaches
/// the old path inside a handler rather than as a value, so `parse_text` refuses
/// it by design (`Position`'s `KEvent` row). Pinned rather than compared.
test "the event path keeps its segments" {
  @debug.assert_eq(
    direct("e.value").unwrap(),
    @tutuca.Expr::event_path(["value"]),
  )
  @debug.assert_eq(
    direct("e.target.value").unwrap(),
    @tutuca.Expr::event_path(["target", "value"]),
  )
}

///|
test "a template's holes and its bookend trim" {
  agree("@str{Hi @(it.name)}")
  agree("@str{@(it.name)}")
  agree("@str{@(it.a) and @(it.b)}")
}

///|
/// A bare name is where the two paths CANNOT agree, and the difference is the
/// point of the change.
///
/// `print_ex` prints a bare name as itself, because it does not know the
/// position — `bound` puts the `@` on at the last moment, inside the view
/// printer, so the expression printer never sees it. Going direct, position is
/// a parameter (`NamePos`), so the same name reads as a binding in a value slot
/// and as a handler name in a handler slot with nothing spelled in between.
test "a bare name reads by position, which the printer could not do" {
  let ex = read_one_ex("item").unwrap()
  let as_value = to_expr(ex, ExCtx::value(), @report.Span::at(0))
  let as_handler = to_expr(ex, ExCtx::value().as_handler(), @report.Span::at(0))
  @debug.assert_eq(as_value.as_bind(), Some("item"))
  @debug.assert_eq(as_handler, @tutuca.Expr::name("item"))
}

///|
test "a loop's binder becomes the binding the renderer answers with" {
  let ex = read_one_ex("row.title").unwrap()
  let ctx = ExCtx::value().with_bind("row", "value")
  let out = to_expr(ex, ctx, @report.Span::at(0))
  @debug.assert_eq(out.as_bind_member(), Some(("value", "title")))
}

///|
test "the span is the one it was read with, not an offset into printed text" {
  let ex = read_one_ex("it.count").unwrap()
  let out = to_expr(ex, ExCtx::value(), @report.Span::of_range(12, 20))
  @debug.assert_eq(out.span(), { start: 12, end_: 20, })
}
