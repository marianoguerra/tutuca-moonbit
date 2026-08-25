// Emitting MoonBit literals into generated source.
//
// Here rather than in each generator for the same reason `binding_name` is:
// three packages write MoonBit source (`viewgen`, `tscript/emit_mbt`, and the
// init-block emitter next door), all three need to spell a string and a Double
// the way MoonBit reads them back, and a copy per generator is a rule that can
// be true in one and false in another. It was: the init-block copy escaped `"`
// `\` and `\n` and not `\t` or `\r`, so a schema default carrying a tab emitted
// a literal tab into the module and the two generators disagreed about the same
// string. `statedef` is the leaf both importers already depend on, so this is
// the one place all three can reach.

///|
/// A double-quoted MoonBit string literal.
pub fn quote(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// A Double that reads back as the same Double. `Double::to_string` prints a
/// whole number with no fraction, which MoonBit would then read as an Int.
pub fn double_lit(d : Double) -> String {
  let s = d.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") || s.contains("N") {
    s
  } else {
    s + ".0"
  }
}
