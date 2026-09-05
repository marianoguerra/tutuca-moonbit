# Migrating to `.tutu`

A component is written today in four `<script>` blocks and a set of
`<template>`s inside an `.html` file, in three notations: the spec language,
the script language, and JSON. The `.tutu` format replaces all of it with one
notation — [shrubbery], the line- and indentation-sensitive layer under
[Rhombus] — in five named sections.

This page is the conversion, construct by construct, with before/after taken
from this repository's own files. It is written to be executed against a real
file, top to bottom.

[shrubbery]: https://docs.racket-lang.org/shrubbery/
[Rhombus]: https://docs.racket-lang.org/rhombus/

## Status — read this first

The migration is **staged. A `.tutu` file compiles today; the repo has not been converted.**

| Stage | What it is | State |
| --- | --- | --- |
| 1 | The file: five sections, their order, the declarations in each | **done** — `tutufile/`, `tutuca outline` |
| 2 | Every section lowered into the block the front end reads | **done** — `tutufile/lower`, and `tutuca gen` takes a `.tutu` |
| 3 | Convert the repo's 86 view files and cards | not started |
| 4 | The card runtime and both playgrounds, which read the four blocks by name | not started |
| 5 | The skill — 8.7k lines, and what an agent authors from | not started |
| 6 | Direct readers, replacing the lowering; then delete `viewfile/` and the old parsers | not started |

So: **a `.tutu` file compiles today.** `tutuca gen card.tutu --name Card`
emits the same MoonBit the `.html` beside it does, and `tutuca outline
card.tutu` says what the file declares. What has not happened is the repo's own
migration: the 86 files, the card runtime, the playgrounds and the skill still
read the old blocks, so **keep the `.html` until stage 3 reaches it**.

How stage 2 works, and why it is staged this way: the five sections are
**lowered** into the blocks the front end already reads, rather than parsed
into its typed forms directly. `tutufile/lower` is a printer — spec section to
`state` block, logic section to script block, view section to templates, the
two data sections to their JSON — so every consumer downstream works on a
`.tutu` file without a line of it changing. The direct readers are the end
state (stage 6); the lowering is deleted when they land, not kept as a second
way in.

### How it is checked

By **equivalence against the file it replaces**. `tutufile/lower` imports none
of the readers; its tests import all of them, lower a card and assert the
`StateDef`, the script block, the fixture, the scene and the view that come
back. End to end, `tutuca gen` over the counter written as `.tutu` emits a
`counter_view_gen.mbt` byte-identical to the one its `.html` produces, save the
source name in the header and the schema fingerprint.

**Naming an anonymous component changes its fingerprint.** A `.html` file may
write `state { … }` with no name; a `.tutu` file always names its components.
The fields, views, codec and generated MoonBit are identical — the fingerprint
is not, because the name is in it. A project that persists state across the
migration re-keys once.

## The file

Five sections, in this order, at most one of each. The section supplies the
keyword for its own kind: a bare name in `spec:` or `logic:` is a component, in
`view:` it is a view, and in `fixtures:` / `tests:` the name is a string.
Everything else names itself — `struct`, `enum`, `protocol` in `spec:`,
`macro` and `@style{…}` in `view:`.

```
spec:       what the components are
logic:      what they do
view:       what they look like
fixtures:   what they start as
tests:      what they must keep doing
```

`script` becomes `logic` because "script" named the `<script>` tag the content
had to live in, not the content.

**Before** — `tutucard/examples/Guarded.html`:

```html
<script type="tutuca/spec">  … </script>
<script type="tutuca/script">… </script>
<script type="tutuca/fixtures">…</script>
<script type="tutuca/test">  … </script>
<template id="Guarded">      … </template>
```

**After** — `guarded.tutu`: the five section headers above, each with the
converted body indented under it. The whole file is at the end of this page.

## Names

Six sigils become one binder each. This is the change that touches every line,
so do it first and the rest follows.

| Today | `.tutu` | Bound by |
| --- | --- | --- |
| `.count` | `it.count` | the enclosing component |
| `$label` | `label` (a property) or `label()` (a `compute`) | the enclosing component |
| `@value`, `@key` | `item`, `i` | the `@each` that binds them |
| `^label` | `label` | the macro's parameter list |
| `*theme` | `dyn.theme` | a `lookup` in this component |
| `&.status` | `~to: it.status` | the parameter it is passed to |
| `state.count` | `it.state.count` | the enclosing component |

