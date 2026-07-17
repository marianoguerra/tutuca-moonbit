// ctx.walk_path: walk the component instances on the handler's path leaf→root.

///|
priv struct CompNode {
  cid : Int
  child : CompNode?
  collector : Array[Int] // shared across the tree; the walk handler fills it
}

///|
impl @tutuca.PathNode for CompNode with fn field(self, name) {
  match name {
    "child" =>
      match self.child {
        Some(c) => Some(c as &@tutuca.PathNode)
        None => None
      }
    _ => None
  }
}

///|
impl @tutuca.PathNode for CompNode with fn as_value(self) {
  Some(Obj(self))
}

///|
impl @tutuca.PathNode for CompNode with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "walk") =>
      Some(
        Handler((_args, ctx) => {
          ctx.walk_path((id, _inst) => {
            self.collector.push(id)
            true
          })
          None
        }),
      )
    (Receive, "walk1") =>
      Some(
        Handler((_args, ctx) => {
          // stop after the first (leaf) component
          ctx.walk_path((id, _inst) => {
            self.collector.push(id)
            false
          })
          None
        }),
      )
    _ => None
  }
}

///|
// CompNode is also a component instance (has a component id).
impl @tutuca.Obj for CompNode with fn component_id(self) {
  Some(self.cid)
}

///|
test "walk_path visits component instances leaf -> root" {
  let collector : Array[Int] = []
  let leaf = CompNode::{ cid: 2, child: None, collector }
  let root = CompNode::{ cid: 1, child: Some(leaf), collector }
  let tx = @transactor.Transactor::new(root)
  // dispatch "walk" at .child (the leaf); the handler walks leaf -> root
  let _ = tx.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("child")]),
    "walk",
    ([] : Array[@tutuca.Value]),
  )
  tx.settle()
  inspect(collector.map(x => x.to_string()).join(","), content="2,1")
}

///|
test "walk_path callback can stop early by returning false" {
  let collector : Array[Int] = []
  let leaf = CompNode::{ cid: 2, child: None, collector }
  let root = CompNode::{ cid: 1, child: Some(leaf), collector }
  let tx = @transactor.Transactor::new(root)
  let _ = tx.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("child")]),
    "walk1",
    ([] : Array[@tutuca.Value]),
  )
  tx.settle()
  // returning false after the leaf stops before the root is visited
  inspect(collector.map(x => x.to_string()).join(","), content="2")
}
