// The starter cards.
//
// Each is a whole component in one file, and each shows one thing the language
// does that a view file alone could not. `build/check-examples.mjs` loads every
// one through the real loader and fails the build if any reports an issue — a
// starter card that does not load is the worst possible first impression, and
// it is exactly the kind of thing that rots as the language moves.
//
// The views are written in **margaui** component classes (`card`, `btn`,
// `input`, `badge`, `join`) rather than in a per-card `<style>` block. The
// shell compiles them: it hands the class names the mounted card publishes to
// `margaui.wasm` and injects the CSS, scoped to the preview pane (see
// `web/margaui.js`). Two reasons it is worth doing here rather than styling
// each card by hand — a starter card is the first thing anyone sees, so it
// should look like something someone would ship; and class lists are the one
// styling route that a `<style>` block cannot demonstrate, since a card's own
// styles are scoped to its view and a utility class is not.
//
// `styles` is the deliberate exception, and it is there because the reverse is
// also true: a class list cannot show what a `<style>` block is FOR — a rule
// scoped to one view, one shared by every view of the component, and one that
// opts out with `data-global`. It uses both routes at once, which is what a
// card that has something of its own to say actually looks like. `drag-reorder`
// is the other, for the two attributes tutuca sets on live nodes.
//
// Write them as LITERAL lists. The collector reads what the views say, so a
// class name assembled at runtime is a class name that never gets compiled —
// which is also why `@if.class` switches between whole literals.
//
// Most of these are MIGRATED from `storybook/examples/` and
// `playground/site/examples/` — the same demos the compiled gallery shows,
// with their `update` arms moved into the block and their MoonBit `compute`
// entries into `compute` declarations. `node tutucard/build/check-examples.mjs`
// runs the real loader over every card that ships; for one that has NOT been
// migrated, `__tutucard.check(source, name)` on its file says what refuses it.
//
// One limit is visible here and is the language's rather than the page's: a
// condition slot still takes `$name` rather than a bare predicate application,
// so `@show="$anyItems"` is how a `pred` is used from a template today.
//
// `todo` is the one card with TWO components: the list and the row, a child
// built at runtime with `new`, and a row that asks the list to drop it with
// `intent dyn` rather than being handed a callback. `nested-state` is the
// other half of what `new` is for — a list of plain RECORDS, where `new Label`
// puts the type's zero at `@cur` and the statements under it fill it in.
//
// Every card fills the sections its structured view can edit WHERE THEY MEAN
// SOMETHING: a `<script type="tutuca/test">` block drives the Tests pane, a
// `<script type="tutuca/init">` block feeds the Examples pane. Two rules keep
// those blocks honest. A card whose init handler overwrites a field reaches a
// different value of it by DRIVING (`drive`) rather than by seeding, because
// mounting seeds the fixture's value first and dispatches init second; and a
// SCENE dispatches nothing, so such a card opens its scenes with
// `{ "send": "init" }`. Cards whose whole point is having no script block
// (tabs, attributes, modifiers) stay scriptless — a test does not undo a
// lesson.

