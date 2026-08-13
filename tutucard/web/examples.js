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
];
