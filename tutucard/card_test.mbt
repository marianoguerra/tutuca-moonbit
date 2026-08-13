// A card, mounted and driven.
//
// The point of this file is the absence: there is no component definition, no
// `update` match, no generated module, and no `moonc` involved in what the
// card does. A `.html` file goes in and a live app comes out.
//
// It is driven through `@harness`, the same headless harness every other
// component test in the repo uses — which is itself part of the claim. A card
// is not a second kind of component with its own test surface; it mounts,
// clicks and reads back exactly like a compiled one.

///|
/// The counter, as a card. Compare `demo/counterlib/counter.html` plus the
/// 30-line `counterlib.mbt` beside it: this is both halves.
fn counter_card() -> String {
  (
    #|<script type="tutuca/state">
    #|  state {
    #|    label   : String
    #|    count   : Int
    #|    history : Array[Int]
    #|  }
    #|  receive { ResetTo(Int) }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  /// Move the counter by d, remembering where it landed.
    #|  on add(d) {
    #|    .count += d
    #|    .history.push .count
    #|  }
    #|  receive resetTo(n) {
    #|    .count = n
    #|    .history.push n
    #|  }
    #|  compute summary { $'{.label}: {.count}' }
    #|</script>
    #|
    #|<template>
    #|  <div class="counter">
    #|    <h1 id="summary"><x text="$summary"></x></h1>
    #|    <span id="count"><x text=".count"></x></span>
    #|    <button id="inc" @on.click="add 1">+1</button>
    #|    <button id="dec" @on.click="add -1">-1</button>
    #|    <button id="reset" @on.click="resetCount">reset</button>
    #|    <input id="label" :value=".label" @on.input="setLabel value">
    #|    <ul id="history"><li @each=".history"><x text="@value"></x></li></ul>
    #|  </div>
    #|</template>
  )
}

///|
/// Mount a card as an app, the ordinary way.
fn mount_card(
  source : String,
  name? : String = "Counter",
) -> @harness.Harness raise {
  let card = @tutucard.load(source, name~)
  assert_eq(card.issues.map(i => i.message), [])
  let m = @component.ModuleDef::new(
    name="card",
    components=[card.component],
    macros=card.macros,
  )
  @harness.mount(m, name)
}

///|
test "a card mounts, renders and dispatches with no MoonBit behind it" {
  let h = mount_card(counter_card())
  assert_eq(h.text("#count"), "0")
  h.click("#inc")
  assert_eq(h.text("#count"), "1")
  h.click("#inc")
  assert_eq(h.text("#count"), "2")
  h.click("#dec")
  assert_eq(h.text("#count"), "1")
  // …and the statement after the assignment ran too.
  assert_eq(h.texts("li"), ["1", "2", "1"])
  h.destroy()
}

///|
test "the mutators a card gets for free" {
  // `resetCount` and `setLabel` are answered by NOTHING in the script. They
  // come from `schema_mutators` over the declared schema — the same generator
  // a wasm guest's come from — which is why two thirds of the components in
  // the corpus need no handler at all.
  let h = mount_card(counter_card())
  h.click("#inc")
  assert_eq(h.text("#count"), "1")
  h.click("#reset")
  assert_eq(h.text("#count"), "0")
  h.type_into("#label", "Tally")
  assert_eq(h.text("#summary"), "Tally: 0")
  h.destroy()
}

///|
test "a compute is read from a slot like any other $name" {
  let h = mount_card(counter_card())
  assert_eq(h.text("#summary"), ": 0")
  h.click("#inc")
  assert_eq(h.text("#summary"), ": 1")
  h.destroy()
}

///|
test "a receive arm answers a message the views never write" {
  // The whole reason the schema declares `variant receive`: no template
  // mentions `resetTo`, so before the schema it could only be matched as a
  // string.
  let h = mount_card(counter_card())
  h.click("#inc")
  h.click("#inc")
  assert_eq(h.text("#count"), "2")
  h.send_at_root("resetTo", args=[Num(9)])
  assert_eq(h.text("#count"), "9")
  assert_eq(h.texts("li"), ["1", "2", "9"])
  h.destroy()
}

///|
test "a card's instance answers the schema, so an inspector can read it" {
  let h = mount_card(counter_card())
  guard! h.drive_value() is Obj(o)
  guard! o.obj_schema() is Some(si)
  assert_eq(si.name, "Counter")
  assert_eq(si.field_names(), ["label", "count", "history"])
  // What the card ANSWERS is what its script declares, plus the messages the
  // schema does.
  assert_eq(si.inputs, ["add"])
  assert_eq(si.receives, ["resetTo"])
  assert_eq(si.methods, ["summary"])
  assert_eq(si.view_names, ["main"])
  h.destroy()
}

