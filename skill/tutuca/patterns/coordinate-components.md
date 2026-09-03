# Coordinate components

**Problem:** move state between components — tell one component something,
ask for work you can't name a handler for, or run async work and fold in
the result.

The channels are **effects the block spells**: `send`, `sendAt`, `intent
<route>` and `forward`. An effect is queued, not performed — it goes out only
if the whole body finished, because a message sent beside a transition that did
not happen is the one outcome nobody can reason about afterwards.

```html
<script type="tutuca/spec">
  state Status { message: String, count: Int }
  /// The two names a sibling addresses this component by. No view writes
  /// either, so the schema is the only place they can be declared — and
  /// declaring them is what lets the block answer them.
  handle Status {
    message { flash(String), clear
    }
  }

  state Chat { draft: String, status: Status }

  state Log { label: String, log: Array[String] }
  handle Log {
    message { onItemClick
    }
  }
  handle Log {
    intent { itemSelected(String)
    }
  }

  state Feed { items: Array[Any], isLoading: Bool, error: String }
  /// The three `loadData…` names are the ANSWERS. Declaring them is what makes
  /// `intent lex 'loadData'` a request rather than a notification — the
  /// generator reads this list and fills the intent's opts in.
  handle Feed {
    message { init, loadDataOk(Array[Any]), loadDataFailed(String),
                 loadDataUnhandled
    }
  }
</script>

<script type="tutuca/script" for="Status">
  receive flash(m) {
    .message = m
    .count += 1
  }
  receive clear { .message = '' }
</script>

<script type="tutuca/script" for="Log">
  /// Name the JOB, not the target, and let the route find who does it. `dyn`
  /// walks the ancestors, starting at the sender's PARENT.
  receive onItemClick { intent dyn 'itemSelected' .label }

  /// The ancestor that answers. The first `intent` arm that REPLIES ends the
  /// walk; one that only records it is an observer.
  answer itemSelected(label) { .log.insertAt 0 label }
</script>

<script type="tutuca/script" for="Feed">
  /// `lex` walks the IntentFns registered on the SCOPE, not the tree. A bare
  /// `intent` takes `dyn lex`: try the ancestors, then the scope.
  receive init {
    ask lex 'loadData'
    .isLoading = true
  }

  /// Three outcomes, three arms, each with its own shape. There is
  /// deliberately no fourth: a combined payload is one an arm can read the
  /// wrong slot of.
  receive loadDataOk(rows) {
    .items = rows
    .isLoading = false
  }
  receive loadDataFailed(e) {
    .error = e
    .isLoading = false
  }
  receive loadDataUnhandled {
    .error = 'nothing in the scope answers `loadData`'
    .isLoading = false
  }
</script>

<template id="Status"><span @text=".message"></span></template>
<template id="Chat">
  <section>
    <x render=".status"></x>
    <!-- `submit` addresses the SIBLING, which is the one arm below in MoonBit -->
    <input :value=".draft" @on.input="setDraft e.value" @on.keydown+send="submit">
  </section>
</template>
<template id="Log">
  <section>
    <p @text=".label" @on.click="onItemClick"></p>
    <li @each=".log"><x text="@value"></x></li>
  </section>
</template>
<template id="Feed">
  <section>
    <div @show=".isLoading">Loading</div>
    <button @on.click="loadAnotherWay">Load another way</button>
    <li @each=".items"><x text="@value"></x></li>
  </section>
</template>
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
won't use — `intent dyn 'itemSelected' .label` over passing the entire
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
//    block's `intent lex 'loadData'` gets these three filled in from the
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
