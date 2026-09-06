# Coordinate components

**Problem:** move state between components — tell one component something,
ask for work you can't name a handler for, or run async work and fold in
the result.

The channels are **effects the block spells**: `send`, `sendAt`, `intent
<route>` and `forward`. An effect is queued, not performed — it goes out only
if the whole body finished, because a message sent beside a transition that did
not happen is the one outcome nobody can reason about afterwards.

```tutu
spec:
  Status:
    field message :: String
    field count :: Int

    message flash(String)

    message clear

  Chat:
    field draft :: String
    field status :: Instance.of(Status)

  Log:
    field label :: String
    field log :: List.of(String)

    message on_item_click

    intent item_selected(String)

  Feed:
    field items :: List.of(Any)
    field is_loading :: Bool
    field error :: String

    message init

    message load_data_ok(List.of(Any))

    message load_data_failed(String)

    message load_data_unhandled

logic:
  Status:
    receive flash(m):
      it.message := m
      it.count += 1

    receive clear:
      it.message := ""

  Log:
    /// Name the JOB, not the target, and let the route find who does it. `dyn`
    /// walks the ancestors, starting at the sender's PARENT.
    receive on_item_click:
      ask("item_selected", it.label, ~route: dyn)

    /// The ancestor that answers. The first `intent` arm that REPLIES ends the
    /// walk; one that only records it is an observer.
    answer item_selected(label):
      it.log.insert_at(0, label)

  Feed:
    /// `lex` walks the IntentFns registered on the SCOPE, not the tree. A bare
    /// `ask` takes `dyn lex`: try the ancestors, then the scope.
    receive init:
      ask("load_data", ~route: lex)
      it.is_loading := true

    /// Three outcomes, three arms, each with its own shape. There is
    /// deliberately no fourth: a combined payload is one an arm can read the
    /// wrong slot of.
    receive load_data_ok(rows):
      it.items := rows
      it.is_loading := false

    receive load_data_failed(e):
      it.error := e
      it.is_loading := false

    receive load_data_unhandled:
      it.error := "nothing in the scope answers `loadData`"
      it.is_loading := false

view:
  Status:
    @span{@(it.message)}

  Chat:
    @section{@render(it.status) @comment{ `submit` addresses the SIBLING, which is the one arm below in MoonBit } @input(~value: it.draft, ~on_input: it.draft := e.value, ~on_keydown: submit ~send)}

  Log:
    @section{@p(~on_click: on_item_click){@(it.label)} @each(value, key in it.log){@li{@(value)}}}

  Feed:
    @section{@show(it.is_loading){@div{Loading}} @button(~on_click: load_another_way){Load another way} @each(value, key in it.items){@li{@(value)}}}
```

Pick by **what you know**: `send` / `receive` when you can name the target,
`intent` when you can only name the job. `send 'name' args` addresses SELF —
two call sites sharing one body — and `sendAt &.status 'flash' .draft`
addresses a position, where `&.status` denotes the place and `.status` would
denote what is there. Every intent ends in exactly one of three named answers
— `<name>Ok`, `<name>Failed`, `<name>Unhandled` — dispatched back to the sender
as ordinary `receive` arms. `<name>Unhandled` means the route ran out with
nobody claiming it, which is a different sentence from a handler failing.

Carry the most granular payload across the channel, not whole objects you
won't use — `ask dyn 'itemSelected' .label` over passing the entire
instance (same reasoning as handler args:
[testing.md](../testing.md) *Designing handlers so tests stay simple*).

**When it stays MoonBit.** Two things here, and `update` gets `ctx` as its
explicit third parameter:

```moonbit nocheck
// nocheck: bucket arguments, not compilable items
// 1. `sendAt` — the block spells it and a card runs it, but `gen` does
//    not emit a position yet, so an addressed send is a MoonBit arm today.
update=(s : ChatState, msg, ctx) => match msg {
  Receive("submit", _) => {
    ctx.at().field("status").send("flash", [Str(s.draft)])
    Unchanged   // this arm answered; nothing further is tried
  }
  _ => Unhandled
},

// 2. An intent naming its OWN answers, which is all `IntentOpts` carries. The
//    block's `ask lex 'loadData'` gets these three filled in from the
//    schema; writing them here is how a sender names its own.
update=(s : FeedState, msg, ctx) => match msg {
  Receive("loadAnotherWay", _) => {
    ctx.intent("loadData", [], @tutuca.IntentOpts::new(
      route=[Lex],
      on_ok_name="loadDataOk",
      on_failed_name="loadDataFailed",
      on_unhandled_name="loadDataUnhandled",
    ))
    Next({ ..s, isLoading: true })
  }
  _ => Unhandled
},
```

An answer that has to build something — turning a response into child
component instances — is MoonBit for the same reason `item.make` always is.
`ctx.at()` addresses by `.field("x")` / `.index(name, i)` / `.key(name, k)`,
default self; the `lex` handlers themselves are `intents={ "loadData": [...] }`
on the `ModuleDef`.

`receive init` is a convention, not a lifecycle hook — dispatch it with
`app.send_at_root("init")`.
