// Tree navigation — click folders to toggle open/closed, files to select (logged below).

///|
/// A TreeItem renders its own children with `<x render-each=".items">` — the
/// component renders ITSELF, recursively, stopping where `items` is empty.
fn tree_item_comp() -> @component.Component {
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
      // emit an event any ancestor may observe, then toggle self
      "onItemClick": (inst, _args, ctx) => {
        ctx.bubble("treeItemSelected", [inst.to_value()])
        match inst.get("isOpen") {
          Bool(b) => Some(inst.set("isOpen", Bool(!b)))
          _ => None
        }
      },
    },
    bubble={
      // a TreeItem between the source and the root sees the event and passes it
      // on unchanged (returning None = no change)
      "treeItemSelected": (_inst, _args, _ctx) => None,
    },
  )
}

///|
/// The root catches the bubbled event and records it — aggregate state kept
/// without threading callbacks down the tree.
fn tree_root_comp() -> @component.Component {
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

///|
/// Build a TreeItem (and, recursively, its children) from plain data.
fn tree_item_from_data(
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
fn main {
  @host.mount(build(), "app")
}