Names you own are `snake_case`: fields, handlers, computes, rules, fixtures,
and a component's own message names. `loadRowsOk` becomes `load_rows_ok`, and
the derived intent answers become `<name>_ok` / `_failed` / `_unhandled`.

**Names a protocol owns are not yours to rename.** A protocol id and its
members are a wire vocabulary — `"tutuca.dev/universal/Container@1"` and
`Container::appendCell`, `Container::cellField` — dispatched by a second host
as those exact strings, and `@1` is a promise that they do not move. A `.tutu`
card declaring `Container` under a snake_case rewrite would answer
`::append_cell` where a `.html` card answers `::appendCell`: the same protocol
id, the same version, different members, composing with nothing, silently. It
is not only cards — `compose/build.mbt` reads `"cellField"` as a literal.

So the rule is: **the converter renames nothing.** Everything printed here
carries the spelling you wrote, and a protocol member keeps its camelCase in a
file whose own names are snake_case. That wart is correct, and the frozen ids
are why.

## Values and operators

| Today | `.tutu` |
| --- | --- |
| `'text'` | `"text"` |
| `$'Hi {.name}'` | `@str{Hi @(it.name)}` |
| `.a is 'x'` / `is not` | `it.a == "x"` / `!=` |
| `a and b` / `or` / `not a` | `a && b` / `\|\|` / `!a` |
| `empty? .items` | `it.items.is_empty()` |
| `len .items` | `it.items.length()` |
| `contains (lower .title) q` | `it.title.lower().contains(q)` |
| `has .picked @value` | `it.picked.has(item)` |
| `max 0 (.qty - 1)` | `math.max(0, it.qty - 1)` |
| `str x` / `int x` / `num x` | `x.to_string()` / `x.to_int()` / `x.to_number()` |
| `truthy? x` / `null? x` | `x.is_truthy()` / `x == none` |
| `null` | `none` — a value, so `it.cells.push(none)` works |

`x == none` reads as the shape predicate `null? x` in an expression, because
that predicate is total where a comparison against a null is not. In a **scene**
it does not: `expect state it.child == none` is an assertion about a value and
prints `"is": null`. The two sections have separate printers, which is why the
fold is where it applies and absent where it would be wrong.
| `if c { a } else { b }` | `if c \| a \| b` |
| `a implies b` | `a implies b` (unchanged) |

The parenthesisation rule does not change: operators with no declared relative
precedence must be parenthesised, which is shrubbery's own rule.
`(it.n > 0) && it.open`, never `it.n > 0 && it.open`.

## Types

| Today | `.tutu` |
| --- | --- |
| `count: Int` | `field count :: Int` |
| `Array[Item]` | `List.of(Item)` |
| `Map[String, V]` | `Map.of(String, V)` |
| `Set[Visibility]` | `Set.of(Visibility)` |
| `T?` | `maybe(T)` |
| `(A, B)` | `Tuple.of(A, B)` |
| `Instance[Legend]` | `Instance.of(Legend)` |
| `Instance[protocol P & Q]` | `Instance.of(P && Q)` |
| `Any`, `Component` | unchanged |

`field` takes an optional `= expr` initialiser, which the old spelling had no
place for: `field step :: Int = 1`.

## `spec:` — the component's shape

**Before** — `tutucard/examples/Todos.html`:

```html
<script type="tutuca/spec">
  /// A list that makes its own rows.
  state Todos {
    /// What is being typed.
    draft: String
    /// The rows, each a child instance.
    items: Array[Todo]

    property {
      count: Int { get }
    }

    /// True while there is something to add.
    pred typed
      format $'nothing to add' { not (empty? .draft) }
  }

  /// One row, declared beside the list that makes it.
  state Todo {
    text: String
    done: Bool
    property { caption: String { get } }
  }
</script>
```

**After**:

```
spec:
  /// A list that makes its own rows.
  Todos ~root:
    /// What is being typed.
    field draft :: String
    /// The rows, each a child instance.
    field items :: List.of(Todo)

    property count :: Int

    /// True while there is something to add.
    pred typed:
      ~format: "nothing to add"
      !it.draft.is_empty()

  /// One row, declared beside the list that makes it.
  Todo:
    field text :: String
    field done :: Bool
    property caption :: String
```

Point by point:

- `state Todos { … }` → `Todos:`, because the section says these are
  components. `data-root` on a template becomes the `~root` option.
