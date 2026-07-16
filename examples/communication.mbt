// Ports of:
//   docs/examples/send-receive.js — ctx.send / ctx.at.field(..).send + receive
//   docs/examples/tree.js         — recursion, ctx.bubble, and JS `statics`
//
// PORT RULE — where a handler that needs `ctx` goes.
// JS appends `ctx` as the last argument to EVERY dispatched handler
// (transactor.js:416), so a `methods.submit(ctx)` can send messages. MoonBit
// splits the two on purpose:
//
//   MethodFn        (Instance, Array[Value])            -> Value      // pure
//   InstanceHandler (Instance, Array[Value], &Ctx)      -> Instance?  // effectful
//
// because a method is ALSO evaluated in value positions (`@text="$label"`,
// `@show="$canSubmit"`) where no event and no ctx exist. So: a handler that
// needs ctx goes in `input` / `receive` / `bubble` / `response`, and the view
// calls it by BARE name. The tutorial already says the methods/input split is
// organizational, so this costs nothing.

///|
/// A sibling that owns its own state and knows nothing about who messages it —
/// the path is the only coupling.
fn status_comp() -> @component.Component {
  @component.component(
    name="Status",
    view=(
      #|<div class="alert alert-info" @show="truthy? .message">
      #|  <span class="msg" @text=".message"></span>
      #|  <small>(flashed <x text=".count"></x> times)</small>
      #|</div>
    ),
    fields={
      "message": @component.FieldSpec::of_default(Str("")),
      "count": @component.FieldSpec::of_default(Num(0)),
    },
    receive={
      "flash": (inst, args, _ctx) => {
        match (args, inst.get("count")) {
          ([Str(msg), ..], Num(n)) =>
            Some(inst.set("message", Str(msg)).set("count", Num(n + 1)))
          _ => None
        }
      },
      "clear": (inst, _args, _ctx) => Some(inst.set("message", Str(""))),
    },
  )
}

///|
/// `ctx.send_at_path(path, name, args)` addresses a specific component by path;
/// `ctx.send(name, args)` dispatches a `receive` handler on SELF (so several call
/// sites can share one handler body without duplicating it).
fn send_receive_comp() -> @component.Component {
  @component.component(
    name="SendReceive",
    view=(
      #|<section class="flex flex-col gap-2">
      #|  <x render=".status"></x>
      #|  <input class="input" :value=".draft" @on.input="$setDraft value"
      #|    @on.keydown+send="submit"
      #|    placeholder="Type a message and press Enter" />
      #|  <div class="flex gap-2">
      #|    <button class="btn btn-primary send" @on.click="submit">Send</button>
      #|    <button class="btn btn-ghost clear" @on.click="clearStatus">Clear status</button>
      #|  </div>
      #|</section>
    ),
    fields={
      "status": @component.FieldSpec::comp("Status"),
      "draft": @component.FieldSpec::of_default(Str("")),
    },
    input={
      "submit": (inst, _args, ctx) => {
        let text = match inst.get("draft") {
          Str(s) => s.trim().to_owned()
          _ => ""
        }
        if text == "" {
          return None
        }
        // message the sibling child by path — JS spells this
        // `ctx.at.field("status").send("flash", [text])`
        ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "flash", [
          Str(text),
        ])
        // …and message SELF, reusing the `clearDraft` receive handler
        ctx.send("clearDraft", []) // this handler changes nothing directly; the messages do
        None
      },
      "clearStatus": (_inst, _args, ctx) => {
        ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "clear", [])
        None
      },
    },
    receive={
      "clearDraft": (inst, _args, _ctx) => Some(inst.set("draft", Str(""))),
    },
  )
}

///|
pub fn send_receive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="send-receive",
    components=[send_receive_comp(), status_comp()],
    examples=[
      { component: "SendReceive", title: "Default", args: {}, view: None },
    ],
  )
}

///|
/// A TreeItem renders its own children with `<x render-each=".items">` — the
/// component renders ITSELF, recursively, stopping where `items` is empty.
///
/// PORT NOTE — `statics`. JS puts a `fromData` factory in a `statics` bucket and
/// calls it `TreeItem.Class.fromData(v)`. MoonBit needs no such bucket: a static
/// is just a plain function (`tree_item_from_data` below) that closes over the
/// Component and calls `.make(...)`. Nothing in the framework calls statics —
/// they are plain class methods in JS too.
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
/// The JS `statics.fromData` factory, as a plain MoonBit function: build a
/// TreeItem (and, recursively, its children) from plain data.
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
pub fn tree_module() -> @component.ModuleDef {
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
