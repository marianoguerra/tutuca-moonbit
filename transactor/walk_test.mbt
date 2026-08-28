// The intent walk, end to end: one dispatch that may visit many positions.
//
// Every case here is about WHERE the intent goes and what ends it, which is
// the half `tscript/conformance` cannot state: a corpus case is one transition
// and a walk is many. The four cases the corpus lists as belonging here — an
// observer above a replier, a declining handler and the walk continuing,
// `reply` twice across two hops, and route exhaustion in its three shapes —
// are each a test below.
//
// The tree is Root > Panel > Item, and the intent is always dispatched from
// Item, so a default route visits Panel then Root and then the lexical scope.

///|
priv struct WItem {
  seen : String
}

///|
fn witem(seen : String) -> @tutuca.Value {
  Obj(WItem::{ seen, })
}

///|
impl @tutuca.Obj for WItem with fn obj_field(self, name) {
  match name {
    "seen" => Some(Str(self.seen))
    _ => None
  }
}

///|
impl @tutuca.Obj for WItem with fn obj_handler(_self, bucket, name) {
  match (bucket, name) {
    // The senders. Each spells one route.
    (Receive, "go") =>
      Some(
        Handler((args, ctx) => {
          ctx.intent("saveDraft", args, @tutuca.IntentOpts::new())
          None
        }),
      )
    (Receive, "go-answered") =>
      Some(
        Handler((args, ctx) => {
          ctx.intent(
            "saveDraft",
            args,
            @tutuca.IntentOpts::new(
              on_ok_name="saveDraftOk",
              on_error_name="saveDraftError",
              on_unhandled_name="saveDraftUnhandled",
            ),
          )
          None
        }),
      )
    (Receive, "go-error-only") =>
      Some(
        Handler((args, ctx) => {
          ctx.intent(
            "saveDraft",
            args,
            @tutuca.IntentOpts::new(on_error_name="saveDraftError"),
          )
          None
        }),
      )
    (Receive, "go-lex") =>
      Some(
        Handler((args, ctx) => {
          ctx.intent(
            "saveDraft",
            args,
            @tutuca.IntentOpts::new(route=[Lex], on_ok_name="saveDraftOk"),
          )
          None
        }),
      )
    (Receive, "go-lex-first") =>
      Some(
        Handler((args, ctx) => {
          ctx.intent(
            "saveDraft",
            args,
            @tutuca.IntentOpts::new(route=[Lex, Dyn], on_ok_name="saveDraftOk"),
          )
          None
        }),
      )
    // The bridge: a message this component does not answer, let out as an
    // intent from this component's own position.
    (Receive, "saveDraft") =>
      Some(
        Handler((_args, ctx) => {
          ctx.forward(None, None)
          None
        }),
      )
    // A component may not answer its own intent: the `dyn` leg starts at the
    // parent, so this arm must never fire for an intent this node dispatched.
    (Intent, "saveDraft") => Some(Handler((_args, _ctx) => Some(witem("SELF"))))
    // The answers, which arrive as ordinary messages.
    (Receive, "saveDraftOk") =>
      Some(Handler((args, _ctx) => Some(witem("ok:" + show_args(args)))))
    (Receive, "saveDraftError") =>
      Some(Handler((args, _ctx) => Some(witem("error:" + show_args(args)))))
    (Receive, "saveDraftUnhandled") =>
      Some(Handler((args, _ctx) => Some(witem("unhandled:" + show_args(args)))))
    _ => None
  }
}

///|
fn show_args(args : Array[@tutuca.Value]) -> String {
  args.map(a => a.to_repr().to_string()).join(",")
}

///|
/// The middle of the tree. Which arm it exposes is chosen per test by `role`,
/// because what a walk does depends entirely on what the position in the
/// middle of it decides to be.
priv struct WPanel {
  item : @tutuca.Value
  role : String
  seen : String
}

///|
fn wpanel(item : @tutuca.Value, role : String, seen : String) -> @tutuca.Value {
  Obj(WPanel::{ item, role, seen, })
}

///|
impl @tutuca.Obj for WPanel with fn obj_field(self, name) {
  match name {
    "item" => Some(self.item)
    "seen" => Some(Str(self.seen))
    _ => None
  }
}

