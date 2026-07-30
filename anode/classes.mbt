// Class collection for margaui-style scanners (spec.mbt
// ANode::collect_classes). Mirrors JS ParseCtxClassSetCollector semantics:
// only literal class fragments are collected — a NameVal/Field in `:class`
// contributes nothing.

///|
/// Split on any whitespace run (JS `s.split(/\s+/)`).
fn add_classes(s : String, into : Set[String]) -> Unit {
  let buf = StringBuilder::new()
  fn flush() {
    let t = buf.to_string()
    if t != "" {
      into.add(t)
    }
    buf.reset()
  }

  for c in s {
    if is_tpl_space(c) {
      flush()
    } else {
      buf.write_char(c)
    }
  }
  flush()
}

///|
/// Literal fragments of a class-position value: Const strings whole, and the
/// Const parts of a template string (JS _maybeAddVal/_maybeAddStrTpl).
fn add_val_classes(val : @tutuca.Val, into : Set[String]) -> Unit {
  match val {
    Const(lit=LStr(s), ..) => add_classes(s, into)
    StrTpl(parts) =>
      for part in parts {
        if part is Some(Const(lit=LStr(s), ..)) {
          add_classes(s, into)
        }
      }
    _ => ()
  }
}

///|
fn add_attr_classes(attrs : Attrs, into : Set[String]) -> Unit {
  match attrs {
    ConstAttrs(m) => if m.get("class") is Some(LStr(s)) { add_classes(s, into) }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name="class", val~) | ConstA(name="class", val~) =>
            add_val_classes(val, into)
          If(ia) =>
            if ia.name == "class" {
              match ia.then_val {
                Some(v) => add_val_classes(v, into)
                None => ()
              }
              match ia.else_val {
                Some(v) => add_val_classes(v, into)
                None => ()
              }
            }
          _ => ()
        }
      }
  }
}

///|
pub fn ANode::collect_classes(self : ANode, into : Set[String]) -> Unit {
  if self is Dom(d) {
    add_attr_classes(d.attrs, into)
  }
  self.for_each_child(child => child.collect_classes(into))
}
