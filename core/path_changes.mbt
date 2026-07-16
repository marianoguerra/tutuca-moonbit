// `ctx.at` — the fluent relative-path builder handlers use to address a
// sub-path of their own position (JS transactor.js PathChanges / path.js
// PathBuilder). `ctx.at.field("status").send("flash", args)` sends to the
// handler's path with a FieldStep("status") appended. Builder methods return a
// fresh PathChanges (immutable), so a base can be reused.

///|
pub struct PathChanges {
  ctx : &Ctx
  steps : Array[Step]
}

///|
/// A builder rooted at `ctx`'s dispatch path (JS `get at`). Usually reached
/// through `Ctx::at`, exposed for callers holding a `&Ctx` directly.
pub fn PathChanges::of(ctx : &Ctx) -> PathChanges {
  { ctx, steps: [] }
}

///|
fn PathChanges::add(self : PathChanges, step : Step) -> PathChanges {
  let steps = self.steps.copy()
  steps.push(step)
  { ctx: self.ctx, steps }
}

///|
/// Descend into field `name` (JS PathBuilder.field).
pub fn PathChanges::field(self : PathChanges, name : String) -> PathChanges {
  self.add(FieldStep(name))
}

///|
/// Descend into element `i` of sequence field `name` (JS PathBuilder.index).
pub fn PathChanges::index(
  self : PathChanges,
  name : String,
  i : Int,
) -> PathChanges {
  self.add(SeqStep(field=name, key=KInt(i)))
}

///|
/// Descend into keyed element `key` of map field `name` (JS PathBuilder.key).
pub fn PathChanges::key(
  self : PathChanges,
  name : String,
  key : String,
) -> PathChanges {
  self.add(SeqStep(field=name, key=KStr(key)))
}

///|
/// The absolute dispatch path this builder addresses: the ctx's path with the
/// accumulated steps appended (JS PathChanges.buildPath).
pub fn PathChanges::build_path(self : PathChanges) -> DispatchPath {
  self.ctx.path().concat(self.steps)
}

///|
/// Send `name` at the built path (JS PathChanges.send).
pub fn PathChanges::send(
  self : PathChanges,
  name : String,
  args : Array[Value],
) -> Unit {
  self.ctx.send_at_path(self.build_path(), name, args)
}

///|
/// Bubble `name` from the built path (JS PathChanges.bubble: skipSelf + bubbles).
pub fn PathChanges::bubble(
  self : PathChanges,
  name : String,
  args : Array[Value],
) -> Unit {
  self.ctx.bubble_at_path(self.build_path(), name, args)
}
