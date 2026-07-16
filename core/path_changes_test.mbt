// ctx.at (PathChanges) builder: field/index/key accumulate steps and
// send/bubble dispatch at the ctx path + accumulated steps.

///|
priv struct RecordingCtx {
  base : @core.DispatchPath
  sends : Array[(Array[@core.Step], String, Bool)]
}

///|
impl @core.Ctx for RecordingCtx with fn path(self) {
  self.base
}

///|
impl @core.Ctx for RecordingCtx with fn send_at_path(self, path, name, _args) {
  self.sends.push((path.to_transaction_path().steps, name, false))
}

///|
impl @core.Ctx for RecordingCtx with fn bubble_at_path(self, path, name, _args) {
  self.sends.push((path.to_transaction_path().steps, name, true))
}

///|
test "ctx.at builds a relative path and sends/bubbles at it" {
  let ctx = RecordingCtx::{
    base: @core.DispatchPath::of_steps([FieldStep("root")]),
    sends: [],
  }
  // field / index / key chain
  ctx.at().field("status").send("flash", [Str("hi")])
  ctx.at().index("items", 3).send("init", [])
  ctx.at().key("byId", "x7").bubble("ping", [])
  // build_path exposes the absolute path without dispatching
  let p = ctx.at().field("a").index("b", 1).build_path()
  assert_eq(ctx.sends.length(), 3)
  // send #1: base(root) + field(status)
  assert_true(
    ctx.sends[0].0 == [FieldStep("root"), FieldStep("status")] &&
    ctx.sends[0].1 == "flash" &&
    ctx.sends[0].2 == false,
  )
  // send #2: base + index -> SeqStep with an int key
  assert_true(
    ctx.sends[1].0 == [FieldStep("root"), SeqStep(field="items", key=KInt(3))],
  )
  // send #3: bubble, base + key -> SeqStep with a string key
  assert_true(
    ctx.sends[2].0 == [FieldStep("root"), SeqStep(field="byId", key=KStr("x7"))] &&
    ctx.sends[2].2 == true,
  )
  assert_true(
    p.to_transaction_path().steps ==
    [FieldStep("root"), FieldStep("a"), SeqStep(field="b", key=KInt(1))],
  )
}
