// All Together Now — compose independent example components as fields of one
// root. Each sub-component (Counter, the to-do list, the tree) is defined with
// no knowledge of being composed; the root embeds each with
// `FieldSpec::comp(name)` and renders it in its own tab with `<x render=".field">`.
// (The full docs example also folds in the JSON editor, personal site and
// drag-and-drop — see those playgrounds above; the mechanism is identical.)
//
// Six components, ONE view file: composability.html names each with
// `<template id="Name">`, and the generator emits a `<name>_views()` builder
// per component (counter_views(), items_views(), tree_root_views(), …).

// --- Counter (from the counter example) ------------------------------------
struct CxCounterState {
  count : Int
} derive(ToJson, FromJson)

fn cx_counter_comp() -> @component.Component {
  @component.component(
    views=counter_views(),
    name="Counter",
    init=CxCounterState::{ count: 0 },
    mutate={ "inc": (s : CxCounterState, _a) => { count: s.count + 1 } },
    update=(s : CxCounterState, msg, _ctx) => match CounterMsg::from_dispatch(msg) {
      Some(Dec) => Some({ count: s.count - 1 })
      Some(Unknown(_, _)) | None => None
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
    views=item_views(),
    name="Item",
    init=CxTodoItemState::{ completed: false, text: "do the thing" },
  )
}

struct CxTodoItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

fn cx_todo_items_comp(item : @component.Component) -> @component.Component {
  @component.component(
    views=items_views(),
    name="Items",
    init=CxTodoItemsState::{ items: [] },
    update=(s : CxTodoItemsState, msg, _ctx) => match ItemsMsg::from_dispatch(msg) {
      Some(OnAddItem) => Some({ items: s.items + [item.make(Map([]))] })
      Some(Unknown(_, _)) | None => None
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
    views=tree_item_views(),
    name="TreeItem",
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
    // a raw `match msg`: Bubble is raised by component code, so the views
    // cannot declare it and TreeItemMsg cannot type it
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
    views=tree_root_views(),
    name="TreeRoot",
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
    views=composability_views(),
    name="Composability",
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
