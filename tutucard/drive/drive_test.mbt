// The step vocabulary, driven against an ordinary module.
//
// No guest, no manifest, no wasm: `drive_scene` takes a mounted harness, and a
// `ModuleDef` mounts one on every backend. What is being tested is what a verb
// DOES and what a reader ANSWERS, and neither has anything to do with where the
// component came from.
//
// The module is defined here rather than borrowed, for the reason the harness's
// own demo gives: a self-contained fixture is readable without opening another
// package, and this file doubles as the vocabulary's documentation.

///|
priv struct TodoState {
  draft : String
  todos : Array[@tutuca.Value]
  done : Bool
}

///|
/// A list with a text input, a checkbox and a guarded button — one of each
/// thing a scene has a verb for.
fn todo_module() -> @component.ModuleDef {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <input class="draft" :value=".draft" @on.input="setDraft e.value">
          #|  <button class="add" @on.click="add">add</button>
          #|  <ul><li class="todo" @each=".todos"><x text="@value"></x></li></ul>
          #|  <output class="count" @text="$total"></output>
          #|  <input class="all" type="checkbox" :checked=".done" @on.input="setDone e.value">
          #|  <a class="home" href="/here">home</a>
          #|  <button class="clear" @on.click="clear">clear</button>
          #|</div>
        ),
      ),
    },
    name="Todo",
    init=TodoState::{ draft: "", todos: [], done: false },
    compute={ "total": (s, _args) => Num(s.todos.length().to_double()) },
    update=(s : TodoState, msg, _ctx) => {
      match msg {
        Receive("add", _) =>
          if s.draft == "" {
            // A guard: nothing to add, so nothing happens. From the DOM's side
            // this is indistinguishable from a selector that matched nothing,
            // which is what the `refused` reader is for.
            Unchanged
          } else {
            let todos = s.todos.copy()
            todos.push(Str(s.draft))
            Next({ ..s, todos, draft: "" })
          }
        Receive("clear", _) => Next({ ..s, todos: [] })
        _ => Unhandled
      }
    },
  )
  @component.ModuleDef::new(name="todo", components=[comp])
}

///|
impl @component.Fields for TodoState with fn encode(s) {
  { "draft": Str(s.draft), "todos": List(s.todos), "done": Bool(s.done) }
}

///|
impl @component.Fields for TodoState with fn decode(f) {
  guard f.get("draft") is Some(Str(d)) else { return None }
  guard f.get("todos") is Some(List(t)) else { return None }
  guard f.get("done") is Some(Bool(b)) else { return None }
  Some({ draft: d, todos: t, done: b })
}

///|
impl @component.Fields for TodoState with fn schema() {
  @component.SchemaInfo::new(
    fingerprint="drive-todo",
    fields=[
      @component.FieldInfo::new("draft", TyText),
      @component.FieldInfo::new("todos", TyList(TyAny)),
      @component.FieldInfo::new("done", TyBool),
    ],
    view_handlers=["add", "clear", "setDraft", "setDone"],
    view_names=["main"],
  )
}

///|
/// Drive a block against the module, and answer the report.
fn drive(src : String) -> @drive.SceneResult raise {
  let scenes = @scenedef.parse_scenes(src)
  let h = @harness.mount(todo_module(), "Todo")
  @drive.drive_scene(h, scenes[0])
}

///|
/// Every step's verdict, one per line, which is what a failing report reads
/// like.
fn lines(r : @drive.SceneResult) -> String {
  r.steps
  .map(s => {
    "\{s.at} " +
    (if s.ok { "ok" } else { "FAIL" }) +
    (if s.why == "" { "" } else { " — " + s.why })
  })
  .join("\n")
}

///|
test "a scene drives and reads" {
  let r = drive(
    (
      #|{ "adds two": { "steps": [
      #|  { "type": "input.draft", "value": "milk" },
      #|  { "click": "button.add" },
      #|  { "type": "input.draft", "value": "eggs" },
      #|  { "click": "button.add" },
      #|  { "expect": "count", "at": "li.todo", "is": 2 },
      #|  { "expect": "texts", "at": "li.todo", "is": ["milk", "eggs"] },
      #|  { "expect": "text",  "at": "output.count", "is": "2" },
      #|  { "expect": "value", "at": "input.draft", "is": "" },
      #|  { "expect": "attr",  "at": "a.home", "name": "href", "is": "/here" },
      #|  { "expect": "state", "at": ".todos[1]", "is": "eggs" },
      #|  { "expect": "html",  "contains": "<li class=\"todo\">milk</li>" }
      #|] } }
    ),
  )
  inspect(
    lines(r),
    content=(
      #|0 ok
      #|1 ok
      #|2 ok
      #|3 ok
      #|4 ok
      #|5 ok
      #|6 ok
      #|7 ok
      #|8 ok
      #|9 ok
      #|10 ok
    ),
  )
  assert_true(r.ok)
}

