// All Together Now — compose independent example components as fields of one
// root. Each sub-component (Counter, the to-do list, the tree) is defined with
// no knowledge of being composed; the root embeds each with
// `FieldSpec::comp(name)` and renders it in its own tab with `<x render=".field">`.
// (The full docs example also folds in the JSON editor, personal site, drag-and-
// drop and visual-wasm — see those playgrounds above; the mechanism is identical.)

// --- Counter (from the counter example) ------------------------------------
struct CxCounterState {
  count : Int
} derive(ToJson, FromJson)

fn cx_counter_comp() -> @component.Component {
  @component.component(
    name="Counter",
    view=(
      #|<div style="display:flex;gap:.5rem;align-items:center;font-size:1.5rem">
      #|  <button @on.click="dec">-</button>
      #|  <b @text=".count"></b>
      #|  <button @on.click="$inc">+</button>
      #|</div>
    ),
    init=CxCounterState::{ count: 0 },
    mutate={ "inc": (s : CxCounterState, _a) => { count: s.count + 1 } },
    update=(s : CxCounterState, msg, _ctx) => match msg {
      Input("dec", _) => Some({ count: s.count - 1 })
      _ => None
    },
  )
}

// --- To-Do (from the todo example) -----------------------------------------
struct CxTodoItemState {
  completed : Bool
  text : String
} derive(ToJson, FromJson)

fn cx_todo_item_comp() -> @component.Component {
  @component.component(
    name="Item",
    view=(
      #|<div class="flex gap-3 items-center">
      #|  <input type="checkbox" class="checkbox" :checked=".completed" @on.input="$setCompleted value" />
      #|  <input class="input" :value=".text" @on.input="$setText value" :disabled=".completed" />
      #|</div>
    ),
    init=CxTodoItemState::{ completed: false, text: "do the thing" },
  )
}

struct CxTodoItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

fn cx_todo_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    name="Items",
    view=(
      #|<div class="flex flex-col gap-3">
      #|  <button class="btn btn-soft btn-success add" @on.click="onAddItem">Add Task</button>
      #|  <div class="flex flex-col gap-3 w-full">
      #|    <div @each=".items" class="flex gap-3 justify-center items-center w-full row">
      #|      <x render-it></x>
      #|      <button class="btn btn-soft btn-sm btn-error btn-circle font-mono rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</div>
    ),
    init=CxTodoItemsState::{ items: [] },
    update=(s : CxTodoItemsState, msg, _ctx) => match msg {
      Input("onAddItem", _) => Some({ items: s.items + [item.make(Map([]))] })
      _ => None
    },
  )
}

// --- Tree (from the tree example) ------------------------------------------
struct CxTreeItemState {
  type_ : String
  label : String
  isOpen : Bool
  items : Array[@tutuca.Value]
} derive (
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

fn cx_tree_item_comp() -> @component.Component {
  @component.component(
    name="TreeItem",
    view=(
      #|<section>
      #|  <p class="head"
      #|    @if.class=".isOpen" @then="$'head open type-{.type}'" @else="$'head closed type-{.type}'"
      #|    @text=".label" @on.click="onItemClick"></p>
      #|  <div class="pl-3 pt-1 flex flex-col gap-2 kids" @show="$areChildsVisible">
      #|    <x render-each=".items"></x>
      #|  </div>
      #|</section>
    ),
    style=(
      #|user-select: none;
      #|.head { cursor: pointer; }
      #|.head:before { content: "⏺️"; margin-right: 0.25rem; }
      #|.head.type-file:before { content: "📄️"; }
      #|.head.open.type-dir:before { content: "📂️"; }
      #|.head.closed.type-dir:before { content: "📁️"; }
    ),
    init=CxTreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      isOpen: true,
      items: [],
    },
    compute={
      "areChildsVisible": (s : CxTreeItemState, _args) => Bool(
        s.isOpen && s.items.length() > 0,
      ),
    },
    update=(s : CxTreeItemState, msg, ctx) => match msg {
      Input("onItemClick", _) => {
        let mut self_v : @tutuca.Value = Null
        ctx.walk_path((_id, inst) => {
          self_v = inst
          false // stop at the leaf: self
        })
        ctx.bubble("treeItemSelected", [self_v])
        Some({ ..s, isOpen: !s.isOpen })
      }
      Bubble("treeItemSelected", _) => None
      _ => None
    },
  )
}

