// The schema-aware view checks.
//
// Half of these are negative fixtures: each is a view that renders WRONG and
// silently today, and the assertion is that it now fails generation with a
// message naming the fix. The other half guard against the opposite failure
// — a check firing on a view that is fine — which is the way a generator
// like this actually gets abandoned.

///|
/// Generate, returning the error message or "" on success.
fn gen_err(src : String, name : String) -> String {
  try {
    @viewgen.emit_module(name, "t.tutu", @viewgen.read_file(src, name~))
    |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
/// A `spec:` section wrapping the given declarations for the `Board`
/// component, and a `view:` section holding its only view.
///
/// Both arrive already indented for the section they go in — a helper that
/// re-indented them would be a helper that reads shrubbery to write it.
fn board(spec : String, view : String) -> String {
  "spec:\n" + spec + "\nview:\n  Board:\n" + view + "\n"
}

///|
test "a misspelt root field fails generation and suggests the right name" {
  let msg = gen_err(
    board(
      "  Board:\n    field label :: String\n    field count :: Int\n", "    p():\n      @(it.labelx)",
    ),
    "Board",
  )
  assert_true(msg.contains("`.labelx` is not a field of the Board state"))
  assert_true(msg.contains("did you mean `.label`?"))
}

///|
test "a field with no near miss is told where to declare it" {
  let msg = gen_err(
    board(
      "  Board:\n    field label :: String\n", "    p():\n      @(it.somethingElse)",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the Board state"))
  assert_true(msg.contains("`spec:` section"))
}

///|
test "reads inside an @each are checked against the ELEMENT type" {
  // The hole this whole stage exists to close: view_surface stops collecting
  // field reads under @each, so before now this was not merely unchecked —
  // it was not even looked at.
  let msg = gen_err(
    board(
      "  struct Card(title :: String, done :: Bool)\n\n  Board:\n    field cards :: List.of(Card)\n",
      "    ul():\n      each(value, key in it.cards):\n        li():\n          @(it.titel)",
    ),
    "Board",
  )
  assert_true(msg.contains("`.titel` is not a field of Card"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "@value.member inside a loop is checked too" {
  let msg = gen_err(
    board(
      "  struct Card(title :: String)\n\n  Board:\n    field cards :: List.of(Card)\n",
      "    ul():\n      each(value, key in it.cards):\n        li():\n          @(value.titel)",
    ),
    "Board",
  )
  assert_true(msg.contains("not a field of the loop item (Card)"))
  assert_true(msg.contains("did you mean `.title`?"))
}

///|
test "a correct loop body generates cleanly" {
  assert_eq(
    gen_err(
      board(
        "  struct Card(title :: String, done :: Bool)\n\n  Board:\n    field cards :: List.of(Card)\n",
        "    ul():\n      each(value, key in it.cards):\n        li():\n          @(it.title)\n          @(value.done)",
      ),
      "Board",
    ),
    "",
  )
}

///|
test "@each over a scalar is refused" {
  let msg = gen_err(
    board(
      "  Board:\n    field count :: Int\n", "    ul():\n      each(value, key in it.count):\n        li():\n          \"x\"",
    ),
    "Board",
  )
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("`.count` is Int"))
}

///|
test "@each over a set, a list or an ordered map is fine" {
  for
    expr in [
      ("  Board:\n    field tags :: Set.of(String)\n", "it.tags"),
      ("  Board:\n    field xs :: List.of(Int)\n", "it.xs"),
      ("  Board:\n    field m :: Map.of(String, Any)\n", "it.m"),
    ] {
    let (spec, path) = expr
    assert_eq(
      gen_err(
        board(spec, "    ul():\n      each(value, key in \{path}):\n        li(): \"x\""),
        "Board",
      ),
      "",
    )
  }
}

///|
test "<x render> on a non-component is refused" {
  let msg = gen_err(
    board(
      "  Board:\n    field label :: String\n", "    div():\n      render(it.label)",
    ),
    "Board",
  )
  assert_true(msg.contains("`<x render>` needs a component"))
  assert_true(msg.contains("`.label` is String"))
}

///|
test "<x render> on a declared child slot is fine" {
  let src = "spec:\n" +
    "  Card:\n    field title :: String\n\n" +
    "  Board:\n    field lead :: Instance.of(Card)\n" +
    "\nview:\n" +
    "  Card:\n    p(): @(it.title)\n\n" +
    "  Board:\n    div():\n      render(it.lead)\n"
  assert_eq(gen_err(src, "Ignored"), "")
}

///|
test "an opaque scope silences the checks inside it" {
  // `any` and a child component have no schema this file can see, so a read
  // through either is unknown — and unknown must never mean wrong, or the
  // escape hatch stops being one.
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field detail :: Any\n    field slot :: Instance\n    field rows :: List.of(Any)\n",
        "    div():\n      render(it.slot)\n      \" \"\n      ul():\n        each(value, key in it.rows):\n          li():\n            @(it.whatever)",
      ),
      "Board",
    ),
    "",
  )
}

///|
test "a file with no `spec:` section is checked against nothing" {
  // No schema, no checks — unknown is not wrong.
  assert_eq(
    gen_err("view:\n  Board:\n    p():\n      @(it.anythingAtAll)\n", "Board"),
    "",
  )
}

///|
test "the counter demo's own view passes its schema" {
  // The migrated reference example, checked here as well as by compiling.
  let src = "spec:\n" +
    "  Counter:\n    field label :: String\n    field count :: Int\n    field history :: List.of(Int)\n" +
    "\nview:\n  Counter:\n" +
    "    h1():\n      @(it.label)\n      \": \"\n      @(it.count)\n" +
    "    ul():\n      each(value, key in it.history):\n        li():\n          @(value)"
  assert_eq(gen_err(src, "Counter"), "")
}

///|
test "a nested record two levels down is still checked" {
  let msg = gen_err(
    board(
      "  struct Inner(deep :: String)\n\n  struct Outer(inner :: Inner)\n\n  Board:\n    field o :: Outer\n",
      "    p():\n      @(it.o)\n      each(value, key in it.o):\n        span():\n          \"x\"",
    ),
    "Board",
  )
  // `.o` is a record, which is not iterable.
  assert_true(msg.contains("`@each` needs a collection"))
  assert_true(msg.contains("Outer"))
}

///|
test "`~push_view` keeps the state scope" {
  // `~push_view` pushes a VIEW NAME onto the render stack, not a value
  // (render/render.mbt:63). The state under it is still this component's, so
  // its fields must stay checkable — and reads that are fine must not be
  // flagged.
  let spec = "  Board:\n    field items :: List.of(Any)\n    field view :: String\n    field q :: String\n"
  assert_eq(
    gen_err(
      board(
        spec, "    div(~push_view: it.view):\n      each(value, key in it.items):\n        render(value)\n      \" \"\n      p(): @(it.q)",
      ),
      "Board",
    ),
    "",
  )
  // ...and a typo under a push-view is still caught, which it would not be
  // if the scope went opaque.
  let msg = gen_err(
    board(spec, "    div(~push_view: it.view):\n      p(): @(it.qq)"),
    "Board",
  )
  assert_true(msg.contains("`.qq` is not a field of the Board state"))
}

///|
test "a container in `@show` is a test that cannot fail" {
  // `Value::is_truthy` answers `true` for List, Map and Obj unconditionally
  // (core/value_eval.mbt:98), so `@show=".alts"` shows the element for an
  // EMPTY list too. It reads as a guard and is not one.
  let msg = gen_err(
    board(
      "  Board:\n    field alts :: List.of(String)\n", "    show(it.alts):\n      div():\n        \"alternatives\"",
    ),
    "Board",
  )
  assert_true(msg.contains("always truthy"))
  assert_true(msg.contains("empty? .alts"))
  // A record is the same story, and so is `@hide`.
  let rec = gen_err(
    board(
      "  struct Card(title :: String)\n\n  Board:\n    field c :: Card\n", "    hide(it.c):\n      div():\n        \"x\"",
    ),
    "Board",
  )
  assert_true(rec.contains("hide"), msg=rec)
  assert_true(rec.contains("always truthy"))
}

///|
test "a truthiness test that can decide something is left alone" {
  // The predicate is the fix the message asks for, so it must not itself
  // trip the check.
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field alts :: List.of(String)\n", "    show(it.alts.is_empty()):\n      div():\n        \"none\"",
      ),
      "Board",
    ),
    "",
  )
  // A string, a number and an option are NOT flagged. `@show=".role"` beside
  // `@text=".role"` hides an empty badge and is the idiomatic spelling —
  // storybook/examples/personal_site.tutu does exactly this.
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field role :: String\n    field count :: Int\n    field note :: maybe(String)\n    field on :: Bool\n",
        "    show(it.role):\n      p():\n        \"r\"\n    show(it.count):\n      p():\n        \"c\"\n" +
        "    show(it.note):\n      p():\n        \"n\"\n    hide(it.on):\n      p():\n        \"o\"",
      ),
      "Board",
    ),
    "",
  )
  // An unknown type still checks nothing: unknown is not wrong.
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field anything :: Any\n", "    show(it.anything):\n      div():\n        \"x\"",
      ),
      "Board",
    ),
    "",
  )
}

