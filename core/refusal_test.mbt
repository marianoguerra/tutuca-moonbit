// The refusal channel, over the funnel it exists for.
//
// `Path::update` decides between four outcomes and hands back the same root for
// all four. Two of them are refusals — nothing was there, or nothing answered —
// and two are DECLINES, which are the intended design and stay silent. These
// cases are the difference, asserted from outside.

///|
priv struct Note {
  text : String
}

///|
fn note(text : String) -> @core.Value {
  Obj(Note::{ text, })
}

///|
impl @core.Obj for Note with fn obj_field(self, name) {
  match name {
    "text" => Some(Str(self.text))
    _ => None
  }
}

///|
impl @core.Obj for Note with fn obj_with_field(_self, name, v) {
  match (name, v) {
    ("text", Str(s)) => Some(note(s))
    _ => None
  }
}

///|
impl @core.Obj for Note with fn obj_handler(_self, bucket, name) {
  match (bucket, name) {
    (Receive, "retitle") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(note(s))
            _ => None
          }
        }),
      )
    // The DECLINE: an arm that answers None because another bucket serves this,
    // or because there was nothing to do.
    (Receive, "shrug") => Some(Handler((_args, _ctx) => None))
    // A rule refusing, as a body with a contract would report it.
    (Receive, "guarded") =>
      Some(
        Handler((_args, _ctx) => {
          @core.precondition_failed(
            handler="guarded",
            pred="hasText",
            sentence="a note with no text cannot be retitled",
            state=Map({ "text": Str("") }),
          )
          None
        }),
      )
    _ => None
  }
}

///|
fn tree() -> @core.Value {
  Map({ "notes": Map({ "a": note("first") }) })
}

///|
fn at(key : String) -> @core.Path {
  @core.Path::new(steps=[SeqStep(field="notes", key=KStr(key))])
}

///|
/// Drive `body` with the channel on, and answer what left by it.
fn watched(body : () -> Unit) -> Array[@core.Refusal] {
  let out : Array[@core.Refusal] = []
  let off = @core.on_runtime_notice(n => {
    match n {
      Refused(r) => out.push(r)
      _ => ()
    }
  })
  body()
  off()
  out
}

///|
test "nothing claimed the name, and nothing answered the path" {
  let root = tree()
  let missing_name = watched(() => {
    at("a").update(root, Receive, "nope", []) |> ignore
  })
  assert_eq(missing_name.length(), 1)
  assert_eq(missing_name[0].code, NoHandler)
  assert_eq(missing_name[0].asked, "nope")
  // The state that was rejected is the LEAF the name was asked of, which is the
  // one worth looking at when a name goes unanswered.
  assert_eq(
    @core.Path::new(steps=[FieldStep("text")]).lookup(missing_name[0].state),
    Some(Str("first")),
  )
  assert_eq(missing_name[0].path, at("a"))
  let missing_leaf = watched(() => {
    at("zz").update(root, Receive, "retitle", [Str("x")]) |> ignore
  })
  assert_eq(missing_leaf.length(), 1)
  assert_eq(missing_leaf[0].code, PathUnresolved)
  assert_eq(
    missing_leaf[0].to_line(),
    "PATH_UNRESOLVED at `retitle` on \{Repr(at("zz").steps)}",
  )
}

///|
test "a handler that ran is silent, whether or not it moved anything" {
  let root = tree()
  // Moved.
  assert_eq(
    watched(() => {
      at("a").update(root, Receive, "retitle", [Str("second")]) |> ignore
    }),
    [],
  )
  // DECLINED — an arm answering None has not refused anything, and the mutator
  // behind it is the intended design. This is the case the channel must stay
  // quiet about, or it becomes noise a team mutes.
  assert_eq(
    watched(() => at("a").update(root, Receive, "shrug", []) |> ignore),
    [],
  )
  // Handed a shape it cannot use: the handler decided, so it is a decline too.
  assert_eq(
    watched(() => at("a").update(root, Receive, "retitle", [Num(3.0)]) |> ignore),
    [],
  )
}

///|
test "a rule inside the dispatch reports where it happened" {
  let root = tree()
  let said = watched(() => {
    at("a").update(root, Receive, "guarded", []) |> ignore
  })
  assert_eq(said.length(), 1)
  assert_eq(said[0].code, Precondition)
  assert_eq(said[0].rule, "hasText")
  // The producer knows the rule and the state and has no idea where the
  // dispatch landed. The scope opened around the handler is what fills that in.
  assert_eq(said[0].path, at("a"))
  assert_eq(
    said[0].to_line(),
    "PRECONDITION hasText at `guarded` on \{Repr(at("a").steps)} — a note with no text cannot be retitled",
  )
}

///|
test "one dispatch produces at most one record" {
  // Two rules break inside one handler — the second is the first being handed
  // back up the chain, and a listener that saw both would be reading one
  // failure as two.
  let obj : @core.Value = Map({ "notes": Map({ "a": Obj(Twice::{ }) }) })
  let said = watched(() => at("a").update(obj, Receive, "twice", []) |> ignore)
  assert_eq(said.length(), 1)
  assert_eq(said[0].rule, "first")
}

///|
priv struct Twice {}

