///|
fn status_comp() -> @component.Component {
  status_component(initial={ message: "", count: 0, })
}

///|
/// `ctx.send_at_path(path, name, args)` addresses a specific component by path;
/// `ctx.send(name, args)` dispatches a `Receive` arm on SELF (so several call
/// sites can share one handler body without duplicating it).
///
/// Only `submit` and `clearStatus` are left: both address the CHILD by path,
/// which is the one thing the script block deliberately does not spell.
/// `clearDraft` — the message `submit` sends to itself — is in the block.
fn send_receive_comp() -> @component.Component {
  send_receive_component(initial={ ..SendReceiveState::zero(), draft: "", }, update=(
    s,
    msg,
    ctx,
  ) => {
    match msg {
      Receive("submit", _) => {
        let text = s.draft.trim().to_owned()
        if text != "" {
          // message the sibling child by path
          ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "flash", [
            Str(text),
          ])
          // …and message SELF, reusing the `clearDraft` receive handler
          ctx.send("clear_draft", []) // this handler changes nothing directly; the messages do
        }
        Unchanged
      }
      Receive("clear_status", _) => {
        ctx.send_at_path(ctx.path().concat([FieldStep("status")]), "clear", [])
        Unchanged
      }
      _ => Unhandled
    }
  })
}

///|
pub fn send_receive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="send-receive",
    components=[send_receive_comp(), status_comp()],
    examples=[
      { component: "SendReceive", title: "Default", args: Map([]), view: None, },
    ],
  )
}

///|
/// A TreeItem renders its own children with `<x render-each=".items">` — the
/// component renders ITSELF, recursively, stopping where `items` is empty.
///
/// Statics. MoonBit needs no statics bucket: a static
/// is just a plain function (`tree_item_from_data` below) that closes over the
/// Component and calls `.make(...)`. Nothing in the framework calls statics —
/// they are plain functions.
fn tree_item_comp() -> @component.Component {
  tree_item_component(
    initial={ type_: "dir", label: "A Tree Item", is_open: true, items: [], },
    compute=m => {
      match m {
        AreChildsVisible =>
          Some((s, _args, _stack) => Bool(s.is_open && s.items.length() > 0))
      }
    },
    update=(s, msg, ctx) => {
      match msg {
        // emit an event any ancestor may observe, then toggle self. The event
        // carries this item's own instance value, read off the dispatch path
        // (its leaf is self).
        Receive("on_item_click", _) => {
          let mut self_v : @tutuca.Value = Null
          ctx.walk_path((_id, inst) => {
            self_v = inst // stop at the leaf: self
            false
          })
          ctx.intent(
            "treeItemSelected",
            [self_v],
            @tutuca.IntentOpts::new(route=[Dyn]),
          )
          Next({ ..s, is_open: !s.is_open, })
        }
        // a TreeItem between the source and the root sees the event and passes
        // it on unchanged (returning None = no change)
        Intent("treeItemSelected", _) => Unhandled
        _ => Unhandled
      }
    },
  )
}

///|
/// The root catches the bubbled event and records it — aggregate state kept
/// without threading callbacks down the tree.
fn tree_root_comp() -> @component.Component {
  tree_root_component(initial={ ..TreeRootState::zero(), log: [], }, update=(
    s,
    msg,
    _ctx,
  ) => {
    match msg {
      Intent("treeItemSelected", args) => {
        let label = match args {
          [Obj(o), ..] =>
            match o.field("label") {
              Some(Str(v)) => v
              _ => "?"
            }
          _ => "?"
        }
        let log = s.log.copy()
        log.insert(0, "selected: \{label}")
        Next({ ..s, log, })
      }
      _ => Unhandled
    }
  })
}

///|
/// The `fromData` factory, as a plain MoonBit function: build a
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
    "is_open": Bool(true),
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
