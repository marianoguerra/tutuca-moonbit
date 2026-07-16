// Event registration data (src/anode.js NodeEvents/NodeEvent, parse side
// only — the runtime modifier wrappers are render territory).

///|
fn NodeEvents::add(
  self : NodeEvents,
  name : String,
  handler : @tutuca.HandlerParse,
  modifiers : Array[String],
) -> Unit {
  self.handlers.push({ name, handler, modifiers })
}
