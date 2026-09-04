// Generated from `std.card.html` by `node demo/universal/std/embed.mjs`.
// DO NOT EDIT.
//
// Change `std.card.html`, rerun the task, commit both halves.

///|
/// The layout kit, as source.
///
/// It is compiled by the same compiler that compiles anything a person pastes
/// into the page, and registered by the same `register_module`. The ONE way it
/// differs is that it is here rather than fetched — which is a fact about when
/// it arrives, not about what it is allowed to do.
pub fn card_source() -> String {
  let src =
    #|<script type="tutuca/spec">
    #|  /// The three protocols the shell speaks, and the only things it knows about
    #|  /// a component before it has one in hand.
    #|  ///
    #|  /// A protocol rather than a base component, because the shell must not be
    #|  /// able to tell its own layout kit from a card somebody wrote ten seconds
    #|  /// ago. It asks "do you implement this", never "are you one of mine".
    #|  protocol Holder = "tutuca.dev/universal/Holder@1" {
    #|    handle { message { hold(Any), empty } }
    #|    express { intent { addRequested(Bool) } }
    #|    property { filled: Bool }
    #|  }
    #|
    #|  /// A thing with cells.
    #|  ///
    #|  /// `cellField` is the load-bearing member. A container is CONSTRUCTED with
    #|  /// its cells already in it — an arrangement is built from the inside out and
    #|  /// handed over finished — so the one thing a builder cannot work out for
    #|  /// itself is what that constructor argument is called. One string answers it,
    #|  /// and the code that fills a grid is the code that fills a tab strip.
    #|  protocol Container = "tutuca.dev/universal/Container@1" {
    #|    handle { message { appendCell, removeAt(Int), insertAt(Int) } }
    #|    /// What the container's own chrome raises when a person clicks an insert
    #|    /// strip or a cell's `x`. It ASKS rather than doing it, and the shell
    #|    /// answers by sending the message above at the container's own path.
    #|    ///
    #|    /// Not squeamishness about a card mutating itself — a view cannot name a
    #|    /// qualified handler at all, so the protocol message and a local one would
    #|    /// have to be two bodies saying the same thing. One body, asked for.
    #|    /// `-1` means append.
    #|    express { intent { insertRequested(Int), removeRequested(Int) } }
    #|    property { count: Int, cellField: String }
    #|  }
    #|
    #|  /// A component that can draw its own settings.
    #|  ///
    #|  /// A VIEW ROLE and not a schema: the component ships the UI, so the shell
    #|  /// never generates a form and never has to guess what a field means. One
    #|  /// role with a different local view behind it per component — a container's
    #|  /// editor still has to render its children or nested cells become
    #|  /// unreachable, and a leaf's is a form.
    #|  protocol Editable = "tutuca.dev/universal/Editable@1" {
    #|    view { editor }
    #|  }
    #|
    #|  /// The universal holder: what a `+` is, and what every cell contains.
    #|  ///
    #|  /// A HOLDER, not a placeholder that gets replaced. Empty it draws a `+`;
    #|  /// filled it draws what it holds and keeps holding it. That is what gives
    #|  /// every placed component one uniform home for the chrome, and what makes
    #|  /// "insert a cell here" always "insert an empty hole", with no kind to decide
    #|  /// and no binding to invent.
    #|  state Hole implements Holder, Editable {
    #|    /// What this holds, or null, which is what draws the `+`.
    #|    ///
    #|    /// UNCONSTRAINED on purpose. `Instance[protocol X]` would check the claim
    #|    /// and reject a value that does not make it — and a hole that must accept
    #|    /// anything a person can load cannot constrain what that is.
    #|    child : Instance
    #|    /// Whether what it holds draws its own settings, decided when the shell
    #|    /// put it there. A view cannot ask the catalog, and the moment of placing
    #|    /// is the one moment the answer is known.
    #|    editable : Bool
    #|    /// Whether this ONE cell is showing its child's settings — the third of
    #|    /// the three ways into an editor, and the narrowest. The other two are
    #|    /// views pushed from above and touch no state at all.
    #|    configuring : Bool
    #|    property {
    #|      pub filled : Bool { get }
    #|      Holder::filled = filled
    #|    }
    #|    view { Editable::editor = chrome }
    #|  }
    #|
    #|  handle Hole { message { Holder::hold(Any), Holder::empty } }
    #|  express Hole { intent { Holder::addRequested(Bool) } }
    #|
    #|  /// A row or a column: the flexbox subset, and nothing else.
    #|  ///
    #|  /// There is no `vbox` and no `hbox`. They are the same component with two
    #|  /// sets of arguments, and the palette lists a preset as its own row, so a
    #|  /// person typing either still finds one.
    #|  state Box implements Container, Editable {
    #|    children : Array[Hole]
    #|    direction : String
    #|    justify : String
    #|    align : String
    #|    wrap : Bool
    #|    gap : Int
    #|    padding : Int
    #|    property {
    #|      pub count : Int { get }
    #|      pub cellField : String { get }
    #|      Container::count = count
    #|      Container::cellField = cellField
    #|    }
    #|    view { Editable::editor = arrange }
    #|  }
    #|
    #|  express Box {
    #|    intent { Container::insertRequested(Int), Container::removeRequested(Int) }
    #|  }
    #|
    #|  handle Box {
    #|    message {
    #|      Container::appendCell
    #|      Container::removeAt(Int)
    #|      Container::insertAt(Int)
    #|    }
    #|  }
    #|
    #|  /// A uniform grid: every cell the same size, children in row-major order.
    #|  ///
    #|  /// Uniform on purpose. A grid whose tracks can each be something different is
    #|  /// the layout easiest to get subtly wrong and hardest to explain to somebody
    #|  /// adding a cell; a bento box wants a component of its own rather than a mode
    #|  /// of this one.
    #|  state Grid implements Container, Editable {
    #|    children : Array[Hole]
    #|    cols : Int
    #|    rows : Int
    #|    gap : Int
    #|    padding : Int
    #|    property {
    #|      pub count : Int { get }
    #|      pub cellField : String { get }
    #|      Container::count = count
    #|      Container::cellField = cellField
    #|    }
    #|    view { Editable::editor = arrange }
    #|  }
    #|
    #|  express Grid {
    #|    intent { Container::insertRequested(Int), Container::removeRequested(Int) }
    #|  }
    #|
    #|  handle Grid {
    #|    message {
    #|      Container::appendCell
    #|      Container::removeAt(Int)
    #|      Container::insertAt(Int)
    #|    }
    #|  }
    #|
    #|  /// A tab strip and one page at a time.
    #|  ///
    #|  /// Labels live BESIDE the pages rather than inside them, because a page IS a
    #|  /// hole: wrapping each one in a component that carried its own label would
    #|  /// make this the only container whose cells are not holes, and every builder
    #|  /// would need a special case for it.
    #|  state Tabs implements Container, Editable {
    #|    tabs : Array[Hole]
    #|    labels : Array[String]
    #|    active : Int
    #|    property {
    #|      pub count : Int { get }
    #|      pub cellField : String { get }
    #|      Container::count = count
    #|      Container::cellField = cellField
    #|    }
    #|    view { Editable::editor = arrange }
    #|  }
    #|
    #|  express Tabs {
    #|    intent { Container::insertRequested(Int), Container::removeRequested(Int) }
    #|  }
    #|
    #|  handle Tabs {
    #|    message {
    #|      Container::appendCell
    #|      Container::removeAt(Int)
    #|      Container::insertAt(Int)
    #|      activate(Int)
    #|    }
    #|  }
    #|
    #|  /// A leaf: a run of text.
    #|  state Text implements Editable {
    #|    text : String
    #|    size : String
    #|    view { Editable::editor = configure }
    #|  }
    #|
    #|  /// A leaf: editable multi-line text. The other half of the notepad.
    #|  state Textarea implements Editable {
    #|    text : String
    #|    rows : Int
    #|    placeholder : String
    #|    view { Editable::editor = configure }
    #|  }
    #|
    #|  /// A leaf: markdown, sanitized by construction.
    #|  ///
    #|  /// `@setinnermd` needs no special trust. A markdown payload has no raw route
    #|  /// — the filter walks it into nodes and puts every element and every
    #|  /// attribute to the sanitizer — so this loads under the same policy every
    #|  /// other card gets, which is the claim this whole demo is making.
    #|  state Markdown implements Editable {
    #|    text : String
    #|    view { Editable::editor = configure }
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/script" for="Hole">
    #|  get filled { not (null? .child) }
    #|
    #|  /// Hold this. The shell builds the instance — it is the only thing that can,
    #|  /// since building a component from another module needs the registry — and
    #|  /// hands it over finished.
    #|  receive Holder::hold(inst) {
    #|    .child = inst
    #|    .editable = false
    #|  }
    #|
    #|  /// Empty it again, which gives the `+` back rather than deleting a cell.
    #|  receive Holder::empty {
    #|    .child = null
    #|    .editable = false
    #|  }
    #|
    #|  /// The `+` was clicked. `ctrl` is "let me configure it" rather than "place it
    #|  /// with its defaults". The shell answers by opening the picker AT this cell:
    #|  /// it reads the asking path off the intent, so nothing has to be stored here
    #|  /// and no cell can name another.
    #|  receive add(ctrl) { ask Holder::addRequested ctrl }
    #|
    #|  /// The `x`. Local, because emptying a hole is the hole's own business and
    #|  /// needs nothing the shell knows — unlike a container's cells, which change
    #|  /// the ARRANGEMENT and so are the shell's to apply.
    #|  receive askEmpty {
    #|    .child = null
    #|    .editable = false
    #|    .configuring = false
    #|  }
    #|
    #|  /// What the shell knows and a view cannot ask: whether what is held draws its
    #|  /// own settings. Sent right after `hold`, because the catalog is the only
    #|  /// thing that can answer and only the shell can reach it.
    #|  receive markEditable(on) { .editable = on }
    #|
    #|  /// Show the held component under its own `editor` role, or stop.
    #|  receive toggleConfig { .configuring = not .configuring }
    #|</script>
    #|
    #|<script type="tutuca/script" for="Text">
    #|  compute sized { $'font-size:{.size}' }
    #|</script>
    #|
    #|<script type="tutuca/script" for="Box">
    #|  receive askInsert(i) { ask Container::insertRequested i }
    #|  receive askRemove(i) { ask Container::removeRequested i }
    #|  get count { len .children }
    #|  get cellField { 'children' }
    #|  compute wrapMode { if .wrap { 'wrap' } else { 'nowrap' } }
    #|  compute style {
    #|    $'display:flex;flex-direction:{.direction};justify-content:{.justify};align-items:{.align};flex-wrap:{wrapMode};gap:{.gap}px;padding:{.padding}px'
    #|  }
    #|  compute isRow { .direction is 'row' }
    #|  receive Container::appendCell {
    #|    new Hole
    #|    .children.push cur
    #|  }
    #|  receive Container::removeAt(i) { .children.deleteAt i }
    #|  receive Container::insertAt(i) {
    #|    new Hole
    #|    .children.insertAt i cur
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/script" for="Grid">
    #|  receive askInsert(i) { ask Container::insertRequested i }
    #|  receive askRemove(i) { ask Container::removeRequested i }
    #|  get count { len .children }
    #|  get cellField { 'children' }
    #|  compute style {
    #|    $'display:grid;grid-template-columns:repeat({.cols},minmax(0,1fr));grid-template-rows:repeat({.rows},minmax(0,1fr));gap:{.gap}px;padding:{.padding}px'
    #|  }
    #|  receive Container::appendCell {
    #|    new Hole
    #|    .children.push cur
    #|  }
    #|  receive Container::removeAt(i) { .children.deleteAt i }
    #|  receive Container::insertAt(i) {
    #|    new Hole
    #|    .children.insertAt i cur
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/script" for="Tabs">
    #|  /// Which row is the open one, bound per row.
    #|  ///
    #|  /// It has to be an enricher: inside `@each` a `.field` reads the ITEM, and a
    #|  /// page is a Hole, which has no idea which tab it is. The strip's own index
    #|  /// is the only thing that knows, and this is how it reaches the row.
    #|  enrich markActive {
    #|    @active = @key is .active
    #|  }
    #|  receive askInsert(i) { ask Container::insertRequested i }
    #|  receive askRemove(i) { ask Container::removeRequested i }
    #|  get count { len .tabs }
    #|  get cellField { 'tabs' }
    #|  receive activate(i) { .active = i }
    #|  receive Container::appendCell {
    #|    new Hole
    #|    .tabs.push cur
    #|    .labels.push 'tab'
    #|  }
    #|  receive Container::removeAt(i) {
    #|    .tabs.deleteAt i
    #|    .labels.deleteAt i
    #|  }
    #|  receive Container::insertAt(i) {
    #|    new Hole
    #|    .tabs.insertAt i cur
    #|    .labels.insertAt i 'tab'
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/test">
    #|{
    #|  "an empty hole renders nothing at all": {
    #|    "component": "Hole",
    #|    "steps": [
    #|      { "expect": "html", "contains": "tut-hole" },
    #|      { "expect": "state", "at": ".child", "is": null }
    #|    ]
    #|  },
    #|  "a box opens its cells as holes, and grows one more": {
    #|    "component": "Box",
    #|    "args": { "direction": "row", "gap": 8 },
    #|    "steps": [
    #|      { "expect": "count", "at": "div.tut-hole", "is": 0 },
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "expect": "count", "at": "div.tut-hole", "is": 2 },
    #|      { "expect": "state", "at": ".direction", "is": "row" }
    #|    ]
    #|  },
    #|  "a cell inserted in the middle lands in the middle": {
    #|    "component": "Box",
    #|    "steps": [
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "send": "tutuca.dev/universal/Container@1::insertAt", "args": [1] },
    #|      { "expect": "count", "at": "div.tut-hole", "is": 3 }
    #|    ]
    #|  },
    #|  "a tab strip grows a label beside every page": {
    #|    "component": "Tabs",
    #|    "steps": [
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "expect": "text", "at": "button.tab-label", "is": "tab" },
    #|      { "expect": "state", "at": ".labels", "is": ["tab"] }
    #|    ]
    #|  },
    #|  "removing a tab takes its label with it": {
    #|    "component": "Tabs",
    #|    "steps": [
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "expect": "count", "at": "button.tab-label", "is": 2 },
    #|      { "send": "tutuca.dev/universal/Container@1::removeAt", "args": [0] },
    #|      { "expect": "count", "at": "button.tab-label", "is": 1 },
    #|      { "expect": "state", "at": ".labels", "is": ["tab"] }
    #|    ]
    #|  },
    #|  "one tab is open at a time, and activate picks it": {
    #|    "component": "Tabs",
    #|    "steps": [
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "send": "tutuca.dev/universal/Container@1::appendCell" },
    #|      { "expect": "state", "at": ".active", "is": 0 },
    #|      { "send": "activate", "args": [1] },
    #|      { "expect": "state", "at": ".active", "is": 1 }
    #|    ]
    #|  },
    #|  "a textarea writes what is typed": {
    #|    "component": "Textarea",
    #|    "args": { "rows": 4, "placeholder": "..." },
    #|    "steps": [
    #|      { "type": "textarea.tut-textarea", "value": "note to self" },
    #|      { "expect": "state", "at": ".text", "is": "note to self" }
    #|    ]
    #|  },
    #|  "a hole holds what it is given and gives the slot back": {
    #|    "component": "Hole",
    #|    "steps": [
    #|      { "send": "tutuca.dev/universal/Holder@1::empty" },
    #|      { "expect": "state", "at": ".child", "is": null },
    #|      { "expect": "state", "at": ".editable", "is": false }
    #|    ]
    #|  }
    #|}
    #|</script>
    #|
    #|<!-- The templates.
    #|     Three things here cannot be said inside a template, and each one is a bug
    #|     that no test on the in-memory DOM can see:
    #|
    #|     `pt-5` on the chrome is a reserved BAND, not decoration. Without it the
    #|     badge and the `x` sit on top of whatever is held and INTERCEPT ITS CLICKS —
    #|     a tabbed thing whose first tab cannot be selected. There is no layout in
    #|     `@memdom`, so nothing there overlaps and nothing there fails.
    #|
    #|     There is no comment INSIDE any template below. One before the root makes
    #|     the view a fragment; one inside it sits where the renderer's boundary meta
    #|     is expected and ends the chain dispatch walks — which is how a click inside
    #|     a held component stops reaching that component.
    #|
    #|     And the chrome's `drop` handler forwards what it does not recognise.
    #|     `drop` is the only DOM event that bubbles across component boundaries and
    #|     dispatch gives it to the first ancestor with a handler, so a hole claiming
    #|     it unconditionally would swallow the page-wide file drop. -->
    #|<template id="Hole:main">
    #|  <div class="tut-hole flex items-center justify-center w-full"><x render=".child"></x></div>
    #|</template>
    #|
    #|<template id="Hole:chrome">
    #|  <div class="tut-hole relative w-full min-h-8 pt-5 px-1 pb-1 flex items-center justify-center rounded outline-1 outline-dashed outline-base-300">
    #|    <button class="hole-add btn btn-ghost btn-block min-h-16 text-3xl font-thin opacity-30 hover:opacity-100"
    #|            @show="not .filled" @on.click="add e.isCtrl">+</button>
    #|    <button class="hole-config absolute top-0.5 left-1 z-10 badge badge-xs badge-ghost cursor-pointer"
    #|            @show=".editable" @on.click="toggleConfig">edit</button>
    #|    <button class="hole-remove absolute top-0.5 right-1 z-10 btn btn-xs btn-circle btn-ghost opacity-40 hover:opacity-100"
    #|            @show=".filled" @on.click="askEmpty">x</button>
    #|    <x render=".child" as="tutuca.dev/universal/Editable@1::editor" @show=".configuring"></x>
    #|    <x render=".child" @hide=".configuring"></x>
    #|  </div>
    #|</template>
    #|
    #|<template id="Box:main">
    #|  <div class="tut-box w-full" :style="$style"><x render-each=".children"></x></div>
    #|</template>
    #|
    #|<template id="Box:arrange">
    #|  <div class="tut-box w-full" :style="$style">
    #|    <div class="tut-cell relative" @each=".children">
    #|      <button class="cell-before absolute z-20 rounded bg-primary opacity-0 hover:opacity-60"
    #|              @if.style="$isRow"
    #|              @then="'inset-block:0;inset-inline-start:-4px;inline-size:8px'"
    #|              @else="'inset-inline:0;inset-block-start:-4px;block-size:8px'"
    #|              @on.click="askInsert @key"></button>
    #|      <x render-it></x>
    #|    </div>
    #|    <button class="cell-append rounded bg-primary opacity-20 hover:opacity-60"
    #|            @if.style="$isRow"
    #|            @then="'inline-size:8px;align-self:stretch'"
    #|            @else="'block-size:8px'"
    #|            @on.click="askInsert -1"></button>
    #|  </div>
    #|</template>
    #|
    #|<template id="Grid:main">
    #|  <div class="tut-grid w-full" :style="$style"><x render-each=".children"></x></div>
    #|</template>
    #|
    #|<template id="Grid:arrange">
    #|  <div class="tut-grid w-full" :style="$style">
    #|    <div class="tut-cell relative" @each=".children">
    #|      <button class="cell-remove absolute top-0 right-0 z-20 btn btn-xs btn-ghost opacity-0 hover:opacity-70"
    #|              @on.click="askRemove @key">x</button>
    #|      <x render-it></x>
    #|    </div>
    #|  </div>
    #|</template>
    #|
    #|<template id="Tabs:main">
    #|  <div class="tut-tabs w-full flex flex-col gap-2">
    #|    <div role="tablist" class="tab-strip tabs tabs-box">
    #|      <button role="tab" class="tab-label tab" @each=".labels"
    #|              @on.click="activate @key" @text="@value"></button>
    #|    </div>
    #|    <span class="contents" @each=".tabs" @enrich-with="markActive">
    #|      <x render-it @show="@active"></x>
    #|    </span>
    #|  </div>
    #|</template>
    #|
    #|<template id="Tabs:arrange">
    #|  <div class="tut-tabs w-full flex flex-col gap-2">
    #|    <div role="tablist" class="tab-strip tabs tabs-box">
    #|      <button role="tab" class="tab-label tab" @each=".labels"
    #|              @on.click="activate @key" @text="@value"></button>
    #|      <button class="tab-add tab" @on.click="askInsert -1">+</button>
    #|      <button class="tab-close tab" @hide="empty? .tabs" @on.click="askRemove .active">x</button>
    #|    </div>
    #|    <span class="contents" @each=".tabs" @enrich-with="markActive">
    #|      <x render-it @show="@active"></x>
    #|    </span>
    #|  </div>
    #|</template>
    #|
    #|<template id="Text:main"><span class="tut-text" :style="$sized" @text=".text"></span></template>
    #|
    #|
    #|<template id="Text:configure">
    #|  <label class="tut-config flex flex-col gap-1 w-full">
    #|    <input class="cfg-text input input-bordered input-sm w-full" :value=".text" @on.input=".text = e.value">
    #|    <input class="cfg-size input input-bordered input-xs w-full" :value=".size" @on.input=".size = e.value">
    #|  </label>
    #|</template>
    #|
    #|<template id="Textarea:main">
    #|  <textarea class="tut-textarea textarea textarea-bordered w-full font-mono"
    #|            :rows=".rows" :placeholder=".placeholder"
    #|            :value=".text" @on.input=".text = e.value"></textarea>
    #|</template>
    #|
    #|<template id="Textarea:configure">
    #|  <label class="tut-config flex flex-col gap-1 w-full">
    #|    <input class="cfg-rows input input-bordered input-xs w-full" :value=".rows" @on.input=".rows = e.value">
    #|    <input class="cfg-placeholder input input-bordered input-xs w-full" :value=".placeholder" @on.input=".placeholder = e.value">
    #|  </label>
    #|</template>
    #|
    #|<template id="Markdown:main"><article class="tut-markdown prose w-full" @setinnermd=".text"></article></template>
    #|
    #|<template id="Markdown:configure">
    #|  <textarea class="cfg-md textarea textarea-bordered w-full font-mono" :rows="6"
    #|            :value=".text" @on.input=".text = e.value"></textarea>
    #|</template>
  src
}
