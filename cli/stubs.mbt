///|
/// Shared "not implemented" emitter for commands whose MoonBit port is
/// blocked on missing layers. The blocker list comes from the command's
/// registry entry (see the TODO(port) comments in registry.mbt). Exit code 1
/// like any other usage-level failure; the command-specific exit codes
/// (2 lint / 3 render / 4 test) stay reserved until the commands are real.
pub fn stub(name : String, missing : Array[String]) -> Emit {
  let buf = StringBuilder::new()
  buf.write_string("tutuca \{name}: not implemented in the MoonBit port yet\n")
  buf.write_string("missing:\n")
  for m in missing {
    buf.write_string("  - \{m}\n")
  }
  { out: "", err: buf.to_string(), exit_code: 1 }
}
