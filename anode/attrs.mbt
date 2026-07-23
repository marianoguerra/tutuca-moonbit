// Attribute parsing (src/attribute.js). The JS module-level AttrParser
// singleton becomes a per-call allocation; the [pAttrs, wrapperAttrs,
// textChild] tuple becomes AttrParseResult (spec.mbt).

///|
let boolean_attrs : Set[String] = Set::from_array([
  "itemscope", "allowfullscreen", "formnovalidate", "ismap", "nomodule", "novalidate",
  "readonly", "async", "autofocus", "autoplay", "controls", "default", "defer", "disabled",
  "hidden", "inert", "loop", "open", "required", "reversed", "scoped", "seamless",
  "checked", "muted", "multiple", "selected",
])

///|
priv struct AttrParser {
  px : ParseContext
  items : Array[AttrItem]
  wrappers : Array[WrapperAttr]
  mut text_child : @tutuca.Val?
  mut each_attr : WrapperAttr?
  mut if_attr : IfAttr?
  mut events : NodeEvents?
}

///|
fn AttrParser::new(px : ParseContext) -> AttrParser {
  {
    px,
    items: [],
    wrappers: [],
    text_child: None,
    each_attr: None,
    if_attr: None,
    events: None,
  }
}

///|
pub fn parse_attributes(
  attrs : Array[(String, String)],
  px : ParseContext,
  parse_all? : Bool = false,
) -> AttrParseResult {
  AttrParser::new(px).parse(attrs, parse_all~)
}

///|
fn AttrParser::parse(
  self : AttrParser,
  attrs : Array[(String, String)],
  parse_all? : Bool = false,
) -> AttrParseResult {
  for pair in attrs {
    let (name, value) = pair
    if name is [':', .. rest] {
      // Attribute names arrive lowercased; restore the one camelCase SVG
      // attribute authored through a dynamic binding (JS special case).
      let attr_name = if name == ":viewbox" {
        "viewBox"
      } else {
        rest.to_owned()
      }
      self.parse_attr(attr_name, value, parse_all~)
    } else if name is ['@', .. rest] {
      self.parse_directive(value, rest.to_owned())
    } else {
      let lit : @tutuca.Lit = if value == "" && boolean_attrs.contains(name) {
        LBool(true)
      } else {
        LStr(value)
      }
      self.items.push(ConstA(name~, val=Const(lit~, from_macro=false)))
    }
  }
  {
    attrs: attrs_of_items(self.items),
    wrappers: self.wrappers,
    text_child: self.text_child,
  }
}

///|
pub fn attrs_of_items(items : Array[AttrItem]) -> Attrs {
  let dynamic = items
    .iter()
    .any(item => {
      match item {
        // A macro-var-sourced constant stays constant (JS comment).
        Plain(val~, ..) => !(val is Const(..))
        RawHtml(_) | If(_) => true
        ConstA(_) => false
      }
    })
  if dynamic {
    DynAttrs(items)
  } else {
    const_attrs_from_items(items)
  }
}

///|
/// Collapse an all-constant item list into the evaluated map (JS
/// ConstAttrs.fromAttrs; every val is Const in a list nothing made dynamic).
fn const_attrs_from_items(items : Array[AttrItem]) -> Attrs {
  let m : Map[String, @tutuca.Lit] = Map([])
  for item in items {
    match item {
      ConstA(name~, val~) | Plain(name~, val~) =>
        if val is Const(lit~, ..) {
          m[name] = lit
        }
      _ => ()
    }
  }
  ConstAttrs(m)
}

///|
fn AttrParser::parse_attr(
  self : AttrParser,
  name : String,
  value : String,
  parse_all? : Bool = false,
) -> Unit {
  let val = if parse_all {
    self.px.pval(value, @tutuca.parse_macro_attr)
  } else {
    self.px.pval(value, @tutuca.parse_text)
  }
  match val {
    Some(v) =>
      // A macro-var-sourced constant stays constant (JS comment):
      // attrs_of_items keeps a Plain(Const) in the constant collapse.
      self.items.push(Plain(name~, val=v))
    None => self.px.issue(BadValue(role=Attr(name~), value~))
  }
}

///|
fn AttrParser::push_wrapper(
  self : AttrParser,
  kind : WrapperKind,
  raw : String,
  val : @tutuca.Val?,
) -> WrapperAttr {
  let node = WrapperAttr::{
    kind,
    raw,
    val,
    enrich_with_val: None,
    when_val: None,
    loop_with_val: None,
  }
  self.wrappers.push(node)
  node
}

///|
fn AttrParser::directive_value(
  self : AttrParser,
  directive_name : String,
  s : String,
  parser : (String, @tutuca.ParseCtx) -> @tutuca.Val?,
) -> @tutuca.Val? {
  let val = self.px.pval(s, parser)
  if val is None {
    self.px.issue(BadValue(role=Directive(name=directive_name), value=s))
  }
  val
}

