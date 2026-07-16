// DomEvent construction + the closed name→field mapping handler args use
// (JS InputEvent.lookupName, transactor.js:339-378 — update the lint layer
// if more names are added).

///|
pub fn DomEvent::new(
  name~ : String,
  value? : @tutuca.Value = Null,
  key? : String = "",
  key_code? : Int = 0,
  alt? : Bool = false,
  shift? : Bool = false,
  ctrl_or_cmd? : Bool = false,
  meta? : Bool = false,
  drag_info? : @tutuca.Value = Null,
) -> DomEvent {
  { name, value, key, key_code, alt, shift, ctrl_or_cmd, meta, drag_info }
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
    // target / event / ctx: not exposed (DOM objects are not Values)
    _ => Null
  }
}