///|
impl @tutuca.Obj for WPanel with fn obj_with_field(self, name, v) {
  match name {
    "item" => Some(wpanel(v, self.role, self.seen))
    _ => None
  }
}

///|
impl @tutuca.Obj for WPanel with fn obj_handler(self, bucket, name) {
  guard (bucket, name) is (Intent, "saveDraft") else { return None }
  match self.role {
    // Runs, changes state, does not answer. The design's one rule: a handler
    // that runs does not consume the intent.
    "observe" =>
      Some(
        Handler((_args, _ctx) => Some(wpanel(self.item, self.role, "observed"))),
      )
    // Declines. No successor, no effects — the shape a failed `requires`
    // leaves behind — and the walk goes on.
    "decline" => Some(Handler((_args, _ctx) => None))
    "reply" =>
      Some(
        Handler((_args, ctx) => {
          ctx.reply(Str("panel"))
          Some(wpanel(self.item, self.role, "replied"))
        }),
      )
    "fail" =>
      Some(
        Handler((_args, ctx) => {
          ctx.fail(Str("panel-failed"))
          None
        }),
      )
    "stop" =>
      Some(
        Handler((_args, ctx) => {
          ctx.stop_propagation()
          Some(wpanel(self.item, self.role, "stopped"))
        }),
      )
    // Runs, then amends what the next position sees.
    "amend" =>
      Some(
        Handler((_args, ctx) => {
          ctx.forward(Some([Str("enriched")]), None)
          Some(wpanel(self.item, self.role, "amended"))
        }),
      )
    _ => None
  }
}

///|
priv struct WRoot {
  panel : @tutuca.Value
  role : String
  seen : String
}

///|
fn wroot(panel : @tutuca.Value, role : String, seen : String) -> @tutuca.Value {
  Obj(WRoot::{ panel, role, seen, })
}

///|
impl @tutuca.Obj for WRoot with fn obj_field(self, name) {
  match name {
    "panel" => Some(self.panel)
    "seen" => Some(Str(self.seen))
    _ => None
  }
}

///|
impl @tutuca.Obj for WRoot with fn obj_with_field(self, name, v) {
  match name {
    "panel" => Some(wroot(v, self.role, self.seen))
    _ => None
  }
}

///|
impl @tutuca.Obj for WRoot with fn obj_handler(self, bucket, name) {
  guard (bucket, name) is (Intent, "saveDraft") else { return None }
  match self.role {
    "reply" =>
      Some(
        Handler((args, ctx) => {
          ctx.reply(Str("root:" + show_args(args)))
          Some(wroot(self.panel, self.role, "replied"))
        }),
      )
    "observe" =>
      Some(
        Handler((_args, _ctx) => Some(wroot(self.panel, self.role, "observed"))),
      )
    "none" => None
    _ => None
  }
}

///|
/// Root(role) > Panel(role) > Item.
fn tree(panel_role : String, root_role : String) -> @tutuca.Value {
  wroot(wpanel(witem(""), panel_role, ""), root_role, "")
}

///|
fn item_at() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep("panel"), FieldStep("item")])
}

///|
fn read(root : @tutuca.Value, steps : Array[@tutuca.Step]) -> String {
  match @tutuca.Path::new(steps~).lookup(root) {
    Some(Str(s)) => s
    _ => "?"
  }
}

///|
fn item_seen(root : @tutuca.Value) -> String {
  read(root, [FieldStep("panel"), FieldStep("item"), FieldStep("seen")])
}

///|
fn panel_seen(root : @tutuca.Value) -> String {
  read(root, [FieldStep("panel"), FieldStep("seen")])
}

///|
fn root_seen(root : @tutuca.Value) -> String {
  read(root, [FieldStep("seen")])
}

///|
/// The kinds and names an observer saw, in order — which is what "where did
/// the intent go" looks like from outside.
fn trace(tx : @transactor.Transactor) -> Array[String] {
  let out : Array[String] = []
  let _ = tx.observe(r => out.push(r.kind.label() + ":" + r.name))
  out
}

// ---------------------------------------------------------------------------