///|
test "a constant id inside a loop is not an id" {
  // The loop emits its body once per item, so `id="row"` is stamped on every
  // one of them. Only the compiled tree knows the element repeats — this is
  // not visible to an HTML linter reading the source.
  let msg = gen_err(
    board(
      "  Board:\n    field items :: List.of(Any)\n", "    ul():\n      each(value, key in it.items):\n        li(id: \"row\"):\n          @(value)",
    ),
    "Board",
  )
  assert_true(msg.contains("`~id: \"row\"` sits inside an `@each`"), msg~)
  assert_true(msg.contains("use a class"))
  // Nested one level deeper is the same story.
  assert_true(
    gen_err(
      board(
        "  Board:\n    field items :: List.of(Any)\n", "    ul():\n      each(value, key in it.items):\n        li():\n          span(id: \"cell\"):\n            \"x\"",
      ),
      "Board",
    ).contains("`~id: \"cell\"`"),
  )
}

///|
test "an id outside the loop, and a per-item id, are both fine" {
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field items :: List.of(Any)\n", "    ul(id: \"list\"):\n      each(value, key in it.items):\n        li(id: @str{row-@(key)}):\n          @(value)",
      ),
      "Board",
    ),
    "",
  )
  // `<x render-each>` drops the element it is written on, so there is no host
  // markup to repeat and nothing to report.
  assert_eq(
    gen_err(
      board(
        "  Board:\n    field items :: List.of(Any)\n", "    div(id: \"pane\"):\n      each(value, key in it.items):\n        render(value)",
      ),
      "Board",
    ),
    "",
  )
}

