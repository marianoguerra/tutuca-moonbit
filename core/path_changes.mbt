// `ctx.at` — the fluent relative-path builder handlers use to address a
// sub-path of their own position. `ctx.at.field("status").send("flash", args)` sends to the
// handler's path with a FieldStep("status") appended. Builder methods return a
// fresh PathChanges (immutable), so a base can be reused.

///|
pub struct PathChanges {
  ctx : &Ctx
  steps : Array[Step]
}

///|
/// A builder rooted at `ctx`'s dispatch path. Usually reached
/// through `Ctx::at`, exposed for callers holding a `&Ctx` directly.
fn PathChanges::of(ctx : &Ctx) -> PathChanges {
  { ctx, steps: [], }
}

///|
/// Each builder method spells its step through the absolute `Path` builder, so
/// the relative and absolute forms cannot disagree about what a step is.
fn PathChanges::of_path(self : PathChanges, p : Path) -> PathChanges {
  { ctx: self.ctx, steps: p.steps, }
}

///|
fn PathChanges::as_path(self : PathChanges) -> Path {
  { steps: self.steps, }
}

///|
/// Descend into field `name`.
pub fn PathChanges::field(self : PathChanges, name : String) -> PathChanges {
  self.of_path(self.as_path().field(name))
}

///|
/// Descend into element `i` of sequence field `name`.
pub fn PathChanges::index(
  self : PathChanges,
  name : String,
  i : Int,
) -> PathChanges {
  self.of_path(self.as_path().index(name, i))
}

///|
/// Descend into keyed element `key` of map field `name`.
pub fn PathChanges::key(
  self : PathChanges,
  name : String,
  key : String,
) -> PathChanges {
  self.of_path(self.as_path().key(name, key))
}

///|
/// The absolute dispatch path this builder addresses: the ctx's path with the
/// accumulated steps appended.
pub fn PathChanges::build_path(self : PathChanges) -> DispatchPath {
  self.ctx.path().concat(self.steps)
}

///|
/// Send `name` at the built path.
pub fn PathChanges::send(
  self : PathChanges,
  name : String,
  args : Array[Value],
) -> Unit {
  self.ctx.send_at_path(self.build_path(), name, args)
}

///|
/// Dispatch an intent from the built path — the routed twin of `send`. One
/// method, and the route says which scope answers.
pub fn PathChanges::intent(
  self : PathChanges,
  name : String,
  args : Array[Value],
  opts? : IntentOpts = IntentOpts::new(),
) -> Unit {
  self.ctx.intent_at_path(self.build_path(), name, args, opts)
}

///|
/// Write `name` at the built path.
///
/// The twin of `send`, and the distinction between them is the one the
/// generated-mutator fallback used to blur: a dispatch ASKS a component to
/// decide something, and a write says what a member is now. A view spells the
/// second `.field = v`; this is the same door for a caller holding a ctx.
pub fn PathChanges::set(self : PathChanges, name : String, v : Value) -> Unit {
  self.ctx.set_member_at_path(self.build_path(), name, v)
}
