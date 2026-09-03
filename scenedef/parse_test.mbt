///|
/// The whole vocabulary in one block, so a change to any verb moves this.
test "a scene reads every verb" {
  let scenes = @scenedef.parse_scenes(
    (
      #|{
      #|  "the whole vocabulary": {
      #|    "component": "Todo",
      #|    "init": "fresh",
      #|    "args": { "draft": "milk" },
      #|    "raw": true,
      #|    "steps": [
      #|      { "send": "init" },
      #|      { "send": "seed", "args": [1, "two"] },
      #|      { "click": "button.inc" },
      #|      { "click": "li.todo", "nth": 2 },
      #|      { "type": "input.new", "value": "eggs" },
      #|      { "key": "input.new", "is": "Enter" },
      #|      { "check": "input.toggle", "is": true, "nth": 1 },
      #|      { "fire": "section", "event": "emoji-click", "value": { "u": "!" } },
      #|      { "drag": "li.todo", "from": 0, "to": 2 }
      #|    ]
      #|  }
      #|}
    ),
  )
  assert_eq(scenes.length(), 1)
  let s = scenes[0]
  inspect(s.component, content="Todo")
  inspect(s.init, content="fresh")
  assert_true(s.raw)
  assert_eq(s.args.get("draft"), Some(Str("milk")))
  @debug.assert_eq(s.steps.length(), 9)
  @debug.assert_eq(s.steps[1], Send(name="seed", args=[Num(1), Str("two")]))
  @debug.assert_eq(s.steps[3], Click(sel="li.todo", nth=2))
  @debug.assert_eq(
    s.steps[5],
    Key(sel="input.new", key="Enter", value=None, nth=0),
  )
  @debug.assert_eq(s.steps[8], Drag(sel="li.todo", from=0, to=2))
}

///|
test "a scene reads every reader" {
  let scenes = @scenedef.parse_scenes(
    (
      #|{
      #|  "reads": { "steps": [
      #|    { "expect": "text",    "at": "output", "is": "2" },
      #|    { "expect": "texts",   "at": "li", "is": ["a", "b"] },
      #|    { "expect": "attr",    "at": "a", "name": "href", "is": "/x" },
      #|    { "expect": "prop",    "at": "input", "name": "value", "is": "hi" },
      #|    { "expect": "value",   "at": "input", "is": "hi" },
      #|    { "expect": "checked", "at": "input", "is": true },
      #|    { "expect": "count",   "at": "li.done", "is": 3 },
      #|    { "expect": "state",   "at": ".count", "is": 2 },
      #|    { "expect": "state",   "is": { "count": 2 } },
      #|    { "expect": "html",    "contains": "done" },
      #|    { "expect": "renders", "is": 1 },
      #|    { "expect": "refused", "is": [] }
      #|  ] }
      #|}
    ),
  )
  let words = scenes[0].steps.map(s => {
    match s {
      Read(e) => e.reader.word()
      _ => "?"
    }
  })
  inspect(
    words.join(" "),
    content="text texts attr prop value checked count state state html renders refused",
  )
}

///|
/// An expectation with no answer is not a mistake — it is the RECORD form, and
/// the runner fills it in. That is the one thing about this block worth an
/// agent's time, so it gets a test of its own.
test "an expectation with no answer records instead of judging" {
  let scenes = @scenedef.parse_scenes(
    (
      #|{ "record": { "steps": [
      #|  { "expect": "text", "at": "output" },
      #|  { "expect": "text", "at": "output", "is": "2" }
      #|] } }
    ),
  )
  let wants = scenes[0].steps.map(s => {
    match s {
      Read(e) => e.want
      _ => None
    }
  })
  @debug.assert_eq(wants[0], None)
  @debug.assert_eq(wants[1], Some(WIs(Str("2"))))
}

///|
test "a place reads as the steps a lookup walks" {
  @debug.assert_eq(@scenedef.parse_place(".count"), [FieldStep("count")])
  @debug.assert_eq(@scenedef.parse_place(".rows[0].label"), [
    SeqStep(field="rows", key=KInt(0)),
    FieldStep("label"),
  ])
  @debug.assert_eq(@scenedef.parse_place(".byId['a'].n"), [
    SeqStep(field="byId", key=KStr("a")),
    FieldStep("n"),
  ])
}

