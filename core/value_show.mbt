// Source round-trip (JS per-class toString): every Val prints back as its
// original syntax. Implements the Show declare in spec.mbt.

///|
fn val_source(val : Val) -> String {
  match val {
    Const(lit~, ..) =>
      match lit {
        LStr(s) => escape_str_literal(s)
        LNull => "null"
        LBool(b) => if b { "true" } else { "false" }
        LNum(n) => num_source(n)
      }
    // JS StrTplVal has no toString of its own; reconstructing the `$'…'`
    // source is strictly more useful and keeps macro-attr round-trips sane.
    StrTpl(parts) => {
      let buf = StringBuilder::new()
      buf.write_string("$'")
      for part in parts {
        match part {
          Some(Const(lit=LStr(s), ..)) =>
            // Re-escape the raw text (the parse unescaped it once).
            for c in s {
              if c is ('\'' | '\\') {
                buf.write_char('\\')
              }
              buf.write_char(c)
            }
          Some(v) => {
            buf.write_char('{')
            buf.write_string(val_source(v))
            buf.write_char('}')
          }
          None => buf.write_string("{}")
        }
      }
      buf.write_char('\'')
      buf.to_string()
    }
    Predicate(pred~, args~) =>
      pred.name() + " " + args.map(a => val_source(a)).join(" ")
    Name(name) => name
    HandlerName(name~, ..) => name
    TypeName(name) => name
    Bind(name) => "@" + name
    BindMember(name~, prop~) => "@" + name + "." + prop
    Dyn(name) => "*" + name
    Field(name) => "." + name
    Method(name) => "$" + name
    SeqAccess(seq~, key~) => "." + seq + "[." + key + "]"
  }
}

///|
pub impl Show for Val with fn output(self, logger) {
  logger.write_string(val_source(self))
}
