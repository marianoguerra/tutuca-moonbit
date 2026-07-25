// The UPDATE workload: how much does it cost to change a mounted app?
//
// render.mbt measures mount + first render. This measures the second render and
// everything under it — new state, re-render to a vdom, diff against the live
// one, patch the DOM — with nothing else in the timed region:
//
//   - the app is mounted ONCE, outside the bench, and shared across iterations
//   - the seeded state is built once too (render.mbt's memo)
//   - the workload dispatches a real DOM event and reads back `render_count()`,
//     an Int, instead of serializing the DOM (which for a 1000-row list costs
//     several times the patch being measured)
//
// Every workload is a ROUND TRIP — a change and the change back — so an app can
// be reused across iterations without drifting: two diff+patch passes per
// reported number, not one. `patch_test.mbt` asserts each one restores the DOM
// it started from, so "reused across iterations" is checked rather than assumed.
//
// The in-memory DOM is the point, not a limitation: @memdom's primitives are
// plain array splices with no layout, style or event-system cost behind them, so
// what is left is tutuca's own diff and patch. One caveat to keep in mind when
// reading the move-heavy numbers: @memdom holds children in an Array, so both
// `detach`'s index scan and the splice are O(children) where a real DOM is O(1).
// See OPTIMIZATIONS.md.
//
// What the harness itself adds is one selector walk per dispatched event, to find
// the element to fire at. `@harness.Harness::find` stops at the match it wants,
// so firing at the first row of a long list is cheap — but a selector that
// matches something AFTER the list (a pager button) still walks past it.
// `find_cost` benchmarks the walk alone, so that part can be subtracted instead
// of guessed at.

///|
/// n todo rows, mounted. `.checkbox` / `.input` / `.add` / `.rm` are the row
/// controls; see storybook/examples/todo.html.
pub fn mount_todo(n : Int) -> @harness.Harness {
  mounted("todo/\{n}", todo_module, "Items", todo_args(n))
}

///|
/// One counter. The smallest possible change: one text node.
pub fn mount_counter() -> @harness.Harness {
  mounted("counter", counter_module, "Counter", Map([]))
}

///|
/// n people behind a filter + pager: a change to the query re-runs the pipeline
/// over every item while only a page of them is in the DOM.
pub fn mount_people(n : Int) -> @harness.Harness {
  mounted("people/\{n}", filter_paginate_module, "SharedPeople", people_args(n))
}

///|
/// The JSON editor's array, whose rows are draggable — the one example with a
/// reorder handler, so the one that can measure a MOVE as opposed to a
/// replacement.
pub fn mount_json(depth : Int, breadth : Int) -> @harness.Harness {
  mounted(
    "json/\{depth}x\{breadth}",
    json_module,
    "JsonArray",
    json_args(depth, breadth),
  )
}

///|
/// The composability example: six tab panes, one shown at a time. Switching
/// tabs is the largest change the framework can be asked for — a whole subtree
/// leaves the DOM and another arrives.
pub fn mount_tabs() -> @harness.Harness {
  mounted(
    "tabs",
    composability_module,
    "Composability",
    example_args(composability_module, "Default (To-Do tab)"),
  )
}

// ---------------------------------------------------------------------------
// The round trips. Each returns render_count() so the bench has a cheap witness
// that the app actually re-rendered.

///|
/// NO-OP: set the first row's checkbox to the value it already has, twice. The
/// state swaps to an equal value, so the renderer and the differ do their full
/// walk and the DOM ends up untouched — the floor for any change at this size.
pub fn patch_noop(h : @harness.Harness) -> Int {
  let before = h.checked_of(".checkbox") catch { e => fail_patch("noop", e) }
  act("noop", () => h.check(".checkbox", before))
  act("noop", () => h.check(".checkbox", before))
  h.render_count()
}

///|
/// SMALL: one text node changes. `+` then `-` on the counter.
pub fn patch_counter(h : @harness.Harness) -> Int {
  act("counter", () => h.click(".btn-success"))
  act("counter", () => h.click(".btn-error"))
  h.render_count()
}

///|
/// SMALL: one row's attributes change. Tick the first row's checkbox and untick
/// it — a real DOM write, on one node, either way.
pub fn patch_toggle(h : @harness.Harness) -> Int {
  let before = h.checked_of(".checkbox") catch { e => fail_patch("toggle", e) }
  act("toggle", () => h.check(".checkbox", !before))
  act("toggle", () => h.check(".checkbox", before))
  h.render_count()
}