///|
test "a walk of N hops produces N queued transactions and one answer" {
  let tx = @transactor.Transactor::new(tree("observe", "reply"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go-answered", [Str("draft")])
  tx.settle() |> ignore
  // receive:go-answered, then one intent hop per ancestor, then the answer.
  inspect(
    seen.join(" "),
    content="receive:go-answered intent:saveDraft intent:saveDraft answer:saveDraftOk",
  )
  assert_eq(panel_seen(tx.root), "observed")
  assert_eq(root_seen(tx.root), "replied")
  assert_eq(item_seen(tx.root), "ok:RStr(\"root:RStr(\\\"draft\\\")\")")
}

///|
test "an observer above a replier does not consume the intent" {
  // Panel runs and does not answer; Root answers. Both ran, one replied.
  let tx = @transactor.Transactor::new(tree("observe", "reply"))
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(panel_seen(tx.root), "observed")
  assert_eq(root_seen(tx.root), "replied")
}

///|
test "a declining handler leaves no successor and the walk continues" {
  // The shape a failed `requires` leaves: no state change, no effects. The
  // corpus states that half as one transition; this is the other half.
  let tx = @transactor.Transactor::new(tree("decline", "reply"))
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(panel_seen(tx.root), "")
  assert_eq(root_seen(tx.root), "replied")
  assert_eq(item_seen(tx.root), "ok:RStr(\"root:\")")
}

///|
test "a reply ends the walk, so the position above it never runs" {
  let tx = @transactor.Transactor::new(tree("reply", "observe"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(panel_seen(tx.root), "replied")
  // Root's arm exists and did not run.
  assert_eq(root_seen(tx.root), "")
  inspect(
    seen.join(" "),
    content="receive:go-answered intent:saveDraft answer:saveDraftOk",
  )
}

///|
test "the one-shot is per intent, across hops" {
  // Panel replies. Root would too, and never gets the chance — so there is one
  // answer and not two. The one-shot flag lives on the WALK, not on a hop:
  // with several handlers on the route, a per-hop flag would let each of them
  // answer once and the sender would hear several.
  let tx = @transactor.Transactor::new(tree("reply", "reply"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(seen.filter(s => s.has_prefix("answer:")).length(), 1)
  assert_eq(item_seen(tx.root), "ok:RStr(\"panel\")")
}

///|
test "fail answers with the error name" {
  let tx = @transactor.Transactor::new(tree("fail", "reply"))
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "error:RStr(\"panel-failed\")")
  // The walk ended, so Root never ran.
  assert_eq(root_seen(tx.root), "")
}

///|
test "stop ends the walk and answers nothing, even to a sender that asked" {
  let tx = @transactor.Transactor::new(tree("stop", "reply"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_eq(panel_seen(tx.root), "stopped")
  assert_eq(root_seen(tx.root), "")
  assert_eq(item_seen(tx.root), "")
  assert_eq(seen.filter(s => s.has_prefix("answer:")).length(), 0)
}

///|
test "route exhaustion: Unhandled declared, and it carries the intent's own arguments" {
  let tx = @transactor.Transactor::new(tree("none", "none"))
  let _ = tx.push_send(item_at(), "go-answered", [Str("draft")])
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "unhandled:RStr(\"draft\")")
}

///|
test "route exhaustion: only Error declared, so it gets noHandler" {
  let tx = @transactor.Transactor::new(tree("none", "none"))
  let _ = tx.push_send(item_at(), "go-error-only", [Str("draft")])
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "error:RStr(\"noHandler\")")
}

///|
test "route exhaustion: neither declared, so nothing happens" {
  // A notification. Nothing answered it, and no ancestor had to.
  let tx = @transactor.Transactor::new(tree("none", "none"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go", [Str("draft")])
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "")
  assert_eq(seen.filter(s => s.has_prefix("answer:")).length(), 0)
}

///|
test "the dyn leg starts at the parent, so a component never re-enters itself" {
  // Item declares an `Intent` arm for the very name it dispatches. It must not
  // fire: a cycle needs two components.
  let tx = @transactor.Transactor::new(tree("none", "reply"))
  let _ = tx.push_send(item_at(), "go-answered", [])
  tx.settle() |> ignore
  assert_true(item_seen(tx.root) != "SELF")
  assert_eq(root_seen(tx.root), "replied")
}

///|
test "forward from a receive body lets the name out as an intent" {
  // The bridge. Item answers `saveDraft` with `forward`, so the same name
  // reaches Root as an intent, from Item's own position — which is where the
  // answer comes back to.
  let tx = @transactor.Transactor::new(tree("observe", "reply"))
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "saveDraft", [Str("d")])
  tx.settle() |> ignore
  inspect(
    seen.join(" "),
    content="receive:saveDraft intent:saveDraft intent:saveDraft answer:saveDraftOk",
  )
  assert_eq(root_seen(tx.root), "replied")
}

///|
test "forward in an intent body amends what the next position sees" {
  let tx = @transactor.Transactor::new(tree("amend", "reply"))
  let _ = tx.push_send(item_at(), "go-answered", [Str("original")])
  tx.settle() |> ignore
  assert_eq(panel_seen(tx.root), "amended")
  assert_eq(item_seen(tx.root), "ok:RStr(\"root:RStr(\\\"enriched\\\")\")")
}

// ---------------------------------------------------------------------------
// The lexical leg.
//
// Its handlers are static functions with no state, and the thing worth testing
// is the decision in the intent walk: `lex` WALKS — a declining
// handler hands the intent to the next one — and the walk is resolution rather
// than dispatch, so a `Pass` produces no transaction.

///|
struct Registry {
  handlers : Array[@transactor.IntentHandler]
}

///|
pub impl @transactor.Intents for Registry with fn intents_for(self, _leaf, name) {
  if name == "saveDraft" {
    self.handlers
  } else {
    []
  }
}

///|
/// A handler that declines, counting that it was asked.
fn passer(count : Ref[Int]) -> @transactor.IntentHandler {
  IntentHandler((_call, answer) => {
    count.val = count.val + 1
    answer(Pass)
  })
}

///|
test "a lex handler answers, and the answer reaches the sender" {
  let asked : Ref[Int] = { val: 0, }
  let reg = Registry::{
    handlers: [
      IntentHandler((call, answer) => {
        asked.val = asked.val + 1
        answer(Ok(Str("lex:" + show_args(call.args))))
      }),
    ],
  }
  let tx = @transactor.Transactor::new(tree("none", "none"), intents=reg)
  let _ = tx.push_send(item_at(), "go-lex", [Str("d")])
  tx.settle() |> ignore
  assert_eq(asked.val, 1)
  assert_eq(item_seen(tx.root), "ok:RStr(\"lex:RStr(\\\"d\\\")\")")
}

///|
test "a declining lex handler hands the intent to the next one, and costs no transaction" {
  let passed : Ref[Int] = { val: 0, }
  let reg = Registry::{
    handlers: [
      passer(passed),
      passer(passed),
      IntentHandler((_call, answer) => answer(Ok(Str("third")))),
    ],
  }
  let tx = @transactor.Transactor::new(tree("none", "none"), intents=reg)
  let seen = trace(tx)
  let _ = tx.push_send(item_at(), "go-lex", [])
  tx.settle() |> ignore
  assert_eq(passed.val, 2)
  assert_eq(item_seen(tx.root), "ok:RStr(\"third\")")
  // Two declines and one answer, and NOT one queued hop per frame: the whole
  // leg resolved inside the transaction that was already running.
  //
  // The three `intent:` records are those three decisions, one per handler
  // asked. They are the only trace a lexical hop leaves — it is invoked inline
  // rather than queued — and the reason they are worth emitting is right here:
  // the sentence above describes what happens, and until these existed nothing
  // could observe it. `passed.val` counts the declines from inside the
  // handlers; this counts them from outside, which is where a devtool stands.
  inspect(
    seen.join(" "),
    content="intent:saveDraft intent:saveDraft intent:saveDraft receive:go-lex answer:saveDraftOk",
  )
}

///|
test "a lex leg that answers nothing falls through to the next leg" {
  let passed : Ref[Int] = { val: 0, }
  let reg = Registry::{ handlers: [passer(passed), passer(passed)], }
  let tx = @transactor.Transactor::new(tree("none", "reply"), intents=reg)
  let _ = tx.push_send(item_at(), "go-lex-first", [])
  tx.settle() |> ignore
  assert_eq(passed.val, 2)
  // `lex dyn`: the scope declined, so the ancestors were asked next.
  assert_eq(root_seen(tx.root), "replied")
}

///|
test "a lex handler may answer later, and the walk waits for it" {
  // Callback style, exactly as a request handler already is. The walk is not
  // allowed to assume a static handler answers synchronously.
  let later : Ref[((@tutuca.IntentAnswer) -> Unit)?] = { val: None, }
  let reg = Registry::{
    handlers: [IntentHandler((_call, answer) => later.val = Some(answer))],
  }
  let tx = @transactor.Transactor::new(tree("none", "none"), intents=reg)
  let _ = tx.push_send(item_at(), "go-lex", [])
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "")
  match later.val {
    Some(answer) => answer(Ok(Str("eventually")))
    None => fail("the handler was never asked")
  }
  tx.settle() |> ignore
  assert_eq(item_seen(tx.root), "ok:RStr(\"eventually\")")
}

///|
test "INTENT_DEPTH cuts a walk that will not end, and the sender is told" {
  // A chain longer than the limit. A real one is a `forward` cycle between two
  // components; this is the same counter reached the cheap way, and it is the
  // exhaustion path that has to run afterwards — a sender that asked for an
  // answer must learn something rather than wait forever.
  let passed : Ref[Int] = { val: 0, }
  let handlers : Array[@transactor.IntentHandler] = []
  for _ in 0..<(@transactor.INTENT_DEPTH + 10) {
    handlers.push(passer(passed))
  }
  let reg = Registry::{ handlers, }
  let refusals : Array[String] = []
  let restore = @tutuca.on_runtime_notice(n => {
    match n {
      Refused(r) => refusals.push(r.code.word() + ":" + r.asked)
      _ => ()
    }
  })
  let tx = @transactor.Transactor::new(tree("none", "none"), intents=reg)
  let _ = tx.push_send(item_at(), "go-answered", [Str("d")])
  tx.settle() |> ignore
  restore()
  // Two of the sixty-four went to the `dyn` leg — Panel and Root — before the
  // scope was asked at all. The limit counts POSITIONS across the whole walk,
  // not frames of one leg, which is the only reading that catches a cycle
  // spanning both.
  assert_eq(passed.val, @transactor.INTENT_DEPTH - 2)
  assert_true(refusals.contains("INTENT_DEPTH:saveDraft"))
  assert_eq(item_seen(tx.root), "unhandled:RStr(\"d\")")
}

///|
test "a sender that declared Ok alone hears about an intent nobody answered" {
  let refusals : Array[String] = []
  let restore = @tutuca.on_runtime_notice(n => {
    match n {
      Refused(r) => refusals.push(r.code.word())
      _ => ()
    }
  })
  let tx = @transactor.Transactor::new(tree("none", "none"))
  let _ = tx.push_send(item_at(), "go-lex", [])
  tx.settle() |> ignore
  restore()
  // `go-lex` declares on_ok_name and nothing else. No answer arrives, and the
  // question does not disappear in silence.
  assert_true(refusals.contains("NO_HANDLER"))
}

///|
test "the sender stays open until the answer has settled" {
  // The sender's tracking unit is held for the whole walk and then handed to
  // the answer's subtree, so the sender stays open until the answer itself has
  // settled. A walk has many hops and at most one answer, so the unit belongs
  // to the walk rather than to any one hop — this is the test that says so.
  let tx = @transactor.Transactor::new(tree("observe", "reply"))
  let sender = tx.push_send(item_at(), "go-answered", [])
  let settled : Ref[Bool] = { val: false, }
  sender.completion().on_subtree_settled(() => settled.val = true)
  tx.settle() |> ignore
  assert_true(settled.val)
  // And the answer really did land, so "settled" is not "gave up".
  assert_eq(item_seen(tx.root), "ok:RStr(\"root:\")")
}

///|
test "a walk nobody answers still lets the sender go" {
  let tx = @transactor.Transactor::new(tree("none", "none"))
  let sender = tx.push_send(item_at(), "go", [])
  let settled : Ref[Bool] = { val: false, }
  sender.completion().on_subtree_settled(() => settled.val = true)
  tx.settle() |> ignore
  assert_true(settled.val)
}
