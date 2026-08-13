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
// Write them as LITERAL lists. The collector reads what the views say, so a
// class name assembled at runtime is a class name that never gets compiled —
// which is also why `@if.class` switches between whole literals.
//
// Nine of these are MIGRATED from `storybook/examples/` and
// `playground/site/examples/` — the same demos the compiled gallery shows,
// with their `update` arms moved into the block and their MoonBit `compute`
// entries into `compute` declarations. What each migration cost, and which of
// the corpus is still out of reach, is in `docs/cards-from-examples.md`.
//
// Two limits are visible here and are the language's rather than the page's.
// **There is no record literal**, so an `Array[Struct]` can be read, indexed and
// written through, but never APPENDED to from a card — which is why `todo`
// below holds an `Array[String]`. And a condition slot still takes `$name`
// rather than a bare predicate application, so `@show="$anyItems"` is how a
// `pred` is used from a template today.

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
  on add(d) {
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
        <input class="input input-sm w-full" :value=".label" @on.input="setLabel value">
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
  on addItem {
    if (trim .draft) is not '' {
      .items.push (trim .draft)
      .draft = ''
    }
  }
  on removeAt(i) { .items.deleteAt i }

  compute caption { $'{(len .items)} item(s)' }
  compute anyItems { not (empty? .items) }
</script>

<template>
  <div class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <h2 class="card-title">Todos</h2>
      <div class="flex gap-2 items-center">
        <input class="input input-sm w-full" placeholder="what needs doing"
               :value=".draft" @on.input="setDraft value"
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
  receive Filter { Init }
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
               :value=".query" @on.input="setQuery value">
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
  receive Inbox { Note(String), Bump(Int) }
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
  on shout { send 'note' 'shouted' }
  on quiet { send 'note' 'quiet' }
  on five { send 'bump' 5 }
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
    name: "traffic-light",
    source: `<script type="tutuca/state">
  state TrafficLight {
    lightIndex : Int
  }
</script>

<script type="tutuca/script">
  /// Step to the next colour, wrapping at the end of the cycle.
  on nextLight {
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
  on incCount {
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
      <input class="input input-sm" :value=".str" @on.input="setStr value"
             :title="$'Content is {.str}'">
      <!-- \`valueAsInt\` rather than a handler that parses the string: the
           argument names are where a card does its conversions. -->
      <input class="input input-sm" type="number" :value=".num"
             @on.input="setNum valueAsInt">
      <label class="flex gap-2 items-center">
        <input class="checkbox checkbox-sm" type="checkbox" :checked=".bool"
               @on.input="setBool value">
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
        @on.input="setQuery value"
        @on.keydown+send="setLastSentSearch value"
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
    name: "scope",
    source: `<script type="tutuca/state">
  state RenderWithScope {
    text : String
  }

  receive RenderWithScope { Init }
</script>

<script type="tutuca/script">
  receive init { .text = 'Hello' }

  /// A scope enricher: handed no row, it answers the bindings the subtree
  /// below reads as \`@len\` and \`@lower\`.
  ///
  /// The MoonBit original bound \`@upper\`. The reading vocabulary has
  /// \`lower\` and no \`upper\`, so the migration lowercases instead — the one
  /// place a card cannot follow this example word for word.
  enrichScope info {
    @len = len .text
    @lower = lower .text
  }
</script>

<template>
  <section class="card bg-base-200 max-w-md">
    <div class="card-body gap-3">
      <input class="input input-sm" :value=".text" @on.input="setText value">
      <div @enrich-with="info">
        <p>Text: <span @text=".text"></span></p>
        <p>Len: <span @text="@len"></span></p>
        <p>Lower: <span @text="@lower"></span></p>
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

  receive ListFilterEnrich { Init }
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
        @on.input="setQuery value" @on.keydown+cancel="resetQuery"
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

  receive Iteration { Init }
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

  receive MdPreview { Init }
</script>

<script type="tutuca/script">
  /// One line, because a string literal in the block language has two
  /// escapes — \\' and \\\\ — and no \\n, and no multi-line spelling. Seeding a
  /// document means typing one, which for this example is the point anyway.
  receive init {
    .source = '# Markdown — type on the left, read on the right'
  }
</script>

<template>
  <div class="flex gap-3 items-stretch">
    <textarea class="textarea flex-1 font-mono text-xs" spellcheck="false"
      :value=".source" @on.input="setSource value"></textarea>
    <!-- Markdown, rendered straight into the vdom by the render-time filter —
         no handler, no library on the page. -->
    <div class="flex-1 p-3 bg-base-100 rounded overflow-auto"
      @setinnermd=".source"></div>
  </div>
</template>
`,
  },
];