///|
/// The HTML comes back WITHOUT the renderer's bookkeeping, which is what makes
/// it worth handing to a reader — and what stops a snapshot moving because a
/// component id did.
test "the html a scene answers is the markup, not the bookkeeping" {
  let r = drive(
    (
      #|{ "one": { "steps": [
      #|  { "type": "input.draft", "value": "milk" },
      #|  { "click": "button.add" }
      #|] } }
    ),
  )
  assert_true(r.html.contains("<li class=\"todo\">milk</li>"))
  assert_false(r.html.contains("data-cid"))
  assert_false(r.html.contains("data-eid"))
  assert_false(r.html.contains("§"))
  // ...and `raw` brings them back, for whoever is debugging the renderer
  // rather than the card.
  let raw = drive(
    (
      #|{ "one": { "raw": true, "steps": [ { "click": "button.add" } ] } }
    ),
  )
  assert_true(raw.html.contains("data-cid"))
}

///|
/// A scene with no `expect` in it is a DRIVE, and it still answers everything.
/// This is the shape an agent writes first.
test "a scene that asserts nothing still reports what happened" {
  let r = drive(
    (
      #|{ "just look": { "steps": [
      #|  { "type": "input.draft", "value": "milk" },
      #|  { "click": "button.add" }
      #|] } }
    ),
  )
  assert_true(r.ok)
  assert_eq(r.steps.length(), 2)
  inspect(
    r.state.to_json().stringify(),
    content="{\"draft\":\"\",\"todos\":[\"milk\"],\"done\":false}",
  )
  assert_true(r.html.contains("milk"))
  // Two transactions: the input and the click.
  assert_eq(r.activity.length(), 0) // filled in by the mounter, not by drive_scene
}

///|
/// An expectation with no answer RECORDS. It never fails, and what it read
/// comes back — which is `moon test --update` for a card.
test "an expectation with no answer records what it read" {
  let r = drive(
    (
      #|{ "record": { "steps": [
      #|  { "type": "input.draft", "value": "milk" },
      #|  { "click": "button.add" },
      #|  { "expect": "texts", "at": "li.todo" },
      #|  { "expect": "state", "at": ".draft" }
      #|] } }
    ),
  )
  assert_true(r.ok)
  @debug.assert_eq(r.steps[2].got, Some(List([Str("milk")])))
  @debug.assert_eq(r.steps[2].want, None)
  @debug.assert_eq(r.steps[3].got, Some(Str("")))
}

///|
/// A disagreement names the reader and both values, because a report that says
/// only "step 4 failed" sends you back to the component to find out what it
/// did instead.
test "a failing expectation says what it wanted and what it got" {
  let r = drive(
    (
      #|{ "wrong": { "steps": [
      #|  { "click": "button.add" },
      #|  { "expect": "count", "at": "li.todo", "is": 1 },
      #|  { "expect": "html", "contains": "class=\"nope\"" }
      #|] } }
    ),
  )
  assert_false(r.ok)
  inspect(
    lines(r),
    content=(
      #|0 ok
      #|1 FAIL — `count` answered 0, not 1
      #|2 FAIL — `html` does not contain "class=\"nope\""
    ),
  )
}

///|
/// The one that makes a scene about a guarded button mean anything.
///
/// Clicking `add` with an empty draft changes nothing, and so does clicking a
/// selector that matches nothing. From the DOM they are the same. `refused` is
/// the only thing that tells them apart, and a scene that does not ask gets
/// them in the scene's own list either way.
test "a guard that declined is not a click that did nothing" {
  let r = drive(
    (
      #|{ "guarded": { "steps": [
      #|  { "send": "nope" },
      #|  { "expect": "refused", "is": ["NO_HANDLER at `nope`"] },
      #|  { "click": "button.clear" },
      #|  { "expect": "refused", "is": [] }
      #|] } }
    ),
  )
  inspect(
    lines(r),
    content=(
      #|0 ok
      #|1 ok
      #|2 ok
      #|3 ok
    ),
  )
  @debug.assert_eq(r.refusals, ["NO_HANDLER at `nope`"])
}

///|
/// A selector that matches nothing is a FAILURE, not a silent pass. It is the
/// shape a typo takes, and the harness reports it by raising — so the step
/// carries the sentence rather than the scene dying.
test "a selector that matches nothing fails the step, not the scene" {
  let r = drive(
    (
      #|{ "typo": { "steps": [
      #|  { "click": "button.nosuch" },
      #|  { "expect": "count", "at": "li.todo", "is": 0 }
      #|] } }
    ),
  )
  assert_false(r.ok)
  assert_false(r.steps[0].ok)
  assert_true(r.steps[0].why.contains("nosuch"))
  // ...and the scene kept going, so the rest of the block is still reported.
  assert_true(r.steps[1].ok)
}

///|
test "check, key and renders" {
  let r = drive(
    (
      #|{ "more verbs": { "steps": [
      #|  { "check": "input.all", "is": true },
      #|  { "expect": "state", "at": ".done", "is": true },
      #|  { "expect": "checked", "at": "input.all", "is": true },
      #|  { "type": "input.draft", "value": "x" },
      #|  { "key": "input.draft", "is": "Enter" },
      #|  { "expect": "state", "at": ".draft", "is": "x" }
      #|] } }
    ),
  )
  inspect(
    lines(r),
    content=(
      #|0 ok
      #|1 ok
      #|2 ok
      #|3 ok
      #|4 ok
      #|5 ok
    ),
  )
}
