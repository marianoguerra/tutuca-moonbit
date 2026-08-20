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
// `todo` holds an `Array[String]` because it was written before `new` — a list
// of RECORDS is what `nested-state` shows, where `new Label` puts the type's
// zero at `@cur` and the statements under it fill it in.

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

<template>
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
`,
  },
  {
    name: "todo",
    source: `<script type="tutuca/state">
  state Todo {
    draft : String
    items : Array[String]
    done  : Set[String]
  }
</script>

<script type="tutuca/script">
  /// Add the draft, unless it is only whitespace. The guard is the whole
  /// handler: everything else a list needs is a generated mutator.
  receive addItem {
    if (trim .draft) is not '' {
      .items.push (trim .draft)
      .draft = ''
    }
  }
  receive removeAt(i) { .items.deleteAt i }

  compute caption { $'{(len .items)} item(s)' }
  compute anyItems { not (empty? .items) }
</script>

<template>
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title">Todos</h2>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full" placeholder="what needs doing"
               :value=".draft" @on.input="setDraft e.value"
               @on.keydown+send="addItem">
        <button class="btn btn-sm btn-primary" @on.click="addItem">add</button>
      </div>
      <ul class="flex flex-col gap-2" @show="$anyItems">
        <li class="flex gap-3 items-center w-full" @each=".items">
          <input type="checkbox" class="checkbox checkbox-sm"
                 @on.click="toggleInDone @value">
          <span class="w-full"><x text="@value"></x></span>
          <button class="btn btn-xs btn-soft btn-error btn-circle"
                  @on.click="removeAt @key">&times;</button>
        </li>
      </ul>
      <p class="opacity-60 italic" @hide="$anyItems">nothing yet</p>
      <span class="badge badge-sm badge-neutral"><x text="$caption"></x></span>
    </div>
  </div>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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
        Search: "<span @text=".lastSentSearch"></span>"
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

<template>
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

<template>
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input class="input input-sm" :value=".text" @on.input="setText e.value">
      <div @enrich-with="info">
        <p>Text: <span @text=".text"></span></p>
        <p>Len: <span @text="@len"></span></p>
        <p>Upper: <span @text="@upper"></span></p>
      </div>
    </div>
  </section>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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

<template>
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
      <p>Discriminant: <x text="$discriminant"></x> — <x text="$classify"></x></p>
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

<template>
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title" @text=".title"></h2>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full" placeholder="add a label"
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

<template>
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

<!-- A macro is pure template expansion: no state, no handlers, no lifecycle.
     \`@on.click="inc"\` inside one calls \`inc\` on the COMPONENT it expanded
     into, which is the whole difference from a child component.

     A card may DECLARE several components now — one \`state\` each, one
     \`<script ... for="Comp">\` each, \`<template id="Comp:main">\` — and a
     host may mount any of them. What it still cannot do is BUILD one while it
     runs: \`new\` makes a declared record, not an instance, so a card composes
     children something else created. A macro needs none of that, which is why
     it was always the answer here.

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

<template>
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
