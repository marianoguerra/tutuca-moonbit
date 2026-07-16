// Drag support (the _handleDragEvent half of JS app.js; touch synthesis
// lives in the browser glue). dragstart captures a DragInfo from the SOURCE
// render: the teleported value plus a stack rebuilt WITH frame-only steps,
// so handlers can read the source's @each binds via dragInfo.lookupBind.
// `drop` bubbles across component boundaries (reconstruction's
// BUBBLING_EVENTS) and every dispatch while a drag is active sees the
// dragInfo arg.

///|
/// The `dragInfo` handler argument (JS class DragInfo as an Obj):
/// type / value / lookupBind(name).
priv struct DragInfoObj {
  drag_type : String
  val : @tutuca.Value
  stack : @render.RenderStack
}

///|
impl @tutuca.Obj for DragInfoObj with fn obj_field(self, name) {
  match name {
    "type" => Some(Str(self.drag_type))
    "value" => Some(self.val)
    "lookupBind" =>
      Some(
        Fn(args => {
          match args {
            [_, Str(n), ..] => @tutuca.Stack::lookup_bind(self.stack, n)
            _ => Null
          }
        }),
      )
    _ => None
  }
}

///|
impl @tutuca.Obj for DragInfoObj with fn obj_debug(self) {
  "DragInfo(\{self.drag_type})"
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
    if cur.is_same_node(root) {
      return None
    }
    if cur.attribute("data-droptarget") is Some(_) {
      return Some(cur)
    }
    match cur.parent_node() {
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
          let t = match self.drag_info_value() {
            Obj(o) =>
              match o.obj_field("type") {
                Some(Str(s)) => s
                _ => "_external"
              }
            _ => "_external"
          }
          @vdom.DomNode::set_attribute(dt, "data-draggingover", t)
          self.cur_drag_over = Some(dt)
        }
        None => ()
      }
    "dragstart" => {
      @vdom.DomNode::set_attribute(node, "data-dragging", "1")
      guard self.transactor.root.as_value() is Some(root_val) else { return }
      // teleported so the dragged value resolves to its real location
      let txn_path = path.compact().to_transaction_path()
      let value = match txn_path.lookup(self.transactor.root) {
        Some(n) => n.as_value().unwrap_or(Null)
        None => Null
      }
      let drag_type = node.attribute("data-dragtype").unwrap_or("?")
      // the drag stack keeps frame-only steps (@each binds) — compact()
      // would strip them; DynSteps are still teleported
      let stack0 = @render.RenderStack::new(root_val, comps=self.scope.comps)
      let stack = @render.build_stack(path.to_transaction_path(), stack0).unwrap_or(
        stack0,
      )
      self.drag = Some(DragState::{
        node,
        info: Obj(DragInfoObj::{ drag_type, val: value, stack }),
      })
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
