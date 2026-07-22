// Ports of:
//   docs/examples/send-receive.js — ctx.send / ctx.at.field(..).send + receive
//   docs/examples/tree.js         — recursion, ctx.bubble, and JS `statics`
//
// PORT RULE — where a handler goes in the typed API.
// JS appends `ctx` as the last argument to EVERY dispatched handler
// (transactor.js:416), so a `methods.submit(ctx)` can send messages. MoonBit
// splits the buckets by what they can do:
//
//   update  (S, Dispatch, &Ctx) -> S?     // effectful: Input/Receive/Bubble/
//                                         // Response arms, may send/bubble
//   mutate  (S, Array[Value]) -> S        // pure state change, $-callable
//   compute (S, Array[Value]) -> Value    // pure value read, $-callable
//
// because a $-callable is ALSO evaluated in value positions (`@text="$label"`,
// `@show="$canSubmit"`) where no event and no ctx exist. So: a handler that
// needs ctx goes in an `update` arm (Input for view events, Receive/Bubble/
// Response for messages), and the view calls it by BARE name. The tutorial
// already says the methods/input split is organizational, so this costs
// nothing.

///|
priv struct StatusState {
  message : String
  count : Int
} derive(ToJson, FromJson)

///|
/// A sibling that owns its own state and knows nothing about who messages it —
/// the path is the only coupling.
fn status_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="alert alert-info" @show="truthy? .message">
          #|  <span class="msg" @text=".message"></span>
          #|  <small>(flashed <x text=".count"></x> times)</small>
          #|</div>
        ),
      ),
    },
    name="Status",
    init=StatusState::{ message: "", count: 0 },
    update=(s : StatusState, msg, _ctx) => {
      match msg {
        Receive("flash", [Str(m), ..]) =>
          Some({ message: m, count: s.count + 1 })
        Receive("clear", _) => Some({ ..s, message: "" })
        _ => None
      }
    },
  )
}

///|
priv struct SendReceiveState {
  draft : String
} derive(ToJson, FromJson)

///|
/// `ctx.send_at_path(path, name, args)` addresses a specific component by path;
/// `ctx.send(name, args)` dispatches a `Receive` arm on SELF (so several call
/// sites can share one handler body without duplicating it).
fn send_receive_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
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
      ),
    },
    name="SendReceive",
    init=SendReceiveState::{ draft: "" },
    specs={ "status": @component.FieldSpec::comp("Status") },
    update=(s : SendReceiveState, msg, ctx) => {
      match msg {
        Input("submit", _) => {
          let text = s.draft.trim().to_owned()
          if text != "" {
            // message the sibling child by path — JS spells this
            // `ctx.at.field("status").send("flash", [text])`
            ctx.send_at_path(
              ctx.path().concat([FieldStep("status")]),
              "flash",
              [Str(text)],
            )
            // …and message SELF, reusing the `clearDraft` receive handler
            ctx.send("clearDraft", []) // this handler changes nothing directly; the messages do
          }
          None
        }
        Input("clearStatus", _) => {
          ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "clear", [])
          None
        }
        Receive("clearDraft", _) => Some({ draft: "" })
        _ => None
      }
    },
  )
}

///|
pub fn send_receive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="send-receive",
    components=[send_receive_comp(), status_comp()],
    examples=[
      { component: "SendReceive", title: "Default", args: Map([]), view: None },
    ],
  )
}

///|
priv struct TreeItemState {
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
///
/// PORT NOTE — `statics`. JS puts a `fromData` factory in a `statics` bucket and
/// calls it `TreeItem.Class.fromData(v)`. MoonBit needs no such bucket: a static
/// is just a plain function (`tree_item_from_data` below) that closes over the
/// Component and calls `.make(...)`. Nothing in the framework calls statics —
/// they are plain class methods in JS too.
fn tree_item_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
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
      ),
    },
    name="TreeItem",
    init=TreeItemState::{
      type_: "dir",
      label: "A Tree Item",
      isOpen: true,
      items: [],
    },
    compute={
      "areChildsVisible": (s : TreeItemState, _args) => {
        Bool(s.isOpen && s.items.length() > 0)
      },
    },
    update=(s : TreeItemState, msg, ctx) => {
      match msg {
        // emit an event any ancestor may observe, then toggle self. The event
        // carries this item's own instance value, read off the dispatch path
        // (its leaf is self).
        Input("onItemClick", _) => {
          let mut self_v : @tutuca.Value = Null
          ctx.walk_path((_id, inst) => {
            self_v = inst // stop at the leaf: self
            false
          })
          ctx.bubble("treeItemSelected", [self_v])
          Some({ ..s, isOpen: !s.isOpen })
        }
        // a TreeItem between the source and the root sees the event and passes
        // it on unchanged (returning None = no change)
        Bubble("treeItemSelected", _) => None
        _ => None
      }
    },
  )
}

///|
priv struct TreeRootState {
  log : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
/// The root catches the bubbled event and records it — aggregate state kept
/// without threading callbacks down the tree.
fn tree_root_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex flex-col gap-3">
          #|  <x render=".root"></x>
          #|  <ul class="flex flex-col gap-2 max-h-[40vh] overflow-y-auto log">
          #|    <li @each=".log"><x text="@value"></x></li>
          #|  </ul>
          #|</div>
        ),
      ),
    },
    name="TreeRoot",
    init=TreeRootState::{ log: [] },
    specs={ "root": @component.FieldSpec::comp("TreeItem") },
    update=(s : TreeRootState, msg, _ctx) => {
      match msg {
        Bubble("treeItemSelected", args) => {
          let label = match args {
            [Obj(o), ..] =>
              match o.obj_field("label") {
                Some(Str(v)) => v
                _ => "?"
              }
            _ => "?"
          }
          let log = s.log.copy()
          log.insert(0, Str("selected: \{label}"))
          Some({ log, })
        }
        _ => None
      }
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
  comp.make({
    "type": Str(type_),
    "label": Str(label),
    "isOpen": Bool(true),
    "items": List(items),
  })
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
