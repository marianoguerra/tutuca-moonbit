// Attribute parsing. AttrParser is a per-call allocation here; the
// [pAttrs, wrapperAttrs, textChild] tuple becomes AttrParseResult (spec.mbt).

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
  mut text_child : @tutuca.Expr?
  mut each_attr : WrapperAttr?
  mut if_attr : IfAttr?
  mut events : NodeEvents?
  mut bind_target : @tutuca.Expr?
  mut bind_source : String?
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
    bind_target: None,
    bind_source: None,
  }
}

///|
fn parse_attributes(
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
      // attribute authored through a dynamic binding.
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
      self.items.push(ConstA(name~, val=@tutuca.Expr::lit(lit)))
    }
  }
  let bind = if parse_all && self.bind_target is Some(_) {
    // `@bind` owns a host DOM property/event pair; a macro call has neither.
    // Macro arguments use `:name`, including an argument literally named
    // `bind`.
    self.px.issue(
      UnknownDirective(name="bind", value=self.bind_source.unwrap_or("")),
    )
    None
  } else {
    self.finish_bind()
  }
  {
    attrs: attrs_of_items(self.items),
    wrappers: self.wrappers,
    text_child: self.text_child,
    bind,
  }
}

///|
pub fn attrs_of_items(items : Array[AttrItem]) -> Attrs {
  let dynamic = items
    .iter()
    .any(item => {
      match item {
        // A macro-var-sourced constant stays constant.
        Plain(val~, ..) => !(val is ELit(..))
        RawHtml(_) | RawMarkdown(_) | SafeHtml(_) | SafeSvg(_) | If(_) => true
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
        if val is ELit(lit~, ..) {
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
    self.px.pval(value, @tscript.parse_macro_attr)
  } else {
    self.px.pval(value, @tscript.parse_text)
  }
  match val {
    Some(v) =>
      // A macro-var-sourced constant stays constant:
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
  val : @tutuca.Expr?,
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
  parser : (String, @tscript.ParseCtx) -> @tutuca.Expr?,
) -> @tutuca.Expr? {
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
      let val = self.directive_value(directive_name, s, @tscript.parse_text)
      // Pushed even when the value failed to parse (kept with
      // the null-const sentinel).
      self.items.push(RawHtml(val~))
    }
    "setinnermd" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_text)
      // Same "push even on a failed parse" rule as the raw-HTML directive
      // above, so the two behave alike where they can.
      self.items.push(RawMarkdown(val~))
    }
    "setinnerhtml" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_text)
      self.items.push(SafeHtml(val~))
    }
    "setinnersvg" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_text)
      self.items.push(SafeSvg(val~))
    }
    "push-view" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_text)
      self.push_wrapper(PushView, s, val) |> ignore
    }
    "text" =>
      self.text_child = self.directive_value(
        directive_name, s, @tscript.parse_text,
      )
    "show" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_bool)
      self.push_wrapper(Show, s, val) |> ignore
    }
    "hide" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_bool)
      self.push_wrapper(Hide, s, val) |> ignore
    }
    "each" => {
      let val = self.directive_value(directive_name, s, @tscript.parse_sequence)
      self.each_attr = Some(self.push_wrapper(Each, s, val))
    }
    "enrich-with" => {
      let val = self.directive_value(
        directive_name, s, @tscript.parse_alter_handler,
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
    "bind" => {
      self.bind_source = Some(s)
      self.bind_target = self.directive_value(
        directive_name, s, @tscript.parse_text,
      )
    }
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
/// Finish the parser half of `@bind`: mirror the state value into the DOM and
/// register the setter event. Its coercion remains deliberately unset until
/// viewgen has the component schema in hand.
fn AttrParser::finish_bind(self : AttrParser) -> BindData? {
  guard self.bind_target is Some(target) else { return None }
  let tag = self.px.current_tag.unwrap_or("").to_lower()
  let checkbox = tag == "input" && self.static_attr("type") == Some("checkbox")
  let property = if checkbox { "checked" } else { "value" }
  let event_name = if tag == "select" { "change" } else { "input" }
  self.items.push(Plain(name=property, val=target))
  let events = self.ensure_events()
  let field = target.as_field().unwrap_or("invalidBindTarget")
  let event : NodeEvent = {
    name: event_name,
    handler: {
      handler: @tutuca.Expr::lit(LNull),
      args: [],
      action: Some(
        PropertySet(name=field, value=@tutuca.Expr::event_path(["value"])),
      ),
    },
    modifiers: [],
    binding: Some(BindPending),
  }
  events.handlers.push(event)
  Some({ target, property, event, })
}

///|
fn AttrParser::static_attr(self : AttrParser, wanted : String) -> String? {
  for item in self.items {
    match item {
      ConstA(name~, val=ELit(lit=LStr(value), ..)) if name == wanted =>
        return Some(value.to_lower())
      _ => ()
    }
  }
  None
}

///|
fn AttrParser::ensure_events(self : AttrParser) -> NodeEvents {
  match self.events {
    Some(ev) => ev
    None => {
      let ev = self.px.register_events()
      self.events = Some(ev)
      self.items.push(
        ConstA(name="data-eid", val=@tutuca.Expr::lit(LNum(ev.id.to_double()))),
      )
      ev
    }
  }
}

///|
fn AttrParser::parse_when(self : AttrParser, s : String) -> Unit {
  if self.each_attr is Some(ea) {
    ea.when_val = self.directive_value("when", s, @tscript.parse_alter_handler)
  }
}

///|
fn AttrParser::parse_loop_with(self : AttrParser, s : String) -> Unit {
  if self.each_attr is Some(ea) {
    ea.loop_with_val = self.directive_value(
      "loop-with", s, @tscript.parse_alter_handler,
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
  match self.px.pval(value, @tscript.parse_bool) {
    Some(cond_val) => {
      let if_attr = IfAttr::{ name, cond_val, then_val: None, else_val: None, }
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
    ia.then_val = self.branch_val("then", s)
  }
}

///|
fn AttrParser::parse_else(self : AttrParser, s : String) -> Unit {
  if self.if_attr is Some(ia) {
    ia.else_val = self.branch_val("else", s)
  }
}

///|
/// A branch value, or None with the reason said out loud.
///
/// An UNSET branch is legal and means "leave the attribute alone"; a branch
/// that was written and did not parse must NOT become the same None —
/// `@then="btn btn-primary"` (a class list, missing its quotes) would render
/// as an element with no class and nothing to read about why. The conditional
/// itself already reports a value it cannot parse; this is the other half.
fn AttrParser::branch_val(
  self : AttrParser,
  branch : String,
  s : String,
) -> @tutuca.Expr? {
  match self.px.pval(s, @tscript.parse_text) {
    Some(v) => Some(v)
    None => {
      self.px.issue(BadValue(role=Directive(name=branch), value=s))
      None
    }
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
  let handler = @tscript.parse_input_handler(value, self.px.value_ctx())
  self.px.drain_value_issues()
  if handler is Some(h) {
    let events = self.ensure_events()
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
fn Attrs::set_data_attr(self : Attrs, key : String, val : @tutuca.Lit) -> Unit {
  match self {
    ConstAttrs(m) => m[key] = val
    DynAttrs(items) => items.push(ConstA(name=key, val=@tutuca.Expr::lit(val)))
  }
}

///|
/// The plain string a constant scalar interpolates to (`${val}` style):
/// numbers/bools/null via the value layer's source rendering, strings as-is.
fn lit_plain_string(lit : @tutuca.Lit) -> String {
  match lit {
    LStr(s) => s
    _ => "\{@tutuca.Expr::lit(lit)}"
  }
}

///|
fn Attrs::to_macro_vars(self : Attrs) -> Map[String, String] {
  let r : Map[String, String] = Map([])
  match self {
    // JS: new ConstVal(`${value}`).toString() — the evaluated scalar is
    // stringified first, so the result is always a quoted string literal.
    ConstAttrs(m) =>
      for name, lit in m {
        r[name] = "\{@tutuca.Expr::lit(LStr(lit_plain_string(lit)))}"
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => r[name] = "\{val}"
          // If has no .val and RawHtml's null sentinel would stringify
          // oddly; neither occurs in real macro calls — skipped here.
          RawHtml(_) | RawMarkdown(_) | SafeHtml(_) | SafeSvg(_) | If(_) => ()
        }
      }
  }
  r
}