///|
fn AttrParser::parse_directive(
  self : AttrParser,
  s : String,
  directive_name : String,
) -> Unit {
  match directive_name {
    "dangerouslysetinnerhtml" => {
      let val = self.directive_value(directive_name, s, @tutuca.parse_text)
      // Pushed even when the value failed to parse (JS keeps the attr with
      // the null-const sentinel).
      self.items.push(RawHtml(val~))
    }
    "push-view" => {
      let val = self.directive_value(directive_name, s, @tutuca.parse_text)
      self.push_wrapper(PushView, s, val) |> ignore
    }
    "text" =>
      self.text_child = self.directive_value(
        directive_name, s, @tutuca.parse_text,
      )
    "show" => {
      let val = self.directive_value(directive_name, s, @tutuca.parse_bool)
      self.push_wrapper(Show, s, val) |> ignore
    }
    "hide" => {
      let val = self.directive_value(directive_name, s, @tutuca.parse_bool)
      self.push_wrapper(Hide, s, val) |> ignore
    }
    "each" => {
      let val = self.directive_value(directive_name, s, @tutuca.parse_sequence)
      self.each_attr = Some(self.push_wrapper(Each, s, val))
    }
    "enrich-with" => {
      let val = self.directive_value(
        directive_name, s, @tutuca.parse_alter_handler,
      )
      match self.each_attr {
        Some(ea) => ea.enrich_with_val = val
        // A loop-less @enrich-with wraps the node in a scope frame.
        None => self.push_wrapper(Scope, s, val) |> ignore
      }
    }
    "when" => self.parse_when(s)
    "loop-with" => self.parse_loop_with(s)
    "then" => self.parse_then(s)
    "else" => self.parse_else(s)
    _ =>
      if directive_name is [.. "on.", ..] {
        self.parse_event(directive_name, s)
      } else if directive_name is [.. "if.", ..] {
        self.parse_if(directive_name, s)
      } else if directive_name is [.. "then.", ..] {
        self.parse_then(s)
      } else if directive_name is [.. "else.", ..] {
        self.parse_else(s)
      } else {
        self.px.issue(UnknownDirective(name=directive_name, value=s))
      }
  }
}

///|
fn AttrParser::parse_when(self : AttrParser, s : String) -> Unit {
  if self.each_attr is Some(ea) {
    ea.when_val = self.directive_value("when", s, @tutuca.parse_alter_handler)
  }
}

///|
fn AttrParser::parse_loop_with(self : AttrParser, s : String) -> Unit {
  if self.each_attr is Some(ea) {
    ea.loop_with_val = self.directive_value(
      "loop-with", s, @tutuca.parse_alter_handler,
    )
  }
}

///|
fn AttrParser::parse_if(
  self : AttrParser,
  directive_name : String,
  value : String,
) -> Unit {
  let name = directive_name[3:].to_owned()
  match self.px.pval(value, @tutuca.parse_bool) {
    Some(cond_val) => {
      let if_attr = IfAttr::{ name, cond_val, then_val: None, else_val: None }
      self.if_attr = Some(if_attr)
      self.items.push(If(if_attr))
    }
    None => self.px.issue(BadValue(role=IfDirective(name~), value~))
  }
}

///|
fn AttrParser::parse_then(self : AttrParser, s : String) -> Unit {
  // Applies to the most recent @if.<name>; silently ignored without one (JS).
  if self.if_attr is Some(ia) {
    ia.then_val = self.px.pval(s, @tutuca.parse_text)
  }
}

///|
fn AttrParser::parse_else(self : AttrParser, s : String) -> Unit {
  if self.if_attr is Some(ia) {
    ia.else_val = self.px.pval(s, @tutuca.parse_text)
  }
}

///|
fn AttrParser::parse_event(
  self : AttrParser,
  directive_name : String,
  value : String,
) -> Unit {
  let parts = directive_name[3:]
    .to_owned()
    .split("+")
    .map(v => v.to_owned())
    .collect()
  let event_name = parts[0]
  let modifiers = parts[1:].to_owned()
  let handler = @tutuca.parse_input_handler(value, self.px.value_ctx())
  self.px.drain_value_issues()
  if handler is Some(h) {
    let events = match self.events {
      Some(ev) => ev
      None => {
        let ev = self.px.register_events()
        self.events = Some(ev)
        self.items.push(
          ConstA(
            name="data-eid",
            val=Const(lit=LNum(ev.id.to_double()), from_macro=false),
          ),
        )
        ev
      }
    }
    events.add(event_name, h, modifiers)
  }
}

// ---------------------------------------------------------------------------
// Attrs methods

///|
pub fn Attrs::is_constant(self : Attrs) -> Bool {
  self is ConstAttrs(_)
}

///|
pub fn Attrs::set_data_attr(
  self : Attrs,
  key : String,
  val : @tutuca.Lit,
) -> Unit {
  match self {
    ConstAttrs(m) => m[key] = val
    DynAttrs(items) =>
      items.push(ConstA(name=key, val=Const(lit=val, from_macro=false)))
  }
}

///|
/// The plain string a constant scalar interpolates to in JS (`${val}`):
/// numbers/bools/null via the value layer's source rendering, strings as-is.
fn lit_plain_string(lit : @tutuca.Lit) -> String {
  match lit {
    LStr(s) => s
    _ => "\{@tutuca.Val::Const(lit~, from_macro=false)}"
  }
}

///|
pub fn Attrs::to_macro_vars(self : Attrs) -> Map[String, String] {
  let r : Map[String, String] = Map([])
  match self {
    // JS: new ConstVal(`${value}`).toString() — the evaluated scalar is
    // stringified first, so the result is always a quoted string literal.
    ConstAttrs(m) =>
      for name, lit in m {
        r[name] = "\{@tutuca.Val::Const(lit=LStr(lit_plain_string(lit)), from_macro=false)}"
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => r[name] = "\{val}"
          // JS would crash on If (no .val) and stringify RawHtml's null
          // sentinel; neither occurs in real macro calls — skipped here.
          RawHtml(_) | If(_) => ()
        }
      }
  }
  r
}
