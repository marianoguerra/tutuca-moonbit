// Drag support (touch synthesis
// lives in the browser glue). dragstart captures a DragInfo from the SOURCE
// render: the resumed value plus a stack rebuilt WITH frame-only steps,
// so handlers can read the source's @each binds via dragInfo.lookupBind.
// `drop` bubbles across component boundaries (reconstruction's
// BUBBLING_EVENTS) and every dispatch while a drag is active sees the
// dragInfo arg.

///|
/// The `dragInfo` handler argument: `type`, `value`, and `lookupBind(name)`.
///
/// A plain `Map`, where it was an `Obj` with two methods. `Obj` is the seam a
/// COMPONENT INSTANCE crosses — an identity, a schema, a dispatch bucket, a
/// successor — and this has none of those: it is three entries a handler reads
/// once, and one of them is a function, which a `Value::Fn` already is.
/// Implementing a nine-method trait to answer `field` was the trait being used
/// as a record.
fn drag_info(
  drag_type : String,
  value : @tutuca.Value,
  stack : @render.RenderStack,
) -> @tutuca.Value {
  Map({
    "type": Str(drag_type),
    "value": value,
    "lookupBind": Fn(args => {
      match args {
        // The Fn convention: element 0 is the this-slot.
        [_, Str(n), ..] => @tutuca.Stack::lookup_bind(stack, n)
        _ => Null
      }
    }),
  })
}

///|
/// The app's live drag capture: the dragged source node (for attribute
/// cleanup) and the DragInfo value handlers receive.
pub struct DragState[N] {
  node : N
  info : @tutuca.Value
}

///|
fn is_drag_event(name : String) -> Bool {
  name == "dragstart" ||
  name == "dragover" ||
  name == "dragend" ||
  name == "drop"
}

///|
fn[N : @vdom.DomWalk] closest_droptarget(node : N, root : N) -> N? {
  let mut cur = node
  for _hop in 0..<10000 {
    if @vdom.DomNode::is_same_node(cur, root) {
      return None
    }
    if cur.attribute("data-droptarget") is Some(_) {
      return Some(cur)
    }
    match @vdom.DomNode::parent_node(cur) {
      Some(p) => cur = p
      None => return None
    }
  }
  None
}

///|
fn[N : @vdom.DomWalk] App::clean_drag_over(self : App[N]) -> Unit {
  match self.cur_drag_over {
    Some(n) => @vdom.DomNode::remove_attribute(n, "data-draggingover")
    None => ()
  }
  self.cur_drag_over = None
}

///|
fn[N] App::drag_info_value(self : App[N]) -> @tutuca.Value {
  match self.drag {
    Some(d) => d.info
    None => Null
  }
}

///|
fn[N : @vdom.DomWalk] App::handle_drag(
  self : App[N],
  node : N,
  name : String,
  path : @tutuca.DispatchPath,
) -> Unit {
  match name {
    "dragover" =>
      match closest_droptarget(node, self.root_node) {
        Some(dt) => {
          self.clean_drag_over()
          // JS: draggingover carries the drag's type, "_external" when the
          // drag came from outside the app
          let t = match self.drag_info_value().field("type") {
            Str(s) => s
            _ => "_external"
          }
          @vdom.DomNode::set_attribute(dt, "data-draggingover", t)
          self.cur_drag_over = Some(dt)
        }
        None => ()
      }
    "dragstart" => {
      @vdom.DomNode::set_attribute(node, "data-dragging", "1")
      let root_val = self.transactor.root
      // The active resume frame is the dragged value's real location.
      let txn_path = path.compact().to_transaction_path()
      let value = match txn_path.lookup(self.transactor.root) {
        Some(n) => n
        None => Null
      }
      let drag_type = node.attribute("data-dragtype").unwrap_or("?")
      // The drag stack keeps frame-only steps (@each binds); compact() would
      // strip them.
      let stack0 = @render.RenderStack::new(root_val, comps=self.scope.comps)
      let stack = @render.build_dispatch_stack(path, stack0).unwrap_or(stack0)
      self.drag = Some({ node, info: drag_info(drag_type, value, stack), })
    }
    "drop" => self.clean_drag_over()
    _ => {
      // dragend: clear the capture and every drag attribute
      match self.drag {
        Some(d) => @vdom.DomNode::remove_attribute(d.node, "data-dragging")
        None => ()
      }
      self.drag = None
      self.clean_drag_over()
    }
  }
}