- A `property { … }` section becomes one `property` declaration per member.
  `pub` becomes `~public`. A property whose body is one field read may be
  declared and implemented on one line in `spec:` —
  `property count :: Int ~public:` with `get: it.count` under it — because a field read is not
  behaviour; anything more goes in `logic:`.
- `format $'…' { … }` becomes the option `~format:` followed by the body, under
  the one rule the notation has: **options lead the block, the body follows.**

The rest of the spec block converts the same way:

| Today | `.tutu` |
| --- | --- |
| `struct Line { what: String, qty: Int }` | `struct Line(what :: String, qty :: Int)` |
| `enum Priority { low, high }` | `enum Priority:` then one case per line |
| `invariant conserved { (.here + .there) is .total }` | `invariant conserved: (it.here + it.there) == it.total` |
| `handle B { message { reset, focus_row(Int) } }` | `message reset` / `message focus_row(Int)` |
| `handle B { intent { row_picked(Int) } }` | `intent row_picked(Int)` |
| `express B { intent { save_rows } }` | `express intent save_rows` |
| `provide { theme = .theme, Cell = self }` | `provide theme = it.theme` / `provide Cell = self` |
| `lookup { theme, color = 'gray' }` | `lookup theme` / `lookup color = "gray"` |
| `where i is index of .items` | `where it.i is_index_of it.items` |
| `where n between 0 and 100` | `where it.n in_range(0, 100)` |
| `where t is member of .tags` | `where it.t is_member_of it.tags` |
| `where items is nonempty` | `where !it.items.is_empty()` |
| `where i is index of .items or none` | `where it.i is_index_of it.items ~or_none` |
| `state X implements A, B` | `implements A` / `implements B`, one per line |

### Protocols

A protocol is a declaration of the spec section, and its id is a quoted string
because it is a wire name rather than an identifier. Its members are `message`,
`intent`, `express`, `property` and `view` — the same words a component uses,
which is the point: a protocol is a component with the bodies removed.

**Before** — `demo/universal/std/std.card.html`:

```html
<script type="tutuca/spec">
  protocol Container = "tutuca.dev/universal/Container@1" {
    handle { message { appendCell, removeAt(Int), insertAt(Int) } }
    express { intent { insertRequested(Int), removeRequested(Int) } }
    property { count: Int, cellField: String }
  }

  protocol Editable = "tutuca.dev/universal/Editable@1" {
    view { editor }
  }

  state Box implements Container, Editable {
    cells : Array[Any]
    property {
      pub count : Int { get }
      Container::count = count
      Container::cellField = cellField
    }
    view { Editable::editor = arrange }
  }

  handle Box { message { Container::appendCell, Container::removeAt(Int) } }
  express Box { intent { Container::insertRequested(Int) } }
</script>
```

**After**:

```
spec:
  protocol Container = "tutuca.dev/universal/Container@1":
    message appendCell
    message removeAt(Int)
    message insertAt(Int)
    express intent insertRequested(Int)
    express intent removeRequested(Int)
    property count :: Int
    property cellField :: String

  protocol Editable = "tutuca.dev/universal/Editable@1":
    view editor

  Box:
    implements Container
    implements Editable
    field cells :: List.of(Any)
    property count :: Int ~public
    property Container::count = count
    property Container::cellField = cellField
    view Editable::editor = arrange
    message Container::appendCell
    message Container::removeAt(Int)
    express intent Container::insertRequested(Int)
```

Three things to know:

- **One `implements` per line**, and one `message` per line. Shrubbery admits a
  comma only immediately inside `(`, `[` or `{`, so `implements A, B` does not
  parse — the same rule that makes a scene step a call.
- **A protocol property that a holder may WRITE** takes `~writable`:
  `property value :: Int ~writable` is the old `value: Int set`.
- **`Container::count = count`** binds the protocol's member to a local one, and
  `view Editable::editor = arrange` does the same for a view role. Both are
  lines of the component, and both keep the protocol's spelling on the left.

A `message` declaration survives only for names answered somewhere the file
cannot see — a hand-written MoonBit `update` arm. A name a `receive` in
`logic:` answers is declared by that `receive`, so `handle`'s list stops being
a second copy of the signature.

## `logic:` — what it does

**Before** — `tutucard/examples/Todos.html` and `Cart.html`:

