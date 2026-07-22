// Tree navigation — click folders to toggle open/closed, files to select (logged below).

///|
struct TreeItemState {
  type_ : String
  label : String
  isOpen : Bool
  items : Array[@tutuca.Value]
} derive (
  ToJson(fields(type_(rename="type"))),
  FromJson(fields(type_(rename="type"))),
)

///|
/// A TreeItem renders its own children with `<x render-each=".items">` — the
/// component renders ITSELF, recursively, stopping where `items` is empty.
fn tree_item_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<section>
      #|  <p class="head"
      #|    @if.class=".isOpen" @then="$'head open type-{.type}'" @else="$'head closed type-{.type}'"
      #|    @text=".label" @on.click="onItemClick"></p>
      #|  <div class="pl-3 pt-1 flex flex-col gap-2 kids" @show="$areChildsVisible">
      #|    <x render-each=".items"></x>
      #|  </div>
      #|</section>
    ), style=(
      #|user-select: none;
      #|.head { cursor: pointer; }
      #|.head:before { content: "⏺️"; margin-right: 0.25rem; }
      #|.head.type-file:before { content: "📄️"; }
      #|.head.open.type-dir:before { content: "📂️"; }
      #|.head.closed.type-dir:before { content: "📁️"; }
    )),
  },
  name="TreeItem",
  init=TreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      isOpen: true,
      items: [],
    },
  compute={
      "areChildsVisible": (s : TreeItemState, _args) => Bool(
        s.isOpen && s.items.length() > 0,
      ),
    },
  update=(s : TreeItemState, msg, ctx) => match msg {
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
        Some({ ..s, isOpen: !s.isOpen })
      }
      // a TreeItem between the source and the root sees the event and passes
      // it on unchanged (returning None = no change)
      Bubble("treeItemSelected", _) => None
      _ => None
    },
)
}

///|
/// The root catches the bubbled event and records it — aggregate state kept
/// without threading callbacks down the tree.
struct TreeRootState {
  log : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn tree_root_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="flex flex-col gap-3">
      #|  <x render=".root"></x>
      #|  <ul class="flex flex-col gap-2 max-h-[40vh] overflow-y-auto log">
      #|    <li @each=".log"><x text="@value"></x></li>
      #|  </ul>
      #|</div>
    )),
  },
  name="TreeRoot",
  init=TreeRootState::{ log: [] },
  specs={ "root": @component.FieldSpec::comp("TreeItem") },
  update=(s : TreeRootState, msg, _ctx) => match msg {
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
