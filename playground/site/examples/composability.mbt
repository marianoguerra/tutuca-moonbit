// All Together Now — compose independent example components as fields of one
// root. Each sub-component (Counter, the to-do list, the tree) is defined with
// no knowledge of being composed; the root embeds each with
// `FieldSpec::comp(name)` and renders it in its own tab with `<x render=".field">`.
// (The full docs example also folds in the JSON editor, personal site, drag-and-
// drop and visual-wasm — see those playgrounds above; the mechanism is identical.)

// --- Counter (from the counter example) ------------------------------------
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
    fields={ "count": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "inc": (inst, _a) => match inst.get("count") {
        Num(n) => inst.set("count", Num(n + 1)).to_value()
        _ => inst.to_value()
      },
    },
    input={
      "dec": (inst, _a, _c) => match inst.get("count") {
        Num(n) => Some(inst.set("count", Num(n - 1)))
        _ => None
      },
    },
  )
}

// --- To-Do (from the todo example) -----------------------------------------
fn cx_todo_item_comp() -> @component.Component {
  @component.component(
    name="Item",
    view=(
      #|<div class="flex gap-3 items-center">
      #|  <input type="checkbox" class="checkbox" :checked=".completed" @on.input="$setCompleted value" />
      #|  <input class="input" :value=".text" @on.input="$setText value" :disabled=".completed" />
      #|</div>
    ),
    fields={
      "completed": @component.FieldSpec::of_default(Bool(false)),
      "text": @component.FieldSpec::of_default(Str("do the thing")),
    },
  )
}

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
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    input={
      "onAddItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(item.make(Map([])).to_value())
        Some(inst.set("items", List(items)))
      },
    },
  )
}

// --- Tree (from the tree example) ------------------------------------------
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
    fields={
      "type": @component.FieldSpec::of_default(Str("dir")),
      "label": @component.FieldSpec::of_default(Str("A Tree Item")),
      "isOpen": @component.FieldSpec::of_default(Bool(true)),
      "items": @component.FieldSpec::of_default(List([])),
    },
    methods={
      "areChildsVisible": (inst, _args) => {
        match (inst.get("isOpen"), inst.get("items")) {
          (Bool(open), List(kids)) => Bool(open && kids.length() > 0)
          _ => Bool(false)
        }
      },
    },
    input={
      "onItemClick": (inst, _args, ctx) => {
        ctx.bubble("treeItemSelected", [inst.to_value()])
        match inst.get("isOpen") {
          Bool(b) => Some(inst.set("isOpen", Bool(!b)))
          _ => None
        }
      },
    },
    bubble={ "treeItemSelected": (_inst, _args, _ctx) => None },
  )
}

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
    fields={
      "root": @component.FieldSpec::comp("TreeItem"),
      "log": @component.FieldSpec::of_default(List([])),
    },
    bubble={
      "treeItemSelected": (inst, args, _ctx) => {
        let label = match args {
          [Obj(o), ..] =>
            match o.obj_field("label") {
              Some(Str(s)) => s
              _ => "?"
            }
          _ => "?"
        }
        let log = match inst.get("log") {
          List(a) => a.copy()
          _ => []
        }
        log.insert(0, Str("selected: \{label}"))
        Some(inst.set("log", List(log)))
      },
    },
  )
}

fn cx_tree_item_from_data(
  comp : @component.Component,
  type_ : String,
  label : String,
  items : Array[@tutuca.Value],
) -> @tutuca.Value {
  comp
  .make({
    "type": Str(type_),
    "label": Str(label),
    "isOpen": Bool(true),
    "items": List(items),
  })
  .to_value()
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
    fields={
      "activeSection": @component.FieldSpec::of_default(Str("counter")),
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