```html
<script type="tutuca/script" for="Todos">
  receive add requires typed {
    new Todo
    cur.text = .draft
    cur.done = false
    .items.push cur
    .draft = ''
  }

  receive drop(i) {
    .items.deleteAt i
  }

  get count { len .items }
</script>

<script type="tutuca/script" for="Cart">
  receive checkout requires hasItem {
    ask dyn 'lineReady' .item (.qty * .price)
    .sent = true
    drop
  }
</script>
```

**After**:

```
logic:
  Todos:
    receive add:
      ~requires: typed
      it.items.push(Todo(text: it.draft, done: false))
      it.draft := ""

    receive drop(i :: Int):
      it.items.delete_at(i)

    property count :: Int: get: it.items.length()

  Cart:
    receive checkout:
      ~requires: has_item
      ask("line_ready", it.item, it.qty * it.price, ~route: dyn)
      it.sent := true
      drop()
```

Point by point:

- `for="Todos"` goes away: the section repeats the component's name.
- `requires` / `ensures` become the options `~requires:` / `~ensures:`.
- A write is `:=`, which separates it from the `=` that gives a field or a
  fixture entry its value. `+=` and friends are unchanged.
- Collection statements become method calls: `.items.push cur` →
  `it.items.push(…)`, `deleteAt` → `delete_at`, `setAt` → `set_at`,
  `insertAt` → `insert_at`, `removeAt` → `delete_at`, `toggle` → `toggle`.
  The aliases that parsed but only one backend implemented (`clear`, `delete`,
  `set`, `removeAt`) are not methods, so they do not parse at all.
- **`new` / `cur` go away.** Every `struct` and component has a parenthesised
  parameter list, so an aggregate is spelled directly. A `new` block whose
  writes are all straight-line becomes one constructor call; one that branches
  needs the branches lifted into the call's arguments.
- Effects become calls, and what decorated them becomes options:
  `sendAt &.status 'flash' 'Ready'` → `send("flash", "Ready", ~to: it.status)`;
  `ask dyn 'x' a` → `ask("x", a, ~route: dyn)`; `ask lex dyn 'x'` →
  `ask("x", ~route: [lex, dyn])`. `notify`, `reply`, `fail`, `forward` and
  `drop` are the same verbs, called.

Render-time members take their row as parameters instead of reading it out of
the air — this is the conversion with the most judgement in it:

**Before** — `tutucard/examples/Enriched.html`:

```html
<script type="tutuca/script">
  pred matches { contains (str @value) .needle }
  pred second { @key is 1 }

  enrich row {
    @tag = str @value
    @echo = str @tag
    @at = @key
  }

  bindWith info {
    @heading = .title
    @width = len .title
  }
</script>
```

**After**:

```
logic:
  Enriched:
    pred matches(item, i):
      item.to_string().contains(it.needle)

    pred second(item, i): i == 1

    enrich row(item, i):
      tag = item.to_string()
      echo = tag.to_string()
      at = i

    bind_with info:
      heading = it.title
      width = it.title.length()
```

`@value` becomes the first parameter and `@key` the second, named by the
`@each` in the view that calls them. An enricher's bindings stop carrying `@`:
they are the names it introduces.

## `view:` — the markup

The templates become at-notation: an element is `@name(options){content}`, an
attribute is a keyword option, and text is text with `@(expr)` escaping back to
the expression language.

**Before** — `storybook/examples/counter.html`:

```html
<template>
  <div class="join join-vertical">
    <button class="btn btn-error" @on.click="dec">-</button>
    <div class="stats">
      <div class="stat text-center">
        <div class="stat-title">Count</div>
        <div class="stat-value" @text=".count"></div>
        <div class="stat-desc">Current Count</div>
      </div>
    </div>
    <button class="btn btn-success" @on.click="inc">+</button>
  </div>
</template>
```

**After**:

```
view:
  Counter:
    @div(~class: "join join-vertical"){
      @button(~class: "btn btn-error", ~on_click: dec){-}
      @div(~class: "stats"){
        @div(~class: "stat text-center"){
          @div(~class: "stat-title"){Count}
          @div(~class: "stat-value"){@(it.count)}
          @div(~class: "stat-desc"){Current Count}
        }
      }
      @button(~class: "btn btn-success", ~on_click: inc){+}
    }
```

The directive table:

