// All Together Now — compose independent example components as fields of one
// root. Each sub-component (Counter, the to-do list, the tree) is defined with
// no knowledge of being composed; the root embeds each with
// a declared child slot and renders it in its own tab with `<x render=".field">`.
// (The full docs example also folds in the JSON editor, personal site and
// drag-and-drop — see those playgrounds above; the mechanism is identical.)
//
// Six components, ONE view file: composability.html names each with
// `<template id="Name">`, and the generator emits a `<name>_views()` builder
// per component (counter_views(), items_views(), tree_root_views(), …).

// --- Counter (from the counter example) ------------------------------------

fn cx_counter_comp() -> @component.Component {
  // `inc` and `dec` are in the view file's `<script type="tutuca/script"
  // for="Counter">` block, so the whole counter is its seed.
  counter_component(initial=CounterState::{ count: 0 })
}

// --- To-Do (from the todo example) -----------------------------------------

fn cx_todo_item_comp() -> @component.Component {
  item_component(
    initial=ItemState::{ completed: false, text: "do the thing" },
  )
}


fn cx_todo_items_comp(item : @component.Component) -> @component.Component {
  items_component(
    initial=ItemsState::{ items: [] },
    update=(s, msg, _ctx) => match ItemsMsg::from_dispatch(msg) {
      Some(OnAddItem) => Next({ items: s.items + [item.make(Map([]))] })
      // Served by a generated mutator or another bucket: the view
      // spells these bare now, so they arrive as Inputs, and
      // returning None falls through to whatever answers them.
      Some(RemoveInItemsAt(_)) => Unhandled
      Some(Unknown(_, _)) | None => Unhandled
    },
  )
}

// --- Tree (from the tree example) ------------------------------------------

fn cx_tree_item_comp() -> @component.Component {
  tree_item_component(
    initial=TreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      isOpen: true,
      items: [],
    },
    compute=m => match m {
      AreChildsVisible =>
        Some((s, _args, _stack) => Bool(s.isOpen && s.items.length() > 0))
    },
    // a raw `match msg`: an Intent arrives because a walk routed here, so the
    // views cannot declare it and TreeItemMsg cannot type it
    update=(s, msg, ctx) => match msg {
      Receive("onItemClick", _) => {
        let mut self_v : @tutuca.Value = Null
        ctx.walk_path((_id, inst) => {
          self_v = inst
          false // stop at the leaf: self
        })
        ctx.intent("treeItemSelected", [self_v], @tutuca.IntentOpts::new(route=[Dyn]))
        Next({ ..s, isOpen: !s.isOpen })
      }
      Intent("treeItemSelected", _) => Unhandled
      _ => Unhandled
    },
  )
}


fn cx_tree_root_comp() -> @component.Component {
  tree_root_component(
    initial={ ..TreeRootState::zero(), log: [] },
    update=(s, msg, _ctx) => match msg {
      Intent("treeItemSelected", args) => {
        let label = match args {
          [Obj(o), ..] =>
            match o.field("label") {
              Some(Str(l)) => l
              _ => "?"
            }
          _ => "?"
        }
        let log = s.log.copy()
        log.insert(0, "selected: \{label}")
        Next({ ..s, log, })
      }
      _ => Unhandled
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

fn composability_comp(tree_args : Map[String, @tutuca.Value]) -> @component.Component {
  composability_component(
    initial={ ..ComposabilityState::zero(), activeSection: "counter" },
    slot_args={ "tree": tree_args },
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
