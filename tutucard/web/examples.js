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
// `ask dyn` rather than being handed a callback. `nested-state` is the
// other half of what `new` is for — a list of plain RECORDS, where `new Label`
// puts the type's zero at `cur` and the statements under it fill it in.
//
// Every card fills the sections its structured view can edit WHERE THEY MEAN
// SOMETHING: a `tests:` section drives the Tests pane, a
// `fixtures:` section feeds the Examples pane. Two rules keep
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
    source: `spec:
  Counter:
    field label :: String
    field count :: Int
    field history :: List.of(Int)

logic:
  Counter:
    /// Move the counter by d, remembering where it landed.
    receive add(d):
      it.count += d
      it.history.push(it.count)

    compute summary: @str{@(it.label): @(it.count)}

view:
  Counter:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@h2(~class: "card-title"){@(summary())}@div(~class: "join"){@button(~class: "btn btn-sm join-item", ~on_click: add(1)){+1} @button(~class: "btn btn-sm join-item", ~on_click: add(-1)){-1} @button(~class: "btn btn-sm join-item btn-ghost", ~on_click: it.count := default){reset}} @label(~class: "flex gap-2 items-center"){@span(~class: "opacity-70"){label} @input(~class: "input input-sm w-full", ~value: it.label, ~on_input: it.label := e.value)} @ul(~class: "flex gap-1 flex-wrap"){@each(value, key in it.history){@li(~class: "badge badge-sm badge-neutral"){@(value)}}}}}

  Counter.row:
    @div(~class: "flex gap-2 items-center"){@span(~class: "badge badge-neutral"){@(summary())} @button(~class: "btn btn-xs", ~on_click: add(1)){+1}}

fixtures:
  "as a row":
    ~doc: "The same state under the card's other view. Which view to show it as is the one thing a value cannot say about itself."
    ~view: "row"
    it.label = "Compact"
    it.count = 7

  "counted up":
    ~doc: "The same three, arrived at by pressing — a fixture can be reached by DOING rather than described."
    it.label = "Pressed"
    ~drive:
      click("button.join-item")
      click("button.join-item")
      click("button.join-item")

  "fresh" ~default:
    ~doc: "A counter nobody has pressed yet — what a visitor meets."
    it.label = "Counter"

  "with history":
    ~doc: "What three presses leave behind, without pressing three times."
    it.label = "Demo"
    it.count = 3
    it.history = [1, 2, 3]

tests:
  "pressing remembers where it landed":
    type("input.input-sm", "Counter")
    expect text("h2.card-title") == "Counter: 0"
    click("button.join-item")
    click("button.join-item")
    expect text("h2.card-title") == "Counter: 2"
    expect texts("li.badge-neutral") == ["1", "2"]

  "reset zeroes the count and keeps the history":
    type("input.input-sm", "Counter")
    click("button.join-item")
    click("button.join-item")
    click("button.btn-ghost")
    expect text("h2.card-title") == "Counter: 0"
    expect state it.history == [1, 2]

  "renaming relabels the summary":
    type("input.input-sm", "Renamed")
    expect state it.label == "Renamed"
    expect text("h2.card-title") == "Renamed: 0"
`,
  },
  {
    name: "todo",
    source: `spec:
  /// TWO components in one card: the list, and the row beside it. A file may
  /// declare as many as it likes — one \`state\` each, one
  /// \`<script type="tutuca/script" for="…">\` each, one
  /// \`<template id="…:main">\` each — and the FIRST one is what a host mounts
  /// when told no other name. A component that only ever appears inside
  /// another one belongs beside it rather than in a file of its own.
  Todo:
    field draft :: String
    field next_id :: Int
    field items :: Map.of(String, Instance.of(TodoItem))

    intent remove_item(String)

  /// A \`Map\` rather than an \`Array\` because a row has to be able to name
  /// ITSELF to the list, and an index stops naming the same row the moment
  /// anything above it is dropped. The key is minted once, at the push, and
  /// the row carries its own copy — so \`removeItem\` means the same thing
  /// whenever it arrives.
  TodoItem:
    field id :: String
    field text :: String
    field done :: Bool
    field editing :: Bool
    field draft :: String

logic:
  Todo:
    /// Add the draft, unless it is only whitespace.
    ///
    /// \`new TodoItem\` names the SIBLING component and opens an argument map for
    /// it; \`cur.…\` fills that in, and the child is made at the moment \`cur\`
    /// is read — which is the \`setAt\`. The key is spelled twice rather than
    /// read back off \`cur\`, because reading it is what would build the child.
    receive add_item:
      if (it.draft.trim() != "")
      | 
          it.next_id += 1
          it.items.set_at(@str{row-@(it.next_id)}, TodoItem(id: @str{row-@(it.next_id)}, text: it.draft.trim()))
          it.draft := ""

    /// The other end of the row's \`intent dyn\`. An \`intent\` arm that changes
    /// state and does not \`reply\` is an OBSERVER and the walk goes on; this one
    /// is the last hop anyway, so there is nothing left to observe it.
    answer remove_item(id):
      it.items.delete_at(id)

    compute caption: @str{@(it.items.length()) item(s)}

    compute any_items: !(it.items.is_empty())

  TodoItem:
    receive toggle:
      it.done := !it.done

    /// Double-click the text and the row edits itself: the draft starts as a
    /// copy, so abandoning it costs nothing. Both halves are the row's own
    /// business and the list never hears about them.
    receive start_edit:
      it.draft := it.text
      it.editing := true

    /// Enter commits — unless what is left is only whitespace, in which case the
    /// row keeps what it had.
    receive commit_edit:
      if (it.draft.trim() != "")
      | it.text := it.draft.trim()
      it.editing := false

    /// Escape throws the draft away.
    receive cancel_edit:
      it.editing := false

    /// The row does not know the list's shape, or that there IS a list. It names
    /// the JOB and lets the route find who does it: \`dyn\` walks the dispatch
    /// path starting at the sender's PARENT — a walk is never offered to the
    /// component that raised it — and the first hop with a \`removeItem\` arm
    /// acts on it. Nothing here would change if the row were nested three deep.
    ///
    /// \`notify\` and not \`ask\`, because the row wants nothing back: it is
    /// announcing that it should go, and whoever owns the list decides what that
    /// means. An \`ask\` with no answer arms would run identically and read as
    /// though someone forgot to write them.
    receive request_remove:
      notify("remove_item", it.id, ~route: dyn)

    compute label: if it.done | @str{@(it.text) (done)} | it.text

view:
  Todo:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@h2(~class: "card-title"){Todos}@div(~class: "flex gap-2 items-center"){@input(~class: "input input-sm w-full draft", ~placeholder: "what needs doing", ~value: it.draft, ~on_input: it.draft := e.value, ~on_keydown: add_item ~send) @button(~class: "btn btn-sm btn-primary add", ~on_click: add_item){add}} @comment{@" \`<x render-each>\` renders each item as a component in its own right, with its own state and its own handlers — where \`@each\` would render a value with THIS component's. "} @show(any_items()){@ul(~class: "flex flex-col gap-2"){@each(value, key in it.items){@render(value)}}} @hide(any_items()){@p(~class: "opacity-60 italic"){nothing yet}} @span(~class: "badge badge-sm badge-neutral tally"){@(caption())}}}

  TodoItem:
    @li(~class: "flex gap-3 items-center w-full"){@input(~type: "checkbox", ~class: "checkbox checkbox-sm check", ~on_click: toggle) @hide(it.editing){@span(~class: "w-full label", ~on_dblclick: start_edit){@(label())}} @show(it.editing){@input(~class: "input input-xs w-full edit", ~value: it.draft, ~on_input: it.draft := e.value, ~on_keydown: commit_edit ~send, ~on_keydown: cancel_edit ~cancel)} @button(~class: "btn btn-xs btn-soft btn-error btn-circle remove", ~on_click: request_remove){×}}

fixtures:
  "empty" ~default:
    ~doc: "A list nobody has used yet — what a visitor meets."

  "one being edited":
    ~doc: "Mid-edit, which no amount of seeded state says better than the double-click that gets there."
    ~drive:
      type("input.draft", "review the diff")
      click("button.add")
      fire("span.label", "dblclick")

  "two rows":
    ~doc: "A list that has been used, arrived at by using it: a row is a CHILD built at runtime with new, and a child is an instance rather than data — so a fixture reaches this state by DOING what a person would have done rather than by writing the items into value."
    ~drive:
      type("input.draft", "write the tests")
      click("button.add")
      type("input.draft", "ship it")
      click("button.add")

  "empty" ~default:
    ~doc: "A list nobody has used yet — what a visitor meets."

  "one being edited":
    ~doc: "Mid-edit, which no amount of seeded state says better than the double-click that gets there."
    ~drive:
      type("input.draft", "review the diff")
      click("button.add")
      fire("span.label", "dblclick")

  "two rows":
    ~doc: "A list that has been used, arrived at by using it: a row is a CHILD built at runtime with new, and a child is an instance rather than data — so a fixture reaches this state by DOING what a person would have done rather than by writing the items into value."
    ~drive:
      type("input.draft", "write the tests")
      click("button.add")
      type("input.draft", "ship it")
      click("button.add")

tests:
  "adding makes rows":
    type("input.draft", "write it")
    click("button.add")
    type("input.draft", "ship it")
    click("button.add")
    expect texts("span.label") == ["write it", "ship it"]
    expect text("span.tally") == "2 item(s)"

  "a row asks the list to drop it":
    type("input.draft", "one")
    click("button.add")
    type("input.draft", "two")
    click("button.add")
    click("button.remove")
    expect texts("span.label") == ["two"]
    expect text("span.tally") == "1 item(s)"

  "double-click edits the text":
    type("input.draft", "wrng")
    click("button.add")
    expect count("input.edit") == 0
    fire("span.label", "dblclick")
    expect count("input.edit") == 1
    type("input.edit", "right")
    key("input.edit", "Enter")
    expect texts("span.label") == ["right"]
    expect count("input.edit") == 0

  "escape leaves the text alone":
    type("input.draft", "keep")
    click("button.add")
    fire("span.label", "dblclick")
    type("input.edit", "nope")
    key("input.edit", "Escape")
    expect texts("span.label") == ["keep"]

  "a row strikes itself through":
    type("input.draft", "a")
    click("button.add")
    click("input.check")
    expect texts("span.label") == ["a (done)"]
`,
  },
  {
    name: "filter",
    source: `spec:
  Filter:
    field query :: String
    field names :: List.of(String)

    message init

logic:
  Filter:
    receive init:
      it.names.push("Ada Lovelace")
      it.names.push("Grace Hopper")
      it.names.push("Alan Turing")
      it.names.push("Barbara Liskov")

    /// A row survives when the query is empty or its text contains it.
    /// Case-folded on both sides, so the filter is not a spelling test.
    ///
    /// @when takes this bare, because an iteration filter has always been
    /// a name — which is why the predicates design could absorb "when" into
    /// "pred" without changing a single call site.
    pred matches(value, key): (it.query.is_empty() || (value.lower()).contains(it.query.lower()))

    compute caption: @str{@(it.names.length()) name(s)}

view:
  Filter:
    @div(~class: "card bg-base-200 max-w-md"){
      @div(~class: "card-body gap-3"){
        @div(~class: "flex gap-2 items-center"){@input(~class: "input input-sm w-full", ~placeholder: "filter", ~value: it.query, ~on_input: it.query := e.value) @span(~class: "badge badge-sm badge-neutral"){@(caption())}}
        @ul(~class: "flex flex-col gap-1"){
          @each(value, key in it.names, ~when: matches){
            @li(~class: "badge badge-ghost w-full justify-start"){@(value)}
          }
        }
      }
    }

fixtures:
  "narrowed to gr":
    ~doc: "The same four names behind a query: the fixture seeds the query and the init handler still fills the list, because mounting dispatches init after the value is seeded."
    it.query = "gr"

  "the whole list" ~default:
    ~doc: "An empty query keeps every row — the init handler fills the names, and the fixture only has to say what the box holds."

tests:
  "typing narrows the list":
    send("init")
    expect count("li.badge-ghost") == 4
    expect text("span.badge-neutral") == "4 name(s)"
    type("input.input-sm", "gr")
    expect texts("li.badge-ghost") == ["Grace Hopper"]
    expect text("span.badge-neutral") == "4 name(s)"
    type("input.input-sm", "")
    expect count("li.badge-ghost") == 4

  "matching is case-folded on both sides":
    send("init")
    type("input.input-sm", "HOPPER")
    expect texts("li.badge-ghost") == ["Grace Hopper"]
`,
  },
  {
    name: "messages",
    source: `spec:
  Inbox:
    field status :: String
    field seen :: Int

    message note(String)

    message bump(Int)

logic:
  Inbox:
    receive note(text):
      it.status := text
      it.seen += 1

    receive bump(by):
      it.seen += by

    /// A handler that raises one at itself. The dispatch goes through the
    /// transactor exactly as a parent's would, which is what the Activity panel
    /// beside this is showing.
    receive shout:
      send("note", "shouted")

    receive quiet:
      send("note", "quiet")

    receive five:
      send("bump", 5)

view:
  Inbox:
    @div(~class: "card bg-base-200 max-w-md"){
      @div(~class: "card-body gap-3"){
        @h2(~class: "card-title"){@(it.status)}
        @p(~class: "flex gap-2 items-center"){@span(~class: "opacity-70"){seen} @span(~class: "badge badge-sm badge-primary"){@(it.seen)}}
        @div(~class: "join"){@button(~class: "btn btn-sm join-item", ~on_click: shout){shout} @button(~class: "btn btn-sm join-item", ~on_click: quiet){quiet} @button(~class: "btn btn-sm join-item btn-primary", ~on_click: five){bump 5}}
      }
    }

fixtures:
  "a few notes in":
    ~doc: "The same card after some traffic, without driving it there."
    it.status = "hello"
    it.seen = 3

  "quiet start" ~default:
    ~doc: "No headline and an empty tally — what the schema's zero looks like."

tests:
  "a note updates the headline and the tally":
    expect text("h2.card-title") == ""
    click("button.join-item")
    expect text("h2.card-title") == "shouted"
    expect state it.seen == 1
    click("button.btn-primary")
    expect state it.seen == 6
    expect text("span.badge-primary") == "6"
`,
  },
  {
    name: "intents",
    source: `spec:
  Feed:
    field rows :: List.of(Any)
    field query :: String
    field echoed :: String
    field error :: String
    field busy :: Bool

    message init

    message rows_ok(Any)

    message rows_failed(Any)

    message rows_unhandled

    message echo_ok(Any)

    message echo_failed(Any)

    message echo_unhandled

logic:
  Feed:
    /// \`ask\` hands a NAME to a ROUTE, and whatever is on that route answers
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
    receive init:
      ask("rows", ~route: lex)
      it.busy := true

    receive reload:
      ask("rows", ~route: lex)
      it.busy := true
      it.error := ""

    /// Whatever follows the name is the PAYLOAD. \`echo\` answers with the first
    /// thing it was handed, so what comes back is what went out.
    receive echo_query:
      ask("echo", it.query, ~route: lex)
      it.busy := true

    /// The third outcome, with nothing mocked: this name is on no route, so the
    /// walk runs out and nobody answered. Not a crash, and — the part v1 could
    /// not say — not a failure either.
    receive break_it:
      ask("nothing_answers_this", ~route: lex)
      it.busy := true
      it.error := ""

    /// One arm per outcome, and each gets only what it is about. v1 sent one
    /// payload carrying BOTH a result and an error, exactly one of which was
    /// Null, and every arm began by working out which. The branch is gone with
    /// the pair.
    receive rows_ok(res):
      it.busy := false
      it.rows := res

    receive rows_failed(err):
      it.busy := false
      it.error := err.to_string()

    receive rows_unhandled:
      it.busy := false
      it.error := "nothing on this page answers \`rows\`"

    receive echo_ok(res):
      it.busy := false
      it.echoed := res.to_string()

    receive echo_failed(err):
      it.busy := false
      it.error := err.to_string()

    receive echo_unhandled:
      it.busy := false
      it.error := "nothing on this page answers \`echo\`"

view:
  Feed:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@show(it.busy){@p(~class: "opacity-60 italic"){asking the host…}} @hide(it.error.is_empty()){@div(~class: "alert alert-error"){@span(~class: "font-mono text-sm"){@(it.error)}}} @hide(it.busy){@ul(~class: "flex flex-col gap-1"){@each(value, key in it.rows){@li(~class: "rounded bg-base-100 p-2"){@p(~class: "font-bold"){@(value.title)}@p(~class: "text-sm opacity-70"){@(value.description)}}}}} @div(~class: "flex gap-2 items-center"){@input(~class: "input input-sm w-full", ~placeholder: "say something", ~value: it.query, ~on_input: it.query := e.value, ~on_keydown: echo_query ~send) @button(~class: "btn btn-sm", ~on_click: echo_query){echo it}} @hide(it.echoed.is_empty()){@p(~class: "badge badge-sm badge-neutral"){@(it.echoed)}} @div(~class: "join"){@button(~class: "btn btn-sm btn-primary join-item", ~on_click: reload){reload} @button(~class: "btn btn-sm btn-soft btn-error join-item", ~on_click: break_it){break it}}}}

fixtures:
  "a feed that travels with the card":
    ~doc: "A fixture may carry its own intent ANSWERS, which beats both the clock and whatever the page registers — so this card loads filled wherever it runs, page fixtures or none."
    ~intents:
      ok("rows", [{title: "Tutuca", description: "A SPA framework that fits in your head"}, {title: "MoonBit", description: "The language this port is written in"}])

  "fresh" ~default:
    ~doc: "Nothing asked yet. The page answers rows LATE, so the preview shows its own asking state for half a beat before the rows land."

tests:
  "the answer fills the list":
    ~intents:
      ok("rows", [{title: "Tutuca", description: "A SPA framework that fits in your head"}, {title: "MoonBit", description: "The language this port is written in"}])
    send("reload")
    expect count("li.rounded") == 2
    expect texts("p.font-bold") == ["Tutuca", "MoonBit"]
    expect count("div.alert-error") == 0

  "echo hands the payload back":
    ~intents:
      ok("echo", 41)
    type("input.input-sm", "hello")
    key("input.input-sm", "Enter")
    expect text("p.badge") == "41"

  "an unanswered name is silence, not a crash":
    expect count("div.alert-error") == 0
    click("button.btn-error")
    expect count("div.alert-error") == 0
    expect text("p.opacity-60") == "asking the host…"
`,
  },
  {
    name: "traffic-light",
    source: `spec:
  TrafficLight:
    field light_index :: Int

logic:
  TrafficLight:
    /// Step to the next colour, wrapping at the end of the cycle.
    receive next_light:
      it.light_index := ((it.light_index + 1) mod 3)

    /// The colour is DERIVED, never stored. In MoonBit this indexed an array
    /// of names; the value language has no array literal, so the same mapping
    /// is nested ifs — which is the whole of what changed in the migration.
    compute light: if (it.light_index == 0) | "red" | (if (it.light_index == 1) | "orange" | "green")

view:
  TrafficLight:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-2"){@button(~class: "btn btn-primary", ~on_click: next_light){Next light} @p{@"Light is: "@code{@(light())}}@p(~class: "advice"){@" You must "@show((light() == "red")){@span{STOP}} @show((light() == "orange")){@span{SLOW DOWN}} @show((light() == "green")){@span{GO}}}}}

fixtures:
  "fresh" ~default:
    ~doc: "Red, where every cycle starts."

  "green means go":
    ~doc: "The last colour before the cycle wraps."
    it.light_index = 2

  "mid-cycle":
    ~doc: "One press in."
    it.light_index = 1

tests:
  "it cycles and wraps":
    expect text("code") == "red"
    click("button.btn-primary")
    expect text("code") == "orange"
    click("button.btn-primary")
    expect text("code") == "green"
    expect text("span") == "GO"
    click("button.btn-primary")
    expect text("code") == "red"

  "the advice follows the light":
    expect text("span") == "STOP"
    expect count("span") == 1
    click("button.btn-primary")
    expect text("span") == "SLOW DOWN"
`,
  },
  {
    name: "tabs",
    source: `spec:
  TabbedUI:
    field tab :: String

view:
  TabbedUI:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@div(~role: "tablist", ~class: "tabs tabs-border"){@button(~role: "tab", ~class: if (it.tab == "overview") | "tab tab-active" | "tab", ~on_click: it.tab := "overview"){Overview} @button(~role: "tab", ~class: if (it.tab == "features") | "tab tab-active" | "tab", ~on_click: it.tab := "features"){Features} @button(~role: "tab", ~class: if (it.tab == "pricing") | "tab tab-active" | "tab", ~on_click: it.tab := "pricing"){Pricing}} @show((it.tab == "overview")){@div(~class: "p-3"){@h4{Overview}@p{A short summary of what this product does.}}} @show((it.tab == "features")){@div(~class: "p-3"){@h4{Features}@p{The list of features lives on this tab.}}} @show((it.tab == "pricing")){@div(~class: "p-3"){@h4{Pricing}@p{What it costs.}}}}}

fixtures:
  "overview open" ~default:
    ~doc: "The schema's zero is the empty string, under which NO panel shows — a fixture is how a card starts somewhere a visitor can read."
    it.tab = "overview"

  "pricing open":
    ~doc: "The same component, one field apart."
    it.tab = "pricing"

tests:
  "a tab switches the panel":
    expect count("div.p-3") == 0
    click("button.tab", ~nth: 1)
    expect text("h4") == "Features"
    expect count("div.p-3") == 1
    expect attr("button.tab", "class") == "tab tab-active" ~nth: 1
    expect attr("button.tab", "class") == "tab"
    click("button.tab", ~nth: 2)
    expect text("h4") == "Pricing"
`,
  },
  {
    name: "show-hide",
    source: `spec:
  ShowHide:
    field is_open :: Bool
    field count :: Int

logic:
  ShowHide:
    /// The panel's own counter. \`toggleIsOpen\` is not here because it is not
    /// written anywhere: a Bool field generates its own toggle.
    receive inc_count:
      it.count += 1

    compute label: if it.is_open | "Hide details" | "Show details"

view:
  ShowHide:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-2"){@button(~class: "btn btn-primary", ~on_click: it.is_open := !it.is_open){@(label())} @show(it.is_open){@div(~class: "p-3"){@p{@"Details panel — only visible when "@code{isOpen}@" is true."} @button(~class: "btn btn-sm", ~on_click: inc_count){Click me} @p{@"Clicked "@(it.count)@" times."}}} @hide(it.is_open){@p(~class: "opacity-60"){(details are hidden)}} @p{@"Count, only when open: "@show(it.is_open){@(it.count)}}}}

fixtures:
  "closed" ~default:
    ~doc: "The panel absent and the button making its offer."

  "open with history":
    ~doc: "Open, with a count that survived the closing it never had — both fields in one fixture."
    it.is_open = true
    it.count = 4

tests:
  "the panel is only there while it is open":
    expect text("button.btn-primary") == "Show details"
    expect count("div.p-3") == 0
    click("button.btn-primary")
    expect text("button.btn-primary") == "Hide details"
    expect count("div.p-3") == 1

  "the counter keeps counting across a close":
    click("button.btn-primary")
    click("button.btn-sm")
    click("button.btn-sm")
    expect state it.count == 2
    click("button.btn-primary")
    expect count("div.p-3") == 0
    expect state it.count == 2
`,
  },
  {
    name: "attributes",
    source: `spec:
  AttributeBinding:
    field str :: String
    field num :: Int
    field bool :: Bool

view:
  AttributeBinding:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@input(~class: "input input-sm", ~value: it.str, ~on_input: it.str := e.value, ~title: @str{Content is @(it.str)}) @comment{ \`valueAsInt\` rather than a handler that parses the string: the argument names are where a card does its conversions. } @input(~class: "input input-sm", ~type: "number", ~value: it.num, ~on_input: it.num := e.valueAsInt) @label(~class: "flex gap-2 items-center"){@input(~class: "checkbox checkbox-sm", ~type: "checkbox", ~checked: it.bool, ~on_input: it.bool := e.value)@" bool "} @p{@"String: "@span{@(it.str)}}@p{@"Number: "@span{@(it.num)}}@p{@"Boolean: "@span{@(it.bool)}}}}

fixtures:
  "blank" ~default:
    ~doc: "Every field at its zero — the inputs and the readouts agree, because both are the same state."

  "half filled":
    ~doc: "One fixture showing all three bindings at once."
    it.str = "tutuca"
    it.num = 5
    it.bool = true

tests:
  "every binding writes straight through":
    type("input.input-sm", "hey")
    expect state it.str == "hey"
    expect attr("input.input-sm", "title") == "Content is hey"
    type("input.input-sm", "7", ~nth: 1)
    expect state it.num == 7
    check("input.checkbox", true)
    expect state it.bool == true
`,
  },
  {
    name: "modifiers",
    source: `spec:
  EventModifiers:
    field query :: String
    field last_sent_search :: Any

view:
  EventModifiers:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@comment{ Three handlers, no script block: every one of them is a mutator the schema generated. The modifiers are guards — +send is Enter, +cancel is Escape. } @input(~type: "search", ~class: "input input-sm", ~value: it.query, ~on_input: it.query := e.value, ~on_keydown: it.last_sent_search := e.value ~send, ~on_keydown: it.query := default ~cancel, ~placeholder: "Search (Enter to send, Esc to clear)") @show(it.last_sent_search.is_truthy()){@p{@" Search: \\""@span(~class: "sent"){@(it.last_sent_search)}@"\\" "}}}}

fixtures:
  "a sent search":
    ~doc: "The paragraph a +send keydown reveals — seeded, since Any is the one field a fixture may fill with anything."
    it.last_sent_search = "shoes"

  "blank" ~default:
    ~doc: "Nothing typed and nothing sent."

tests:
  "enter sends what the box holds":
    expect count("span.sent") == 0
    type("input.input-sm", "shoes")
    key("input.input-sm", "Enter", "shoes")
    expect text("span.sent") == "shoes"
    expect state it.query == "shoes"

  "escape clears the box and leaves the sent value alone":
    type("input.input-sm", "shoes")
    key("input.input-sm", "Enter", "shoes")
    key("input.input-sm", "Escape")
    expect state it.query == ""
    expect state it.last_sent_search == "shoes"
`,
  },
  {
    name: "file-picker",
    source: `spec:
  FilePicker:
    field name :: String
    field size :: Double
    field type :: String
    field has_file :: Bool

logic:
  FilePicker:
    /// A change on a file input hands the handler the WHOLE file — an Obj with
    /// \`name\`, \`size\` and \`type\` on it — so the handler reads a place rooted at
    /// its own parameter. The steps below \`f\` are the steps \`.field\` takes, and
    /// what tells \`f.name\` from \`f .name\` is attachment, the rule already in
    /// force for \`min .a .b\` against \`min .a.b\`.
    ///
    /// One way only: an argument is a value the caller handed over rather than a
    /// position this component owns, so \`f.name = 'x'\` is refused by the parser.
    receive pick(f):
      if (f == none)
      | it.has_file := false
      | 
          it.name := f.name
          it.size := f.size
          it.type := f.type
          it.has_file := true

    /// The browser answers '' for a file whose type it cannot name, which is a
    /// word worth saying rather than an empty cell.
    compute type_label: if it.type.is_empty() | "unknown" | it.type

    /// \`size\` is a Double because that is what the event carries; \`int\` is how a
    /// card asks for the reading rather than the storage.
    compute size_label: @str{@(it.size.to_int()) bytes}

view:
  FilePicker:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@label(~class: "flex flex-col gap-1"){@span(~class: "text-sm opacity-70"){Pick a file} @input(~type: "file", ~class: "file-input file-input-sm", ~on_change: pick(e.value))} @show(it.has_file){@table(~class: "table"){@tbody{@tr{@th{Name}@td{@(it.name)}}@tr{@th{Size}@td{@(size_label())}}@tr{@th{Type}@td{@(type_label())}}}}} @hide(it.has_file){@p(~class: "opacity-70"){Nothing picked yet.}}}}

fixtures:
  "a picked file":
    ~doc: "The table filled in — what pick(f) copied off the file. A file input itself cannot be driven headless, so this is also how a scene starts when it wants the table."
    it.name = "photo.png"
    it.size = 20480
    it.type = "image/png"
    it.has_file = true

  "nothing yet" ~default:
    ~doc: "The empty state the card is honest about."
`,
  },
  {
    name: "scope",
    source: `spec:
  RenderWithScope:
    field text :: String

    message init

logic:
  RenderWithScope:
    receive init:
      it.text := "Hello"

    /// A scope enricher: handed no row, it answers the bindings the subtree
    /// below reads as \`@len\` and \`@upper\`.
    bind_with info:
      len = it.text.length()
      upper = it.text.upper()

view:
  RenderWithScope:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@input(~class: "input input-sm", ~value: it.text, ~on_input: it.text := e.value) @div(~enrich_with: info){@p{@"Text: "@span{@(it.text)}}@p{@"Len: "@span(~class: "len"){@(len)}}@p{@"Upper: "@span(~class: "upper"){@(upper)}}}}}

fixtures:
  "fresh" ~default:
    ~doc: "Hello, as the init handler spells it — and the two bindings its enricher derives."

  "typed longer":
    ~doc: "Reached by DOING rather than seeded: the init handler would overwrite a value's text, so a fixture that wants different text drives the box."
    ~drive:
      type("input.input-sm", "tutuca")

tests:
  "the subtree reads what the enricher wrote":
    send("init")
    expect text("span.len") == "5"
    expect text("span.upper") == "HELLO"
    type("input.input-sm", "tutuca")
    expect text("span.len") == "6"
    expect text("span.upper") == "TUTUCA"
`,
  },
  {
    name: "dynamic-bindings",
    source: `spec:
  Palette:
    field theme :: String
    field draft :: String
    field swatches :: List.of(Instance.of(Swatch))

    message init

    provide theme = it.theme

  Swatch:
    field label :: String

    lookup theme = "slate"

logic:
  Palette:
    receive init:
      it.theme := "rose"
      it.swatches.push(Swatch(label: "first"))
      it.swatches.push(Swatch(label: "second"))

    receive set_draft(t):
      it.draft := t

    receive set_theme(t):
      it.theme := t

    receive add:
      ~requires: typed
      it.swatches.push(Swatch(label: it.draft))
      it.draft := ""

    pred typed:
      ~format: @str{nothing to add}
      !(it.draft.is_empty())

view:
  Palette:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@label(~class: "text-sm opacity-70"){Theme, provided to the whole subtree} @input(~class: "theme input input-sm", ~value: it.theme, ~on_input: set_theme(e.value)) @div(~class: "flex gap-2"){@input(~class: "draft input input-sm flex-1", ~value: it.draft, ~on_input: set_draft(e.value)) @button(~class: "btn btn-sm", ~on_click: add){add}}@ul(~class: "flex flex-col gap-1"){@each(value, key in it.swatches){@render(value)}}}}

  Swatch:
    @li(~class: "row flex gap-2"){@span(~class: "label font-medium"){@(it.label)} @span(~class: "theme badge badge-sm"){@(dyn.theme)}}

fixtures:
  "two swatches" ~default:
    ~doc: "A theme the rows read, and two rows reading it."
    ~drive:
      send("init")

  "two swatches" ~default:
    ~doc: "A theme the rows read, and two rows reading it."
    ~drive:
      send("init")

tests:
  "every swatch reads the theme, and follows it":
    send("init")
    expect texts("span.theme") == ["rose", "rose"]
    type("input.theme", "amber")
    expect texts("span.theme") == ["amber", "amber"]

  "a swatch with nothing above it reads its default":
    ~component: Swatch
    ~args: {label: "alone"}
    expect text("span.theme") == "slate"
`,
  },
  {
    name: "list-enrich",
    source: `spec:
  ListFilterEnrich:
    field items :: List.of(String)
    field query :: String

    message init

logic:
  ListFilterEnrich:
    receive init:
      it.items.push("alpha")
      it.items.push("beta")
      it.items.push("gamma")
      it.items.push("delta")

    /// The loop asks the block twice per row: once whether to keep it, once
    /// for what the template cannot work out on its own.
    pred filter_item(value, key): (value.lower()).contains(it.query.lower())

    enrich enrich_item(value, key):
      count = value.length()

view:
  ListFilterEnrich:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@input(~type: "search", ~class: "input input-sm", ~value: it.query, ~on_input: it.query := e.value, ~on_keydown: it.query := default ~cancel, ~placeholder: "Filter entries") @ul(~class: "flex flex-col gap-1"){@each(value, key in it.items, ~when: filter_item, ~enrich_with: enrich_item){@li{@span{@(key)}@": "@(value)@" ("@(count)@" characters) "}}}}}

fixtures:
  "all four" ~default:
    ~doc: "The init handler fills the list; the empty query keeps every row."

  "narrowed to ga":
    ~doc: "The same four behind a query — the fixture seeds only what the person would have typed."
    it.query = "ga"

tests:
  "the loop asks the block twice per row":
    send("init")
    expect count("li") == 4
    expect text("li") contains "alpha (5 characters)"
    type("input.input-sm", "ga")
    expect count("li") == 1
    expect text("li") contains "gamma (5 characters)"
`,
  },
  {
    name: "list-iteration",
    source: `spec:
  Iteration:
    field items :: List.of(String)

    message init

logic:
  Iteration:
    receive init:
      it.items.push("first")
      it.items.push("second")
      it.items.push("third")

view:
  Iteration:
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-2"){@comment{ The two names a loop binds, and nothing else in the file. } @ul(~class: "flex flex-col gap-1"){@each(value, key in it.items){@li{@span(~class: "badge badge-sm badge-neutral"){@(key)} @(value)}}}}}

tests:
  "each row binds a key and a value":
    send("init")
    expect count("li") == 3
    expect text("span.badge-neutral") == "1" ~nth: 1
    expect text("li") contains "third" ~nth: 2
`,
  },
  {
    name: "markdown",
    source: `spec:
  MdPreview:
    field source :: String

    message init

logic:
  MdPreview:
    /// A whole document on one line: \`\\n\` is an escape a literal carries,
    /// beside \`\\'\`, \`\\\\\`, \`\\t\` and \`\\r\`. (A literal may also span lines
    /// as itself — either spelling means the same string.)
    receive init:
      it.source := "# Markdown\\n\\nType on the left, read on the right.\\n\\n- a list\\n- of things\\n\\n> and a quote\\n"

view:
  MdPreview:
    @div(~class: "flex gap-3 items-stretch"){@textarea(~class: "textarea flex-1 font-mono text-xs", ~spellcheck: "false", ~value: it.source, ~on_input: it.source := e.value) @comment{ Markdown, rendered straight into the vdom by the render-time filter — no handler, no library on the page. } @div(~class: "flex-1 p-3 bg-base-100 rounded overflow-auto", ~inner_md: it.source)}

fixtures:
  "a different document":
    ~doc: "Reached by typing rather than seeded, for the usual reason: init would overwrite the value."
    ~drive:
      type("textarea", "# Cheatsheet\\n\\n- heads\\n- lists\\n")

  "starter document" ~default:
    ~doc: "What the init handler types, already rendered on the right."

tests:
  "typing renders markdown live":
    send("init")
    expect html contains "<h1>"
    expect html contains "<li>of things</li>"
    type("textarea", "# Typed\\n\\n- one")
    expect html contains "<h1>Typed</h1>"
    expect html contains "<li>one</li>"
`,
  },
  {
    name: "text",
    source: `spec:
  TextDirective:
    field str :: String
    field num :: Int
    field bool :: Bool
    field not_set :: Any

    message init

logic:
  TextDirective:
    receive init:
      it.str := "hello"
      it.num := 42
      it.bool := true

    /// The method the last row calls. \`upper\` is the fold \`lower\` always had
    /// a twin for.
    compute get_str_upper: it.str.upper()

view:
  TextDirective:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body grid grid-cols-[auto_auto] gap-x-4 gap-y-2 items-center"){@span{String:} @span{@(it.str)} @span{Number:} @span{@(it.num)} @span{Boolean:} @(it.bool) @comment{ A Null renders as nothing at all, not as the word "null". } @span{notSet:} @span{@(it.not_set)} @span{Method call:} @span{@(get_str_upper())}}}

tests:
  "what each spelling renders":
    send("init")
    expect state it.num == 42
    expect text("span") == "42" ~nth: 3
    expect text("span") == "" ~nth: 6
    expect text("span") == "HELLO" ~nth: 8
`,
  },
  {
    name: "raw-html",
    source: `spec:
  DangerSetInnerHtml:
    field content :: String

    message init

logic:
  DangerSetInnerHtml:
    receive init:
      it.content := "<b>bold</b> and <i>italic</i>, straight into the DOM"

view:
  DangerSetInnerHtml:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@comment{ The escape hatch, named so nobody reaches for it by accident. } @div(~class: "p-2 bg-base-100 rounded", ~dangerously_inner_html: it.content) @textarea(~class: "textarea font-mono text-xs", ~value: it.content, ~on_input: it.content := e.value)}}
`,
  },
  {
    name: "conditional-attrs",
    source: `spec:
  ConditionalAttributes:
    field is_active :: Bool

view:
  ConditionalAttributes:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body"){@comment{@" Two @if on one element, so every @then/@else after the first names its attribute: HTML forbids duplicate attributes, and the parser would drop the second pair before tutuca saw it. "} @button(~class: if it.is_active | "btn btn-success" | "btn btn-ghost", ~title: if it.is_active | "Click to disable" | "Click to enable", ~on_click: it.is_active := !it.is_active){@show(it.is_active){@span{Enabled}} @hide(it.is_active){@span{Disabled}}}}}

fixtures:
  "disabled" ~default:
    ~doc: "The ghost half of both conditional attributes."

  "enabled":
    ~doc: "The success half — one field, two attributes following it."
    it.is_active = true

tests:
  "both attributes follow the flag":
    expect attr("button", "class") == "btn btn-ghost"
    expect attr("button", "title") == "Click to enable"
    click("button")
    expect attr("button", "class") == "btn btn-success"
    expect attr("button", "title") == "Click to disable"
    expect text("span") == "Enabled"
`,
  },
  {
    name: "styles",
    source: `spec:
  Styled:
    field loud :: Bool

logic:
  Styled:
    compute label: if it.loud | "quieten it" | "make it loud"

view:
  @style{.common { color: mediumaquamarine; font-style: italic; }}

  @style(~global){.styled-global { color: violet; text-decoration: underline dotted; }}

  Styled:
    @style{.mine { color: gold; font-weight: 600; } .mine.loud { font-size: 1.4rem; letter-spacing: .05em; }}
    @comment{ A <style> inside a template belongs to THAT view: the runtime scopes it to the component's own nodes, so \`.mine\` here reaches neither the page around the card nor another card on it. }
    @" "
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@comment{ A class list and a scoped rule compose: \`card\`, \`btn\` and the rest are compiled by margaui, \`mine\` is this file's. Switching between whole literals is what keeps both readable to the collector. } @p(~class: if it.loud | "mine loud" | "mine"){@" styled by the view's own block "}@p(~class: "common"){styled by the file's common block}@p(~class: "styled-global"){styled by the global block} @button(~class: "btn btn-sm", ~on_click: it.loud := !it.loud){@(label())}}}

fixtures:
  "loud":
    ~doc: "The modifier class on, and the whole literal switched with it."
    it.loud = true

  "quiet" ~default:
    ~doc: "The scoped rule alone."

tests:
  "the class list switches as a whole literal":
    expect attr("p.mine", "class") == "mine"
    expect text("button.btn-sm") == "make it loud"
    click("button.btn-sm")
    expect attr("p.mine", "class") == "mine loud"
    expect attr("p.common", "class") == "common"
    expect attr("p.styled-global", "class") == "styled-global"
`,
  },
  {
    name: "swatches",
    source: `spec:
  SwatchPicker:
    field color :: String
    field palette :: List.of(String)

    message init

logic:
  SwatchPicker:
    receive init:
      it.color := "#ef4444"
      it.palette.push("#ef4444")
      it.palette.push("#f59e0b")
      it.palette.push("#10b981")
      it.palette.push("#3b82f6")
      it.palette.push("#8b5cf6")

    /// Lay each swatch out along the row, and ring the selected one. Both are
    /// answers ABOUT the row, which is what an enricher is for — the loop hands
    /// it \`@key\` and \`@value\`, and the template reads what it wrote.
    enrich swatch(value, key):
      cx = (32 + (key * 46))
      ring = if (value == it.color) | "#111827" | "transparent"

view:
  SwatchPicker:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-2"){@svg(~viewBox: "0 0 380 130", ~role: "img"){@rect(~x: "20", ~y: "12", ~width: "340", ~height: "52", ~rx: "8", ~fill: it.color) @each(value, key in it.palette, ~enrich_with: swatch){@circle(~cx: cx, ~cy: "98", ~r: "18", ~fill: value, ~stroke_width: "3", ~stroke: ring, ~on_click: it.color := value)}} @p(~class: "text-sm"){@"Selected: "@(it.color)}}}

fixtures:
  "blue picked":
    ~doc: "The ring moved, without moving it."
    it.color = "#3b82f6"

  "five swatches" ~default:
    ~doc: "Red selected, as the init handler leaves it."

tests:
  "picking a swatch moves the ring":
    send("init")
    expect attr("circle", "stroke") == "#111827"
    expect attr("circle", "stroke") == "transparent" ~nth: 1
    click("circle", ~nth: 3)
    expect state it.color == "#3b82f6"
    expect attr("rect", "fill") == "#3b82f6"
    expect attr("circle", "stroke") == "transparent"
    expect attr("circle", "stroke") == "#111827" ~nth: 3
`,
  },
  {
    name: "quadratic",
    source: `spec:
  Quadratic:
    field a :: Int
    field b :: Int
    field c :: Int

    message init

logic:
  Quadratic:
    receive init:
      it.a := 1
      it.b := -3
      it.c := 2

    /// b² − 4ac, and what it says about the roots. \`classify\` calls
    /// \`discriminant\` by name, which is how one body reaches another.
    compute discriminant: ((it.b * it.b) - (4 * it.a * it.c))

    compute classify: if (discriminant > 0) | "two distinct real roots" | (if (discriminant == 0) | "one repeated real root" | "no real roots")

view:
  Quadratic:
    @div(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@div(~class: "flex gap-3 text-sm"){@label(~class: "flex items-center gap-1"){@"a "@input(~type: "number", ~class: "input input-sm w-16", ~value: it.a, ~on_input: it.a := e.valueAsInt)} @label(~class: "flex items-center gap-1"){@"b "@input(~type: "number", ~class: "input input-sm w-16", ~value: it.b, ~on_input: it.b := e.valueAsInt)} @label(~class: "flex items-center gap-1"){@"c "@input(~type: "number", ~class: "input input-sm w-16", ~value: it.c, ~on_input: it.c := e.valueAsInt)}} @comment{ MathML, namespaced by the subtree it sits in — no directive needed. } @math(~display: "block"){@mn{@(it.a)}@mo{⁢} @msup{@mi{x}@mn{2}}@mo{+} @mn{@(it.b)}@mo{⁢}@mi{x}@mo{+} @mn{@(it.c)}@mo{=}@mn{0}} @p(~class: "verdict"){@"Discriminant: "@(discriminant())@" — "@(classify())}}}

fixtures:
  "repeated root":
    ~doc: "Reached by typing, since the init handler would overwrite seeded coefficients: b = −2, c = 1 lands the discriminant on zero."
    ~drive:
      type("input.input-sm", "-2", ~nth: 1)
      type("input.input-sm", "1", ~nth: 2)

  "two distinct real roots" ~default:
    ~doc: "What the init handler seeds: 1, −3, 2 — discriminant 1."

tests:
  "the verdict follows the coefficients":
    send("init")
    expect text("p.verdict") contains "1 — two distinct real roots"
    type("input.input-sm", "2", ~nth: 1)
    expect state it.b == 2
    expect text("p.verdict") contains "-4"
    expect text("p.verdict") contains "no real roots"
    type("input.input-sm", "1", ~nth: 2)
    expect text("p.verdict") contains "one repeated real root"
`,
  },
  {
    name: "nested-state",
    source: `spec:
  Nested:
    field title :: String
    field draft :: String
    field labels :: List.of(Label)

    message init

  struct Label(text :: String, done :: Bool)

logic:
  Nested:
    /// \`new\` builds the zero of a declared type and puts it at \`cur\`; the
    /// statements under it fill it in, and \`push\` takes it from there. This is
    /// what a card could not do until the language had a way to NAME a value
    /// being built — there is no record literal, and \`cur\` is why none is
    /// needed.
    receive init:
      it.title := "Nested state"
      it.labels.push(Label(text: "read the schema"))
      it.labels.push(Label(text: "write a handler", done: true))

    receive add_label:
      if (it.draft.trim() != "")
      | 
          it.labels.push(Label(text: it.draft.trim()))
          it.draft := ""

    /// A nested WRITE: \`.labels[key].done\` is the place, and the spine above it
    /// is rebuilt. This is the pair a view slot cannot spell.
    receive toggle_label(key):
      it.labels[key].done := !it.labels[key].done

view:
  Nested:
    @div(~class: "card bg-base-200 max-w-md"){
      @div(~class: "card-body gap-3"){
        @h2(~class: "card-title"){@(it.title)}
        @div(~class: "flex gap-2 items-center"){@input(~class: "input input-sm w-full draft", ~placeholder: "add a label", ~value: it.draft, ~on_input: it.draft := e.value, ~on_keydown: add_label ~send) @button(~class: "btn btn-sm btn-primary", ~on_click: add_label){add}}
        @ul(~class: "flex flex-col gap-1"){
          @each(value, key in it.labels){
            @li{@button(~class: if value.done | "btn btn-xs btn-success" | "btn btn-xs", ~on_click: toggle_label(key)){@(value.text)}}
          }
        }
      }
    }

fixtures:
  "one added by doing":
    ~doc: "The third label, arrived at by typing and pressing — a record built at runtime is reached by running what builds it."
    ~drive:
      type("input.draft", "ship it")
      click("button.btn-primary")

  "seeded by init" ~default:
    ~doc: "Two labels, as the init handler builds them with new."

tests:
  "init builds two records, one already done":
    send("init")
    expect count("li") == 2
    expect text("button.btn-xs") == "write a handler" ~nth: 1
    expect attr("button.btn-xs", "class") == "btn btn-xs btn-success" ~nth: 1

  "toggling writes through the nested place":
    send("init")
    click("button.btn-xs", ~nth: 1)
    expect state it.labels[1].done == false
    expect attr("button.btn-xs", "class") == "btn btn-xs" ~nth: 1

  "adding appends another record":
    send("init")
    type("input.draft", "ship it")
    click("button.btn-primary")
    expect state it.draft == ""
    expect count("li") == 3
    expect text("button.btn-xs") == "ship it" ~nth: 2
`,
  },
  {
    name: "contracts",
    source: `spec:
  Seats:
    field capacity :: Int
    field taken :: Int
    field waiting :: Int

    /// THE INVARIANT — the one rule nothing has to mention. It is checked after
    /// every transition this block declares, including the ones written
    /// without a thought for it.
    ///
    /// A rule is declared in \`spec:\` beside the fields it is about, with the
    /// \`pred\`s a handler names: what a component GUARANTEES is part of what it
    /// is, not part of what it does.
    invariant within_capacity: (it.taken <= it.capacity)

    message init

logic:
  Seats:
    receive init:
      it.capacity := 6
      it.taken := 2
      it.waiting := 3

    /// A \`pred\` names a rule. Where it ATTACHES is what the rule IS — the same
    /// three names below are read by the badges at the bottom, which is the
    /// point of a rule having a name at all.
    pred can_seat: ((it.waiting > 0) && (it.taken < it.capacity))

    pred someone_seated: (it.taken > 0)

    pred none_waiting: (it.waiting == 0)

    /// PRECONDITION — asked before the body, against the state as it arrived,
    /// so a refusal needs no rollback. One clause of each kind per handler:
    /// two rules become one by naming their \`and\`, which is what \`canSeat\` is.
    receive seat:
      ~requires: can_seat
      it.taken += 1
      it.waiting -= 1

    receive stand:
      ~requires: someone_seated
      it.taken -= 1
      it.waiting += 1

    /// POSTCONDITION — asked after the body, against the successor. There is no
    /// \`old\`, so what an \`ensures\` says is where the transition had to LAND.
    receive seat_all:
      ~ensures: none_waiting
      it.taken += it.waiting
      it.waiting := 0

    /// The same claim, from a handler that seats one person. It holds when one
    /// is all there was, and otherwise the rule catches the lie: the transition
    /// is abandoned whole — no successor, no effects — and
    /// \`@tutuca.postcondition_failed\` goes through the warn hook with the
    /// handler and the rule in it. Open the console and press it with three
    /// people waiting.
    receive rush:
      ~ensures: none_waiting
      it.taken += 1
      it.waiting -= 1

    receive queue:
      it.waiting += 1

    /// Refused by a rule it does not name, and reported rather than silent —
    /// which is the whole difference between a contract and an \`if\` at the top
    /// of the body.
    receive overbook:
      it.taken := (it.capacity + 1)

view:
  Seats:
    @div(~class: "card bg-base-200 max-w-md"){
      @div(~class: "card-body gap-3"){
        @div(~class: "stats bg-base-100"){
          @div(~class: "stat"){
            @div(~class: "stat-title"){seated}
            @div(~class: "stat-value text-2xl"){@(it.taken)}
          }
          @div(~class: "stat"){
            @div(~class: "stat-title"){waiting}
            @div(~class: "stat-value text-2xl"){@(it.waiting)}
          }
          @div(~class: "stat"){
            @div(~class: "stat-title"){capacity}
            @div(~class: "stat-value text-2xl"){@(it.capacity)}
          }
        }
        @div(~class: "flex gap-2 items-center flex-wrap"){@div(~class: "join"){@button(~class: "btn btn-sm join-item", ~on_click: seat){seat one} @button(~class: "btn btn-sm join-item", ~on_click: stand){stand one} @button(~class: "btn btn-sm join-item", ~on_click: queue){queue one}}@div(~class: "join"){@button(~class: "btn btn-sm btn-primary join-item", ~on_click: seat_all, ~title: "a postcondition it keeps"){seat all} @button(~class: "btn btn-sm btn-soft btn-warning join-item", ~on_click: rush, ~title: "a postcondition it only keeps when one was all there was"){rush}} @button(~class: "btn btn-sm btn-soft btn-error", ~on_click: overbook, ~title: "refused by the invariant, and reported"){overbook}}
        @ul(~class: "flex flex-col gap-1 font-mono text-xs"){
          @li(~class: "flex gap-2 items-center"){@span(~class: if within_capacity() | "badge badge-sm badge-success" | "badge badge-sm badge-error"){@(within_capacity())}@" withinCapacity: the invariant, kept after every handler "}
          @li(~class: "flex gap-2 items-center"){@span(~class: if can_seat() | "badge badge-sm badge-success" | "badge badge-sm badge-error"){@(can_seat())}@" canSeat: what \`seat\` asks before it moves anybody "}
          @li(~class: "flex gap-2 items-center"){@span(~class: if none_waiting() | "badge badge-sm badge-success" | "badge badge-sm badge-error"){@(none_waiting())}@" noneWaiting: where \`seat all\` and \`rush\` have to land "}
        }
      }
    }

fixtures:
  "early doors" ~default:
    ~doc: "Two seated, three waiting — what the init handler seeds."

  "one from full":
    ~doc: "Seat everybody, queue one more: the state rush declines from. Reached by driving, since init would overwrite seeded numbers."
    ~drive:
      send("seat_all")
      send("queue")

tests:
  "seat moves one across and says nothing":
    send("init")
    send("seat")
    expect state it.taken == 3
    expect state it.waiting == 2
    expect log == []

  "a precondition turns the handler away before it moves anybody":
    send("init")
    send("seat_all")
    expect state it.taken == 5
    send("seat")
    expect state it.taken == 5
    expect log contains "its precondition"

  "rush abandons whole when more than one waits":
    send("init")
    send("rush")
    expect state it.taken == 2
    expect state it.waiting == 3
    expect log contains "was abandoned"

  "the invariant refuses overbook without being asked":
    send("init")
    send("overbook")
    expect state it.taken == 2
    expect log contains "broke the invariant"
`,
  },
  {
    name: "macros",
    source: `spec:
  MacroDemo:
    field count :: Int
    field status :: String

    message init

logic:
  MacroDemo:
    receive init:
      it.status := "warning"

    receive inc:
      it.count += 1

view:
  /// A macro is pure template expansion: no state, no handlers, no lifecycle.
  /// \`~on_click: inc\` inside one calls \`inc\` on the COMPONENT it expanded
  /// into, which is the whole difference from a child component.
  macro badge(~label: "New", ~kind: "neutral"):
    @span(~class: if kind | @str{badge badge-@(kind)} | "badge"){@(label)}

  /// \`@slot\` is where the call's children go, and \`@slot("name")\` is a second
  /// place to put some of them.
  macro panel(~title: "Panel"):
    @div(~class: "card bg-base-100"){
      @div(~class: "card-body gap-2"){
        @h3(~class: "card-title text-base"){@(title)}
        @slot
        @div(~class: "card-actions"){@slot("actions")}
      }
    }

  MacroDemo:
    @div(~class: "card bg-base-200 max-w-md"){
      @div(~class: "card-body gap-3"){
        @comment{ A parameter, a default, and a DYNAMIC one read off the state. }
        @p(~class: "flex gap-2 items-center"){
          @badge()
          @badge(~label: "Sale", ~kind: "success")
          @badge(~label: "Live", ~kind: it.status)
        }
        @comment{ The default slot takes the children; a named one takes the ones that ask for it by name. }
        @panel(~title: "Slots"){
          @p{This paragraph is the macro call's child.}
          @fill("actions"){
            @button(~class: "btn btn-sm btn-primary", ~on_click: inc){+1}
          }
        }
        @p{@"Count: "@(it.count)}
      }
    }

fixtures:
  "fresh" ~default:
    ~doc: "Count at zero and the Live badge reading the status the init handler set."

  "pressed once":
    ~doc: "The one field a macro card of this shape owns — macros themselves hold nothing."
    it.count = 1

tests:
  "a macro expands into the component around it":
    send("init")
    expect text("span.badge-neutral") == "New"
    expect attr("span.badge", "class") == "badge badge-success" ~nth: 1
    expect attr("span.badge", "class") == "badge badge-warning" ~nth: 2
    click("button.btn-primary")
    expect state it.count == 1
    expect text("p") == "Count: 1" ~nth: 2
`,
  },
  {
    name: "drag-reorder",
    source: `spec:
  Reorder:
    field items :: List.of(String)
    field query :: String

    message init

logic:
  Reorder:
    receive init:
      it.items.push("write the ones")
      it.items.push("read the twos")
      it.items.push("review the threes")
      it.items.push("ship the fours")
      it.items.push("plan the fives")

    /// Filtering keeps the keys it hides: a row's @key is its index in .items,
    /// not its position on screen, which is why the two indices a drop names
    /// still address the list.
    pred filter_item(value, key): (value.lower()).contains(it.query.lower())

    /// A drop fires on the TARGET row, and \`dragKey\` answers the SOURCE row's
    /// @key — the one thing the target cannot see for itself, since the source's
    /// binds only exist on the stack the drag captured. Asking for it by name is
    /// what makes this a card at all: \`dragInfo\` carries a lookupBind FUNCTION,
    /// and a block cannot apply a function it did not name.
    ///
    /// Both arms read the row before they move it, and the second index accounts
    /// for the shift the insert just caused.
    receive move_row(target, source):
      if (source != target)
      | 
          if (source < target)
          | 
              it.items.insert_at((target + 1), it.items[source])
              it.items.delete_at(source)
          | 
              it.items.insert_at(target, it.items[source])
              it.items.delete_at((source + 1))

view:
  Reorder:
    @style{/* The two attributes tutuca manages during a drag. No class route exists for either — they are set on the live nodes — so this is the one card that has to say something a utility class cannot. */ [data-dragging="1"] { opacity: .5; } [data-draggingover="reorder-row"] { outline: 1px dashed currentColor; outline-offset: 2px; }}
    @section(~class: "card bg-base-200 max-w-md"){@div(~class: "card-body gap-3"){@input(~type: "search", ~class: "input input-sm", ~value: it.query, ~on_input: it.query := e.value, ~on_keydown: it.query := default ~cancel, ~placeholder: "Filter entries") @comment{ data-dragtype on the source and data-droptarget on the target pair a draggable with where it may land; both are on the same row here, since every row is both. } @ul(~class: "flex flex-col gap-1"){@each(value, key in it.items, ~when: filter_item){@li(~class: "badge badge-ghost w-full justify-start gap-2 cursor-grab", ~draggable: "true", ~data_dragtype: "reorder-row", ~data_droptarget: "reorder-row", ~on_drop: move_row(key, e.dragKey)){@span(~class: "opacity-60"){@(key)} @(value)}}}}}

fixtures:
  "filtered to the t rows":
    ~doc: "Two of five visible. The hidden keys are what a drop still addresses, which is the scene below."
    it.query = "the t"

  "five rows" ~default:
    ~doc: "What the init handler pushes, in order."

tests:
  "a drop moves the row after the target":
    send("init")
    drag("li.cursor-grab", 0, 2)
    expect state it.items == ["read the twos", "review the threes", "write the ones", "ship the fours", "plan the fives"]
    expect text("li.cursor-grab") contains "write the ones" ~nth: 2

  "a drop names list places, not screen positions":
    send("init")
    type("input.input-sm", "the t")
    expect count("li.cursor-grab") == 2
    drag("li.cursor-grab", 0, 1)
    expect state it.items == ["write the ones", "review the threes", "read the twos", "ship the fours", "plan the fives"]

  "dropping a row on itself changes nothing":
    send("init")
    drag("li.cursor-grab", 1, 1)
    expect state it.items == ["write the ones", "read the twos", "review the threes", "ship the fours", "plan the fives"]
`,
  },
];
