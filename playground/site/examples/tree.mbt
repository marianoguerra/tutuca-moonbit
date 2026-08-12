// Tree navigation — click folders to toggle open/closed, files to select
// (logged below). Both components' views live in the View tab (tree.html) and
// arrive here compiled, as `tree_item_views()` and `tree_root_views()`.


///|
/// A TreeItem renders its own children with `<x render-each=".items">` — the
/// component renders ITSELF, recursively, stopping where `items` is empty.
fn tree_item_comp() -> @component.Component {
  tree_item_component(
    init=TreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      isOpen: true,
      items: [],
    },
    compute=m => match m {
      AreChildsVisible =>
        Some((s, _args) => Bool(s.isOpen && s.items.length() > 0))
    },
    // A raw `match msg`: this component handles a Bubble, which the views
    // cannot declare, so `TreeItemMsg::from_dispatch` cannot type it.
    update=(s, msg, ctx) => match msg {
      // emit an event any ancestor may observe (payload: this item's own
      // instance value, read off the dispatch path — its leaf is self),
      // then toggle self
      Input("onItemClick", _) => {
        let mut self_v : @tutuca.Value = Null
        ctx.walk_path((_id, inst) => {
          self_v = inst
          false // stop at the leaf: self
        })
        ctx.bubble("treeItemSelected", [self_v])
        Next({ ..s, isOpen: !s.isOpen })
      }
      // a TreeItem between the source and the root sees the event and passes
      // it on unchanged (returning None = no change)
      Bubble("treeItemSelected", _) => Unhandled
      _ => Unhandled
    },
  )
}


///|
fn tree_root_comp() -> @component.Component {
  tree_root_component(
    init={ ..TreeRootState::zero(), log: [] },
    update=(s, msg, _ctx) => match msg {
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
        Next({ ..s, log, })
      }
      _ => Unhandled
    },
  )
}

///|
/// Build a TreeItem (and, recursively, its children) from plain data.
fn tree_item_from_data(
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

///|
fn tree_module() -> @component.ModuleDef {
  let item = tree_item_comp()
  let file = (label : String) => tree_item_from_data(item, "file", label, [])
  let sample = tree_item_from_data(item, "dir", "src", [
    tree_item_from_data(item, "dir", "components", [
      file("button.js"),
      file("card.js"),
    ]),
    file("index.js"),
    file("README.md"),
  ])
  @component.ModuleDef::new(name="tree", components=[tree_root_comp(), item], examples=[
    {
      component: "TreeRoot",
      title: "Default",
      args: { "root": sample },
      view: None,
    },
  ])
}

///|
fn build() -> @component.ModuleDef {
  tree_module()
}

///|
