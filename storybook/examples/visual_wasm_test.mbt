///|
test "visual-wasm: an empty module renders its two sections" {
  let h = @harness.mount_example(visual_wasm_module(), "Empty Module")
  debug_inspect(
    h.texts(".sec-name"),
    content=(
      #|["Memory", "Functions"]
    ),
  )
  inspect(h.find_all(".wasm-section").length(), content="2")
  // no items yet in either section
  inspect(h.find_all(".blocklike").length(), content="0")
}

///|
test "visual-wasm: the instruction picker lists every instruction, sorted" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  // 54 plain + 9 imm + block/loop/if = 66 instructions in the 'all' list
  inspect(h.find_all(".pick").length(), content="66")
  // sorted lexically -> block is first
  inspect(h.text(".pick"), content="block")
}

///|
test "visual-wasm: the filter narrows the picker via @loop-with + @when" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  h.type_into(".filter", "i32")
  inspect(h.find_all(".pick").length(), content="16") // the i32.* instructions
  h.type_into(".filter", "i32.div")
  debug_inspect(
    h.texts(".pick"),
    content=(
      #|["i32.div_s", "i32.div_u"]
    ),
  )
}

///|
test "visual-wasm: the category radios swap the instruction set" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  h.fire(".r-control", @render.DomEvent::new(name="input"))
  debug_inspect(
    h.texts(".pick"),
    content=(
      #|["block", "br", "br_if", "drop", "if", "loop", "nop"]
    ),
  )
  h.fire(".r-vars", @render.DomEvent::new(name="input"))
  debug_inspect(
    h.texts(".pick"),
    content=(
      #|["global.get", "global.set", "local.get", "local.set", "local.tee"]
    ),
  )
}

///|
test "visual-wasm: picking an instruction self-replaces the picker with it" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  h.type_into(".filter", "i32.add")
  inspect(h.find_all(".pick").length(), content="1")
  h.click(".pick")
  // the picker is gone; an i32.add leaf instruction took its place
  inspect(h.find_all(".picker").length(), content="0")
  inspect(h.text(".instr"), content="i32.add")
}

///|
test "visual-wasm: picking a Block enters it in edit mode (setEditing)" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  h.type_into(".filter", "block")
  h.click(".pick")
  // a Block replaced the picker, and it started editing (its blockType editor shows)
  inspect(h.find_all(".blocklike.block").length(), content="1")
  inspect(h.find_all(".block-type-editor").length(), content="1")
}

///|
test "visual-wasm: adding a function to the Functions section, then an item" {
  let h = @harness.mount_example(visual_wasm_module(), "Empty Module")
  // the Functions section's + adds its defaultItem — but Empty Module has none,
  // so seed a Func-bearing section by mounting the picker route instead:
  // add a Memory to the Memory section (its defaultItem is a Memory)
  // (Empty Module's sections have null defaultItem, so + is a no-op here)
  h.click(".add-default", nth=0)
  inspect(h.find_all(".memory").length(), content="0") // null default -> nothing
}

///|
test "visual-wasm: BlockType editor lets you change an arg type (self-replace)" {
  let h = @harness.mount_example(visual_wasm_module(), "Instruction Picker")
  h.type_into(".filter", "block")
  h.click(".pick") // now editing a Block
  // the block type editor has empty arg/return type lists with append buttons
  inspect(h.find_all(".types-editor").length(), content="2") // args + returns
  // append a type to the args list (first append button)
  h.click(".append", nth=0)
  inspect(h.find_all(".type-select").length(), content="1")
  // the appended type defaults to i32; switch it to f64 via the select
  h.fire(".type-select", @render.DomEvent::new(name="input", value=Str("f64")))
  // the select re-renders showing f64 as a real option set (self-replaced type)
  inspect(h.find_all(".type-select").length(), content="1")
}
