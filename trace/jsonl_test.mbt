// The file format: what a line says, what a reader refuses, and where it says
// the refusal happened.

///|
fn place_of(src : String) -> @trace.Place {
  @trace.parse_place(src) catch {
    _ => Place([])
  }
}

///|
fn root_json() -> Json {
  Json::object({
    "$component": Json::string("TodoApp"),
    "items": Json::array([
      Json::object({
        "$component": Json::string("Row"),
        "label": Json::string("milk"),
        "done": Json::boolean(false),
      }),
    ]),
  })
}

///|
fn sample() -> @trace.Trace {
  let t = @trace.Trace::new(root=root_json(), origin={
    module_: "todos",
    component: "TodoApp",
    example: "default",
    view: "",
    fingerprint: "6600cf22c0b7a132",
  })
  {
    ..t,
    events: [
      {
        seq: 1,
        turn: 1,
        walk: 0,
        parent: 0,
        at: place_of(""),
        op: Send(name="init", args=[]),
        input: true,
        after: None,
      },
      {
        seq: 2,
        turn: 2,
        walk: 0,
        parent: 0,
        at: place_of(".items[0]"),
        op: Send(name="toggle", args=[Bool(true)]),
        input: true,
        after: None,
      },
      {
        seq: 3,
        turn: 2,
        walk: 7,
        parent: 2,
        at: place_of(".items[0]"),
        op: Intent(
          name="save",
          args=[Str("milk")],
          opts=@tutuca.IntentOpts::new(on_ok_name="saved"),
        ),
        input: false,
        after: None,
      },
      {
        seq: 4,
        turn: 2,
        walk: 7,
        parent: 0,
        at: place_of(".items[0]"),
        op: Offered(name="save", args=[Str("milk")], nth=0),
        input: false,
        after: None,
      },
      {
        seq: 5,
        turn: 2,
        walk: 7,
        parent: 0,
        at: place_of(""),
        op: Answer(nth=0, answer=Ok(Str("stored"))),
        input: true,
        after: None,
      },
      {
        seq: 6,
        turn: 3,
        walk: 0,
        parent: 0,
        at: place_of(".items[0]"),
        op: Refused(
          code="PRECONDITION",
          asked="rename",
          rule="hasText",
          sentence="a row with no label cannot be renamed",
        ),
        input: false,
        after: None,
      },
    ],
  }
}

///|
/// The whole file, verbatim. This is the artifact somebody attaches to a bug
/// report, so it is worth reading in a test: two header lines, then one line
/// per event, with the verb as the key and `derived` written only when true.
test "a trace writes as lines a person can read" {
  inspect(
    sample().to_jsonl(),
    content=(
      #|{"origin":{"module":"todos","component":"TodoApp","example":"default","fingerprint":"6600cf22c0b7a132"},"relocatedFrom":[],"tutucaTrace":1}
      #|{"root":{"$component":"TodoApp","items":[{"$component":"Row","label":"milk","done":false}]}}
      #|{"seq":1,"turn":1,"at":[],"send":"init","args":[]}
      #|{"seq":2,"turn":2,"at":[{"f":"items","k":0}],"send":"toggle","args":[true]}
      #|{"seq":3,"turn":2,"walk":7,"parent":2,"derived":true,"at":[{"f":"items","k":0}],"intent":"save","args":["milk"],"opts":{"route":["dyn","lex"],"ok":"saved"}}
      #|{"seq":4,"turn":2,"walk":7,"derived":true,"at":[{"f":"items","k":0}],"offered":"save","args":["milk"],"nth":0}
      #|{"seq":5,"turn":2,"walk":7,"at":[],"answer":{"ok":"stored"},"nth":0}
      #|{"seq":6,"turn":3,"derived":true,"at":[{"f":"items","k":0}],"refused":"PRECONDITION","asked":"rename","rule":"hasText","sentence":"a row with no label cannot be renamed"}
      #|
    ),
  )
}

///|
test "a trace round-trips through its own file format" {
  let t = sample()
  let back = @trace.from_jsonl(t.to_jsonl())
  assert_eq(back, t)
}

///|
/// The one-value form, beside the line format rather than instead of it: a
/// snapshot and a clipboard both want one value, and neither wants to be
/// appended to.
test "a trace round-trips through one JSON value too" {
  let t = sample()
  assert_eq(@trace.Trace::from_json(t.to_json()), t)
}

///|
/// Slicing lines never reads a `Value`, which is what lets the CLI shorten a
/// trace holding an event kind it has never heard of.
test "the lines split without understanding an event" {
  let future =
    #|{"seq":7,"turn":9,"at":[],"teleported":"somewhere","era":2}
    #|
  let text = sample().to_jsonl() + future
  let (headers, events) = @trace.split_lines(text)
  assert_eq(headers.length(), 2)
  assert_eq(events.length(), 7)
  // And reading it PROPERLY does fail, on the line it failed on — the two are
  // different jobs and only one of them has to understand the file.
  inspect(
    read_err(text),
    content="line 9: no verb here — found seq, turn, at, teleported, era",
  )
}

///|
fn read_err(text : String) -> String {
  try {
    @trace.from_jsonl(text) |> ignore
    "no error"
  } catch {
    e => e.message()
  }
}

///|
/// Every refusal names a line, because the file this reads is routinely a
/// hundred thousand lines long and a message with no position in it is one
/// nobody can act on.
test "a malformed file says which line, and why" {
  inspect(
    read_err(""),
    content="not a trace: a trace needs a header line and a root line",
  )
  inspect(
    read_err("{\"root\":{}}\n{\"tutucaTrace\":1}\n"),
    content="line 1: the first line must name `tutucaTrace`",
  )
  inspect(
    read_err("{\"tutucaTrace\":1}\n{\"nope\":1}\n"),
    content="line 2: the second line must hold `root`",
  )
  inspect(
    read_err("{\"tutucaTrace\":99}\n{\"root\":{}}\n"),
    content="line 1: trace version 99, but this reader knows 1",
  )
  inspect(
    read_err("{\"tutucaTrace\":1}\n{\"root\":{}}\n{\"tutucaTrace\":1}\n"),
    content="line 3: a header line after the events began",
  )
  inspect(
    read_err("{\"tutucaTrace\":1}\n{\"root\":{}}\nnot json\n"),
    content="line 3: Invalid character 'o' at line 1, column 1",
  )
}

///|
/// Blank lines are dropped rather than refused: a file that has been
/// concatenated, hand-edited or written with a trailing newline has them, and
/// refusing one would refuse a file that is otherwise perfectly readable. The
/// line NUMBERS still count them, because that is what an editor shows.
test "blank lines are skipped and still counted" {
  let text = "\n{\"tutucaTrace\":1}\n\n{\"root\":{}}\n\n{\"seq\":1,\"nope\":true}\n"
  inspect(read_err(text), content="line 6: no verb here — found seq, nope")
}

///|
/// An answer is the one thing a rerun cannot recompute, so its three shapes
/// have to survive exactly — including `Pass`, which carries nothing and is
/// therefore a bare word rather than an empty object.
test "the three answers round-trip" {
  let t = sample()
  for a in [(Ok(Num(1)) : @tutuca.IntentAnswer), Failed(Str("nope")), Pass] {
    let one : @trace.Trace = {
      ..t,
      events: [
        {
          seq: 1,
          turn: 1,
          walk: 3,
          parent: 0,
          at: place_of(""),
          op: Answer(nth=1, answer=a),
          input: true,
          after: None,
        },
      ],
    }
    assert_eq(@trace.from_jsonl(one.to_jsonl()), one)
  }
}
