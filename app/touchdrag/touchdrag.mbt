// The touch -> drag state machine (JS App._handleTouchEvent): a single touch
// on a [draggable="true"] element becomes dragstart once it moves >10px,
// dragover while moving (hit-testing under the finger), drop + dragend on
// release. Both event-glue twins drive this one implementation.

///|
/// The per-backend primitives the machine needs. `has_prop`/`get_int`/
/// `get_num` are the typed reads @core.Any can't do on wasm-gc;
/// `element_from_point(root, x, y)` hit-tests under the finger (the js twin
/// descends shadow roots, the wasm twin uses plain document.elementFromPoint);
/// `fire(kind, target)` dispatches a synthetic drag DomEvent into the app at
/// `target` (a raw JS element, never null).
pub(all) struct TouchOps {
  has_prop : (@core.Any, String) -> Bool
  get_int : (@core.Any, String) -> Int
  get_num : (@core.Any, String) -> Double
  element_from_point : (@core.Any, Double, Double) -> @core.Any
  fire : (String, @core.Any) -> Unit
}

///|
/// Live single-touch capture between touchstart and touchend/cancel.
priv struct TouchState {
  id : Double
  start_x : Double
  start_y : Double
  target : @core.Any
  mut active : Bool
}

///|
/// One machine instance per installed app.
pub struct TouchDrag {
  ops : TouchOps
  priv state : Ref[TouchState?]
}

///|
pub fn TouchDrag::new(ops : TouchOps) -> TouchDrag {
  { ops, state: Ref(None) }
}

///|
/// The fixed listener set drag/touch synthesis needs on top of the events the
/// registered views use (both twins' install functions add these).
pub fn drag_touch_events() -> Array[String] {
  [
    "dragstart", "dragover", "dragend", "drop", "touchstart", "touchmove", "touchend",
    "touchcancel",
  ]
}

///|
fn TouchDrag::fire(self : TouchDrag, kind : String, target : @core.Any) -> Unit {
  if !@core.is_nullish(target) {
    (self.ops.fire)(kind, target)
  }
}

///|
fn TouchDrag::prevent_default(self : TouchDrag, ev : @core.Any) -> Unit {
  if (self.ops.has_prop)(ev, "preventDefault") {
    let _ = ev._call("preventDefault", [])
  }
}

///|
fn TouchDrag::touches_len(self : TouchDrag, ev : @core.Any) -> Int {
  let ts = ev._get("touches")
  if @core.is_nullish(ts) {
    0
  } else {
    (self.ops.get_int)(ts, "length")
  }
}

///|
fn first_touch(ev : @core.Any) -> @core.Any {
  let ts = ev._get("touches")
  if @core.is_nullish(ts) {
    @core.null()
  } else {
    ts._get_by_index(0)
  }
}

///|
/// The nearest `[draggable="true"]` ancestor of a touch target, or null.
fn TouchDrag::closest_draggable(
  self : TouchDrag,
  target : @core.Any,
) -> @core.Any {
  if @core.is_nullish(target) || !(self.ops.has_prop)(target, "closest") {
    @core.null()
  } else {
    target._call("closest", [@core.any("[draggable=\"true\"]")])
  }
}

///|
/// Find the touch with `id` across touches/changedTouches, or null.
fn TouchDrag::find_touch(
  self : TouchDrag,
  ev : @core.Any,
  id : Double,
) -> @core.Any {
  for key in ["touches", "changedTouches"] {
    let list = ev._get(key)
    if !@core.is_nullish(list) {
      let n = (self.ops.get_int)(list, "length")
      for i in 0..<n {
        let t = list._get_by_index(i)
        if (self.ops.get_num)(t, "identifier") == id {
          return t
        }
      }
    }
  }
  @core.null()
}

///|
/// Feed one touch event through the machine. `root` is the app's root node
/// (the hit-test anchor).
pub fn TouchDrag::handle(
  self : TouchDrag,
  ev : @core.Any,
  name : String,
  root : @core.Any,
) -> Unit {
  let get_num = self.ops.get_num
  if name == "touchstart" {
    if self.state.val is Some(_) || self.touches_len(ev) != 1 {
      return
    }
    let t = first_touch(ev)
    if @core.is_nullish(t) {
      return
    }
    let draggable = self.closest_draggable(t._get("target"))
    if @core.is_nullish(draggable) {
      return
    }
    self.state.val = Some({
      id: get_num(t, "identifier"),
      start_x: get_num(t, "clientX"),
      start_y: get_num(t, "clientY"),
      target: draggable,
      active: false,
    })
    return
  }
  guard self.state.val is Some(ts) else { return }
  let t = self.find_touch(ev, ts.id)
  if @core.is_nullish(t) {
    return
  }
  let x = get_num(t, "clientX")
  let y = get_num(t, "clientY")
  if name == "touchmove" {
    if !ts.active {
      let dx = x - ts.start_x
      let dy = y - ts.start_y
      if dx * dx + dy * dy < 100.0 {
        return
      }
      ts.active = true
      self.prevent_default(ev)
      self.fire("dragstart", ts.target)
    } else {
      self.prevent_default(ev)
      self.fire("dragover", (self.ops.element_from_point)(root, x, y))
    }
  } else if name == "touchend" || name == "touchcancel" {
    if ts.active {
      if name == "touchend" {
        self.fire("drop", (self.ops.element_from_point)(root, x, y))
      }
      self.fire("dragend", ts.target)
    }
    self.state.val = None
  }
}
