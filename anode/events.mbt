// Event registration data (parse side
// only — the runtime modifier wrappers are render territory).

///|
fn NodeEvents::add(
  self : NodeEvents,
  name : String,
  handler : @tscript.HandlerParse,
  modifiers : Array[String],
) -> Unit {
  self.handlers.push({ name, handler, modifiers, binding: None, })
}
