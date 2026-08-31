// The block language's grammar, pinned by ROUND TRIP.
//
// Every case below parses a form from the design's §2.3, prints it back, and
// parses the printed text again — so a case asserts three things at once: that
// the form parses, that the printer is total over what the parser builds, and
// that printing is a normal form. A grammar checked only by hand-written
// expectations drifts toward "whatever the parser happened to allow"; this
// cannot, because the second parse has to agree with the first.
//
// The printer is canonical rather than faithful: it parenthesizes wherever the
// grammar REQUIRES it, not wherever the author did. So `src` below is what the
// form normalizes to, which is usually what was written and is occasionally
// tidier.

///|
/// Parse one declaration, print it, parse the printed text, and require the
/// two ASTs to agree. Answers the printed source, which is what each case
/// asserts against.
fn trip(source : String) -> String raise {
  let once = @tscript.parse_script(source)
  assert_eq(once.length(), 1)
  let printed = once[0].to_source()
  let twice = @tscript.parse_script(printed)
  assert_eq(twice.length(), 1)
  // Not the ASTs directly: they carry spans, and the second parse's spans
  // index the PRINTED text. Their sources agreeing is the fixed point that
  // matters — print(parse(print(x))) == print(x).
  assert_eq(twice[0].to_source(), printed)
  printed
}

///|
/// The route of the first statement of the first declaration.
fn route_of(source : String) -> Array[@tutuca.Leg] raise {
  guard @tscript.parse_script(source)[0].body is Stmts(sts) else {
    fail("not a statement body")
  }
  guard sts[0] is SEffect(route~, ..) else { fail("not an effect") }
  route
}