///|
/// A list card whose loop asks the block two questions about every row.
fn crew_card() -> String {
  (
    #|<script type="tutuca/state">
    #|  state { query : String, names : Array[String] }
    #|  receive { Init }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  receive init { .names.push 'Ada'; .names.push 'Grace'; .names.push 'Alan' }
    #|  pred matches {
    #|    (empty? .query) or (contains (lower @value) (lower .query))
    #|  }
    #|  enrich row { @tag = $'{@key}:{@value}' }
    #|</script>
    #|
    #|<template>
    #|  <div>
    #|    <input id="q" :value=".query" @on.input="setQuery value">
    #|    <ul><li @each=".names" @when="matches" @enrich-with="row"><x text="@tag"></x></li></ul>
    #|  </div>
    #|</template>
  )
}

///|
test "a @when predicate and an @enrich-with both see the row" {
  // The two are one claim: the renderer hands a filter and an enricher the
  // row's (key, value, iterData), and a card body reads those as the BINDS
  // `@key` / `@value` — not as parameters, which is why neither declares any.
  // A `pred` reached as a plain callable instead read `@value` as Null, and a
  // filter that keeps every row is the quietest possible failure.
  let h = mount_card(crew_card(), name="Crew")
  h.send_at_root("init")
  assert_eq(h.texts("li"), ["0:Ada", "1:Grace", "2:Alan"])
  h.type_into("#q", "al")
  // The key is the ORIGINAL index, so identity survives the filter.
  assert_eq(h.texts("li"), ["2:Alan"])
  h.type_into("#q", "a")
  assert_eq(h.texts("li"), ["0:Ada", "1:Grace", "2:Alan"])
  h.type_into("#q", "zz")
  assert_eq(h.texts("li"), [])
  h.destroy()
}

///|
/// Drag to reorder — the `drag-reorder` starter card, with the styling and the
/// filter taken out.
fn reorder_card() -> String {
  (
    #|<script type="tutuca/state">
    #|  state { items : Array[String] }
    #|  receive { Init }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  receive init { .items.push 'a'; .items.push 'b'; .items.push 'c'; .items.push 'd' }
    #|
    #|  on moveRow(target, source) {
    #|    if source is not target {
    #|      if source < target {
    #|        .items.insertAt (target + 1) .items[source]
    #|        .items.deleteAt source
    #|      } else {
    #|        .items.insertAt target .items[source]
    #|        .items.deleteAt (source + 1)
    #|      }
    #|    }
    #|  }
    #|</script>
    #|
    #|<template>
    #|  <ul><li @each=".items" draggable="true"
    #|      data-dragtype="row" data-droptarget="row"
    #|      @on.drop="moveRow @key dragKey"><x text="@value"></x></li></ul>
    #|</template>
  )
}

///|
test "a card reorders a list from a drop, because it can ask for dragKey" {
  // The drop fires on the TARGET row; the SOURCE row's key lives only on the
  // stack the drag captured, and `dragInfo` hands it over as a FUNCTION to
  // apply — which a block cannot do and should not learn to. `dragKey` is that
  // same answer as a name, and it is the whole of what this card needed.
  let h = mount_card(reorder_card(), name="Reorder")
  h.send_at_root("init")
  assert_eq(h.texts("li"), ["a", "b", "c", "d"])
  // forward: the row lands AT the target, and the ones it passed shift back
  h.drag("li", 0, 2)
  assert_eq(h.texts("li"), ["b", "c", "a", "d"])
  // backward: the same, from the other side of the list
  h.drag("li", 3, 1)
  assert_eq(h.texts("li"), ["b", "d", "c", "a"])
  // a row dropped on itself is not a move
  h.drag("li", 2, 2)
  assert_eq(h.texts("li"), ["b", "d", "c", "a"])
  h.destroy()
}

// -- what a card refuses ----------------------------------------------------

