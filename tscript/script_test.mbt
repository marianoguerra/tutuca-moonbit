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
test "the eight declaration kinds" {
  assert_eq(trip("on reset { .count = 0 }"), "on reset {\n  .count = 0\n}")
  assert_eq(
    trip("receive resetTo(n) { .count = n }"),
    "receive resetTo(n) {\n  .count = n\n}",
  )
  assert_eq(
    trip("bubble rowPicked(i) { .sel = i }"),
    "bubble rowPicked(i) {\n  .sel = i\n}",
  )
  assert_eq(
    trip("response loadRows(rows) { .rows = rows }"),
    "response loadRows(rows) {\n  .rows = rows\n}",
  )
  assert_eq(trip("compute label { .name }"), "compute label { .name }")
  assert_eq(
    trip("pred unfinished { not @value.completed }"),
    "pred unfinished { not @value.completed }",
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
  // `when` could. The kind list is eight rather than nine.
  assert_eq(
    script_err("when unfinished { not @value.completed }"),
    "`when` is not a declaration kind — expected on, receive, bubble, response, compute, pred, enrich or enrichScope",
  )
}

///|
test "a name is answered once per bucket" {
  assert_eq(
    script_err("on add(d) { .count += d }\non add(e) { .count -= e }"),
    "`add` is declared twice in this bucket; a name is answered once, by exact match, with nothing behind it",
  )
  // Different buckets are different questions, so the same name is fine.
  assert_eq(
    script_err("on reset { .count = 0 }\nreceive reset { .count = 0 }"),
    "",
  )
}

// -- statements -------------------------------------------------------------

///|
test "assignment, compound assignment and nested places" {
  assert_eq(
    trip(
      (
        #|on toggleLabel(key) {
        #|  .labels[key].done = not .labels[key].done
        #|  .count += 1
        #|  .count -= 1
        #|}
      ),
    ),
    (
      #|on toggleLabel(key) {
      #|  .labels[key].done = not .labels[key].done
      #|  .count += 1
      #|  .count -= 1
      #|}
    ),
  )
}

///|
test "statements separate on a newline or a semicolon, identically" {
  let a = trip("on go { .a = 1; .b = 2 }")
  let b = trip("on go {\n  .a = 1\n  .b = 2\n}")
  assert_eq(a, b)
}

///|
test "the collection methods are receiver-first" {
  assert_eq(
    trip(
      (
        #|on edit(i, v) {
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
      #|on edit(i, v) {
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
test "a method arity that does not match is refused" {
  assert_eq(
    script_err("on x { .items.push }"),
    "expected 1 for `push`, found 0 argument(s)",
  )
  assert_eq(
    script_err("on x { .items.frobnicate 1 }"),
    "expected a collection method: push, insertAt, setAt, deleteAt, add, remove or toggle, found `frobnicate`",
  )
}

///|
test "the effects" {
  assert_eq(
    trip(
      (
        #|on save {
        #|  send 'flash' .msg
        #|  bubble 'rowPicked' @key
        #|  request 'loadData'
        #|  stop
        #|}
      ),
    ),
    (
      #|on save {
      #|  send 'flash' .msg
      #|  bubble 'rowPicked' @key
      #|  request 'loadData'
      #|  stop
      #|}
    ),
  )
}

///|
test "if / else as a statement, and without an else" {
  assert_eq(
    trip("on publish { if hasTitle { .published = true } }"),
    (
      #|on publish {
      #|  if hasTitle {
      #|    .published = true
      #|  }
      #|}
    ),
  )
  assert_eq(
    trip("on t { if .ok { .n = 1 } else { .n = 2 } }"),
    (
      #|on t {
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
    trip("on set(value) { .label = value }"),
    "on set(value) {\n  .label = value\n}",
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
    trip("on save { sendAt &.status 'flash' 'Saved' }"),
    "on save {\n  sendAt &.status 'flash' 'Saved'\n}",
  )
  assert_eq(
    trip("on pick(k) { sendAt &.rows[k] 'select' }"),
    "on pick(k) {\n  sendAt &.rows[k] 'select'\n}",
  )
  // Anywhere else it is refused, because a place is not a value.
  assert_eq(
    script_err("on x { .a = &.rows[0] }"),
    "`&` names a POSITION and is legal in exactly one place: the first argument of `sendAt`",
  )
  assert_eq(
    script_err("on x { send 'flash' &.status }"),
    "`&` names a POSITION and is legal in exactly one place: the first argument of `sendAt`",
  )
}

///|
test "a place the runtime Path cannot express is refused" {
  // A step is field-then-key, so two keys in a row have no step. Only `&`
  // places are constrained: a plain read is rebuilt by the backend and never
  // becomes a `Path` at all.
  assert_eq(
    script_err("on x { sendAt &.a[0][1] 'go' }"),
    "a path step is a field and then a key, so two keys in a row have no step — write `.a[0].b[1]`",
  )
  assert_eq(script_err("on x { sendAt &.a[0].b[1] 'go' }"), "")
  assert_eq(script_err("compute x { .a[0][1] }"), "")
}

// -- lexical ----------------------------------------------------------------

///|
test "comments vanish and doc comments do not" {
  assert_eq(
    trip(
      (
        #|// an ordinary comment
        #|on reset { .count = 0 } // and a trailing one
      ),
    ),
    "on reset {\n  .count = 0\n}",
  )
}

///|
test "a newline inside brackets does not end a statement" {
  // Which is what lets a long argument list wrap. Inside `{` a newline DOES
  // separate, because that is what it is there for.
  assert_eq(
    trip(
      (
        #|on p {
        #|  .page = clamp .page 0 (
        #|    .n - 1
        #|  )
        #|}
      ),
    ),
    "on p {\n  .page = clamp .page 0 (.n - 1)\n}",
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
    @tscript.parse_script("on add(d) { .count += }") |> ignore
    @tscript.no_span
  } catch {
    err => err.span()
  }
  assert_eq(e, { start: 22, end_: 23 })
}