///|
/// The message a block fails with, or "" when it parses.
fn script_err(source : String) -> String {
  try {
    @tscript.parse_script(source) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

// -- declarations -----------------------------------------------------------

///|
test "the seven declaration kinds" {
  assert_eq(
    trip("receive reset { .count = 0 }"),
    "receive reset {\n  .count = 0\n}",
  )
  assert_eq(
    trip("receive resetTo(n) { .count = n }"),
    "receive resetTo(n) {\n  .count = n\n}",
  )
  assert_eq(
    trip("intent rowPicked(i) { .sel = i }"),
    "intent rowPicked(i) {\n  .sel = i\n}",
  )
  assert_eq(trip("compute label { .name }"), "compute label { .name }")
  assert_eq(
    trip("pred unfinished { not @value.completed }"),
    "pred unfinished { not @value.completed }",
  )
  assert_eq(
    trip("invariant conserved { (.here + .there) is .total }"),
    "invariant conserved { (.here + .there) is .total }",
  )
  assert_eq(
    trip("enrich rowInfo { @cls = 'row' }"),
    "enrich rowInfo {\n  @cls = 'row'\n}",
  )
  assert_eq(
    trip("enrichScope header { @title = .name }"),
    "enrichScope header {\n  @title = .name\n}",
  )
}

///|
test "state dot names the raw state root" {
  assert_eq(trip("get label { state.name }"), "get label { .name }")
}

///|
test "a doc comment attaches to the declaration under it" {
  assert_eq(
    trip(
      (
        #|/// Move the counter to n.
        #|/// Remembering where it landed.
        #|receive resetTo(n) { .count = n }
      ),
    ),
    (
      #|/// Move the counter to n.
      #|/// Remembering where it landed.
      #|receive resetTo(n) {
      #|  .count = n
      #|}
    ),
  )
}

///|
test "`when` is not a declaration kind" {
  // It is the same construct as a boolean `compute` — a name, one expression,
  // no statements — so a `pred` used in a `@when` slot says everything a
  // `when` could. The kind list is nine rather than ten.
  assert_eq(
    script_err("when unfinished { not @value.completed }"),
    "`when` is not a declaration kind — expected receive, intent, compute, pred, invariant, enrich or enrichScope",
  )
}

///|
test "a name is answered once per bucket" {
  assert_eq(
    script_err("receive add(d) { .count += d }\nreceive add(e) { .count -= e }"),
    "`add` is declared twice in this bucket; a name is answered once, by exact match, with nothing behind it",
  )
  // Different buckets are different questions, so the same name is fine — an
  // addressed `reset` and a routed one are two things a component can answer.
  assert_eq(
    script_err("receive reset { .count = 0 }\nintent reset { .count = 0 }"),
    "",
  )
}

// -- statements -------------------------------------------------------------

///|
test "assignment, compound assignment and nested places" {
  assert_eq(
    trip(
      (
        #|receive toggleLabel(key) {
        #|  .labels[key].done = not .labels[key].done
        #|  .count += 1
        #|  .count -= 1
        #|}
      ),
    ),
    (
      #|receive toggleLabel(key) {
      #|  .labels[key].done = not .labels[key].done
      #|  .count += 1
      #|  .count -= 1
      #|}
    ),
  )
}

///|
test "statements separate on a newline or a semicolon, identically" {
  let a = trip("receive go { .a = 1; .b = 2 }")
  let b = trip("receive go {\n  .a = 1\n  .b = 2\n}")
  assert_eq(a, b)
}

///|
test "the collection methods are receiver-first" {
  assert_eq(
    trip(
      (
        #|receive edit(i, v) {
        #|  .items.push v
        #|  .items.insertAt i v
        #|  .items.setAt i v
        #|  .items.deleteAt i
        #|  .tags.add v
        #|  .tags.remove v
        #|  .tags.toggle v
        #|}
      ),
    ),
    (
      #|receive edit(i, v) {
      #|  .items.push v
      #|  .items.insertAt i v
      #|  .items.setAt i v
      #|  .items.deleteAt i
      #|  .tags.add v
      #|  .tags.remove v
      #|  .tags.toggle v
      #|}
    ),
  )
}

///|
test "`new` builds a value into the target, and the target is a place" {
  assert_eq(
    trip(
      (
        #|receive init {
        #|  new Label
        #|  @cur.text = 'Buy milk'
        #|  @cur.done = false
        #|  .labels.push @cur
        #|  new Array[String]
        #|  @cur.push 'a'
        #|  .grid.push @cur
        #|}
      ),
    ),
    (
      #|receive init {
      #|  new Label
      #|  @cur.text = 'Buy milk'
      #|  @cur.done = false
      #|  .labels.push @cur
      #|  new Array[String]
      #|  @cur.push 'a'
      #|  .grid.push @cur
      #|}
    ),
  )
}

///|
test "a type reference prints the way the state block spells it" {
  assert_eq(
    trip("receive x { new Map[String, Int] }"),
    "receive x {\n  new Map[String, Int]\n}",
  )
  assert_eq(
    trip("receive x { new Array[Array[String]] }"),
    "receive x {\n  new Array[Array[String]]\n}",
  )
  // `Array [String]` is a name and then something else, exactly as a detached
  // `[` is everywhere else in the language.
  assert_eq(
    script_err("receive x { new Array [String] }"),
    "expected the end of the statement — a newline or a `;`, found `[`",
  )
  assert_eq(
    script_err("receive x { new }"),
    "expected a type name after `new`, found `}`",
  )
}

///|
test "a method arity that does not match is refused" {
  assert_eq(
    script_err("receive x { .items.push }"),
    "expected 1 for `push`, found 0 argument(s)",
  )
  assert_eq(
    script_err("receive x { .items.frobnicate 1 }"),
    "expected a collection method: push, insertAt, setAt, deleteAt/removeAt, clear, add, remove/delete, set or toggle, found `frobnicate`",
  )
}

///|
test "the effects" {
  assert_eq(
    trip(
      (
        #|receive save {
        #|  send 'flash' .msg
        #|  intent dyn 'rowPicked' @key
        #|  intent lex 'loadData'
        #|  stop
        #|}
      ),
    ),
    (
      #|receive save {
      #|  send 'flash' .msg
      #|  intent dyn 'rowPicked' @key
      #|  intent lex 'loadData'
      #|  stop
      #|}
    ),
  )
}

///|
test "if / else as a statement, and without an else" {
  assert_eq(
    trip("receive publish { if hasTitle { .published = true } }"),
    (
      #|receive publish {
      #|  if hasTitle {
      #|    .published = true
      #|  }
      #|}
    ),
  )
  assert_eq(
    trip("receive t { if .ok { .n = 1 } else { .n = 2 } }"),
    (
      #|receive t {
      #|  if .ok {
      #|    .n = 1
      #|  } else {
      #|    .n = 2
      #|  }
      #|}
    ),
  )
}

// -- expressions ------------------------------------------------------------

///|
test "the atoms are the view's atoms" {
  assert_eq(trip("compute a { .field }"), "compute a { .field }")
  assert_eq(trip("compute a { @bind }"), "compute a { @bind }")
  assert_eq(trip("compute a { @value.member }"), "compute a { @value.member }")
  assert_eq(trip("compute a { $method }"), "compute a { $method }")
  assert_eq(trip("compute a { *dyn }"), "compute a { *dyn }")
  // The two SUBSTITUTED sigils. A block may not hold either — `tscript/check`
  // refuses them by name — but the GRAMMAR does, because a conditional slot is
  // written in this language and a slot stands in a macro frame. The printer
  // has to be total over what parses, or the round trip stops pinning it.
  assert_eq(trip("compute a { ^macro }"), "compute a { ^macro }")
  assert_eq(trip("compute a { $$config }"), "compute a { $$config }")
  assert_eq(trip("pred p { empty? ^label }"), "pred p { empty? ^label }")
  assert_eq(trip("pred p { $$origin is 'x' }"), "pred p { $$origin is 'x' }")
  assert_eq(trip("compute a { 'text' }"), "compute a { 'text' }")
  assert_eq(trip("compute a { 42 }"), "compute a { 42 }")
  assert_eq(trip("compute a { 2.5 }"), "compute a { 2.5 }")
  assert_eq(trip("compute a { true }"), "compute a { true }")
  assert_eq(trip("compute a { false }"), "compute a { false }")
  assert_eq(trip("compute a { null }"), "compute a { null }")
}

///|
test "a string template is the same form a slot writes" {
  assert_eq(
    trip("compute label { $'n={.count}' }"),
    "compute label { $'n={.count}' }",
  )
  assert_eq(
    trip("compute label { $'{.a} and {.b}' }"),
    "compute label { $'{.a} and {.b}' }",
  )
  // An interpolation is a whole expression, not just a name.
  assert_eq(
    trip("compute label { $'total {(.a + .b)}' }"),
    "compute label { $'total {.a + .b}' }",
  )
}

///|
test "nested reads past what a slot can spell" {
  assert_eq(
    trip("compute note { .rows[.sel].meta.note }"),
    "compute note { .rows[.sel].meta.note }",
  )
  assert_eq(trip("compute x { @value.a.b }"), "compute x { @value.a.b }")
}

///|
test "application is juxtaposition, and an argument that is one takes parens" {
  assert_eq(trip("compute n { len .items }"), "compute n { len .items }")
  assert_eq(
    trip("compute p { clamp .page 0 (.n - 1) }"),
    "compute p { clamp .page 0 (.n - 1) }",
  )
  assert_eq(
    trip("compute q { contains (lower .name) 'x' }"),
    "compute q { contains (lower .name) 'x' }",
  )
  // A name with nothing after it is a name, not a call of arity zero — which
  // is what lets `.label = value` mean the parameter.
  assert_eq(
    trip("receive set(value) { .label = value }"),
    "receive set(value) {\n  .label = value\n}",
  )
}

///|
test "the four operator families chain within themselves" {
  assert_eq(trip("pred p { .a and .b and .c }"), "pred p { .a and .b and .c }")
  assert_eq(trip("compute n { .a + .b - .c }"), "compute n { .a + .b - .c }")
  assert_eq(trip("compute n { .a * .b / .c }"), "compute n { .a * .b / .c }")
  assert_eq(trip("compute n { .a mod .b }"), "compute n { .a mod .b }")
  assert_eq(trip("pred p { .a is 'x' }"), "pred p { .a is 'x' }")
  assert_eq(trip("pred p { .a is not 'x' }"), "pred p { .a is not 'x' }")
  assert_eq(trip("pred p { .a >= .b }"), "pred p { .a >= .b }")
  assert_eq(
    trip("pred p { .published implies .title }"),
    "pred p { .published implies .title }",
  )
}

///|
test "mixing families in one chain is refused, and the message says why" {
  assert_eq(
    script_err("compute n { .a + .b * .c }"),
    "a multiplicative operator cannot join a additive chain without parentheses — write `(a additive b) …` to say which grouping you mean",
  )
  assert_eq(script_err("pred p { .a and .b or .c }"), "")
  assert_eq(
    script_err("pred p { (not .busy) and .n > 0 }"),
    "a comparison operator cannot join a logical chain without parentheses — write `(a logical b) …` to say which grouping you mean",
  )
  // …and the parenthesized form is what it is asking for.
  assert_eq(
    trip("pred p { (not .busy) and (.n > 0) }"),
    "pred p { (not .busy) and (.n > 0) }",
  )
}

///|
test "comparison and implication take exactly two operands" {
  assert_eq(
    script_err("pred p { .a < .b < .c }"),
    "`<` takes exactly two operands, so a chain of them has no meaning — parenthesize the pair you mean",
  )
  assert_eq(
    script_err("pred p { .a implies .b implies .c }"),
    "`implies` takes exactly two operands, so a chain of them has no meaning — parenthesize the pair you mean",
  )
}

///|
test "unary not and negation" {
  assert_eq(trip("pred p { not .busy }"), "pred p { not .busy }")
  assert_eq(trip("compute n { -.count }"), "compute n { -.count }")
  // `f - 1` is a subtraction, not `f` applied to `-1`: unary minus is not an
  // argument start, so an argument that wants one takes parentheses.
  assert_eq(trip("compute n { .a - 1 }"), "compute n { .a - 1 }")
  assert_eq(
    trip("compute n { clamp .a (-1) 5 }"),
    "compute n { clamp .a (-1) 5 }",
  )
}

///|
test "if in a value position needs both arms" {
  assert_eq(
    trip("compute cls { if .ok { 'good' } else { 'bad' } }"),
    "compute cls { if .ok { 'good' } else { 'bad' } }",
  )
  assert_eq(
    script_err("compute cls { if .ok { 'good' } }"),
    "expected `else` — an `if` in a value position has to have a value either way, found `}`",
  )
}

// -- places -----------------------------------------------------------------

///|
test "& reifies a position, and only where sendAt takes one" {
  assert_eq(
    trip("receive save { sendAt &.status 'flash' 'Saved' }"),
    "receive save {\n  sendAt &.status 'flash' 'Saved'\n}",
  )
  assert_eq(
    trip("receive pick(k) { sendAt &.rows[k] 'select' }"),
    "receive pick(k) {\n  sendAt &.rows[k] 'select'\n}",
  )
  // Anywhere else it is refused, because a place is not a value.
  assert_eq(
    script_err("receive x { .a = &.rows[0] }"),
    "`&` names a POSITION and is legal in exactly one place: the first argument of `sendAt`",
  )
  assert_eq(
    script_err("receive x { send 'flash' &.status }"),
    "`&` names a POSITION and is legal in exactly one place: the first argument of `sendAt`",
  )
}

///|
test "a place the runtime Path cannot express is refused" {
  // A step is field-then-key, so two keys in a row have no step. Only `&`
  // places are constrained: a plain read is rebuilt by the backend and never
  // becomes a `Path` at all.
  assert_eq(
    script_err("receive x { sendAt &.a[0][1] 'go' }"),
    "a path step is a field and then a key, so two keys in a row have no step — write `.a[0].b[1]`",
  )
  assert_eq(script_err("receive x { sendAt &.a[0].b[1] 'go' }"), "")
  assert_eq(script_err("compute x { .a[0][1] }"), "")
}

// -- lexical ----------------------------------------------------------------

///|
test "comments vanish and doc comments do not" {
  assert_eq(
    trip(
      (
        #|// an ordinary comment
        #|receive reset { .count = 0 } // and a trailing one
      ),
    ),
    "receive reset {\n  .count = 0\n}",
  )
}

///|
test "a newline inside brackets does not end a statement" {
  // Which is what lets a long argument list wrap. Inside `{` a newline DOES
  // separate, because that is what it is there for.
  assert_eq(
    trip(
      (
        #|receive p {
        #|  .page = clamp .page 0 (
        #|    .n - 1
        #|  )
        #|}
      ),
    ),
    "receive p {\n  .page = clamp .page 0 (.n - 1)\n}",
  )
}

///|
test "an identifier may end in ? so a predicate name is one token" {
  assert_eq(trip("pred p { empty? .items }"), "pred p { empty? .items }")
  assert_eq(trip("pred ready? { .n > 0 }"), "pred ready? { .n > 0 }")
}

///|
test "a syntax error names its column" {
  // The whole reason the block is a `<script>` ours rather than a WIT one:
  // it is sliced out of the source with its offset intact, so every failure
  // in it has a real position from the first commit.
  let e = try {
    @tscript.parse_script("receive add(d) { .count += }") |> ignore
    @tscript.no_span
  } catch {
    err => err.span()
  }
  assert_eq(e, { start: 27, end_: 28, })
}

///|
test "a literal with an escape round-trips through the printer" {
  // The printer writes `\n` rather than the newline itself, so a declaration
  // whose seed carries a paragraph stays one line long — and reparses to the
  // same string either way.
  assert_eq(trip("compute v { 'a\\nb' }"), "compute v { 'a\\nb' }")
  assert_eq(trip("compute v { 'a\nb' }"), "compute v { 'a\\nb' }")
  assert_eq(trip("compute v { 'it\\'s' }"), "compute v { 'it\\'s' }")
}

///|
test "a path into an argument, and the attachment that tells it from application" {
  // The one thing that separates the two is the space, and it is the rule the
  // language already runs on: `min .a .b` is two arguments and `min .a.b` is
  // one place (`pre_space` in script_lex.mbt). A parameter is the one kind of
  // name that can never be applied, so nothing else could be meant.
  assert_eq(
    trip("receive pick(f) { .name = f.name }"),
    "receive pick(f) {\n  .name = f.name\n}",
  )
  assert_eq(
    trip("receive pick(f) { .name = f.meta.name }"),
    "receive pick(f) {\n  .name = f.meta.name\n}",
  )
  assert_eq(
    trip("receive at(row) { .n = row[0] }"),
    "receive at(row) {\n  .n = row[0]\n}",
  )
  assert_eq(
    trip("receive at(row, k) { .n = row[k].size }"),
    "receive at(row, k) {\n  .n = row[k].size\n}",
  )
  // Detached, it is what it always was: an application of two arguments.
  assert_eq(
    trip("compute c(f) { contains f .query }"),
    "compute c(f) { contains f .query }",
  )
  // ...and an argument's path binds tighter than the application around it.
  assert_eq(
    trip("compute c(f) { len f.items }"),
    "compute c(f) { len f.items }",
  )
}

// -- contracts --------------------------------------------------------------

///|
test "a contract sits between the name and the body" {
  assert_eq(
    trip("receive push requires canPush { .here -= 1 }"),
    "receive push requires canPush {\n  .here -= 1\n}",
  )
  assert_eq(
    trip("receive push ensures moved { .here -= 1 }"),
    "receive push ensures moved {\n  .here -= 1\n}",
  )
  // Both, and with parameters, which is where the clause has to be told apart
  // from a body: what follows a name is `(`, `{`, or a clause word.
  assert_eq(
    trip("receive setTo(n) requires open ensures small { .count = n }"),
    "receive setTo(n) requires open ensures small {\n  .count = n\n}",
  )
  // Written in the other order, printed in the order they happen. Canonical
  // rather than faithful, exactly as the parentheses are.
  assert_eq(
    trip("receive push ensures moved requires canPush { .here -= 1 }"),
    "receive push requires canPush ensures moved {\n  .here -= 1\n}",
  )
}

///|
test "a contract attaches to a transition and to nothing else" {
  // An `enrich` writes bindings rather than state, so there is no transition
  // for a rule to be about — and a `compute` is a value, not a moment.
  assert_eq(
    script_err("enrich rowInfo requires ok { @cls = 'row' }"),
    "expected a contract on a transition — `on`, `receive`, `bubble` or `response`, found `requires` on `enrich`",
  )
  assert_eq(
    script_err("invariant conserved requires ok { .a is .b }"),
    "expected a contract on a transition — `on`, `receive`, `bubble` or `response`, found `requires` on `invariant`",
  )
}

///|
test "one clause of each kind, and two rules become one by being named" {
  assert_eq(
    script_err("receive push requires canPush requires notBusy { .here -= 1 }"),
    "expected one `requires` — two rules become one by naming their `and` in a `pred`, found a second `requires`",
  )
  assert_eq(
    script_err("receive push ensures a ensures b { .here -= 1 }"),
    "expected one `ensures` — two rules become one by naming their `and` in a `pred`, found a second `ensures`",
  )
  // The clause takes a NAME and not an expression: a rule spelled inline is an
  // `if` with a second spelling, and the point of a contract is the name.
  assert_eq(
    script_err("receive push requires (.here > 0) { .here -= 1 }"),
    "expected the `pred` `requires` names, found `(`",
  )
}

// -- formats ----------------------------------------------------------------

///|
test "a format sits in the same slot a contract does, and prints on its own line" {
  // Canonical is the multi-line form: a sentence is long, and the body under
  // it is the thing being read.
  assert_eq(
    trip("pred hasTitle format $'no title' { .title is not '' }"),
    "pred hasTitle\n  format $'no title' { .title is not '' }",
  )
  // Written across three lines, which is the spelling the design shows, and
  // the same declaration.
  let multi =
    #|pred publishedNeedsTitle
    #|  format $'Cannot publish "{.slug}": the title is empty.'
    #|{ .published implies (nonBlank .title) }
  assert_eq(
    trip(multi),
    "pred publishedNeedsTitle\n  format $'Cannot publish \"{.slug}\": the title is empty.' { .published implies (nonBlank .title) }",
  )
  // An `invariant` is a `pred` with a role, so it takes one too.
  assert_eq(
    trip("invariant conserved format $'{.here} + {.there}' { .here is .there }"),
    "invariant conserved\n  format $'{.here} + {.there}' { .here is .there }",
  )
  // A plain string is a sentence with nothing to interpolate.
  assert_eq(
    trip("pred ok format 'nothing doing' { .a }"),
    "pred ok\n  format 'nothing doing' { .a }",
  )
}

///|
test "a format attaches to a rule and to nothing else" {
  // A sentence describes a FALSE answer, so it needs the answer to be declared
  // a yes or a no. A `compute` that might answer the string "ok" has no false
  // case to describe, and a transition is not the thing that is true or false.
  assert_eq(
    script_err("receive push format $'nope' { .here -= 1 }"),
    "expected a `format` on a rule — `pred` or `invariant`, the two kinds whose answer is declared to be a yes or a no, found `format` on `receive`",
  )
  assert_eq(
    script_err("compute label format $'nope' { .name }"),
    "expected a `format` on a rule — `pred` or `invariant`, the two kinds whose answer is declared to be a yes or a no, found `format` on `compute`",
  )
  assert_eq(
    script_err("pred ok format 'a' format 'b' { .a }"),
    "expected one `format` — a rule says one thing about the failure it describes, found a second `format`",
  )
}

// -- v2: the intent declaration, the four new effects, and the leg words -----

///|
test "the intent declaration round-trips" {
  assert_eq(
    trip("intent saveDraft(text) { reply .count }"),
    "intent saveDraft(text) {\n  reply .count\n}",
  )
  // It is a transition, so it takes contracts like the other four.
  assert_eq(
    trip("intent saveDraft(text) requires hasRoom { .count += 1 }"),
    "intent saveDraft(text) requires hasRoom {\n  .count += 1\n}",
  )
}

///|
test "reply, fail and stop are one-word answers" {
  assert_eq(trip("intent go { reply 1 }"), "intent go {\n  reply 1\n}")
  assert_eq(
    trip("intent go { fail 'disk full' }"),
    "intent go {\n  fail 'disk full'\n}",
  )
  assert_eq(trip("intent go { stop }"), "intent go {\n  stop\n}")
}

///|
test "leg words are written between the verb and the arguments" {
  assert_eq(
    trip("receive go { intent 'saveDraft' .name }"),
    "receive go {\n  intent 'saveDraft' .name\n}",
  )
  assert_eq(
    trip("receive go(k) { intent dyn 'picked' k }"),
    "receive go(k) {\n  intent dyn 'picked' k\n}",
  )
  assert_eq(
    trip("receive go { intent lex 'loadRows' }"),
    "receive go {\n  intent lex 'loadRows'\n}",
  )
  assert_eq(
    trip("receive go { intent lex dyn 'saveDraft' }"),
    "receive go {\n  intent lex dyn 'saveDraft'\n}",
  )
}

///|
test "forward takes leg words, arguments, both or neither" {
  assert_eq(
    trip("receive saveDraft(t) { forward }"),
    "receive saveDraft(t) {\n  forward\n}",
  )
  assert_eq(
    trip("receive saveDraft(t) { forward dyn }"),
    "receive saveDraft(t) {\n  forward dyn\n}",
  )
  assert_eq(
    trip("receive saveDraft(t) { forward lex dyn }"),
    "receive saveDraft(t) {\n  forward lex dyn\n}",
  )
  assert_eq(
    trip("receive saveDraft(t) { forward .enriched }"),
    "receive saveDraft(t) {\n  forward .enriched\n}",
  )
  assert_eq(
    trip("receive saveDraft(t) { forward dyn .enriched }"),
    "receive saveDraft(t) {\n  forward dyn .enriched\n}",
  )
}

///|
test "an empty route prints nothing, so the default stays where it is written" {
  // A bare `intent 'save'` records NO legs, not `[Dyn, Lex]`. The default lives
  // in `@tutuca.IntentOpts::new`, and a parser that resolved it here would be a
  // second place for it to live and a second place for it to drift.
  guard route_of("receive go { intent 'save' }") is [] else {
    fail("a bare intent should record no legs")
  }
  guard route_of("receive go { intent dyn lex 'save' }") is [Dyn, Lex] else {
    fail("the legs written are the legs recorded")
  }
}

// -- the collision: `dyn` and `lex` are contextual ---------------------------
//
// The lexer hands them over as plain identifiers, so only the two positions
// that ask about legs ever treat them as words. Everywhere else they are names.

///|
test "a pred may be called dyn, and a parameter may be called lex" {
  assert_eq(trip("pred dyn { .count > 0 }"), "pred dyn { .count > 0 }")
  assert_eq(
    trip("receive go(lex) { .name = lex }"),
    "receive go(lex) {\n  .name = lex\n}",
  )
  assert_eq(
    trip("receive go(dyn, lex) { .name = dyn }"),
    "receive go(dyn, lex) {\n  .name = dyn\n}",
  )
}

///|
test "a handler may be called dyn, and a contract may name a pred called lex" {
  assert_eq(
    trip("receive dyn { .count = 1 }"),
    "receive dyn {\n  .count = 1\n}",
  )
  assert_eq(
    trip("intent go requires lex { .count = 1 }"),
    "intent go requires lex {\n  .count = 1\n}",
  )
}

///|
test "a leg word is only a leg word before an argument list" {
  // `send` does not take a route, so `dyn` after it is an ordinary name — and
  // the parser must not eat it.
  assert_eq(
    trip("receive go(dyn) { send 'flash' dyn }"),
    "receive go(dyn) {\n  send 'flash' dyn\n}",
  )
  // ...and a parameter named `dyn` is still readable as an argument to an
  // effect that DOES take a route, once the route is over.
  // The leg word wins in the leg position. That is the cost of a contextual
  // keyword, and it is worth writing down because a reader will ask: a
  // parameter named `lex` cannot be forwarded by writing `forward lex`, which
  // is a route. Stage it in a field and write `forward .staged`.
  guard route_of("receive go(lex) { forward lex }") is [Lex] else {
    fail("the leg position reads a leg")
  }
}
