// Dispatch-channel tests ported from test/transactor.test.js: send/receive,
// $unknown fallback, bubbling (path shortens per hop, target_path fixed),
// stop_propagation, send_at_path back to the origin, and completion for a
// synchronous cascade. Handlers RECORD what they saw by transforming their
// own state — no shared logs, fully functional.

///|
priv struct Item {
  label : String
  acked : Bool
}

///|
fn item_node(label : String, acked : Bool) -> &@tutuca.PathNode {
  Item::{ label, acked }
}

///|
impl @tutuca.PathNode for Item with fn field(self, name) {
  match name {
    "label" => Some(@tutuca.Value::Str(self.label) as &@tutuca.PathNode)
    "acked" => Some(@tutuca.Value::Bool(self.acked) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for Item with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "set-label") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(item_node(s, self.acked))
            _ => None
          }
        }),
      )
    (Receive, "poke") =>
      Some(
        Handler((_args, ctx) => {
          ctx.bubble("poked", [Str(self.label)])
          None
        }),
      )
    (Receive, "poke-stop") =>
      Some(
        Handler((_args, ctx) => {
          ctx.bubble("poked-stop", [])
          None
        }),
      )
    (Receive, "ack") =>
      Some(Handler((_args, _ctx) => Some(item_node(self.label, true))))
    (Receive, "$unknown") =>
      Some(Handler((_args, _ctx) => Some(item_node("unknown!", false))))
    _ => None
  }
}

///|
priv struct Panel {
  item : &@tutuca.PathNode
  seen : String
}

///|
impl @tutuca.PathNode for Panel with fn field(self, name) {
  match name {
    "item" => Some(self.item)
    "seen" => Some(@tutuca.Value::Str(self.seen) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for Panel with fn with_field(self, name, v) {
  match name {
    "item" => Some(Panel::{ item: v, seen: self.seen } as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for Panel with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Bubble, "poked") =>
      Some(
        Handler((args, ctx) => {
          // record the payload and how deep this hop's ctx.path is
          let from = match args {
            [Str(s), ..] => s
            _ => "?"
          }
          Some(
            Panel::{
              item: self.item,
              seen: "poked:\{from}@\{ctx.path().items.length()}",
            }
            as &@tutuca.PathNode,
          )
        }),
      )
    (Bubble, "poked-stop") =>
      Some(
        Handler((_args, ctx) => {
          ctx.stop_propagation()
          Some(Panel::{ item: self.item, seen: "stopped" } as &@tutuca.PathNode)
        }),
      )
    _ => None
  }
}

///|
priv struct RootComp {
  panel : &@tutuca.PathNode
  seen : String
}

///|
impl @tutuca.PathNode for RootComp with fn field(self, name) {
  match name {
    "panel" => Some(self.panel)
    "seen" => Some(@tutuca.Value::Str(self.seen) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for RootComp with fn with_field(self, name, v) {
  match name {
    "panel" =>
      Some(RootComp::{ panel: v, seen: self.seen } as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for RootComp with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Bubble, "poked") =>
      Some(
        Handler((_args, ctx) => {
          // dispatch back to the fixed origin of the bubble
          ctx.send_at_path(ctx.target_path(), "ack", [])
          Some(
            RootComp::{
              panel: self.panel,
              seen: "root@path=\{ctx.path().items.length()},target=\{ctx.target_path().items.length()}",
            }
            as &@tutuca.PathNode,
          )
        }),
      )
    (Bubble, "poked-stop") =>
      Some(
        Handler((_args, _ctx) => {
          Some(
            RootComp::{ panel: self.panel, seen: "should-never-fire" }
            as &@tutuca.PathNode,
          )
        }),
      )
    _ => None
  }
}

///|
fn make_tree() -> &@tutuca.PathNode {
  RootComp::{
    panel: Panel::{ item: item_node("it1", false), seen: "" },
    seen: "",
  }
}

///|
fn item_path() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([FieldStep("panel"), FieldStep("item")])
}

///|
fn scalar(
  root : &@tutuca.PathNode,
  steps : Array[@tutuca.Step],
) -> @tutuca.Value {
  match @tutuca.Path::new(steps~).lookup(root) {
    Some(n) => n.as_value().unwrap_or(Null)
    None => Null
  }
}

///|
fn assert_v(got : @tutuca.Value, want : @tutuca.Value) -> Unit raise {
  assert_true(got == want)
}

///|
test "send dispatches to the leaf's receive bucket" {
  let tx = @transactor.Transactor::new(make_tree())
  let _ = tx.push_send(item_path(), "set-label", [Str("hi")])
  tx.settle()
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("item"), FieldStep("label")]),
    Str("hi"),
  )
}

///|
test "a named handler wins; missing name falls back to $unknown" {
  let tx = @transactor.Transactor::new(make_tree())
  let _ = tx.push_send(item_path(), "no-such-message", [])
  tx.settle()
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("item"), FieldStep("label")]),
    Str("unknown!"),
  )
}

///|
test "a missing handler with no $unknown is a silent physical no-op" {
  let tx = @transactor.Transactor::new(make_tree())
  let before = tx.root
  // Panel has no Receive bucket at all
  let _ = tx.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("panel")]),
    "anything",
    [],
  )
  tx.settle()
  assert_true(physical_equal(tx.root, before))
}

///|
test "bubble walks ancestors: path shortens per hop, target_path is fixed" {
  let tx = @transactor.Transactor::new(make_tree())
  let _ = tx.push_send(item_path(), "poke", [])
  tx.settle()
  // Panel saw the bubble with a 1-hop path and the item's payload
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("seen")]),
    Str("poked:it1@1"),
  )
  // Root saw it with a 0-hop path while target_path kept the full origin
  assert_v(scalar(tx.root, [FieldStep("seen")]), Str("root@path=0,target=2"))
  // Root's send_at_path(target_path) reached the originating item
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("item"), FieldStep("acked")]),
    Bool(true),
  )
}

///|
test "stop_propagation halts the bubble before the root" {
  let tx = @transactor.Transactor::new(make_tree())
  let _ = tx.push_send(item_path(), "poke-stop", [])
  tx.settle()
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("seen")]),
    Str("stopped"),
  )
  assert_true(scalar(tx.root, [FieldStep("seen")]) == Str(""))
}

///|
test "completion: subtree settles only after the whole bubble cascade" {
  let tx = @transactor.Transactor::new(make_tree())
  let t = tx.push_send(item_path(), "poke", [])
  let self_done : Ref[Bool] = { val: false }
  let subtree_done : Ref[Bool] = { val: false }
  t.completion().on_settled(() => self_done.val = true)
  t.completion().on_subtree_settled(() => subtree_done.val = true)
  assert_false(self_done.val)
  tx.settle()
  assert_true(self_done.val)
  assert_true(subtree_done.val)
  // and the cascade really ran to the end before settling
  assert_v(
    scalar(tx.root, [FieldStep("panel"), FieldStep("item"), FieldStep("acked")]),
    Bool(true),
  )
}

///|
test "on_change fires once per root swap with new and old" {
  let tx = @transactor.Transactor::new(make_tree())
  let swaps : Ref[Int] = { val: 0 }
  tx.on_change((new_root, old_root) => {
    assert_false(physical_equal(new_root, old_root)) catch {
      _ => ()
    }
    swaps.val = swaps.val + 1
  })
  let _ = tx.push_send(item_path(), "set-label", [Str("x")])
  let _ = tx.push_send(item_path(), "does-not-exist-anywhere", []) // $unknown fires -> swap
  tx.settle()
  assert_eq(swaps.val, 2)
}
