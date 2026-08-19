// DomEvent construction + the closed name→field mapping handler args use
// (JS InputEvent.lookupName, transactor.js:339-378 — update the lint layer
// if more names are added).

///|
pub fn DomEvent::new(
  name~ : String,
  value? : @tutuca.Value = Null,
  read_path? : EventPathReader,
  key? : String = "",
  key_code? : Int = 0,
  alt? : Bool = false,
  shift? : Bool = false,
  ctrl_or_cmd? : Bool = false,
  meta? : Bool = false,
  drag_info? : @tutuca.Value = Null,
) -> DomEvent {
  {
    name,
    value,
    key,
    key_code,
    alt,
    shift,
    ctrl_or_cmd,
    meta,
    drag_info,
    read_path,
  }
}

///|
/// JS toNullIfNaN(parseInt/parseFloat(getValue(e))). Full-string parses (the
/// JS prefix-parse of "12px" → 12 is not mirrored).
fn value_as_num(v : @tutuca.Value, as_int : Bool) -> @tutuca.Value {
  match v {
    Num(n) => if as_int { Num(n.to_int().to_double()) } else { Num(n) }
    Str(s) => {
      let n : Double = @strconv.from_str(s) catch { _ => return Null }
      if as_int {
        Num(n.to_int().to_double())
      } else {
        Num(n)
      }
    }
    _ => Null
  }
}

///|
/// A field of the active `DragInfo` (`app/drag.mbt` builds the Obj), or Null
/// when no drag is in flight.
fn drag_field(info : @tutuca.Value, name : String) -> @tutuca.Value {
  match info {
    Obj(o) => o.obj_field(name).unwrap_or(Null)
    _ => Null
  }
}

///|
/// A bind of the SOURCE render, through the stack the drag captured — what a
/// handler would otherwise reach by pulling `lookupBind` out of `dragInfo` and
/// applying it, which no interpreted handler can do. (`Fn` convention: element
/// 0 is the this-slot.)
fn drag_bind(info : @tutuca.Value, name : String) -> @tutuca.Value {
  match drag_field(info, "lookupBind") {
    Fn(lookup) => lookup([Null, Str(name)])
    _ => Null
  }
}

///|
fn event_field(e : DomEvent, name : String) -> @tutuca.Value {
  match name {
    "value" => e.value
    "valueAsInt" => value_as_num(e.value, true)
    "valueAsFloat" => value_as_num(e.value, false)
    "key" => Str(e.key)
    "keyCode" => Num(e.key_code.to_double())
    "isAlt" => Bool(e.alt)
    "isShift" => Bool(e.shift)
    "isCtrl" | "isCmd" => Bool(e.ctrl_or_cmd)
    "isUpKey" => Bool(e.key == "ArrowUp")
    "isDownKey" => Bool(e.key == "ArrowDown")
    "isSend" => Bool(e.key == "Enter")
    "isCancel" => Bool(e.key == "Escape")
    "isTabKey" => Bool(e.key == "Tab")
    "dragInfo" => e.drag_info
    // The narrow three beside it, the way valueAsInt sits beside value: the
    // source row's key, the dragged value, and the type it declared.
    "dragKey" => drag_bind(e.drag_info, "key")
    "dragValue" => drag_field(e.drag_info, "value")
    "dragType" => drag_field(e.drag_info, "type")
    // target / event / ctx: not exposed (DOM objects are not Values)
    _ => Null
  }
}

///|
/// Whether `name` is one of layer 1's computed accessors.
///
/// Asked of the NAME rather than of the answer, because those are different
/// questions: `e.value` on an empty input is legitimately `Str("")` and
/// `e.isAlt` is legitimately `Bool(false)`, and an accessor that answered
/// falsily would fall through to layer 2 if the test were the ANSWER.
///
/// The list is `@eventpath.event_accessors` — one vocabulary, in the one place
/// three packages can reach.
fn is_computed_accessor(name : String) -> Bool {
  @eventpath.event_accessors.contains(name)
}

///|
/// Resolve `e.<segments>`, in the two layers the design gives it.
///
/// **Layer 1 is the computed accessors, and it SHADOWS layer 2.** That order
/// is the whole of what makes this work, and it is asserted in a test rather
/// than trusted to a comment: a DOM `Event` has no `value` property at all.
/// `value` is computed — the checked state on a checkbox, the picked file's
/// metadata on a file input, the `detail` on a `CustomEvent`, the input's
/// string otherwise — so a path walk consulted first would answer `Null` for
/// every one of the repository's `e.value` call sites and every form in it
/// would stop working.
///
/// **Layer 2 is the allowlisted walk**, and the allowlist is checked HERE.
/// A backend's resolver only ever sees a path that was already permitted, so
/// one place decides and no backend can forget to ask.
pub fn event_path(e : DomEvent, segments : Array[String]) -> @tutuca.Value {
  // Layer 1. Only a single segment can be a computed accessor: they are
  // framework names, not properties of anything, so `e.value.length` is not a
  // read of a shorter one.
  if segments.length() == 1 && is_computed_accessor(segments[0]) {
    return event_field(e, segments[0])
  }
  guard @eventpath.check_event_path(segments) is PathOk else { return Null }
  match e.read_path {
    Some(EventPathReader(read)) => read(segments)
    // No resolver: a test's event, or a backend that has none. A path that
    // does not resolve is Null, which is the same answer.
    None => Null
  }
}
