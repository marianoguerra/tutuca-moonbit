fn tree_item_comp() -> @component.Component {
  tree_item_component(
    initial=TreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      is_open: true,
      items: [],
    },
    compute=m => match m {
      AreChildsVisible =>
        Some((s, _args, _stack) => Bool(s.is_open && s.items.length() > 0))
    },
    // A raw `match msg`: this component answers an Intent, which arrives
    // because a walk routed here rather than because a view named it — so the
    // views cannot declare it and `TreeItemMsg::from_dispatch` cannot type it.
    update=(s, msg, ctx) => match msg {
      // raise an intent along the `dyn` leg — the ancestors, from this
      // component's PARENT up (payload: this item's own instance value, read
      // off the dispatch path, whose leaf is self) — then toggle self
      Receive("on_item_click", _) => {
        let mut self_v : @tutuca.Value = Null
        ctx.walk_path((_id, inst) => {
          self_v = inst
          false // stop at the leaf: self
        })
        ctx.intent("treeItemSelected", [self_v], @tutuca.IntentOpts::new(route=[Dyn]))
        Next({ ..s, is_open: !s.is_open })
      }
      // a TreeItem between the source and the root is an OBSERVER: it sees
      // the intent, does not reply, and the walk goes on to its own parent
      Intent("treeItemSelected", _) => Unhandled
      _ => Unhandled
    },
  )
}


///|
fn tree_root_comp() -> @component.Component {
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
    "is_open": Bool(true),
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