| Today | `.tutu` |
| --- | --- |
| `<span @text=".title"></span>` | `@span{@(it.title)}` |
| `<x text="@value"></x>` | `@(item)` — the op goes away, text is text |
| `<x text="$label"></x>` | `@(label())` |
| `class="btn"` and `:class=".kind"` | one `~class:`, and the silent-drop trap goes with it |
| `:value=".item"` | `~value: it.item` |
| `:title="$'Hi {.name}'"` | `~title: @str{Hi @(it.name)}` |
| `@on.click="inc"` | `~on_click: inc` |
| `@on.input="search e.value"` | `~on_input: search(e.value)` |
| `@on.input=".query = e.value"` | `~on_input: it.query := e.value` |
| `@on.keydown.enter+prevent="add"` | `~on_keydown: add ~key: "Enter" ~prevent` |
| `@bind=".query"` | `~bind: it.query` |
| `@show=".is_open"` | `@show(it.is_open){ … }` — a form, so it wraps a body |
| `@hide="empty? .kind"` | `@hide(it.kind.is_empty()){ … }` |
| `@if.class=".on" @then="'a'" @else="'b'"` | `~class: if it.on \| "a" \| "b"` |
| `@if.style` / `@if.<any attr>` | the same: an `if` in that attribute's value |
| `<li @each=".items">…</li>` | `@each(item in it.items){ @li{…} }` |
| `@each` + `@when="f"` + `@enrich-with="e"` | `@each(item, i in it.rows, ~when: f, ~enrich_with: e){…}` |
| `@loop-with="page"` | `~loop_with: page` on the `@each` |
| `<x render=".item"></x>` | `@render(it.item)` |
| `<x render=".item" as="edit"></x>` | `@render(it.item, ~as: "edit")` |
| `<x render="*active"></x>` | `@render(dyn.active)` |
| `<x render-each=".items"></x>` | `@each(row in it.items){@render(row)}` |
| `<x render-it></x>` | `@render(item)` — the loop already named it |
| `@push-view=".view"` | `~push_view: it.view` |
| `@setinnerhtml=".body"` | `~inner_html: it.body` |
| `@setinnermd` / `@setinnersvg` | `~inner_md:` / `~inner_svg:` |
| `<template id="Note:edit">` | `Note.edit:` |
| `<template … data-root>` | `~root` on the component in `spec:` |
| `<style>` in a template | `@style{ … }` inside that view |
| `<style>` at file level | `@style{ … }` at the top of `view:` |
| `<style data-global>` | `@style(~global){ … }` |
| `<x:badge label="Sale">` | `@badge(~label: "Sale")` |
| `macro` template with `^param` | `macro badge(~label: "New"):` with `label` |

Three naming rules for attributes, which is where the HTML parser used to lose
things: **case is preserved** (`~viewBox:`, `~mapId:`), **an underscore is a
hyphen** (`~aria_label:` → `aria-label`), and anything else goes through
`~attrs: {"xml:lang": "en"}`.

## `fixtures:` and `tests:`

The two JSON blocks become declarations in the same notation, and the step
language is written once for both: a fixture's `~drive:` holds the same
statements a scene does.

**Before** — `tutucard/examples/Guarded.html` and `Todos.html`:

```json
{ "nearly full": { "value": { "n": 2 },
                   "doc": "One press from the rule declining." } }
```
```json
{ "three rows": {
    "doc": "A list that has been used, arrived at by using it.",
    "default": true,
    "drive": [ { "type": "input.draft", "value": "write the design" },
               { "click": "button.add" } ],
    "value": {} } }
```

**After**:

```
fixtures:
  "nearly full":
    ~doc: "One press from the rule declining."
    it.n = 2

  "three rows" ~default:
    ~doc: "A list that has been used, arrived at by using it."
    ~drive:
      type("input.draft", "write the design")
      click("button.add")
```

The envelope keys become options — `~doc`, `~view`, `~tags`, `~default`,
`~drive`, `~intents` — and the `value` object becomes field initialisers,
written the way a `field`'s initialiser is.

**Before** — the scene block of `Guarded.html`:

```json
{
  "the guard stops it at three": {
    "steps": [
      { "click": "button" },
      { "click": "button" },
      { "click": "button" },
      { "expect": "text", "at": "output", "is": "3" },
      { "click": "button" },
      { "expect": "log", "contains": "precondition `room` does not hold" }
    ]
  }
}
```

**After**:

```
tests:
  "the guard stops it at three":
    click("button")
    click("button")
    click("button")
    expect text("output") == "3"
    click("button")
    expect log contains "precondition `room` does not hold"
```

