///|
/// The frozen type section, in wap.
///
/// Read it as the answer to one question: what does a module have to declare so
/// that a reference it builds is the SAME TYPE as a reference a stranger's
/// module built? Everything else in `tgc` follows from this text lowering the
/// same way everywhere.
pub fn preamble_wap() -> String {
  let src =
    #|// tgc/2 — the canonical preamble. FROZEN. Every tgc module carries it.
    #|//
    #|// Wasm GC canonicalizes a recursion group structurally, so two modules that
    #|// declare these types receive the SAME runtime types: a reference built in
    #|// one is readable in the other with no conversion, no linker and no
    #|// registry.
    #|//
    #|// What is frozen is each GROUP, not the file. wap emits a recursion group
    #|// per strongly connected component rather than one group for the module, so
    #|// the only types that move together here are the four that genuinely refer
    #|// to each other — tg_get, tg_inst, tg_vt and tg_call. Everything else is a
    #|// group of one. That is the difference from tgc/1, where all twenty shared
    #|// a group and adding an arm re-typed every module that had ever been built:
    #|// adding a type now breaks nothing, and changing tg_list breaks tg_list.
    #|// tg_ext survives as the extension point for a VALUE nobody knows, which is
    #|// a smaller job than it used to have.
    #|
    #|module tgabi
    #|
    #|// UTF-8 text AND binary. `u8` rather than `i8`: the wasm storage type is i8
    #|// either way and the canonical type is the same, but a read of an unsigned
    #|// element zero-extends, which is what every byte in a UTF-8 string wants.
    #|pub type tg_bytes = [u8]
    #|
    #|// kind 0 is Null. `ref.null` is not null-the-value, it is ABSENCE: "no such
    #|// field" as against "the field is null".
    #|pub type tg_val = { kind :: i32 }
    #|pub type tg_vals = [tg_val?]
    #|pub type tg_entry = { key :: tg_bytes, value :: mut tg_val? }
    #|pub type tg_entries = [tg_entry?]
    #|
    #|// The two vtable slots, and the instance they reach through. These four are
    #|// the one cycle in the format, so they are the one recursion group.
    #|//
    #|// `get` is separate only because it runs once per `.name` per render;
    #|// everything else is one op-coded `call`, so the op space can grow without
    #|// the group changing.
    #|//
    #|// `state` is `eq?`: the owner casts it back to its own type, and anyone
    #|// else TRAPS. Opacity is the engine's, not a convention's.
    #|pub type tg_get = fn(tg_inst, tg_bytes) -> tg_val?
    #|pub type tg_call = fn(tg_inst, i32, tg_bytes, tg_vals, tg_val?) -> tg_val?
    #|pub type tg_vt = { get :: tg_get, call :: tg_call }
    #|pub type tg_inst = {
    #|  vt :: tg_vt,
    #|  desc :: tg_val,
    #|  state :: eq?,
    #|  id :: i64,
    #|}
    #|
    #|// A callable value's target. Not in the group above: nothing it mentions
    #|// mentions it back.
    #|pub type tg_fn = fn(tg_vals, eq?) -> tg_val?
    #|
    #|pub type tg_bool :: tg_val = { value :: i32 }
    #|pub type tg_num :: tg_val = { value :: f64 }
    #|pub type tg_int :: tg_val = { value :: i64 }
    #|pub type tg_str :: tg_val = { value :: tg_bytes }
    #|pub type tg_bin :: tg_val = { value :: tg_bytes }
    #|pub type tg_instant :: tg_val = { secs :: i64, nanos :: i32 }
    #|// Capacity plus length: a wasm-GC array is fixed-length, so a growable list
    #|// amortizes over a longer backing store.
    #|pub type tg_list :: tg_val = { items :: mut tg_vals, count :: mut i32 }
    #|// An entry array rather than a hash map: tutuca's maps are insertion
    #|// ordered and `@each` renders in that order.
    #|pub type tg_map :: tg_val = { entries :: mut tg_entries, count :: mut i32 }
    #|pub type tg_func :: tg_val = { call :: tg_fn, env :: eq? }
    #|pub type tg_comp :: tg_val = { value :: tg_inst }
    #|// The ONE extension point for a value nobody knows. A tag nobody reads is
    #|// survivable; a type nobody shares is a module nobody links.
    #|pub type tg_ext :: tg_val = { ext_kind :: i32, payload :: eq? }
  src
}

///|
/// The same types as WAT, from the compiler rather than from a second copy.
///
/// A hand-written module reads this; so does the message a host prints when a
/// module's types do not match. It is DERIVED — lowered and printed — because
/// the alternative is two spellings of a structural type, and two spellings are
/// two types the first time one of them is edited alone.
pub fn preamble_wat() -> String raise PreambleError {
  let checked = match @wap.check_string(preamble_wap(), fname="tgabi.wap") {
    Ok((checked, _)) => checked
    Err(d) =>
      raise PreambleBug(
        "the preamble did not check: \{d.wap.length()} wap, \{d.wax.length()} wax",
      )
  }
  let wat = checked.to_wat() catch {
    e => raise PreambleBug("the preamble did not print: \{e}")
  }
  type_section_of(wat)
}

///|
/// The type declarations of a printed module, and nothing else.
///
/// The preamble declares no functions, so the module wrapper is all that stands
/// between the printed text and the text a hand-written module wants to paste
/// above its body. Stripping it is a matter of dropping the first line and the
/// last and dedenting the rest — NOT of dropping every line that looks like a
/// close, which is what this did first and which silently ate the `)` that
/// closed a type spanning more than one line.
fn type_section_of(wat : String) -> String {
  let lines : Array[String] = []
  for line in wat.split("\n") {
    lines.push(line.to_owned())
  }
  while lines.length() > 0 && lines[lines.length() - 1].trim(chars=" ") == "" {
    lines.pop() |> ignore
  }
  guard lines.length() >= 2 && lines[0].trim(chars=" ").has_prefix("(module") else {
    return wat
  }
  let out = StringBuilder()
  for i in 1..<(lines.length() - 1) {
    let line = lines[i]
    out.write_string(
      if line.has_prefix("  ") {
        line[2:].to_owned()
      } else {
        line
      },
    )
    out.write_string("\n")
  }
  out.to_string()
}
