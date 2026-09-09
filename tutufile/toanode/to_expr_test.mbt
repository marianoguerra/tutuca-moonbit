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
fn read_one_ex(src : String) -> @sh.Ex? {
  let parsed = @shrub.parse(src + "\n") catch { _ => return None }
  guard parsed.root().it is Multi(gs) && gs.length() == 1 else { return None }
  Some(@sh.read_group(gs[0]) catch { _ => return None })
}

///|
/// The direct translation.
fn direct(src : String) -> @tutuca.Expr? {
  let ex = read_one_ex(src)
  guard ex is Some(ex) else { return None }
  Some(
    @sh.to_expr(ex, @sh.ExCtx::value(), @report.Span::at(0)) catch {
      _ => return None
    },
  )
}

///|
/// The expression reads.
///
/// This was a DIFFERENTIAL assertion: the same source translated directly and
/// through the printer into each of the eleven slot parsers, reduced to a
/// common shape and compared. That is what made the printer safe to delete,
/// and it went with it. What is left is the corpus — every shape the
/// expression language has — and the claim that the reader answers one for
/// each of them.
///
/// The reduction it needed is worth recording, because it is the one place the
/// two spellings genuinely differed. The SLOT parsers read `(.a is 'x')` as an
/// application, the prefix form the old attribute text was written in; the
/// BLOCK parser reads `a == b` as an `EChain` carrying its family. Both
/// evaluate identically — `eval_chain` reduces a chain to exactly that nest of
/// `EApp` before evaluating it, and `Position`'s table gives `EApp`, `EChain`
/// and `EUnary` one kind — so no position told them apart either. Going direct
/// produces the CHAIN, because a body and a slot are one language and one of
/// the two spellings had to go.
fn agree(src : String) -> Unit raise {
  assert_true(direct(src) is Some(_), msg=src)
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
/// `it.state.count` — the raw field behind a property. The printer path emitted
/// a form the slot parser then REFUSED: `state.` is a script-block root, so
/// `parse_text` answered None and the attribute silently carried a parse issue
/// instead of a value.
///
/// There is nothing to refuse now. Both spellings name one position,
/// which is what `tscript` itself concludes — `.count` and `state.count` both
/// parse to `PState("count")` in a body — so the view gets the same answer a
/// body has always got.
test "the raw field behind a property, which the printer could not carry" {
  @debug.assert_eq(direct("it.state.count"), Some(@tutuca.Expr::field("count")))
  @debug.assert_eq(direct("it.state.count"), direct("it.count"))
}

///|
/// Conditions go through `parse_bool`, which is the position they stand in:
/// `@show`, `@when`, `@if.<attr>` and a `pred` body all ask a yes/no question.
test "every operator family lands in the family the runtime knows" {
  agree("it.a == \"x\"")
  agree("it.a != \"x\"")
  agree("it.a && it.b")
  agree("it.a || it.b")
  agree("!it.open")
  agree("(it.n > 0) && it.open")
  agree("it.a implies it.b")
}

///|
/// Arithmetic is body grammar, not slot grammar: no view position admits a
/// product, so the oracle is the block parser rather than a slot's.
test "arithmetic reaches the same chain the block parser builds" {
  agree("it.qty * it.price")
  agree("it.qty + 1")
  agree("it.n - 1")
}

///|
test "a builtin call reaches the same application" {
  agree("it.items.is_empty()")
  agree("it.items.length()")
  agree("it.title.lower().contains(\"a\")")
  agree("it.n.to_string()")
  agree("math.clamp(it.page, 0, 9)")
  // nested arithmetic in an argument makes the whole call body grammar
  agree("math.max(0, it.qty - 1)")
}

///|
test "a compute with no arguments is named" {
  agree("label()")
}

///|
/// A compute WITH arguments, which had no readable spelling until the printer
/// stopped writing one.
///
/// `compute name(args…)` is a declared construct, and the printer spelled the
/// call `$unfinished .rows` — which parses nowhere, because `$` always takes a
/// bare name and has nowhere to put an argument. The application form
/// `(unfinished .rows)` is what a body reads, and it is what both paths produce
/// now.
test "a compute with arguments is an application on both paths" {
  agree("unfinished(it.rows)")
}

///|
test "`x == none` folds into the shape predicate, both ways" {
  agree("it.child == none")
  agree("it.child != none")
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
  let as_value = @sh.to_expr(ex, @sh.ExCtx::value(), @report.Span::at(0))
  let as_handler = @sh.to_expr(
    ex,
    @sh.ExCtx::value().as_handler(),
    @report.Span::at(0),
  )
  @debug.assert_eq(as_value.as_bind(), Some("item"))
  @debug.assert_eq(as_handler, @tutuca.Expr::name("item"))
}

///|
test "a loop's binder becomes the binding the renderer answers with" {
  let ex = read_one_ex("row.title").unwrap()
  let ctx = @sh.ExCtx::value().with_bind("row", "value")
  let out = @sh.to_expr(ex, ctx, @report.Span::at(0))
  @debug.assert_eq(out.as_bind_member(), Some(("value", "title")))
}

///|
test "the span is the one it was read with, not an offset into printed text" {
  let ex = read_one_ex("it.count").unwrap()
  let out = @sh.to_expr(ex, @sh.ExCtx::value(), @report.Span::of_range(12, 20))
  @debug.assert_eq(out.span(), { start: 12, end_: 20, })
}

///|
/// A string template, and the one shape inside it that reads as something else.
test "a template's holes and its text" {
  agree("@str{plain}")
  agree("@str{x @(it.name) y}")
  agree("@str{a (b) c}")
  // Parentheses AROUND a hole are text, because nothing precedes them.
  agree("@str{(@(it.name))}")
}

///|
/// A `(` immediately after a hole, which is the one place a template reads a
/// call where the author meant text.
///
/// At-notation reads `@(x)(y)` as a command and its argument list, so the two
/// arrive as ONE group holding two `Parens` — and a template has no call of
/// that shape, since a hole is a value and a value is not called.
///
/// It used to fall through to the ordinary expression reader, which met the
/// `Brackets` a template is made of and reported "a list or map literal has no
/// place in an expression" — a message about a construct that was not in the
/// file, with no span to contradict it. Reported from a downstream repo, where
/// it cost real time: `@str{@(it.name)(@(it.params))}` is how a function
/// signature is spelled, so writing the obvious thing reached it.
test "a `(` right after a hole is refused by name" {
  let parsed = @shrub.parse("@str{@(it.name)(x)}\n")
  guard parsed.root().it is Multi(gs) && gs.length() == 1 else {
    fail("not one group")
  }
  let msg = match
    (Ok(@sh.read_group(gs[0])) catch { ExError(message~, ..) => Err(message) }) {
    Ok(_) => "read"
    Err(m) => m
  }
  inspect(
    msg,
    content="a `(` right after a hole is read as a call, not as text",
  )
}