The verbs and readers:

| Today | `.tutu` |
| --- | --- |
| `{ "click": "li.todo", "nth": 2 }` | `click("li.todo", ~nth: 2)` |
| `{ "type": "input.draft", "value": "milk" }` | `type("input.draft", "milk")` |
| `{ "key": "input.draft", "is": "Enter" }` | `key("input.draft", "Enter")` |
| `{ "check": "input.done", "is": true }` | `check("input.done", true)` |
| `{ "fire": "section", "event": "e", "value": {…} }` | `fire("section", "e", {…})` |
| `{ "drag": "li.todo", "from": 0, "to": 2 }` | `drag("li.todo", 0, 2)` |
| `{ "send": "init", "args": [1, "two"] }` | `send("init", 1, "two")` |
| `{ "expect": "text", "at": "o", "is": "2" }` | `expect text("o") == "2"` |
| `{ "expect": "texts", "at": "li", "is": [...] }` | `expect texts("li") == [...]` |
| `{ "expect": "attr", "at": "a", "name": "href", … }` | `expect attr("a", "href") == "/here"` |
| `{ "expect": "state", "at": ".count", "is": 2 }` | `expect state it.count == 2` |
| `{ "expect": "html", "contains": "…" }` | `expect html contains "…"` |
| `{ "expect": "count", "at": "li", "is": 3 }` | `expect count("li") == 3` |
| `{ "component": "Board" }` | `~component: Board` |
| `{ "init": "fresh" }` | `~init: "fresh"` |
| `{ "args": { "count": 3 } }` | `~args: { count: 3 }` |
| `{ "intents": { "rows": { "ok": [...] } } }` | `~intents:` then `rows: ok [...]` |
| `{ "raw": true }` | `~raw` |

**A step is a call**, and so is anything else that would need a comma at the
top of a group. `type "input.draft", "milk"` does not parse: shrubbery
admits a comma only immediately inside `(&nbsp;)`, `[&nbsp;]` or `{&nbsp;}`, so
a comma at the top of a group is `MisplacedComma`. Everything else in the
language was already a call, so the steps read better for it.

### One check to run over a converted view

A stylesheet compiled from the classes a view uses only sees the LITERAL
fragments of a bound value, so a class that ends up somewhere the collector
does not look leaves the stylesheet silently and the page renders unstyled in
whichever branch nobody opened. Count before and count after:

```bash
tutuca gen-margaui-css src/ --print-classes | wc -l
```

Equal counts across a conversion is a one-line gate over the whole class of
that failure, and it is worth running per file rather than per batch.

## What the conversion changes underneath

Two consequences worth knowing before you convert a component people have
already used.

- **A renamed field re-keys a snapshot.** A compiled card exports no `persist`,
  so a restore comes back through the declared-field projection, by name. Rename
  `emptyMessage` to `empty_message` and yesterday's snapshot has no key under
  the new name: the card comes back at its opening state. No error and no data
  loss — the source and the transcript survive — but a half-filled form is
  empty. One-time, per card, at conversion.
- **Naming an anonymous component re-keys its schema fingerprint.** The
  fingerprint seeds `ObjId::of`, which the render cache is keyed by, so do not
  run a converted card and its `.html` original in one process: two components
  that hash alike are treated as one. Convert one card per commit.

## What does not convert mechanically

Two things. Everything else in this page is a rewrite rule.

- **A macro that assembles a handler NAME from parameters.** Macro parameters
  substitute as source text today, which is what makes
  `<x:btn-rm :handler="$remove_in_items_at" :arg="@key">` work: the call site
  hands over a handler and its argument as text and the macro body writes
  `@on.click="^handler ^arg"`. Hygienic parameters cannot do that by
  definition. The replacement is to pass the action —
  `@btn_rm(~on_click: it.items.delete_at(i))` — which covers the documented
  idiom; a macro that builds a name out of parts has to be rewritten.
- **A property with both accessors on one line.** Shrubbery's `;` continues the
  innermost block, so `property count :: Int ~public: get: it.count; set(v): …`
  puts the `set` inside the `get`. Write one accessor per line.
- **A `new` block that branches.** `new T` followed by writes under an `if`
  has no constructor call to become, because the arguments differ per branch.
  Lift the branch into the argument: `T(x: if c | a | b)`, or build the two
  calls in the two branches.