///|
/// Generate, returning the ADVISORY findings (the `hints` channel) rather than
/// the fatal ones.
fn gen_hints(src : String, name : String) -> Array[String] {
  let hints : Array[String] = []
  try
    @viewgen.emit_module(name, "t.tutu", @viewgen.read_file(src, name~), hints~)
    |> ignore
  catch {
    _ => ()
  }
  hints
}

///|
/// Two components in one file: a Page holding a list of Rows.
fn page_and_row(page_view : String, row_views : String) -> String {
  "spec:\n" +
  "  Page:\n    field rows :: List.of(Instance.of(Row))\n    field sel :: Instance.of(Row)\n\n" +
  "  Row:\n    field title :: String\n" +
  "\nview:\n  Page:\n" +
  page_view +
  "\n" +
  row_views +
  "\n"
}

///|
test "a read inside a loop over CHILD components is checked against that child" {
  // `Array[Row]` names a sibling state, so the element type is the Row
  // component — a thing one StateDef could never answer.
  let msg = gen_err(
    page_and_row(
      "    ul():\n      each(value, key in it.rows):\n        li():\n          @(it.titel)", "  Row:\n    span(): @(it.title)\n",
    ),
    "Page",
  )
  assert_true(msg.contains("`.titel` is not a field of the Row state"))
  assert_true(msg.contains("did you mean `.title`?"))
  // `@value.member` names the same place and must agree.
  assert_true(
    gen_err(
      page_and_row(
        "    ul():\n      each(value, key in it.rows):\n        li():\n          @(value.titel)", "  Row:\n    span(): @(it.title)\n",
      ),
      "Page",
    ).contains("not a field of the loop item (the Row component)"),
  )
  // The correct spellings both pass.
  assert_eq(
    gen_err(
      page_and_row(
        "    ul():\n      each(value, key in it.rows):\n        li():\n          @(it.title)\n          @(value.title)",
        "  Row:\n    span(): @(it.title)\n",
      ),
      "Page",
    ),
    "",
  )
}

///|
test "an `as=` naming a view the child does not have is reported" {
  // At run time the miss falls back to the child's `main` view, so the site
  // renders the wrong one. Only a table spanning both components can see it.
  let hints = gen_hints(
    page_and_row(
      "    render(it.sel, ~as: \"edit\")", "  Row:\n    span(): @(it.title)\n\n  Row.edt:\n    span()\n",
    ),
    "Page",
  )
  assert_eq(hints.length(), 1)
  assert_true(hints[0].contains("unknown-child-view (hint)"))
  assert_true(hints[0].contains("the Row component has no `edit` view"))
  assert_true(hints[0].contains("did you mean `edt`?"))
  // `render-each` reaches the same check through the loop's element type.
  let each_hints = gen_hints(
    page_and_row(
      "    each(value, key in it.rows):\n      render(value, ~as: \"edit\")", "  Row:\n    span(): @(it.title)\n",
    ),
    "Page",
  )
  assert_eq(each_hints.length(), 1)
  assert_true(each_hints[0].contains("has no `edit` view (it has main)"))
}