export const EXAMPLES = [
  {
    name: "counter",
    source: `<script type="tutuca/state">
  state Counter {
    label   : String
    count   : Int
    history : Array[Int]
  }
</script>

<script type="tutuca/script">
  /// Move the counter by d, remembering where it landed.
  receive add(d) {
    .count += d
    .history.push .count
  }
  compute summary { $'{.label}: {.count}' }
</script>

<script type="tutuca/init">
{
  "fresh": {
    "doc": "A counter nobody has pressed yet — what a visitor meets.",
    "default": true,
    "value": { "label": "Counter" }
  },
  "with history": {
    "doc": "What three presses leave behind, without pressing three times.",
    "value": { "label": "Demo", "count": 3, "history": [1, 2, 3] }
  },
  "counted up": {
    "doc": "The same three, arrived at by pressing — a fixture can be reached by DOING rather than described.",
    "value": { "label": "Pressed" },
    "drive": [
      { "click": "button.join-item" },
      { "click": "button.join-item" },
      { "click": "button.join-item" }
    ]
  },
  "as a row": {
    "doc": "The same state under the card's other view. Which view to show it as is the one thing a value cannot say about itself.",
    "view": "row",
    "value": { "label": "Compact", "count": 7 }
  }
}
</script>

<script type="tutuca/test">
{
  "pressing remembers where it landed": {
    "steps": [
      { "type": "input.input-sm", "value": "Counter" },
      { "expect": "text", "at": "h2.card-title", "is": "Counter: 0" },
      { "click": "button.join-item" },
      { "click": "button.join-item" },
      { "expect": "text", "at": "h2.card-title", "is": "Counter: 2" },
      { "expect": "texts", "at": "li.badge-neutral", "is": ["1", "2"] }
    ]
  },
  "reset zeroes the count and keeps the history": {
    "steps": [
      { "type": "input.input-sm", "value": "Counter" },
      { "click": "button.join-item" },
      { "click": "button.join-item" },
      { "click": "button.btn-ghost" },
      { "expect": "text", "at": "h2.card-title", "is": "Counter: 0" },
      { "expect": "state", "at": ".history", "is": [1, 2] }
    ]
  },
  "renaming relabels the summary": {
    "steps": [
      { "type": "input.input-sm", "value": "Renamed" },
      { "expect": "state", "at": ".label", "is": "Renamed" },
      { "expect": "text", "at": "h2.card-title", "is": "Renamed: 0" }
    ]
  }
}
</script>

<template id="Counter">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title"><x text="$summary"></x></h2>
      <div class="join">
        <button class="btn btn-sm join-item" @on.click="add 1">+1</button>
        <button class="btn btn-sm join-item" @on.click="add -1">-1</button>
        <button class="btn btn-sm join-item btn-ghost" @on.click="resetCount">reset</button>
      </div>
      <label class="flex gap-2 items-center">
        <span class="opacity-70">label</span>
        <input class="input input-sm w-full" :value=".label" @on.input="setLabel e.value">
      </label>
      <ul class="flex gap-1 flex-wrap">
        <li class="badge badge-sm badge-neutral" @each=".history"><x text="@value"></x></li>
      </ul>
    </div>
  </div>
</template>

<template id="Counter:row">
  <div class="flex gap-2 items-center">
    <span class="badge badge-neutral"><x text="$summary"></x></span>
    <button class="btn btn-xs" @on.click="add 1">+1</button>
  </div>
</template>
`,
  },
  {
    name: "todo",
    source: `<script type="tutuca/state">
  /// TWO components in one card: the list, and the row beside it. A file may
  /// declare as many as it likes — one \`state\` each, one
  /// \`<script type="tutuca/script" for="…">\` each, one
  /// \`<template id="…:main">\` each — and the FIRST one is what a host mounts
  /// when told no other name. A component that only ever appears inside
  /// another one belongs beside it rather than in a file of its own.
  state Todo {
    draft  : String
    nextId : Int
    items  : Map[String, TodoItem]
  }

  /// A \`Map\` rather than an \`Array\` because a row has to be able to name
  /// ITSELF to the list, and an index stops naming the same row the moment
  /// anything above it is dropped. The key is minted once, at the push, and
  /// the row carries its own copy — so \`removeItem\` means the same thing
  /// whenever it arrives.
  state TodoItem {
    id      : String
    text    : String
    done    : Bool
    editing : Bool
    draft   : String
  }

  /// What a row asks of whoever is above it. \`receive\` is what something
  /// sends here BY ADDRESS; \`intent\` is what reached here because a walk
  /// routed it. Declaring the bucket is the whole of the wiring — nothing
  /// registers a callback and no row holds a reference to the list.
  intent Todo { removeItem(String) }
</script>

<script type="tutuca/script" for="Todo">
  /// Add the draft, unless it is only whitespace.
  ///
  /// \`new TodoItem\` names the SIBLING component and opens an argument map for
  /// it; \`@cur.…\` fills that in, and the child is made at the moment \`@cur\`
  /// is read — which is the \`setAt\`. The key is spelled twice rather than
  /// read back off \`@cur\`, because reading it is what would build the child.
  receive addItem {
    if (trim .draft) is not '' {
      .nextId += 1
      new TodoItem
      @cur.id = $'row-{.nextId}'
      @cur.text = (trim .draft)
      .items.setAt $'row-{.nextId}' @cur
      .draft = ''
    }
  }

  /// The other end of the row's \`intent dyn\`. An \`intent\` arm that changes
  /// state and does not \`reply\` is an OBSERVER and the walk goes on; this one
  /// is the last hop anyway, so there is nothing left to observe it.
  intent removeItem(id) { .items.deleteAt id }

  compute caption { $'{(len .items)} item(s)' }
  compute anyItems { not (empty? .items) }
</script>

<script type="tutuca/script" for="TodoItem">
  receive toggle { .done = not .done }

  /// Double-click the text and the row edits itself: the draft starts as a
  /// copy, so abandoning it costs nothing. Both halves are the row's own
  /// business and the list never hears about them.
  receive startEdit {
    .draft = .text
    .editing = true
  }

  /// Enter commits — unless what is left is only whitespace, in which case the
  /// row keeps what it had.
  receive commitEdit {
    if (trim .draft) is not '' { .text = (trim .draft) }
    .editing = false
  }

  /// Escape throws the draft away.
  receive cancelEdit { .editing = false }

  /// The row does not know the list's shape, or that there IS a list. It names
  /// the JOB and lets the route find who does it: \`dyn\` walks the dispatch
  /// path starting at the sender's PARENT — an intent is never offered to the
  /// component that raised it — and the first hop with a \`removeItem\` arm
  /// answers. Nothing here would change if the row were nested three deep.
  receive requestRemove { intent dyn 'removeItem' .id }

  compute label { if .done { $'{.text} (done)' } else { .text } }
</script>

<script type="tutuca/init">
{
  "empty": {
    "doc": "A list nobody has used yet — what a visitor meets.",
    "default": true,
    "value": {}
  },
  "two rows": {
    "doc": "A list that has been used, arrived at by using it: a row is a CHILD built at runtime with new, and a child is an instance rather than data — so a fixture reaches this state by DOING what a person would have done rather than by writing the items into value.",
    "value": {},
    "drive": [
      { "type": "input.draft", "value": "write the tests" },
      { "click": "button.add" },
      { "type": "input.draft", "value": "ship it" },
      { "click": "button.add" }
    ]
  },
  "one being edited": {
    "doc": "Mid-edit, which no amount of seeded state says better than the double-click that gets there.",
    "value": {},
    "drive": [
      { "type": "input.draft", "value": "review the diff" },
      { "click": "button.add" },
      { "fire": "span.label", "event": "dblclick" }
    ]
  }
}
</script>

<script type="tutuca/test">
{
  "adding makes rows": {
    "steps": [
      { "type": "input.draft", "value": "write it" },
      { "click": "button.add" },
      { "type": "input.draft", "value": "ship it" },
      { "click": "button.add" },
      { "expect": "texts", "at": "span.label", "is": ["write it", "ship it"] },
      { "expect": "text", "at": "span.tally", "is": "2 item(s)" }
    ]
  },
  "a row asks the list to drop it": {
    "steps": [
      { "type": "input.draft", "value": "one" },
      { "click": "button.add" },
      { "type": "input.draft", "value": "two" },
      { "click": "button.add" },
      { "click": "button.remove" },
      { "expect": "texts", "at": "span.label", "is": ["two"] },
      { "expect": "text", "at": "span.tally", "is": "1 item(s)" }
    ]
  },
  "double-click edits the text": {
    "steps": [
      { "type": "input.draft", "value": "wrng" },
      { "click": "button.add" },
      { "expect": "count", "at": "input.edit", "is": 0 },
      { "fire": "span.label", "event": "dblclick" },
      { "expect": "count", "at": "input.edit", "is": 1 },
      { "type": "input.edit", "value": "right" },
      { "key": "input.edit", "is": "Enter" },
      { "expect": "texts", "at": "span.label", "is": ["right"] },
      { "expect": "count", "at": "input.edit", "is": 0 }
    ]
  },
  "escape leaves the text alone": {
    "steps": [
      { "type": "input.draft", "value": "keep" },
      { "click": "button.add" },
      { "fire": "span.label", "event": "dblclick" },
      { "type": "input.edit", "value": "nope" },
      { "key": "input.edit", "is": "Escape" },
      { "expect": "texts", "at": "span.label", "is": ["keep"] }
    ]
  },
  "a row strikes itself through": {
    "steps": [
      { "type": "input.draft", "value": "a" },
      { "click": "button.add" },
      { "click": "input.check" },
      { "expect": "texts", "at": "span.label", "is": ["a (done)"] }
    ]
  }
}
</script>

<template id="Todo:main">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title">Todos</h2>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full draft" placeholder="what needs doing"
               :value=".draft" @on.input="setDraft e.value"
               @on.keydown+send="addItem">
        <button class="btn btn-sm btn-primary add" @on.click="addItem">add</button>
      </div>
      <!-- \`<x render-each>\` renders each item as a component in its own right,
           with its own state and its own handlers — where \`@each\` would render
           a value with THIS component's. -->
      <ul class="flex flex-col gap-2" @show="$anyItems"><x render-each=".items"></x></ul>
      <p class="opacity-60 italic" @hide="$anyItems">nothing yet</p>
      <span class="badge badge-sm badge-neutral tally"><x text="$caption"></x></span>
    </div>
  </div>
</template>

<template id="TodoItem:main">
  <li class="flex gap-3 items-center w-full">
    <input type="checkbox" class="checkbox checkbox-sm check" @on.click="toggle">
    <span class="w-full label" @hide=".editing" @text="$label"
          @on.dblclick="startEdit"></span>
    <input class="input input-xs w-full edit" @show=".editing"
           :value=".draft" @on.input="setDraft e.value"
           @on.keydown+send="commitEdit" @on.keydown+cancel="cancelEdit">
    <button class="btn btn-xs btn-soft btn-error btn-circle remove"
            @on.click="requestRemove">&times;</button>
  </li>
</template>
`,
  },
  {
    name: "filter",
    source: `<script type="tutuca/state">
  state Filter {
    query : String
    names : Array[String]
  }

  /// The views never write init: the host dispatches it at mount, which
  /// is the only way a card starts anywhere but the schema's zero.
  receive Filter { init }
</script>

<script type="tutuca/script">
  receive init {
    .names.push 'Ada Lovelace'
    .names.push 'Grace Hopper'
    .names.push 'Alan Turing'
    .names.push 'Barbara Liskov'
  }

  /// A row survives when the query is empty or its text contains it.
  /// Case-folded on both sides, so the filter is not a spelling test.
  ///
  /// @when takes this bare, because an iteration filter has always been
  /// a name — which is why the predicates design could absorb "when" into
  /// "pred" without changing a single call site.
  pred matches {
    (empty? .query) or (contains (lower @value) (lower .query))
  }
  compute caption { $'{(len .names)} name(s)' }
</script>

<script type="tutuca/init">
{
  "the whole list": {
    "doc": "An empty query keeps every row — the init handler fills the names, and the fixture only has to say what the box holds.",
    "default": true,
    "value": {}
  },
  "narrowed to gr": {
    "doc": "The same four names behind a query: the fixture seeds the query and the init handler still fills the list, because mounting dispatches init after the value is seeded.",
    "value": { "query": "gr" }
  }
}
</script>

<script type="tutuca/test">
{
  "typing narrows the list": {
    "steps": [
      { "send": "init" },
      { "expect": "count", "at": "li.badge-ghost", "is": 4 },
      { "expect": "text", "at": "span.badge-neutral", "is": "4 name(s)" },
      { "type": "input.input-sm", "value": "gr" },
      { "expect": "texts", "at": "li.badge-ghost", "is": ["Grace Hopper"] },
      { "expect": "text", "at": "span.badge-neutral", "is": "4 name(s)" },
      { "type": "input.input-sm", "value": "" },
      { "expect": "count", "at": "li.badge-ghost", "is": 4 }
    ]
  },
  "matching is case-folded on both sides": {
    "steps": [
      { "send": "init" },
      { "type": "input.input-sm", "value": "HOPPER" },
      { "expect": "texts", "at": "li.badge-ghost", "is": ["Grace Hopper"] }
    ]
  }
}
</script>

<template id="Filter">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full" placeholder="filter"
               :value=".query" @on.input="setQuery e.value">
        <span class="badge badge-sm badge-neutral"><x text="$caption"></x></span>
      </div>
      <ul class="flex flex-col gap-1">
        <li class="badge badge-ghost w-full justify-start"
            @each=".names" @when="matches"><x text="@value"></x></li>
      </ul>
    </div>
  </div>
</template>
`,
  },
  {
    name: "messages",
    source: `<script type="tutuca/state">
  state Inbox {
    status : String
    seen   : Int
  }

  /// The views never write these names, so the schema is the only place
  /// they can be declared — and the only place their payloads can be typed.
  receive Inbox { note(String), bump(Int) }
</script>

<script type="tutuca/script">
  receive note(text) {
    .status = text
    .seen += 1
  }
  receive bump(by) { .seen += by }

  /// A handler that raises one at itself. The dispatch goes through the
  /// transactor exactly as a parent's would, which is what the Activity panel
  /// beside this is showing.
  receive shout { send 'note' 'shouted' }
  receive quiet { send 'note' 'quiet' }
  receive five { send 'bump' 5 }
</script>

<script type="tutuca/init">
{
  "quiet start": {
    "doc": "No headline and an empty tally — what the schema's zero looks like.",
    "default": true,
    "value": {}
  },
  "a few notes in": {
    "doc": "The same card after some traffic, without driving it there.",
    "value": { "status": "hello", "seen": 3 }
  }
}
</script>

<script type="tutuca/test">
{
  "a note updates the headline and the tally": {
    "steps": [
      { "expect": "text", "at": "h2.card-title", "is": "" },
      { "click": "button.join-item" },
      { "expect": "text", "at": "h2.card-title", "is": "shouted" },
      { "expect": "state", "at": ".seen", "is": 1 },
      { "click": "button.btn-primary" },
      { "expect": "state", "at": ".seen", "is": 6 },
      { "expect": "text", "at": "span.badge-primary", "is": "6" }
    ]
  }
}
</script>

<template id="Inbox">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title"><x text=".status"></x></h2>
      <p class="flex gap-2 items-center">
        <span class="opacity-70">seen</span>
        <span class="badge badge-sm badge-primary"><x text=".seen"></x></span>
      </p>
      <div class="join">
        <button class="btn btn-sm join-item" @on.click="shout">shout</button>
        <button class="btn btn-sm join-item" @on.click="quiet">quiet</button>
        <button class="btn btn-sm join-item btn-primary" @on.click="five">bump 5</button>
      </div>
    </div>
  </div>
</template>
`,
  },
  {
    name: "intents",
    source: `<script type="tutuca/state">
  state Feed {
    rows   : Array[Any]
    query  : String
    echoed : String
    error  : String
    busy   : Bool
  }

  /// The ANSWERS live here, with every other message, because an answer IS a
  /// message: it arrives in the same bucket a parent's would and a handler
  /// cannot tell the difference. Declaring them is what makes \`rows\` a
  /// request rather than a notification — a sender expects an answer if and
  /// only if it declares an arm for one, and nobody writes that down twice.
  ///
  /// Three outcomes, three arms, each with its own shape. \`Any\` on the
  /// payloads, because what a host produces is the host's business rather
  /// than the schema's.
  receive Feed {
    init
    rowsOk(Any)
    rowsError(Any)
    rowsUnhandled
    echoOk(Any)
    echoError(Any)
    echoUnhandled
  }
</script>

<script type="tutuca/script">
  /// \`intent\` hands a NAME to a ROUTE, and whatever is on that route answers
  /// whenever it can. \`lex\` is the leg that searches the handlers registered
  /// on the host — what v1 of this framework spelled \`request\`, before the
  /// verb stopped deciding which scope answers.
  ///
  /// It is an EFFECT, so it goes out only if the whole transition finished — a
  /// card never asks for something on the strength of a state it did not reach.
  ///
  /// This page answers two names late and out of a fixture, which is what a
  /// playground can honestly offer; a page with a real fetch registers the
  /// same names against it and the card does not change.
  receive init {
    intent lex 'rows'
    .busy = true
  }

  receive reload {
    intent lex 'rows'
    .busy = true
    .error = ''
  }

  /// Whatever follows the name is the PAYLOAD. \`echo\` answers with the first
  /// thing it was handed, so what comes back is what went out.
  receive echoQuery {
    intent lex 'echo' .query
    .busy = true
  }

  /// The third outcome, with nothing mocked: this name is on no route, so the
  /// walk runs out and nobody answered. Not a crash, and — the part v1 could
  /// not say — not a failure either.
  receive breakIt {
    intent lex 'nothingAnswersThis'
    .busy = true
    .error = ''
  }

  /// One arm per outcome, and each gets only what it is about. v1 sent one
  /// payload carrying BOTH a result and an error, exactly one of which was
  /// Null, and every arm began by working out which. The branch is gone with
  /// the pair.
  receive rowsOk(res) {
    .busy = false
    .rows = res
  }

  receive rowsError(err) {
    .busy = false
    .error = str err
  }

  receive rowsUnhandled {
    .busy = false
    .error = 'nothing on this page answers \`rows\`'
  }

  receive echoOk(res) {
    .busy = false
    .echoed = str res
  }

  receive echoError(err) {
    .busy = false
    .error = str err
  }

  receive echoUnhandled {
    .busy = false
    .error = 'nothing on this page answers \`echo\`'
  }
</script>

<script type="tutuca/init">
{
  "fresh": {
    "doc": "Nothing asked yet. The page answers rows LATE, so the preview shows its own asking state for half a beat before the rows land.",
    "default": true,
    "value": {}
  },
  "a feed that travels with the card": {
    "doc": "A fixture may carry its own intent ANSWERS, which beats both the clock and whatever the page registers — so this card loads filled wherever it runs, page fixtures or none.",
    "value": {},
    "intents": {
      "rows": {
        "ok": [
          { "title": "Tutuca", "description": "A SPA framework that fits in your head" },
          { "title": "MoonBit", "description": "The language this port is written in" }
        ]
      }
    }
  }
}
</script>

<script type="tutuca/test">
{
  "the answer fills the list": {
    "intents": {
      "rows": {
        "ok": [
          { "title": "Tutuca", "description": "A SPA framework that fits in your head" },
          { "title": "MoonBit", "description": "The language this port is written in" }
        ]
      }
    },
    "steps": [
      { "send": "reload" },
      { "expect": "count", "at": "li.rounded", "is": 2 },
      { "expect": "texts", "at": "p.font-bold", "is": ["Tutuca", "MoonBit"] },
      { "expect": "count", "at": "div.alert-error", "is": 0 }
    ]
  },
  "echo hands the payload back": {
    "intents": { "echo": { "ok": 41 } },
    "steps": [
      { "type": "input.input-sm", "value": "hello" },
      { "key": "input.input-sm", "is": "Enter" },
      { "expect": "text", "at": "p.badge", "is": "41" }
    ]
  },
  "an unanswered name is silence, not a crash": {
    "steps": [
      { "expect": "count", "at": "div.alert-error", "is": 0 },
      { "click": "button.btn-error" },
      { "expect": "count", "at": "div.alert-error", "is": 0 },
      { "expect": "text", "at": "p.opacity-60", "is": "asking the host…" }
    ]
  }
}
</script>

<template id="Feed">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <p class="opacity-60 italic" @show=".busy">asking the host…</p>
      <div class="alert alert-error" @hide="empty? .error">
        <span class="font-mono text-sm"><x text=".error"></x></span>
      </div>
      <ul class="flex flex-col gap-1" @hide=".busy">
        <li class="rounded bg-base-100 p-2" @each=".rows">
          <p class="font-bold"><x text="@value.title"></x></p>
          <p class="text-sm opacity-70"><x text="@value.description"></x></p>
        </li>
      </ul>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full" placeholder="say something"
               :value=".query" @on.input="setQuery e.value"
               @on.keydown+send="echoQuery">
        <button class="btn btn-sm" @on.click="echoQuery">echo it</button>
      </div>
      <p class="badge badge-sm badge-neutral" @hide="empty? .echoed">
        <x text=".echoed"></x>
      </p>
      <div class="join">
        <button class="btn btn-sm btn-primary join-item" @on.click="reload">reload</button>
        <button class="btn btn-sm btn-soft btn-error join-item" @on.click="breakIt">break it</button>
      </div>
    </div>
  </div>
</template>
`,
  },
  {
    name: "traffic-light",
    source: `<script type="tutuca/state">
  state TrafficLight {
    lightIndex : Int
  }
</script>

<script type="tutuca/script">
  /// Step to the next colour, wrapping at the end of the cycle.
  receive nextLight {
    .lightIndex = (.lightIndex + 1) mod 3
  }

  /// The colour is DERIVED, never stored. In MoonBit this indexed an array
  /// of names; the value language has no array literal, so the same mapping
  /// is nested ifs — which is the whole of what changed in the migration.
  compute light {
    if .lightIndex is 0 {
      'red'
    } else {
      if .lightIndex is 1 { 'orange' } else { 'green' }
    }
  }
</script>

<script type="tutuca/init">
{
  "fresh": {
    "doc": "Red, where every cycle starts.",
    "default": true,
    "value": {}
  },
  "mid-cycle": {
    "doc": "One press in.",
    "value": { "lightIndex": 1 }
  },
  "green means go": {
    "doc": "The last colour before the cycle wraps.",
    "value": { "lightIndex": 2 }
  }
}
</script>

<script type="tutuca/test">
{
  "it cycles and wraps": {
    "steps": [
      { "expect": "text", "at": "code", "is": "red" },
      { "click": "button.btn-primary" },
      { "expect": "text", "at": "code", "is": "orange" },
      { "click": "button.btn-primary" },
      { "expect": "text", "at": "code", "is": "green" },
      { "expect": "text", "at": "span", "is": "GO" },
      { "click": "button.btn-primary" },
      { "expect": "text", "at": "code", "is": "red" }
    ]
  },
  "the advice follows the light": {
    "steps": [
      { "expect": "text", "at": "span", "is": "STOP" },
      { "expect": "count", "at": "span", "is": 1 },
      { "click": "button.btn-primary" },
      { "expect": "text", "at": "span", "is": "SLOW DOWN" }
    ]
  }
}
</script>

<template id="TrafficLight">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-2">
      <button class="btn btn-primary" @on.click="nextLight">Next light</button>
      <p>Light is: <code @text="$light"></code></p>
      <p class="advice">
        You must
        <span @show="equals? $light 'red'">STOP</span>
        <span @show="equals? $light 'orange'">SLOW DOWN</span>
        <span @show="equals? $light 'green'">GO</span>
      </p>
    </div>
  </section>
</template>
`,
  },
  {
    name: "tabs",
    source: `<script type="tutuca/state">
  state TabbedUI {
    tab : String
  }
</script>

<script type="tutuca/init">
{
  "overview open": {
    "doc": "The schema's zero is the empty string, under which NO panel shows — a fixture is how a card starts somewhere a visitor can read.",
    "default": true,
    "value": { "tab": "overview" }
  },
  "pricing open": {
    "doc": "The same component, one field apart.",
    "value": { "tab": "pricing" }
  }
}
</script>

<script type="tutuca/test">
{
  "a tab switches the panel": {
    "steps": [
      { "expect": "count", "at": "div.p-3", "is": 0 },
      { "click": "button.tab", "nth": 1 },
      { "expect": "text", "at": "h4", "is": "Features" },
      { "expect": "count", "at": "div.p-3", "is": 1 },
      { "expect": "attr", "at": "button.tab", "nth": 1, "name": "class", "is": "tab tab-active" },
      { "expect": "attr", "at": "button.tab", "nth": 0, "name": "class", "is": "tab" },
      { "click": "button.tab", "nth": 2 },
      { "expect": "text", "at": "h4", "is": "Pricing" }
    ]
  }
}
</script>

<template id="TabbedUI">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <div role="tablist" class="tabs tabs-border">
        <button role="tab"
          @if.class="equals? .tab 'overview'" @then="'tab tab-active'" @else="'tab'"
          @on.click="setTab 'overview'">Overview</button>
        <button role="tab"
          @if.class="equals? .tab 'features'" @then="'tab tab-active'" @else="'tab'"
          @on.click="setTab 'features'">Features</button>
        <button role="tab"
          @if.class="equals? .tab 'pricing'" @then="'tab tab-active'" @else="'tab'"
          @on.click="setTab 'pricing'">Pricing</button>
      </div>
      <div class="p-3" @show="equals? .tab 'overview'">
        <h4>Overview</h4><p>A short summary of what this product does.</p>
      </div>
      <div class="p-3" @show="equals? .tab 'features'">
        <h4>Features</h4><p>The list of features lives on this tab.</p>
      </div>
      <div class="p-3" @show="equals? .tab 'pricing'">
        <h4>Pricing</h4><p>What it costs.</p>
      </div>
    </div>
  </section>
</template>
`,
  },
  {
    name: "show-hide",
    source: `<script type="tutuca/state">
  state ShowHide {
    isOpen : Bool
    count  : Int
  }
</script>

<script type="tutuca/script">
  /// The panel's own counter. \`toggleIsOpen\` is not here because it is not
  /// written anywhere: a Bool field generates its own toggle.
  receive incCount {
    .count += 1
  }

  compute label {
    if .isOpen { 'Hide details' } else { 'Show details' }
  }
</script>

<script type="tutuca/init">
{
  "closed": {
    "doc": "The panel absent and the button making its offer.",
    "default": true,
    "value": {}
  },
  "open with history": {
    "doc": "Open, with a count that survived the closing it never had — both fields in one fixture.",
    "value": { "isOpen": true, "count": 4 }
  }
}
</script>

<script type="tutuca/test">
{
  "the panel is only there while it is open": {
    "steps": [
      { "expect": "text", "at": "button.btn-primary", "is": "Show details" },
      { "expect": "count", "at": "div.p-3", "is": 0 },
      { "click": "button.btn-primary" },
      { "expect": "text", "at": "button.btn-primary", "is": "Hide details" },
      { "expect": "count", "at": "div.p-3", "is": 1 }
    ]
  },
  "the counter keeps counting across a close": {
    "steps": [
      { "click": "button.btn-primary" },
      { "click": "button.btn-sm" },
      { "click": "button.btn-sm" },
      { "expect": "state", "at": ".count", "is": 2 },
      { "click": "button.btn-primary" },
      { "expect": "count", "at": "div.p-3", "is": 0 },
      { "expect": "state", "at": ".count", "is": 2 }
    ]
  }
}
</script>

<template id="ShowHide">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-2">
      <button class="btn btn-primary" @on.click="toggleIsOpen" @text="$label"></button>
      <div class="p-3" @show=".isOpen">
        <p>Details panel — only visible when <code>isOpen</code> is true.</p>
        <button class="btn btn-sm" @on.click="incCount">Click me</button>
        <p>Clicked <x text=".count"></x> times.</p>
      </div>
      <p class="opacity-60" @hide=".isOpen">(details are hidden)</p>
      <p>Count, only when open: <x text=".count" @show=".isOpen"></x></p>
    </div>
  </section>
</template>
`,
  },
  {
    name: "attributes",
    source: `<script type="tutuca/state">
  state AttributeBinding {
    str  : String
    num  : Int
    bool : Bool
  }
</script>

<script type="tutuca/init">
{
  "blank": {
    "doc": "Every field at its zero — the inputs and the readouts agree, because both are the same state.",
    "default": true,
    "value": {}
  },
  "half filled": {
    "doc": "One fixture showing all three bindings at once.",
    "value": { "str": "tutuca", "num": 5, "bool": true }
  }
}
</script>

<script type="tutuca/test">
{
  "every binding writes straight through": {
    "steps": [
      { "type": "input.input-sm", "nth": 0, "value": "hey" },
      { "expect": "state", "at": ".str", "is": "hey" },
      { "expect": "attr", "at": "input.input-sm", "nth": 0, "name": "title", "is": "Content is hey" },
      { "type": "input.input-sm", "nth": 1, "value": "7" },
      { "expect": "state", "at": ".num", "is": 7 },
      { "check": "input.checkbox", "is": true },
      { "expect": "state", "at": ".bool", "is": true }
    ]
  }
}
</script>

<template id="AttributeBinding">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input class="input input-sm" :value=".str" @on.input="setStr e.value"
             :title="$'Content is {.str}'">
      <!-- \`valueAsInt\` rather than a handler that parses the string: the
           argument names are where a card does its conversions. -->
      <input class="input input-sm" type="number" :value=".num"
             @on.input="setNum e.valueAsInt">
      <label class="flex gap-2 items-center">
        <input class="checkbox checkbox-sm" type="checkbox" :checked=".bool"
               @on.input="setBool e.value">
        bool
      </label>
      <p>String: <span @text=".str"></span></p>
      <p>Number: <span @text=".num"></span></p>
      <p>Boolean: <span @text=".bool"></span></p>
    </div>
  </section>
</template>
`,
  },
  {
    name: "modifiers",
    source: `<script type="tutuca/state">
  state EventModifiers {
    query          : String
    lastSentSearch : Any
  }
</script>

<script type="tutuca/init">
{
  "blank": {
    "doc": "Nothing typed and nothing sent.",
    "default": true,
    "value": {}
  },
  "a sent search": {
    "doc": "The paragraph a +send keydown reveals — seeded, since Any is the one field a fixture may fill with anything.",
    "value": { "lastSentSearch": "shoes" }
  }
}
</script>

<script type="tutuca/test">
{
  "enter sends what the box holds": {
    "steps": [
      { "expect": "count", "at": "span.sent", "is": 0 },
      { "type": "input.input-sm", "value": "shoes" },
      { "key": "input.input-sm", "is": "Enter", "value": "shoes" },
      { "expect": "text", "at": "span.sent", "is": "shoes" },
      { "expect": "state", "at": ".query", "is": "shoes" }
    ]
  },
  "escape clears the box and leaves the sent value alone": {
    "steps": [
      { "type": "input.input-sm", "value": "shoes" },
      { "key": "input.input-sm", "is": "Enter", "value": "shoes" },
      { "key": "input.input-sm", "is": "Escape" },
      { "expect": "state", "at": ".query", "is": "" },
      { "expect": "state", "at": ".lastSentSearch", "is": "shoes" }
    ]
  }
}
</script>

<template id="EventModifiers">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <!-- Three handlers, no script block: every one of them is a mutator the
           schema generated. The modifiers are guards — +send is Enter,
           +cancel is Escape. -->
      <input type="search" class="input input-sm" :value=".query"
        @on.input="setQuery e.value"
        @on.keydown+send="setLastSentSearch e.value"
        @on.keydown+cancel="resetQuery"
        placeholder="Search (Enter to send, Esc to clear)">
      <p @show="truthy? .lastSentSearch">
        Search: "<span class="sent" @text=".lastSentSearch"></span>"
      </p>
    </div>
  </section>
</template>
`,
  },
  {
    name: "file-picker",
    source: `<script type="tutuca/state">
  state FilePicker {
    name    : String
    size    : Double
    type    : String
    hasFile : Bool
  }
</script>

<script type="tutuca/script">
  /// A change on a file input hands the handler the WHOLE file — an Obj with
  /// \`name\`, \`size\` and \`type\` on it — so the handler reads a place rooted at
  /// its own parameter. The steps below \`f\` are the steps \`.field\` takes, and
  /// what tells \`f.name\` from \`f .name\` is attachment, the rule already in
  /// force for \`min .a .b\` against \`min .a.b\`.
  ///
  /// One way only: an argument is a value the caller handed over rather than a
  /// position this component owns, so \`f.name = 'x'\` is refused by the parser.
  receive pick(f) {
    if (null? f) {
      .hasFile = false
    } else {
      .name = f.name
      .size = f.size
      .type = f.type
      .hasFile = true
    }
  }

  /// The browser answers '' for a file whose type it cannot name, which is a
  /// word worth saying rather than an empty cell.
  compute typeLabel { if (empty? .type) { 'unknown' } else { .type } }

  /// \`size\` is a Double because that is what the event carries; \`int\` is how a
  /// card asks for the reading rather than the storage.
  compute sizeLabel { $'{(int .size)} bytes' }
</script>

<script type="tutuca/init">
{
  "nothing yet": {
    "doc": "The empty state the card is honest about.",
    "default": true,
    "value": {}
  },
  "a picked file": {
    "doc": "The table filled in — what pick(f) copied off the file. A file input itself cannot be driven headless, so this is also how a scene starts when it wants the table.",
    "value": { "name": "photo.png", "size": 20480, "type": "image/png", "hasFile": true }
  }
}
</script>

<template id="FilePicker">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <label class="flex flex-col gap-1">
        <span class="text-sm opacity-70">Pick a file</span>
        <input type="file" class="file-input file-input-sm" @on.change="pick e.value">
      </label>
      <table class="table" @show=".hasFile">
        <tbody>
          <tr><th>Name</th><td><x text=".name"></x></td></tr>
          <tr><th>Size</th><td><x text="$sizeLabel"></x></td></tr>
          <tr><th>Type</th><td><x text="$typeLabel"></x></td></tr>
        </tbody>
      </table>
      <p class="opacity-70" @hide=".hasFile">Nothing picked yet.</p>
    </div>
  </div>
</template>
`,
  },
  {
    name: "scope",
    source: `<script type="tutuca/state">
  state RenderWithScope {
    text : String
  }

  receive RenderWithScope { init }
</script>

<script type="tutuca/script">
  receive init { .text = 'Hello' }

  /// A scope enricher: handed no row, it answers the bindings the subtree
  /// below reads as \`@len\` and \`@upper\`.
  enrichScope info {
    @len = len .text
    @upper = upper .text
  }
</script>

<script type="tutuca/init">
{
  "fresh": {
    "doc": "Hello, as the init handler spells it — and the two bindings its enricher derives.",
    "default": true,
    "value": {}
  },
  "typed longer": {
    "doc": "Reached by DOING rather than seeded: the init handler would overwrite a value's text, so a fixture that wants different text drives the box.",
    "value": {},
    "drive": [{ "type": "input.input-sm", "value": "tutuca" }]
  }
}
</script>

<script type="tutuca/test">
{
  "the subtree reads what the enricher wrote": {
    "steps": [
      { "send": "init" },
      { "expect": "text", "at": "span.len", "is": "5" },
      { "expect": "text", "at": "span.upper", "is": "HELLO" },
      { "type": "input.input-sm", "value": "tutuca" },
      { "expect": "text", "at": "span.len", "is": "6" },
      { "expect": "text", "at": "span.upper", "is": "TUTUCA" }
    ]
  }
}
</script>

<template id="RenderWithScope">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input class="input input-sm" :value=".text" @on.input="setText e.value">
      <div @enrich-with="info">
        <p>Text: <span @text=".text"></span></p>
        <p>Len: <span class="len" @text="@len"></span></p>
        <p>Upper: <span class="upper" @text="@upper"></span></p>
      </div>
    </div>
  </section>
</template>
`,
  },
  {
    name: "dynamic-bindings",
    source: `<script type="tutuca/state">
  state Palette {
    theme : String
    draft : String
    swatches : Array[Swatch]

    /// Published to everything below, and re-evaluated every render: change
    /// \`.theme\` and every swatch reads the new value, with nothing threaded
    /// through it and no message sent.
    provide { theme = .theme }
  }

  state Swatch {
    label : String

    /// What it ASKS FOR, not who supplies it. The default is what it reads
    /// when nothing above provides one.
    lookup { theme = 'slate' }
  }

  receive Palette { init }
</script>

<script type="tutuca/script" for="Palette">
  receive init {
    .theme = 'rose'
    new Swatch
    @cur.label = 'first'
    .swatches.push @cur
    new Swatch
    @cur.label = 'second'
    .swatches.push @cur
  }

  receive setDraft(t) { .draft = t }

  receive setTheme(t) { .theme = t }

  receive add requires typed {
    new Swatch
    @cur.label = .draft
    .swatches.push @cur
    .draft = ''
  }

  pred typed format $'nothing to add' { not (empty? .draft) }
</script>

<script type="tutuca/init">
{
  "two swatches": {
    "doc": "A theme the rows read, and two rows reading it.",
    "default": true,
    "value": {},
    "drive": [{ "send": "init" }]
  }
}
</script>

<script type="tutuca/test">
{
  "every swatch reads the theme, and follows it": {
    "steps": [
      { "send": "init" },
      { "expect": "texts", "at": "span.theme", "is": ["rose", "rose"] },
      { "type": "input.theme", "value": "amber" },
      { "expect": "texts", "at": "span.theme", "is": ["amber", "amber"] }
    ]
  },
  "a swatch with nothing above it reads its default": {
    "component": "Swatch",
    "args": { "label": "alone" },
    "steps": [{ "expect": "text", "at": "span.theme", "is": "slate" }]
  }
}
</script>

<template id="Palette">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <label class="text-sm opacity-70">Theme, provided to the whole subtree</label>
      <input class="theme input input-sm" :value=".theme" @on.input="setTheme e.value">
      <div class="flex gap-2">
        <input class="draft input input-sm flex-1" :value=".draft" @on.input="setDraft e.value">
        <button class="btn btn-sm" @on.click="add">add</button>
      </div>
      <ul class="flex flex-col gap-1"><x render-each=".swatches"></x></ul>
    </div>
  </section>
</template>

<template id="Swatch">
  <li class="row flex gap-2">
    <span class="label font-medium" @text=".label"></span>
    <span class="theme badge badge-sm" @text="*theme"></span>
  </li>
</template>
`,
  },
  {
    name: "list-enrich",
    source: `<script type="tutuca/state">
  state ListFilterEnrich {
    items : Array[String]
    query : String
  }

  receive ListFilterEnrich { init }
</script>

<script type="tutuca/script">
  receive init {
    .items.push 'alpha'
    .items.push 'beta'
    .items.push 'gamma'
    .items.push 'delta'
  }

  /// The loop asks the block twice per row: once whether to keep it, once
  /// for what the template cannot work out on its own.
  pred filterItem {
    contains (lower @value) (lower .query)
  }

  enrich enrichItem {
    @count = len @value
  }
</script>

<script type="tutuca/init">
{
  "all four": {
    "doc": "The init handler fills the list; the empty query keeps every row.",
    "default": true,
    "value": {}
  },
  "narrowed to ga": {
    "doc": "The same four behind a query — the fixture seeds only what the person would have typed.",
    "value": { "query": "ga" }
  }
}
</script>

<script type="tutuca/test">
{
  "the loop asks the block twice per row": {
    "steps": [
      { "send": "init" },
      { "expect": "count", "at": "li", "is": 4 },
      { "expect": "text", "at": "li", "nth": 0, "contains": "alpha (5 characters)" },
      { "type": "input.input-sm", "value": "ga" },
      { "expect": "count", "at": "li", "is": 1 },
      { "expect": "text", "at": "li", "contains": "gamma (5 characters)" }
    ]
  }
}
</script>

<template id="ListFilterEnrich">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input type="search" class="input input-sm" :value=".query"
        @on.input="setQuery e.value" @on.keydown+cancel="resetQuery"
        placeholder="Filter entries">
      <ul class="flex flex-col gap-1">
        <li @each=".items" @when="filterItem" @enrich-with="enrichItem">
          <span @text="@key"></span>: <x text="@value"></x>
          (<x text="@count"></x> characters)
        </li>
      </ul>
    </div>
  </section>
</template>
`,
  },
  {
    name: "list-iteration",
    source: `<script type="tutuca/state">
  state Iteration {
    items : Array[String]
  }

  receive Iteration { init }
</script>

<script type="tutuca/script">
  receive init {
    .items.push 'first'
    .items.push 'second'
    .items.push 'third'
  }
</script>

<script type="tutuca/test">
{
  "each row binds a key and a value": {
    "steps": [
      { "send": "init" },
      { "expect": "count", "at": "li", "is": 3 },
      { "expect": "text", "at": "span.badge-neutral", "nth": 1, "is": "1" },
      { "expect": "text", "at": "li", "nth": 2, "contains": "third" }
    ]
  }
}
</script>

<template id="Iteration">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-2">
      <!-- The two names a loop binds, and nothing else in the file. -->
      <ul class="flex flex-col gap-1">
        <li @each=".items">
          <span class="badge badge-sm badge-neutral" @text="@key"></span>
          <x text="@value"></x>
        </li>
      </ul>
    </div>
  </section>
</template>
`,
  },
  {
    name: "markdown",
    source: `<script type="tutuca/state">
  state MdPreview {
    source : String
  }

  receive MdPreview { init }
</script>

<script type="tutuca/script">
  /// A whole document on one line: \`\\n\` is an escape a literal carries,
  /// beside \`\\'\`, \`\\\\\`, \`\\t\` and \`\\r\`. (A literal may also span lines
  /// as itself — either spelling means the same string.)
  receive init {
    .source = '# Markdown\\n\\nType on the left, read on the right.\\n\\n- a list\\n- of things\\n\\n> and a quote\\n'
  }
</script>

<script type="tutuca/init">
{
  "starter document": {
    "doc": "What the init handler types, already rendered on the right.",
    "default": true,
    "value": {}
  },
  "a different document": {
    "doc": "Reached by typing rather than seeded, for the usual reason: init would overwrite the value.",
    "value": {},
    "drive": [{ "type": "textarea", "value": "# Cheatsheet\\n\\n- heads\\n- lists\\n" }]
  }
}
</script>

<script type="tutuca/test">
{
  "typing renders markdown live": {
    "steps": [
      { "send": "init" },
      { "expect": "html", "contains": "<h1>" },
      { "expect": "html", "contains": "<li>of things</li>" },
      { "type": "textarea", "value": "# Typed\\n\\n- one" },
      { "expect": "html", "contains": "<h1>Typed</h1>" },
      { "expect": "html", "contains": "<li>one</li>" }
    ]
  }
}
</script>

<template id="MdPreview">
  <div class="flex gap-3 items-stretch">
    <textarea class="textarea flex-1 font-mono text-xs" spellcheck="false"
      :value=".source" @on.input="setSource e.value"></textarea>
    <!-- Markdown, rendered straight into the vdom by the render-time filter —
         no handler, no library on the page. -->
    <div class="flex-1 p-3 bg-base-100 rounded overflow-auto"
      @setinnermd=".source"></div>
  </div>
</template>
`,
  },
  {
    name: "text",
    source: `<script type="tutuca/state">
  state TextDirective {
    str    : String
    num    : Int
    bool   : Bool
    notSet : Any
  }

  receive TextDirective { init }
</script>

<script type="tutuca/script">
  receive init {
    .str = 'hello'
    .num = 42
    .bool = true
  }

  /// The method the last row calls. \`upper\` is the fold \`lower\` always had
  /// a twin for.
  compute getStrUpper {
    upper .str
  }
</script>

<script type="tutuca/test">
{
  "what each spelling renders": {
    "steps": [
      { "send": "init" },
      { "expect": "state", "at": ".num", "is": 42 },
      { "expect": "text", "at": "span", "nth": 3, "is": "42" },
      { "expect": "text", "at": "span", "nth": 6, "is": "" },
      { "expect": "text", "at": "span", "nth": 8, "is": "HELLO" }
    ]
  }
}
</script>

<template id="TextDirective">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body grid grid-cols-[auto_auto] gap-x-4 gap-y-2 items-center">
      <span>String:</span> <span @text=".str"></span>
      <span>Number:</span> <span @text=".num"></span>
      <span>Boolean:</span> <x text=".bool"></x>
      <!-- A Null renders as nothing at all, not as the word "null". -->
      <span>notSet:</span> <span @text=".notSet"></span>
      <span>Method call:</span> <span @text="$getStrUpper"></span>
    </div>
  </div>
</template>
`,
  },
  {
    name: "raw-html",
    source: `<script type="tutuca/state">
  state DangerSetInnerHtml {
    content : String
  }

  receive DangerSetInnerHtml { init }
</script>

<script type="tutuca/script">
  receive init {
    .content = '<b>bold</b> and <i>italic</i>, straight into the DOM'
  }
</script>

<!-- No \`tutuca/test\` block, and not as an oversight: this card's one directive
     is @dangerouslysetinnerhtml, which a compiled card may not carry at all —
     the policy refuses raw markup at every tier, because what it renders cannot
     be checked before it renders. The card checks and compiles; mounting the
     bundle is where it stops. -->
<template id="DangerSetInnerHtml">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <!-- The escape hatch, named so nobody reaches for it by accident. -->
      <div class="p-2 bg-base-100 rounded" @dangerouslysetinnerhtml=".content"></div>
      <textarea class="textarea font-mono text-xs" :value=".content"
        @on.input="setContent e.value"></textarea>
    </div>
  </div>
</template>
`,
  },
  {
    name: "conditional-attrs",
    source: `<script type="tutuca/state">
  state ConditionalAttributes {
    isActive : Bool
  }
</script>

<script type="tutuca/init">
{
  "disabled": {
    "doc": "The ghost half of both conditional attributes.",
    "default": true,
    "value": {}
  },
  "enabled": {
    "doc": "The success half — one field, two attributes following it.",
    "value": { "isActive": true }
  }
}
</script>

<script type="tutuca/test">
{
  "both attributes follow the flag": {
    "steps": [
      { "expect": "attr", "at": "button", "name": "class", "is": "btn btn-ghost" },
      { "expect": "attr", "at": "button", "name": "title", "is": "Click to enable" },
      { "click": "button" },
      { "expect": "attr", "at": "button", "name": "class", "is": "btn btn-success" },
      { "expect": "attr", "at": "button", "name": "title", "is": "Click to disable" },
      { "expect": "text", "at": "span", "is": "Enabled" }
    ]
  }
}
</script>

<template id="ConditionalAttributes">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body">
      <!-- Two @if on one element, so every @then/@else after the first names
           its attribute: HTML forbids duplicate attributes, and the parser
           would drop the second pair before tutuca saw it. -->
      <button
        @if.class=".isActive" @then="'btn btn-success'" @else="'btn btn-ghost'"
        @if.title=".isActive" @then.title="'Click to disable'"
        @else.title="'Click to enable'"
        @on.click="toggleIsActive">
        <span @show=".isActive">Enabled</span>
        <span @hide=".isActive">Disabled</span>
      </button>
    </div>
  </div>
</template>
`,
  },
  {
    name: "styles",
    source: `<script type="tutuca/state">
  state Styled {
    loud : Bool
  }
</script>

<script type="tutuca/script">
  compute label { if .loud { 'quieten it' } else { 'make it loud' } }
</script>

<script type="tutuca/init">
{
  "quiet": {
    "doc": "The scoped rule alone.",
    "default": true,
    "value": {}
  },
  "loud": {
    "doc": "The modifier class on, and the whole literal switched with it.",
    "value": { "loud": true }
  }
}
</script>

<script type="tutuca/test">
{
  "the class list switches as a whole literal": {
    "steps": [
      { "expect": "attr", "at": "p.mine", "name": "class", "is": "mine" },
      { "expect": "text", "at": "button.btn-sm", "is": "make it loud" },
      { "click": "button.btn-sm" },
      { "expect": "attr", "at": "p.mine", "name": "class", "is": "mine loud" },
      { "expect": "attr", "at": "p.common", "name": "class", "is": "common" },
      { "expect": "attr", "at": "p.styled-global", "name": "class", "is": "styled-global" }
    ]
  }
}
</script>

<template id="Styled">
  <!-- A <style> inside a template belongs to THAT view: the runtime scopes it
       to the component's own nodes, so \`.mine\` here reaches neither the page
       around the card nor another card on it. -->
  <style>
    .mine { color: gold; font-weight: 600; }
    .mine.loud { font-size: 1.4rem; letter-spacing: .05em; }
  </style>
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <!-- A class list and a scoped rule compose: \`card\`, \`btn\` and the rest
           are compiled by margaui, \`mine\` is this file's. Switching between
           whole literals is what keeps both readable to the collector. -->
      <p @if.class=".loud" @then="'mine loud'" @else="'mine'">
        styled by the view's own block
      </p>
      <p class="common">styled by the file's common block</p>
      <p class="styled-global">styled by the global block</p>
      <button class="btn btn-sm" @on.click="toggleLoud" @text="$label"></button>
    </div>
  </div>
</template>

<!-- Outside every template: the COMMON block, which every view of this
     component gets. A card that grows a second view shares this one and keeps
     its own <style> for what differs. -->
<style>
  .common { color: mediumaquamarine; font-style: italic; }
</style>

<!-- \`data-global\` opts OUT of scoping: the rule is injected once, for the
     page. The class name is the card's own for that reason — a global rule
     with a common name is a rule that reaches somebody else's markup. -->
<style data-global>
  .styled-global { color: violet; text-decoration: underline dotted; }
</style>
`,
  },
  {
    name: "swatches",
    source: `<script type="tutuca/state">
  state SwatchPicker {
    color   : String
    palette : Array[String]
  }

  receive SwatchPicker { init }
</script>

<script type="tutuca/script">
  receive init {
    .color = '#ef4444'
    .palette.push '#ef4444'
    .palette.push '#f59e0b'
    .palette.push '#10b981'
    .palette.push '#3b82f6'
    .palette.push '#8b5cf6'
  }

  /// Lay each swatch out along the row, and ring the selected one. Both are
  /// answers ABOUT the row, which is what an enricher is for — the loop hands
  /// it \`@key\` and \`@value\`, and the template reads what it wrote.
  enrich swatch {
    @cx = 32 + (@key * 46)
    @ring = if (@value is .color) { '#111827' } else { 'transparent' }
  }
</script>

<script type="tutuca/init">
{
  "five swatches": {
    "doc": "Red selected, as the init handler leaves it.",
    "default": true,
    "value": {}
  },
  "blue picked": {
    "doc": "The ring moved, without moving it.",
    "value": { "color": "#3b82f6" }
  }
}
</script>

<script type="tutuca/test">
{
  "picking a swatch moves the ring": {
    "steps": [
      { "send": "init" },
      { "expect": "attr", "at": "circle", "nth": 0, "name": "stroke", "is": "#111827" },
      { "expect": "attr", "at": "circle", "nth": 1, "name": "stroke", "is": "transparent" },
      { "click": "circle", "nth": 3 },
      { "expect": "state", "at": ".color", "is": "#3b82f6" },
      { "expect": "attr", "at": "rect", "name": "fill", "is": "#3b82f6" },
      { "expect": "attr", "at": "circle", "nth": 0, "name": "stroke", "is": "transparent" },
      { "expect": "attr", "at": "circle", "nth": 3, "name": "stroke", "is": "#111827" }
    ]
  }
}
</script>

<template id="SwatchPicker">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-2">
      <svg viewBox="0 0 380 130" role="img">
        <rect x="20" y="12" width="340" height="52" rx="8" :fill=".color"></rect>
        <circle @each=".palette" @enrich-with="swatch"
          :cx="@cx" cy="98" r="18" :fill="@value"
          stroke-width="3" :stroke="@ring"
          @on.click="setColor @value"></circle>
      </svg>
      <p class="text-sm">Selected: <x text=".color"></x></p>
    </div>
  </div>
</template>
`,
  },
  {
    name: "quadratic",
    source: `<script type="tutuca/state">
  state Quadratic {
    a : Int
    b : Int
    c : Int
  }

  receive Quadratic { init }
</script>

<script type="tutuca/script">
  receive init {
    .a = 1
    .b = -3
    .c = 2
  }

  /// b² − 4ac, and what it says about the roots. \`classify\` calls
  /// \`discriminant\` by name, which is how one body reaches another.
  compute discriminant {
    (.b * .b) - (4 * .a * .c)
  }

  compute classify {
    if discriminant > 0 {
      'two distinct real roots'
    } else {
      if discriminant is 0 { 'one repeated real root' } else { 'no real roots' }
    }
  }
</script>

<script type="tutuca/init">
{
  "two distinct real roots": {
    "doc": "What the init handler seeds: 1, −3, 2 — discriminant 1.",
    "default": true,
    "value": {}
  },
  "repeated root": {
    "doc": "Reached by typing, since the init handler would overwrite seeded coefficients: b = −2, c = 1 lands the discriminant on zero.",
    "value": {},
    "drive": [
      { "type": "input.input-sm", "nth": 1, "value": "-2" },
      { "type": "input.input-sm", "nth": 2, "value": "1" }
    ]
  }
}
</script>

<script type="tutuca/test">
{
  "the verdict follows the coefficients": {
    "steps": [
      { "send": "init" },
      { "expect": "text", "at": "p.verdict", "contains": "1 — two distinct real roots" },
      { "type": "input.input-sm", "nth": 1, "value": "2" },
      { "expect": "state", "at": ".b", "is": 2 },
      { "expect": "text", "at": "p.verdict", "contains": "-4" },
      { "expect": "text", "at": "p.verdict", "contains": "no real roots" },
      { "type": "input.input-sm", "nth": 2, "value": "1" },
      { "expect": "text", "at": "p.verdict", "contains": "one repeated real root" }
    ]
  }
}
</script>

<template id="Quadratic">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <div class="flex gap-3 text-sm">
        <label class="flex items-center gap-1">a
          <input type="number" class="input input-sm w-16" :value=".a"
                 @on.input="setA e.valueAsInt"></label>
        <label class="flex items-center gap-1">b
          <input type="number" class="input input-sm w-16" :value=".b"
                 @on.input="setB e.valueAsInt"></label>
        <label class="flex items-center gap-1">c
          <input type="number" class="input input-sm w-16" :value=".c"
                 @on.input="setC e.valueAsInt"></label>
      </div>
      <!-- MathML, namespaced by the subtree it sits in — no directive needed. -->
      <math display="block">
        <mn @text=".a"></mn><mo>&#x2062;</mo>
        <msup><mi>x</mi><mn>2</mn></msup><mo>+</mo>
        <mn @text=".b"></mn><mo>&#x2062;</mo><mi>x</mi><mo>+</mo>
        <mn @text=".c"></mn><mo>=</mo><mn>0</mn>
      </math>
      <p class="verdict">Discriminant: <x text="$discriminant"></x> — <x text="$classify"></x></p>
    </div>
  </div>
</template>
`,
  },
  {
    name: "nested-state",
    source: `<script type="tutuca/state">
  struct Label {
    text : String
    done : Bool
  }

  state Nested {
    title  : String
    draft  : String
    labels : Array[Label]
  }

  receive Nested { init }
</script>

<script type="tutuca/script">
  /// \`new\` builds the zero of a declared type and puts it at \`@cur\`; the
  /// statements under it fill it in, and \`push\` takes it from there. This is
  /// what a card could not do until the language had a way to NAME a value
  /// being built — there is no record literal, and \`@cur\` is why none is
  /// needed.
  receive init {
    .title = 'Nested state'
    new Label
    @cur.text = 'read the schema'
    .labels.push @cur
    new Label
    @cur.text = 'write a handler'
    @cur.done = true
    .labels.push @cur
  }

  receive addLabel {
    if (trim .draft) is not '' {
      new Label
      @cur.text = (trim .draft)
      .labels.push @cur
      .draft = ''
    }
  }

  /// A nested WRITE: \`.labels[key].done\` is the place, and the spine above it
  /// is rebuilt. This is the pair a view slot cannot spell.
  receive toggleLabel(key) {
    .labels[key].done = not .labels[key].done
  }
</script>

<script type="tutuca/init">
{
  "seeded by init": {
    "doc": "Two labels, as the init handler builds them with new.",
    "default": true,
    "value": {}
  },
  "one added by doing": {
    "doc": "The third label, arrived at by typing and pressing — a record built at runtime is reached by running what builds it.",
    "value": {},
    "drive": [
      { "type": "input.draft", "value": "ship it" },
      { "click": "button.btn-primary" }
    ]
  }
}
</script>

<script type="tutuca/test">
{
  "init builds two records, one already done": {
    "steps": [
      { "send": "init" },
      { "expect": "count", "at": "li", "is": 2 },
      { "expect": "text", "at": "button.btn-xs", "nth": 1, "is": "write a handler" },
      { "expect": "attr", "at": "button.btn-xs", "nth": 1, "name": "class", "is": "btn btn-xs btn-success" }
    ]
  },
  "toggling writes through the nested place": {
    "steps": [
      { "send": "init" },
      { "click": "button.btn-xs", "nth": 1 },
      { "expect": "state", "at": ".labels[1].done", "is": false },
      { "expect": "attr", "at": "button.btn-xs", "nth": 1, "name": "class", "is": "btn btn-xs" }
    ]
  },
  "adding appends another record": {
    "steps": [
      { "send": "init" },
      { "type": "input.draft", "value": "ship it" },
      { "click": "button.btn-primary" },
      { "expect": "state", "at": ".draft", "is": "" },
      { "expect": "count", "at": "li", "is": 3 },
      { "expect": "text", "at": "button.btn-xs", "nth": 2, "is": "ship it" }
    ]
  }
}
</script>

<template>
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title" @text=".title"></h2>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full draft" placeholder="add a label"
               :value=".draft" @on.input="setDraft e.value"
               @on.keydown+send="addLabel">
        <button class="btn btn-sm btn-primary" @on.click="addLabel">add</button>
      </div>
      <ul class="flex flex-col gap-1">
        <li @each=".labels">
          <button @if.class="@value.done"
                  @then="'btn btn-xs btn-success'" @else="'btn btn-xs'"
                  @on.click="toggleLabel @key">
            <x text="@value.text"></x>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>
`,
  },
  {
    name: "contracts",
    source: `<script type="tutuca/state">
  state Seats {
    capacity : Int
    taken    : Int
    waiting  : Int
  }

  receive Seats { init }
</script>

<script type="tutuca/script">
  receive init {
    .capacity = 6
    .taken = 2
    .waiting = 3
  }

  /// A \`pred\` names a rule. Where it ATTACHES is what the rule IS — the same
  /// three names below are read by the badges at the bottom, which is the
  /// point of a rule having a name at all.
  pred canSeat { (.waiting > 0) and (.taken < .capacity) }
  pred someoneSeated { .taken > 0 }
  pred noneWaiting { .waiting is 0 }

  /// PRECONDITION — asked before the body, against the state as it arrived,
  /// so a refusal needs no rollback. One clause of each kind per handler:
  /// two rules become one by naming their \`and\`, which is what \`canSeat\` is.
  receive seat requires canSeat {
    .taken += 1
    .waiting -= 1
  }

  receive stand requires someoneSeated {
    .taken -= 1
    .waiting += 1
  }

  /// POSTCONDITION — asked after the body, against the successor. There is no
  /// \`old\`, so what an \`ensures\` says is where the transition had to LAND.
  receive seatAll ensures noneWaiting {
    .taken += .waiting
    .waiting = 0
  }

  /// The same claim, from a handler that seats one person. It holds when one
  /// is all there was, and otherwise the rule catches the lie: the transition
  /// is abandoned whole — no successor, no effects — and
  /// \`@tutuca.postcondition_failed\` goes through the warn hook with the
  /// handler and the rule in it. Open the console and press it with three
  /// people waiting.
  receive rush ensures noneWaiting {
    .taken += 1
    .waiting -= 1
  }

  /// THE INVARIANT — the one rule nothing has to mention. It is checked after
  /// every transition this block declares, including the two below, which
  /// were written without a thought for it.
  invariant withinCapacity { .taken <= .capacity }

  receive queue { .waiting += 1 }

  /// Refused by a rule it does not name, and reported rather than silent —
  /// which is the whole difference between a contract and an \`if\` at the top
  /// of the body.
  receive overbook { .taken = (.capacity + 1) }
</script>

<script type="tutuca/init">
{
  "early doors": {
    "doc": "Two seated, three waiting — what the init handler seeds.",
    "default": true,
    "value": {}
  },
  "one from full": {
    "doc": "Seat everybody, queue one more: the state rush declines from. Reached by driving, since init would overwrite seeded numbers.",
    "value": {},
    "drive": [{ "send": "seatAll" }, { "send": "queue" }]
  }
}
</script>

<script type="tutuca/test">
{
  "seat moves one across and says nothing": {
    "steps": [
      { "send": "init" },
      { "send": "seat" },
      { "expect": "state", "at": ".taken", "is": 3 },
      { "expect": "state", "at": ".waiting", "is": 2 },
      { "expect": "log", "is": [] }
    ]
  },
  "a precondition turns the handler away before it moves anybody": {
    "steps": [
      { "send": "init" },
      { "send": "seatAll" },
      { "expect": "state", "at": ".taken", "is": 5 },
      { "send": "seat" },
      { "expect": "state", "at": ".taken", "is": 5 },
      { "expect": "log", "contains": "its precondition" }
    ]
  },
  "rush abandons whole when more than one waits": {
    "steps": [
      { "send": "init" },
      { "send": "rush" },
      { "expect": "state", "at": ".taken", "is": 2 },
      { "expect": "state", "at": ".waiting", "is": 3 },
      { "expect": "log", "contains": "was abandoned" }
    ]
  },
  "the invariant refuses overbook without being asked": {
    "steps": [
      { "send": "init" },
      { "send": "overbook" },
      { "expect": "state", "at": ".taken", "is": 2 },
      { "expect": "log", "contains": "broke the invariant" }
    ]
  }
}
</script>

<template id="Seats">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <div class="stats bg-base-100">
        <div class="stat">
          <div class="stat-title">seated</div>
          <div class="stat-value text-2xl" @text=".taken"></div>
        </div>
        <div class="stat">
          <div class="stat-title">waiting</div>
          <div class="stat-value text-2xl" @text=".waiting"></div>
        </div>
        <div class="stat">
          <div class="stat-title">capacity</div>
          <div class="stat-value text-2xl" @text=".capacity"></div>
        </div>
      </div>
      <div class="flex gap-2 items-center flex-wrap">
        <div class="join">
          <button class="btn btn-sm join-item" @on.click="seat">seat one</button>
          <button class="btn btn-sm join-item" @on.click="stand">stand one</button>
          <button class="btn btn-sm join-item" @on.click="queue">queue one</button>
        </div>
        <div class="join">
          <button class="btn btn-sm btn-primary join-item" @on.click="seatAll"
                  title="a postcondition it keeps">seat all</button>
          <button class="btn btn-sm btn-soft btn-warning join-item" @on.click="rush"
                  title="a postcondition it only keeps when one was all there was">rush</button>
        </div>
        <button class="btn btn-sm btn-soft btn-error" @on.click="overbook"
                title="refused by the invariant, and reported">overbook</button>
      </div>
      <ul class="flex flex-col gap-1 font-mono text-xs">
        <li class="flex gap-2 items-center">
          <span @if.class="$withinCapacity"
                @then="'badge badge-sm badge-success'"
                @else="'badge badge-sm badge-error'">
            <x text="$withinCapacity"></x>
          </span>
          withinCapacity: the invariant, kept after every handler
        </li>
        <li class="flex gap-2 items-center">
          <span @if.class="$canSeat"
                @then="'badge badge-sm badge-success'"
                @else="'badge badge-sm badge-error'">
            <x text="$canSeat"></x>
          </span>
          canSeat: what \`seat\` asks before it moves anybody
        </li>
        <li class="flex gap-2 items-center">
          <span @if.class="$noneWaiting"
                @then="'badge badge-sm badge-success'"
                @else="'badge badge-sm badge-error'">
            <x text="$noneWaiting"></x>
          </span>
          noneWaiting: where \`seat all\` and \`rush\` have to land
        </li>
      </ul>
    </div>
  </div>
</template>
`,
  },
  {
    name: "macros",
    source: `<script type="tutuca/state">
  state MacroDemo {
    count  : Int
    status : String
  }

  receive MacroDemo { init }
</script>

<script type="tutuca/script">
  receive init { .status = 'warning' }

  receive inc { .count += 1 }
</script>

<script type="tutuca/init">
{
  "fresh": {
    "doc": "Count at zero and the Live badge reading the status the init handler set.",
    "default": true,
    "value": {}
  },
  "pressed once": {
    "doc": "The one field a macro card of this shape owns — macros themselves hold nothing.",
    "value": { "count": 1 }
  }
}
</script>

<script type="tutuca/test">
{
  "a macro expands into the component around it": {
    "steps": [
      { "send": "init" },
      { "expect": "text", "at": "span.badge-neutral", "is": "New" },
      { "expect": "attr", "at": "span.badge", "nth": 1, "name": "class", "is": "badge badge-success" },
      { "expect": "attr", "at": "span.badge", "nth": 2, "name": "class", "is": "badge badge-warning" },
      { "click": "button.btn-primary" },
      { "expect": "state", "at": ".count", "is": 1 },
      { "expect": "text", "at": "p", "nth": 2, "is": "Count: 1" }
    ]
  }
}
</script>

<!-- A macro is pure template expansion: no state, no handlers, no lifecycle.
     \`@on.click="inc"\` inside one calls \`inc\` on the COMPONENT it expanded
     into, which is the whole difference from a child component.

     A card may declare several components — one \`state\` each, one
     \`<script ... for="Comp">\` each, \`<template id="Comp:main">\` — and build
     them while it runs, which is what \`todo\` does. A macro needs none of
     that: it has nothing to hold and nothing to say, so it expands rather than
     mounts, and it is still the answer wherever the shape repeats and the
     STATE does not.

     These lived in MoonBit until a card could hold one: the demo they come
     from (storybook/examples/macros) registers them with \`macros=\` and
     writes its views as raw strings, because the loader used to drop what the
     file declared. -->
<template id="macro:badge" data-label="'New'" data-kind="'neutral'">
  <span @if.class="^kind" @then="$'badge badge-{^kind}'"
        @else="'badge'" @text="^label"></span>
</template>

<template id="macro:panel" data-title="'Panel'">
  <div class="card bg-base-100">
    <div class="card-body gap-2">
      <h3 class="card-title text-base" @text="^title"></h3>
      <x:slot></x:slot>
      <div class="card-actions"><x:slot name="actions"></x:slot></div>
    </div>
  </div>
</template>

<template id="MacroDemo">
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <!-- A parameter, a default, and a DYNAMIC one read off the state. -->
      <p class="flex gap-2 items-center">
        <x:badge></x:badge>
        <x:badge label="Sale" kind="success"></x:badge>
        <x:badge label="Live" :kind=".status"></x:badge>
      </p>

      <!-- The default slot takes the children; a named one takes the ones
           that ask for it by name. -->
      <x:panel title="Slots">
        <p>This paragraph is the macro call's child.</p>
        <!-- A named slot is asked for by an <x slot="…"> wrapper, not by an
             attribute on the child: the wrapper is what carries the name. -->
        <x slot="actions">
          <button class="btn btn-sm btn-primary" @on.click="inc">+1</button>
        </x>
      </x:panel>

      <p>Count: <x text=".count"></x></p>
    </div>
  </div>
</template>
`,
  },
  {
    name: "drag-reorder",
    source: `<script type="tutuca/state">
  state Reorder {
    items : Array[String]
    query : String
  }

  receive Reorder { init }
</script>

<script type="tutuca/script">
  receive init {
    .items.push 'write the ones'
    .items.push 'read the twos'
    .items.push 'review the threes'
    .items.push 'ship the fours'
    .items.push 'plan the fives'
  }

  /// Filtering keeps the keys it hides: a row's @key is its index in .items,
  /// not its position on screen, which is why the two indices a drop names
  /// still address the list.
  pred filterItem {
    contains (lower @value) (lower .query)
  }

  /// A drop fires on the TARGET row, and \`dragKey\` answers the SOURCE row's
  /// @key — the one thing the target cannot see for itself, since the source's
  /// binds only exist on the stack the drag captured. Asking for it by name is
  /// what makes this a card at all: \`dragInfo\` carries a lookupBind FUNCTION,
  /// and a block cannot apply a function it did not name.
  ///
  /// Both arms read the row before they move it, and the second index accounts
  /// for the shift the insert just caused.
  receive moveRow(target, source) {
    if source is not target {
      if source < target {
        .items.insertAt (target + 1) .items[source]
        .items.deleteAt source
      } else {
        .items.insertAt target .items[source]
        .items.deleteAt (source + 1)
      }
    }
  }
</script>

<script type="tutuca/init">
{
  "five rows": {
    "doc": "What the init handler pushes, in order.",
    "default": true,
    "value": {}
  },
  "filtered to the t rows": {
    "doc": "Two of five visible. The hidden keys are what a drop still addresses, which is the scene below.",
    "value": { "query": "the t" }
  }
}
</script>

<script type="tutuca/test">
{
  "a drop moves the row after the target": {
    "steps": [
      { "send": "init" },
      { "drag": "li.cursor-grab", "from": 0, "to": 2 },
      { "expect": "state", "at": ".items", "is": [
        "read the twos",
        "review the threes",
        "write the ones",
        "ship the fours",
        "plan the fives"
      ] },
      { "expect": "text", "at": "li.cursor-grab", "nth": 2, "contains": "write the ones" }
    ]
  },
  "a drop names list places, not screen positions": {
    "steps": [
      { "send": "init" },
      { "type": "input.input-sm", "value": "the t" },
      { "expect": "count", "at": "li.cursor-grab", "is": 2 },
      { "drag": "li.cursor-grab", "from": 0, "to": 1 },
      { "expect": "state", "at": ".items", "is": [
        "write the ones",
        "review the threes",
        "read the twos",
        "ship the fours",
        "plan the fives"
      ] }
    ]
  },
  "dropping a row on itself changes nothing": {
    "steps": [
      { "send": "init" },
      { "drag": "li.cursor-grab", "from": 1, "to": 1 },
      { "expect": "state", "at": ".items", "is": [
        "write the ones",
        "read the twos",
        "review the threes",
        "ship the fours",
        "plan the fives"
      ] }
    ]
  }
}
</script>

<template id="Reorder">
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input type="search" class="input input-sm" :value=".query"
             @on.input="setQuery e.value" @on.keydown+cancel="resetQuery"
             placeholder="Filter entries">
      <!-- data-dragtype on the source and data-droptarget on the target pair
           a draggable with where it may land; both are on the same row here,
           since every row is both. -->
      <ul class="flex flex-col gap-1">
        <li class="badge badge-ghost w-full justify-start gap-2 cursor-grab"
            @each=".items" @when="filterItem"
            draggable="true"
            data-dragtype="reorder-row"
            data-droptarget="reorder-row"
            @on.drop="moveRow @key e.dragKey">
          <span class="opacity-60" @text="@key"></span>
          <x text="@value"></x>
        </li>
      </ul>
    </div>
  </section>
  <style>
    /* The two attributes tutuca manages during a drag. No class route exists
       for either — they are set on the live nodes — so this is the one card
       that has to say something a utility class cannot. */
    [data-dragging="1"] { opacity: .5; }
    [data-draggingover="reorder-row"] {
      outline: 1px dashed currentColor;
      outline-offset: 2px;
    }
  </style>
</template>
`,
  },
];