///|
fn load_err(source : String) -> String {
  try {
    @tutucard.load(source, name="X") |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "a card is one component, and needs a view" {
  assert_eq(
    load_err("<script type=\"tutuca/state\">state { n : Int }</script>"),
    "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible",
  )
  assert_eq(
    load_err("<template id=\"A\">a</template><template id=\"B\">b</template>"),
    "a card is one component, but this file declares `A`, `B` — give each its own file, or generate a module with `tutuca gen-views`",
  )
}

///|
test "a syntax error in the script names its line IN THE FILE" {
  // Rebased from the block's own coordinates. This is what the offset on
  // `@viewfile.Block` is for, and it is the first thing in a view file that
  // can point at a column.
  let src =
    #|<template><b>hi</b></template>
    #|<script type="tutuca/script">
    #|  on ok { .n = 1 }
    #|  on bad { .n = }
    #|</script>
  assert_eq(load_err(src), "line 4: expected a value, found `}`")
}

///|
test "a type error is reported and the card still mounts" {
  // Issues and a component TOGETHER: a card with a bad handler still has views
  // worth rendering and a state worth showing, and refusing to mount anything
  // until everything is right is what makes a live editor unusable.
  let src =
    #|<script type="tutuca/state">
    #|  state { note : Int }
    #|</script>
    #|<script type="tutuca/script">
    #|  on x { .noet = 1 }
    #|</script>
    #|<template><b id="b">hi</b></template>
  let card = @tutucard.load(src, name="C")
  assert_eq(card.issues.map(i => i.code), ["NO_FIELD"])
  assert_eq(card.issues.map(i => i.message), [
    "`.noet` is not a field of the C state — did you mean `.note`?",
  ])
  // Line 5 of the file, not line 2 of the block.
  assert_eq(card.issues.map(i => i.line), [5])
  let m = @component.ModuleDef::new(name="card", components=[card.component])
  let h = @harness.mount(m, "C")
  assert_eq(h.text("#b"), "hi")
  h.destroy()
}

///|
test "a card with no state block is legal and unchecked" {
  // The same trade a view file with no schema already makes: no declaration,
  // no checking, and checking against a guess would be the generator
  // inventing a type.
  let src =
    #|<script type="tutuca/script">
    #|  compute greeting { 'hello' }
    #|</script>
    #|<template><b id="b"><x text="$greeting"></x></b></template>
  let card = @tutucard.load(src, name="C")
  assert_eq(card.issues.map(i => i.message), [])
  let m = @component.ModuleDef::new(name="card", components=[card.component])
  let h = @harness.mount(m, "C")
  assert_eq(h.text("#b"), "hello")
  h.destroy()
}

///|
/// A card that builds its rows instead of being handed them.
fn roster_card() -> String {
  (
    #|<script type="tutuca/state">
    #|  struct Member { name : String, admin : Bool }
    #|  state { members : Array[Member] }
    #|  receive { Init }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  receive init {
    #|    new Member
    #|    @cur.name = 'Ada'
    #|    @cur.admin = true
    #|    .members.push @cur
    #|    new Member
    #|    @cur.name = 'Grace'
    #|    .members.push @cur
    #|  }
    #|  enrich row { @label = if @value.admin { $'{@value.name}*' } else { @value.name } }
    #|</script>
    #|
    #|<template>
    #|  <ul><li @each=".members" @enrich-with="row"><x text="@label"></x></li></ul>
    #|</template>
  )
}

///|
test "a card builds a record and appends it to a list of them" {
  // The gap this closes: `Array[Member]` could be read and written through,
  // but never appended to, because a record had no spelling. Every row here
  // was built by the block itself.
  let h = mount_card(roster_card(), name="Roster")
  h.send_at_root("init")
  assert_eq(h.texts("li"), ["Ada*", "Grace"])
  h.destroy()
}

///|
/// The same card, with an enricher that builds a value of its own.
fn workbench_card() -> String {
  (
    #|<script type="tutuca/state">
    #|  struct Member { name : String, admin : Bool }
    #|  state { members : Array[Member] }
    #|  receive { Init }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  receive init {
    #|    new Member
    #|    @cur.name = 'Ada'
    #|    .members.push @cur
    #|  }
    #|  enrich row {
    #|    new Member
    #|    @cur.name = 'scratch'
    #|    @label = @value.name
    #|  }
    #|</script>
    #|
    #|<template>
    #|  <ul><li @each=".members" @enrich-with="row"><x text="@label"></x>|<x text="@cur"></x></li></ul>
    #|</template>
  )
}

///|
test "the target an enricher builds never reaches the view" {
  // An enricher's binds BECOME a view's scope — `@name` in a template, replayed
  // on every rebuild. The target is a workbench, so `@cur` in a template reads
  // nothing at all, and a card cannot publish a binding a compiled component
  // could not.
  let h = mount_card(workbench_card(), name="Workbench")
  h.send_at_root("init")
  assert_eq(h.texts("li"), ["Ada|"])
  h.destroy()
}

///|
test "a card expands the macros its own file declares" {
  // `<template id="macro:field">` is a declaration the SPLITTER has always
  // returned and the loader used to drop, so `<x:field>` in a card rendered as
  // an unknown element with its attributes intact. It expands now, against the
  // scope the module registers — the same path a generated module's macros
  // take, rather than a second one for cards.
  let src =
    #|<script type="tutuca/state">
    #|  state { name : String, city : String }
    #|</script>
    #|
    #|<template id="macro:field" data-label="'Field'">
    #|  <label class="field">
    #|    <span class="lbl" @text="^label"></span>
    #|    <x:slot></x:slot>
    #|  </label>
    #|</template>
    #|
    #|<template id="Form">
    #|  <div>
    #|    <x:field label="Name"><input id="name" :value=".name"></x:field>
    #|    <x:field><input id="city" :value=".city"></x:field>
    #|  </div>
    #|</template>
  let h = mount_card(src, name="Form")
  // Two expansions: one that passed a label, one that took the declaration's
  // default — and each keeping the child it wrapped.
  assert_eq(h.texts(".lbl"), ["Name", "Field"])
  assert_eq(h.find_all(".field").length(), 2)
  assert_eq(h.find_all("#name").length(), 1)
  h.destroy()
}
