// Name lookup from a handler: `ctx.lookup` and `ctx.make` walking the same
// `dyn`/`lex` legs an intent's route names, and `ctx.send_reply` answering the
// sender of a message.
//
// End to end over a real render, because the `dyn` leg has to REBUILD the
// render stack from the ctx: a handler is never handed the one that evaluated
// its arguments, and a `send` transaction never built one at all.
//
// The tree is Board > Slot, and Board publishes ITSELF as `Cell` — shadowing
// the registered `Cell` for its whole subtree, which is the injection the
// `dyn` leg exists for. `Plain > Slot` is the same Slot with nothing published
// above it.

///|
priv struct LkCellState {
  label : String
}

///|
priv struct LkBoardState {
  theme : String
  label : String
}

///|
priv struct LkPlainState {}

///|
priv struct LkSlotState {
  made : String
}

///|
/// One `update` for every route case, so the route is the only thing that
/// differs between them.
fn lk_slot_update() -> (LkSlotState, @component.Dispatch, &@tutuca.Ctx) -> @component.Update[
  LkSlotState,
] {
  fn made(v : @tutuca.Value?) -> String {
    match v {
      Some(inst) =>
        match inst.field("label") {
          Str(s) => s
          _ => "?"
        }
      None => "none"
    }
  }

  fn shown(v : @tutuca.Value) -> String {
    match v {
      Str(s) => s
      Null => "null"
      _ => "?"
    }
  }

  (_s, msg, ctx) => {
    match msg {
      Receive("build", _) =>
        Next({
          made: made(ctx.make("Cell", Map([]), @tutuca.LookupOpts::new())),
        })
      Receive("buildLex", _) =>
        Next({
          made: made(
            ctx.make("Cell", Map([]), @tutuca.LookupOpts::new(route=[Lex])),
          ),
        })
      Receive("buildDyn", _) =>
        Next({
          made: made(
            ctx.make("Cell", Map([]), @tutuca.LookupOpts::new(route=[Dyn])),
          ),
        })
      Receive("buildNone", _) =>
        Next({
          made: made(
            ctx.make("NoSuchThing", Map([]), @tutuca.LookupOpts::new()),
          ),
        })
      Receive("readTheme", _) =>
        Next({ made: shown(ctx.lookup("theme", @tutuca.LookupOpts::new())) })
      Receive("readThemeLex", _) =>
        Next({
          made: shown(ctx.lookup("theme", @tutuca.LookupOpts::new(route=[Lex]))),
        })
      Receive("readThemeEmpty", _) =>
        Next({
          made: shown(ctx.lookup("theme", @tutuca.LookupOpts::new(route=[]))),
        })
      // The reply names itself: a message carries no expectation of an answer,
      // so its sender declared no arms for one.
      Receive("ping", _) => {
        ctx.send_reply("pong", [Str("from-slot")])
        Unchanged
      }
      _ => Unhandled
    }
  }
}

///|
fn lk_scope() -> @component.ComponentStack raise {
  let scope = @component.ComponentStack::new()
  let cell = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<i><x text=\".label\"></x></i>",
      ),
    },
    name="Cell",
    init=LkCellState::{ label: "registered" },
  )
  let slot = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        // One button, so a view's own `@on.*` — which arrives with no sender —
        // is what the NO_SENDER case fires.
        raw_view="<em class=\"made\" @on.click=\"ping\"><x text=\".made\"></x></em>",
      ),
    },
    name="Slot",
    init=LkSlotState::{ made: "" },
    lookup=[@component.lookup_name("Cell"), @component.lookup_name("theme")],
    update=lk_slot_update(),
  )
  let board = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".slot\"></x></div>",
      ),
    },
    name="Board",
    init=LkBoardState::{ theme: "dark", label: "published" },
    provide={ "Cell": "self", "theme": ".theme" },
    update=(s : LkBoardState, msg, ctx) => {
      match msg {
        // Board is the SENDER here, so the reply has somewhere to land.
        Receive("poke", _) => {
          ctx.at().field("slot").send("ping", [])
          Unchanged
        }
        Receive("pong", [Str(who)]) => Next({ ..s, label: "pong:\{who}" })
        _ => Unhandled
      }
    },
  )
  let plain = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render=\".slot\"></x></div>",
      ),
    },
    name="Plain",
    init=LkPlainState::{  },
  )
  scope.register_components([cell, slot, board, plain])
  scope.compile_all()
  scope
}

///|
/// A mounted root of `name`, and a transactor with the app's name resolution
/// wired in — which is what `App::new` does, and what a bare `Transactor::new`
/// deliberately does not.
fn lk_mount(
  scope : @component.ComponentStack,
  name : String,
) -> (@transactor.Transactor, @memdom.MemNode) raise {
  guard scope.lookup_component(name) is Some(c) else { fail("no \{name}") }
  let root = c.make(Map([]))
  let container = mount(scope.comps, root)
  let tx = @transactor.Transactor::new(
    root,
    names=@app.ScopeNames::new(scope.comps),
  )
  (tx, container)
}

///|
/// Send `name` to the Slot and read back what its handler recorded.
fn lk_made(tx : @transactor.Transactor, name : String) -> String {
  let _ = tx.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("slot")]),
    name,
    [],
  )
  tx.settle() |> ignore
  match
    @tutuca.Path::new(steps=[FieldStep("slot"), FieldStep("made")]).lookup(
      tx.root,
    ) {
    Some(Str(s)) => s
    _ => "?"
  }
}