///|
test "a view name that does resolve, or cannot be known, is reported by nothing" {
  // The name exists.
  assert_eq(
    gen_hints(
      page_and_row(
        "    render(it.sel, ~as: \"edit\")", "  Row:\n    span(): @(it.title)\n\n  Row.edit:\n    input()\n",
      ),
      "Page",
    ).length(),
    0,
  )
  // The name is chosen at run time, so there is nothing to check.
  assert_eq(
    gen_hints(
      page_and_row(
        "    render(it.sel, ~as: it.pick)", "  Row:\n    span(): @(it.title)\n",
      ),
      "Page",
    ).length(),
    0,
  )
  // An untyped `component` slot names no component: unknown is not wrong, in
  // the hints channel as much as in the fatal one.
  assert_eq(
    gen_hints(
      "spec:\n  Page:\n    field sel :: Instance\n\nview:\n  Page:\n    render(it.sel, ~as: \"edit\")\n",
      "Page",
    ).length(),
    0,
  )
}

///|
/// A generated mutator in an event position becomes an ordinary input, and the
/// mutator whose name it borrowed does not answer one — so the button is wired,
/// compiles, and does nothing. This is the shape that reached the landing
/// page's to-do list.
test "a generated mutator sent as a message is reported, and names the write" {
  let hints = gen_hints(
    board(
      "  Board:\n    field items :: List.of(String)\n", "    each(value, key in it.items):\n      div():\n        button(~on_click: remove_in_items_at(key)):\n          \"x\"",
    ),
    "Board",
  )
  assert_eq(hints.length(), 1)
  assert_true(hints[0].contains("mutator-as-message (hint)"))
  assert_true(hints[0].contains("`remove_in_items_at` is a generated mutator"))
  assert_true(hints[0].contains("a mutator is not a message"))
  assert_true(hints[0].contains("write `it.items.remove(<key>)`"))
}

///|
/// The same rule over the other collection kinds, and over a scalar's setter:
/// each names the write that reaches it.
test "the repair names the write for every mutator shape" {
  let set_hints = gen_hints(
    board(
      "  Board:\n    field tags :: Set.of(String)\n", "    button(~on_click: add_in_tags(\"x\")):\n      \"x\"",
    ),
    "Board",
  )
  assert_eq(set_hints.length(), 1)
  assert_true(set_hints[0].contains("write `it.tags.add(<member>)`"))
  let scalar_hints = gen_hints(
    board(
      "  Board:\n    field count :: Int\n", "    button(~on_click: set_count(1)):\n      \"x\"",
    ),
    "Board",
  )
  assert_eq(scalar_hints.length(), 1)
  assert_true(scalar_hints[0].contains("write `it.count := <value>`"))
  // A bool's toggle has no path form — `.open.toggle` is not a property action
  // — so the repair is the expression that says the same thing.
  let bool_hints = gen_hints(
    board(
      "  Board:\n    field open :: Bool\n", "    button(~on_click: toggle_open):\n      \"x\"",
    ),
    "Board",
  )
  assert_eq(bool_hints.length(), 1)
  assert_true(bool_hints[0].contains("write `it.open := !it.open`"))
}

///|
/// …and the writes themselves are silent. A check that fired on the spelling it
/// recommends would be worse than no check. Nor does it fire on a name the
/// component DECLARES: a generated mutator's name can collide with a protocol
/// operation's, and there the view means the message.
test "the path form, a real handler name and a declared message are silent" {
  assert_eq(
    gen_hints(
      board(
        "  Board:\n    field items :: List.of(String)\n", "    each(value, key in it.items):\n      div():\n        button(~on_click: it.items.delete_at(key)):\n          \"x\"",
      ),
      "Board",
    ),
    [],
  )
  assert_eq(
    gen_hints(
      board(
        "  Board:\n    field count :: Int\n", "    button(~on_click: bump):\n      \"x\"",
      ),
      "Board",
    ),
    [],
  )
  assert_eq(
    gen_hints(
      "spec:\n  Board:\n    field open :: Bool\n    message set_open(Bool)\n" +
      "\nview:\n  Board:\n    button(~on_click: set_open(true)):\n      \"x\"\n",
      "Board",
    ),
    [],
  )
}