## The order to migrate the repo in

1. **The converter**: `.html` → `.tutu`, checked by lowering the result back
   and asserting the typed forms match. It is what converts the 86 files in the
   repo that carry a `tutuca/` block.
2. **The corpus**: `tutucard/examples/`, `storybook/examples/`,
   `skill/tutuca/patterns/`, `demo/`, `docs/*.mbt.md`, `examples/*`.
3. **`tutucard` and the playgrounds**, whose checkers and panes read the four
   blocks by name.
4. **The skill** — `skill/tutuca/*.md` is 8.7k lines and is what an agent
   authors from, so it goes as one change rather than file by file. A skill
   half in each notation teaches both.
5. **Deletion**: `viewfile/`, the HTML splitter; `tscript`'s two lexers and
   parsers; the JSON readers in `statedef` and `scenedef`. Per the repo's
   convention there is no retired spelling kept behind a flag — the old
   notation leaves in the same change that stops needing it.

## The whole file, before and after

`tutucard/examples/Guarded.html`:

```html
<script type="tutuca/spec">
  /// A counter with a rule, and a test block that watches the rule hold.
  state Guarded {
    /// How far it has counted.
    n: Int

    /// True while there is room left.
    pred room
      format $'the counter is full at {.n}' { .n < 3 }
  }
</script>

<script type="tutuca/script">
  /// Count one more, while there is room.
  receive bump requires room {
    .n += 1
  }
</script>

<script type="tutuca/fixtures">
{
  "nearly full": {
    "value": { "n": 2 },
    "doc": "One press from the rule declining."
  }
}
</script>

<script type="tutuca/test">
{
  "the guard stops it at three": {
    "steps": [
      { "click": "button" },
      { "click": "button" },
      { "click": "button" },
      { "expect": "text", "at": "output", "is": "3" },
      { "click": "button" },
      { "expect": "text", "at": "output", "is": "3" },
      { "expect": "log", "contains": "precondition `room` does not hold" }
    ]
  },
  "and says nothing while it holds": {
    "steps": [
      { "click": "button" },
      { "expect": "text", "at": "output", "is": "1" },
      { "expect": "log", "is": [] }
    ]
  }
}
</script>

<template id="Guarded">
  <div>
    <button @on.click="bump">+</button>
    <output @text=".n"></output>
  </div>
</template>
```

`guarded.tutu`:

```
spec:
  /// A counter with a rule, and scenes that watch the rule hold.
  Guarded ~root:
    /// How far it has counted.
    field n :: Int = 0

    /// True while there is room left.
    pred room:
      ~format: @str{the counter is full at @(it.n)}
      it.n < 3

logic:
  Guarded:
    /// Count one more, while there is room.
    receive bump:
      ~requires: room
      it.n += 1

view:
  Guarded:
    @div{
      @button(~on_click: bump){+}
      @output{@(it.n)}
    }

fixtures:
  "nearly full":
    ~doc: "One press from the rule declining."
    it.n = 2

tests:
  "the guard stops it at three":
    click("button")
    click("button")
    click("button")
    expect text("output") == "3"
    click("button")
    expect text("output") == "3"
    expect log contains "precondition `room` does not hold"

  "and says nothing while it holds":
    click("button")
    expect text("output") == "1"
    expect log == []
```

`tutuca outline guarded.tutu` reads that today and answers:

```
guarded.tutu
  spec      Guarded ~root
  logic     Guarded
  view      Guarded
  fixtures  "nearly full"
  tests     "the guard stops it at three", "and says nothing while it holds"
```

## The ahead-of-time path

A view file compiled by `gen` converts the same way — the spec and script
blocks and the templates are the same three languages. Two things change
around it:

- **The MoonBit beside it does not.** `storybook/examples/counter.mbt` names
  `counter_component()` and a `ModuleDef`; both are generated from the file and
  neither mentions its notation.
- **The generated modules are regenerated, not converted.**
  `*_view_gen.mbt` and `*_view_ir_gen.mbt` are outputs. Run `gen` against the
  `.tutu` and delete the old pair; never hand-edit either.

## See also

- `tutufile/` — the reader for stage 1, and the package the rest hangs off.
- `cli/outline.mbt` — `tutuca outline`, which is how a converted file is
  checked today.
- `skill/tutuca/schema.md`, `core.md`, `testing.md` — the current notation,
  which stays authoritative until stage 6.