///|
/// A bare key is refused rather than guessed at: the block language has a
/// spelling for "the key held in `.a`", so reading `[a]` as the literal `a`
/// would be this reader disagreeing with the language.
test "a place refuses what it would have to guess at" {
  inspect(
    place_err(".rows[a]"),
    content="a key is a whole number (`[0]`) or a quoted name (`['a']`); a bare `a` would be ambiguous with the key held in `.a`",
  )
  inspect(
    place_err("count"),
    content="a place starts at a field of the state, e.g. `.count`",
  )
  inspect(place_err(".rows[0"), content="a key is not closed: expected `]`")
}

///|
fn place_err(src : String) -> String {
  try {
    @scenedef.parse_place(src) |> ignore
    "no error"
  } catch {
    e => e.message()
  }
}

///|
/// The messages, which are the whole reason this package is separate from the
/// thing that runs a scene: they are what an author reads, and they are
/// checkable with no DOM anywhere.
test "what a bad block says" {
  inspect(
    err("[]"),
    content="test block: expected an object of named scenes, e.g. { \"it counts\": { \"steps\": [] } }",
  )
  inspect(
    err("{ \"a\": 1 }"),
    content="test block: scene `a` is not an object — a scene is { \"steps\": [ … ] }",
  )
  inspect(
    err("{ \"a\": {} }"),
    content="test block: scene `a` declares no `steps`; a scene that drives nothing has nothing to say",
  )
  inspect(
    err("{ \"a\": { \"steps\": [ { \"clik\": \"b\" } ] } }"),
    content="test block: scene `a`, step 0: names no verb — a step is one of `click`, `type`, `key`, `check`, `fire`, `drag`, `send` or `expect`, so did you mean `click`?",
  )
  inspect(
    err("{ \"a\": { \"steps\": [ { \"click\": \"b\", \"type\": \"c\" } ] } }"),
    content="test block: scene `a`, step 0: names both `click` and `type`; a step is one verb, and an object's keys have no order to decide which happens first",
  )
  inspect(
    err("{ \"a\": { \"steps\": [ { \"type\": \"input\" } ] } }"),
    content="test block: scene `a`, step 0: `type` needs a `value`",
  )
  inspect(
    err("{ \"a\": { \"steps\": [ { \"expect\": \"txet\", \"at\": \"p\" } ] } }"),
    content="test block: scene `a`, step 0: nothing reads `txet` — did you mean `text`?",
  )
  inspect(
    err(
      "{ \"a\": { \"steps\": [ { \"expect\": \"count\", \"at\": \"p\", \"contains\": \"x\" } ] } }",
    ),
    content="test block: scene `a`, step 0: `contains` reads a string, and `count` does not answer one — say `is` and mean it exactly",
  )
}

///|
/// The sharp edge the harness has and a CSS engine does not: a descendant
/// combinator is read as one malformed token and silently matches nothing, so
/// a scene written with one PASSES. Refusing it here is the only place the
/// mistake is visible.
test "a selector with a combinator is refused rather than left to match nothing" {
  inspect(
    err("{ \"a\": { \"steps\": [ { \"click\": \".pane .row\" } ] } }"),
    content="test block: scene `a`, step 0: `.pane .row` is not a selector this can mean: a selector is ONE compound selector — a tag plus any number of #id, .class and [attr] qualifiers. There is no descendant combinator and no list; scope by a class the target itself carries",
  )
}

///|
test "an intent fixture answers one of three things" {
  let scenes = @scenedef.parse_scenes(
    (
      #|{ "a": {
      #|  "intents": { "rows": { "ok": [1] }, "boom": { "failed": "no" }, "shrug": "pass" },
      #|  "steps": [ { "send": "init" } ]
      #|} }
    ),
  )
  let i = scenes[0].intents
  @debug.assert_eq(i.get("rows"), Some(Ok(List([Num(1)]))))
  @debug.assert_eq(i.get("boom"), Some(Failed(Str("no"))))
  @debug.assert_eq(i.get("shrug"), Some(Pass))
  inspect(
    err("{ \"a\": { \"intents\": { \"r\": 1 }, \"steps\": [] } }"),
    content="test block: scene `a`'s intent `r`: expected { \"ok\": … }, { \"failed\": … } or \"pass\"",
  )
}

///|
fn err(src : String) -> String {
  try {
    @scenedef.parse_scenes(src) |> ignore
    "no error"
  } catch {
    e => e.message()
  }
}