///|
test "ctx.make: the dyn leg finds the publisher, the lex leg the registration" {
  let scope = lk_scope()
  // Under Board, which publishes itself as `Cell`.
  let (tx, _) = lk_mount(scope, "Board")
  assert_eq(lk_made(tx, "build"), "published")
  assert_eq(lk_made(tx, "buildDyn"), "published")
  // The array IS the walk order, and `lex` skips what was published.
  assert_eq(lk_made(tx, "buildLex"), "registered")
}

///|
test "ctx.make: with nothing published, the default route falls through to lex" {
  let scope = lk_scope()
  let (tx, _) = lk_mount(scope, "Plain")
  assert_eq(lk_made(tx, "build"), "registered")
  // `dyn` alone has nothing to answer with, and does not fall back.
  assert_eq(lk_made(tx, "buildDyn"), "none")
}

///|
test "ctx.make: a name nothing answers is TYPE_NOT_FOUND" {
  let scope = lk_scope()
  let (tx, _) = lk_mount(scope, "Board")
  let seen : Array[@tutuca.Refusal] = []
  let off = @tutuca.on_refusal(r => seen.push(r))
  assert_eq(lk_made(tx, "buildNone"), "none")
  off()
  assert_true(seen.length() == 1)
  assert_true(seen[0].code is TypeNotFound && seen[0].asked == "NoSuchThing")
  // The route is carried on the refusal, because "not found" means nothing
  // without saying where it was looked for.
  assert_eq(seen[0].rule, "dyn lex")
}

///|
test "ctx.lookup: a value answers on dyn, never on lex, and never on an empty route" {
  let scope = lk_scope()
  let (tx, _) = lk_mount(scope, "Board")
  assert_eq(lk_made(tx, "readTheme"), "dark")
  // A scope chain holds components, so a value simply misses there. That is
  // what lets ONE default route serve both `lookup` and `make`.
  assert_eq(lk_made(tx, "readThemeLex"), "null")
  // An empty route asks nothing rather than falling back to the default.
  assert_eq(lk_made(tx, "readThemeEmpty"), "null")
}

///|
test "ctx.send_reply answers the sender under a name the replier picks" {
  let scope = lk_scope()
  let (tx, _) = lk_mount(scope, "Board")
  let _ = tx.push_send(@tutuca.DispatchPath::new(), "poke", [])
  tx.settle() |> ignore
  // The reply is an ordinary message: it lands in Board's `receive` bucket and
  // nothing there can tell it from a send.
  match @tutuca.Path::new(steps=[FieldStep("label")]).lookup(tx.root) {
    Some(Str(s)) => assert_eq(s, "pong:from-slot")
    _ => fail("no label")
  }
}

///|
test "ctx.send_reply with nobody waiting refuses NO_SENDER" {
  let scope = lk_scope()
  let (tx, container) = lk_mount(scope, "Board")
  guard find_el(container, "EM") is Some(em) else { fail("no em") }
  let seen : Array[@tutuca.Refusal] = []
  let off = @tutuca.on_refusal(r => seen.push(r))
  // A view's own `@on.click` is a message with no sender, so there is no
  // position to answer at.
  assert_true(@app.dispatch_dom_event(tx, em, "click", container, scope.comps))
  off()
  assert_true(seen.length() == 1)
  assert_true(seen[0].code is NoSender && seen[0].asked == "pong")
  // Nothing was dispatched: Board never heard a `pong`.
  match @tutuca.Path::new(steps=[FieldStep("label")]).lookup(tx.root) {
    Some(Str(s)) => assert_eq(s, "published")
    _ => fail("no label")
  }
}

///|
impl @component.Fields for LkCellState with fn schema() {
  @component.SchemaInfo::new(fingerprint="lk_cell_state", fields=[
    @component.FieldInfo::new("label", TyText),
  ])
}

///|
impl @component.Fields for LkCellState with fn encode(s) {
  { "label": Str(s.label) }
}

///|
impl @component.Fields for LkCellState with fn decode(f) {
  guard f.get("label") is Some(Str(v)) else { return None }
  Some({ label: v })
}

///|
impl @component.Fields for LkBoardState with fn schema() {
  @component.SchemaInfo::new(fingerprint="lk_board_state", fields=[
    @component.FieldInfo::new("theme", TyText),
    @component.FieldInfo::new("label", TyText),
    @component.FieldInfo::new("slot", TyComp(Some("Slot"))),
  ])
}

///|
impl @component.Fields for LkBoardState with fn encode(s) {
  { "theme": Str(s.theme), "label": Str(s.label) }
}

///|
impl @component.Fields for LkBoardState with fn decode(f) {
  guard f.get("theme") is Some(Str(t)) && f.get("label") is Some(Str(l)) else {
    return None
  }
  Some({ theme: t, label: l })
}

///|
impl @component.Fields for LkPlainState with fn schema() {
  @component.SchemaInfo::new(fingerprint="lk_plain_state", fields=[
    @component.FieldInfo::new("slot", TyComp(Some("Slot"))),
  ])
}

///|
impl @component.Fields for LkPlainState with fn encode(_s) {
  Map([])
}

///|
impl @component.Fields for LkPlainState with fn decode(_f) {
  Some(LkPlainState::{  })
}

///|
impl @component.Fields for LkSlotState with fn schema() {
  @component.SchemaInfo::new(fingerprint="lk_slot_state", fields=[
    @component.FieldInfo::new("made", TyText),
  ])
}

///|
impl @component.Fields for LkSlotState with fn encode(s) {
  { "made": Str(s.made) }
}

///|
impl @component.Fields for LkSlotState with fn decode(f) {
  guard f.get("made") is Some(Str(v)) else { return None }
  Some({ made: v })
}
