// The refusal channel, over the funnel it exists for.
//
// `Path::update` decides between four outcomes and hands back the same root for
// all four. Two of them are refusals — nothing was there, or nothing answered —
// and two are DECLINES, which are the intended design and stay silent. These
// cases are the difference, asserted from outside, because from outside is
// exactly where it used to be invisible.

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
  let off = @core.on_refusal(r => out.push(r))
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
  let obj : @core.Value = Map({ "notes": Map({ "a": Obj(Twice::{  }) }) })
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