///|
/// MIDDLE: the list grows by one, then shrinks by one. `onAddItem` appends a
/// fresh row and `$removeInItemsAt 0` drops the first, so the list keeps its
/// length and rotates by one — the differ sees an insert at the end and a
/// removal at the front, which is the shape that makes an unkeyed differ move
/// every row.
pub fn patch_add_remove(h : @harness.Harness) -> Int {
  act("add", () => h.click(".add"))
  act("remove", () => h.click(".rm"))
  h.render_count()
}

///|
/// MIDDLE: a page of rows is replaced. Next then Prev on the pager — same node
/// count, entirely different contents.
pub fn patch_page(h : @harness.Harness) -> Int {
  act("page", () => h.click(".next"))
  act("page", () => h.click(".prev"))
  h.render_count()
}

///|
/// MIDDLE: reorder. Drag the first row onto the third and back — nodes MOVE
/// rather than change, which is the case a differ can either handle in two
/// splices or by rewriting everything in between.
pub fn patch_move(h : @harness.Harness) -> Int {
  act("move", () => h.drag(".entry", 0, 2))
  act("move", () => h.drag(".entry", 2, 0))
  h.render_count()
}

///|
/// BIG: every rendered row changes. Typing a query re-runs the filter over all n
/// items and the page fills with different people; clearing it puts the first
/// page back.
pub fn patch_refilter(h : @harness.Harness) -> Int {
  act("refilter", () => h.type_into(".q", "person 7"))
  act("refilter", () => h.type_into(".q", ""))
  h.render_count()
}

///|
/// FULL: switch views. Another tab's pane replaces the current one — a whole
/// component subtree unmounts and another renders from scratch.
pub fn patch_switch_view(h : @harness.Harness) -> Int {
  act("switch-view", () => h.click("#tab-json"))
  act("switch-view", () => h.click("#tab-todo"))
  h.render_count()
}

///|
/// The harness's own overhead, on its own: resolve the selector the way a
/// dispatch does, twice, and dispatch nothing. Subtract from the workload above
/// that fires at the same selector.
pub fn find_cost(h : @harness.Harness, sel : String) -> Int {
  let a = h.find(sel) catch { e => fail_patch("find \{sel}", e) }
  let b = h.find(sel) catch { e => fail_patch("find \{sel}", e) }
  a.childs.length() + b.childs.length()
}

// ---------------------------------------------------------------------------

///|
fn mounted(
  label : String,
  m : @component.ModuleDef,
  root : String,
  args : Map[String, @tutuca.Value],
) -> @harness.Harness {
  @harness.mount(m, root, args~) catch {
    e => abort("benchmark patch \{label}: mount failed: \{e}")
  }
}

///|
/// A module's own ExampleDef args, by title — the only place child-component
/// instances are built from the components the module registers.
fn example_args(
  m : @component.ModuleDef,
  title : String,
) -> Map[String, @tutuca.Value] {
  for e in m.examples {
    if e.title == title {
      return e.args
    }
  }
  abort("benchmark patch: module '\{m.name}' has no example '\{title}'")
}

///|
fn act(label : String, f : () -> Unit raise) -> Unit {
  f() catch {
    e => fail_patch(label, e)
  }
}

///|
fn[T] fail_patch(label : String, e : Error) -> T {
  abort("benchmark patch \{label}: \{e}")
}

///|
let counter_module : @component.ModuleDef = @examples.counter_module()

///|
let composability_module : @component.ModuleDef = @examples.composability_module()

///|
/// Named update workloads for the executable shell, each with its own mounted
/// app so a profile of one is not polluted by another's DOM. Mirrors
/// patch_bench_test.mbt; the shell exists to run these under a profiler, where
/// only the big ones are worth the sampling time.
pub fn patch_workloads() -> Array[(String, () -> Int)] {
  let todo_1000 = mount_todo(1000)
  let noop_1000 = mount_todo(1000)
  let add_1000 = mount_todo(1000)
  let people_1000 = mount_people(1000)
  let page_1000 = mount_people(1000)
  let json_deep = mount_json(8, 4)
  let tabs = mount_tabs()
  let counter = mount_counter()
  [
    ("noop/todo/1000", () => patch_noop(noop_1000)),
    ("toggle/todo/1000", () => patch_toggle(todo_1000)),
    ("add+remove/todo/1000", () => patch_add_remove(add_1000)),
    ("move/json/8x4", () => patch_move(json_deep)),
    ("page/people/1000", () => patch_page(page_1000)),
    ("refilter/people/1000", () => patch_refilter(people_1000)),
    ("switch-view", () => patch_switch_view(tabs)),
    ("counter", () => patch_counter(counter)),
  ]
}