struct CxTreeRootState {
  log : Array[@tutuca.Value]
} derive(ToJson, FromJson)

fn cx_tree_root_comp() -> @component.Component {
  @component.component(
    name="TreeRoot",
    view=(
      #|<div class="flex flex-col gap-3">
      #|  <x render=".root"></x>
      #|  <ul class="flex flex-col gap-2 max-h-[40vh] overflow-y-auto log">
      #|    <li @each=".log"><x text="@value"></x></li>
      #|  </ul>
      #|</div>
    ),
    init=CxTreeRootState::{ log: [] },
    specs={ "root": @component.FieldSpec::comp("TreeItem") },
    update=(s : CxTreeRootState, msg, _ctx) => match msg {
      Bubble("treeItemSelected", args) => {
        let label = match args {
          [Obj(o), ..] =>
            match o.obj_field("label") {
              Some(Str(l)) => l
              _ => "?"
            }
          _ => "?"
        }
        let log = s.log.copy()
        log.insert(0, Str("selected: \{label}"))
        Some({ log, })
      }
      _ => None
    },
  )
}

fn cx_tree_item_from_data(
  comp : @component.Component,
  type_ : String,
  label : String,
  items : Array[@tutuca.Value],
) -> @tutuca.Value {
  comp.make({
    "type": Str(type_),
    "label": Str(label),
    "isOpen": Bool(true),
    "items": List(items),
  })
}

fn cx_tree_sample(item : @component.Component) -> @tutuca.Value {
  let file = (label : String) => cx_tree_item_from_data(item, "file", label, [])
  cx_tree_item_from_data(item, "dir", "src", [
    cx_tree_item_from_data(item, "dir", "components", [file("button.js"), file("card.js")]),
    file("index.js"),
    file("README.md"),
  ])
}

// --- The composing root ----------------------------------------------------
struct ComposabilityState {
  activeSection : String
} derive(ToJson, FromJson)

fn composability_comp(tree_args : Map[String, @tutuca.Value]) -> @component.Component {
  @component.component(
    name="Composability",
    view=(
      #|<section class="flex flex-col gap-4">
      #|  <div role="tablist" class="tabs tabs-border">
      #|    <button role="tab" id="tab-counter"
      #|      @if.class="equals? .activeSection 'counter'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setActiveSection 'counter'">Counter</button>
      #|    <button role="tab" id="tab-todo"
      #|      @if.class="equals? .activeSection 'todo'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setActiveSection 'todo'">To-Do</button>
      #|    <button role="tab" id="tab-tree"
      #|      @if.class="equals? .activeSection 'tree'" @then="'tab tab-active'" @else="'tab'"
      #|      @on.click="$setActiveSection 'tree'">Tree</button>
      #|  </div>
      #|  <div class="pane-counter" @show="equals? .activeSection 'counter'"><x render=".counter"></x></div>
      #|  <div class="pane-todo" @show="equals? .activeSection 'todo'"><x render=".todo"></x></div>
      #|  <div class="pane-tree" @show="equals? .activeSection 'tree'"><x render=".tree"></x></div>
      #|</section>
    ),
    init=ComposabilityState::{ activeSection: "counter" },
    specs={
      "counter": @component.FieldSpec::comp("Counter"),
      "todo": @component.FieldSpec::comp("Items"),
      "tree": @component.FieldSpec::comp("TreeRoot", args=tree_args),
    },
  )
}

fn composability_module() -> @component.ModuleDef {
  let item = cx_todo_item_comp()
  let tree_item = cx_tree_item_comp()
  let tree_args : Map[String, @tutuca.Value] = { "root": cx_tree_sample(tree_item) }
  @component.ModuleDef::new(
    name="composability",
    components=[
      composability_comp(tree_args),
      cx_counter_comp(),
      cx_todo_items_comp(item),
      item,
      cx_tree_root_comp(),
      tree_item,
    ],
    examples=[
      { component: "Composability", title: "Default", args: Map([]), view: None },
    ],
  )
}

fn build() -> @component.ModuleDef {
  composability_module()
}