///|
impl @core.Obj for Twice with fn obj_handler(_self, _bucket, _name) {
  Some(
    Handler((_args, _ctx) => {
      @core.precondition_failed(handler="twice", pred="first")
      @core.invariant_failed(handler="twice", pred="second")
      None
    }),
  )
}

///|
test "switched off, the report is the line warn has always printed" {
  let said : Array[String] = []
  let before = @core.warn_hook.val
  @core.warn_hook.val = msg => said.push(msg)
  at("zz").update(tree(), Receive, "retitle", [Str("x")]) |> ignore
  @core.precondition_failed(handler="publish", pred="hasTitle")
  @core.precondition_failed(
    handler="publish",
    pred="hasTitle",
    sentence="the title is empty",
  )
  @core.warn_hook.val = before
  // An unresolvable path never had a line to print and still does not: what the
  // channel adds is a record, not a new stream of warnings.
  assert_eq(said, [
    "contract: `publish` declined — its precondition `hasTitle` does not hold",
    "contract: `publish` declined — its precondition `hasTitle` does not hold: the title is empty",
  ])
}

///|
/// A declared name handed the wrong shape, said out loud.
///
/// The generated `from_dispatch` is the one place that holds both halves — the
/// arguments that arrived and the spelling the schema wrote — and this is the
/// producer it calls. Asserted here rather than through a generated module
/// because what is being pinned is the RECORD: a code of its own, and the
/// argument list carried where a rejected state normally goes.
test "a payload that does not fit its declaration is reported with the args" {
  let said = watched(() => @core.bad_payload("moveTo", "Int, Int", [Str("x")]))
  assert_eq(said.length(), 1)
  assert_eq(said[0].code, BadPayload)
  assert_eq(said[0].asked, "moveTo")
  // Not a state: the arguments, because no arm ran and they are the thing to
  // go and look at.
  assert_eq(said[0].state, List([Str("x")]))
  assert_eq(
    said[0].to_line(),
    "BAD_PAYLOAD at `moveTo` — the arguments do not fit `moveTo(Int, Int)`",
  )
}

///|
/// Nothing is built when nothing is listening, which is what lets the argument
/// list be carried at all — the same bargain a rejected state makes.
test "a payload refusal costs nothing with the channel switched off" {
  // No listener installed: the producer returns before building the record,
  // and `warn` is not reached either — a mismatch is not a warning, it is a
  // record or it is nothing.
  @core.bad_payload("moveTo", "Int, Int", [Str("x")])
}

///|
/// `to_line` is prose and `to_json` is the record: what the sentence folds away
/// — the code as a word to filter on, the address as structure, and the state
/// that was rejected — is exactly what a stored trace or a scene report needs
/// back.
test "a refusal as JSON keeps what the line throws away" {
  let said = watched(() => {
    at("a").update(tree(), Receive, "guarded", []) |> ignore
  })
  assert_eq(said.length(), 1)
  inspect(
    said[0].to_json().stringify(),
    content=(
      #|{"code":"PRECONDITION","asked":"guarded","rule":"hasText","sentence":"a note with no text cannot be retitled","path":"notes[a]","pathKeys":[{"f":"notes","k":"a"}],"state":{"text":""}}
    ),
  )
}

///|
/// A producer with no state in hand writes no `state` key at all. A `null`
/// there would say "the rejected state was null", which is a different and
/// wrong claim.
test "a refusal with no state omits the key" {
  let r : @core.Refusal = {
    code: NoSender,
    asked: "saved",
    rule: "",
    sentence: "",
    state: Null,
    path: @core.Path::new(),
  }
  inspect(
    r.to_json().stringify(),
    content=(
      #|{"code":"NO_SENDER","asked":"saved","rule":"","sentence":"","path":"","pathKeys":[]}
    ),
  )
}

///|
/// The shared address encoding. Short keys because a trace of a real session is
/// mostly these, and `k` absent rather than null because a keyed step and a
/// plain field are different steps.
test "a step key round-trips through JSON" {
  let keys : Array[@core.StepKey] = [
    { field: "rows", key: None, },
    { field: "rows", key: Some(KInt(2)), },
    { field: "byId", key: Some(KStr("a")), },
  ]
  let js = keys.map(k => k.to_json())
  inspect(
    Json::array(js).stringify(),
    content=(
      #|[{"f":"rows"},{"f":"rows","k":2},{"f":"byId","k":"a"}]
    ),
  )
  assert_eq(js.map(j => @core.StepKey::from_json(j)), keys.map(k => Some(k)))
}

///|
/// A step that cannot say where it points is not a step: the reader answers
/// None rather than inventing a field or dropping a key.
test "a malformed step key is refused rather than guessed" {
  assert_eq(@core.StepKey::from_json(Json::string("rows")), None)
  assert_eq(@core.StepKey::from_json(Json::object({})), None)
  assert_eq(
    @core.StepKey::from_json(
      Json::object({ "f": Json::string("rows"), "k": Json::array([]) }),
    ),
    None,
  )
  // An explicit null key is a PLAIN field, not a malformed keyed step: that is
  // what a writer that spells its absent values out produces.
  assert_eq(
    @core.StepKey::from_json(
      Json::object({ "f": Json::string("rows"), "k": Json::null() }),
    ),
    Some({ field: "rows", key: None, }),
  )
}
