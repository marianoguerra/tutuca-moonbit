///|
/// The reader's own shapes, in scope here the way they were when `to_expr`
/// lived in this package.
using @sh {type Ex}

///|
using @sh {type ExError}

///|
using @sh {type Arg}

///|
using @sh {type ExCtx}

// The `view:` section, read straight into `@anode.ANode`.
//
// At-notation is already a tree of elements, attributes and content. The
// printer path turned that tree into HTML text and had the HTML parser turn it
// back — two grammars and an escaping layer for a translation that is a fold.
// This is the fold.
//
// WHITESPACE IS WHAT THE FILE SAYS. Written `@p{a @b{c} d}`, a paragraph has
// a text node holding `a` and a trailing space, then an element, then a text
// node holding a leading space and `d` — because that is what was written.
// Nothing is trimmed, nothing is condensed, and there is no block/inline table
// (`anode/whitespace.mbt`) consulted: that table exists to undo the whitespace
// an HTML tokenizer manufactures from source layout, and at-notation
// manufactures none. Shrubbery already strips a multi-line body's indentation
// and keeps its newlines, so the text nodes here are the author's own.
//
// The consequence to know: a body written across lines has `"\n"` text nodes
// between its children, where the printer path had them condensed away. Between
// block elements that renders identically; between INLINE elements it renders
// what the author wrote, which is the case the condensing table used to get
// wrong in the other direction.

///|
/// A macro, held as the shrubbery tree it was written as.
///
/// `@anode.Macro` holds SOURCE, and `Macro::expand` re-parses that source once
/// per call site with the caller's arguments installed as `macro_vars` in the
/// value parser — so a macro's body is parsed as many times as it is used, and
/// its parameters are substituted by a parser rather than by the expander.
///
/// Here the body is the block it was read from and a parameter is an `Ex`.
/// Expansion is `subst_ex`: a substitution over the expression tree, before
/// anything becomes an `@tutuca.Expr`. Nothing re-parses, and a macro argument
/// can be any expression rather than anything that survives being printed and
/// read back.
pub(all) struct MacroDef {
  name : String
  params : Array[String]
  defaults : Map[String, Ex]
  body : Array[@ast.Node]
}

///|
/// The state one file's views are built with: the node ids handed out, the
/// event table they index, and the macros the file declares.
pub struct ViewBuilder {
  mut next_id : Int
  /// The namespace elements are being built in.
  ///
  /// An element inside `<svg>` is in the SVG namespace, and the HTML parser
  /// says so on every descendant rather than only on the root — `DomData.ns`
  /// is what `to_dom` reads to call `createElementNS`. At-notation has no
  /// namespace syntax, so the enclosing `@svg` is what decides, exactly as the
  /// tokenizer's insertion mode does.
  mut ns : @anode.Ns?
  handlers : Array[Array[@anode.NodeEvent]]
  macros : Map[String, MacroDef]
  /// Macro names currently being expanded. A macro that reaches itself is
  /// refused rather than followed, which is `RecursiveMacro` on the old path.
  expanding : Array[String]
}

///|
pub fn ViewBuilder::new(
  macros? : Map[String, MacroDef] = Map([]),
) -> ViewBuilder {
  { next_id: 0, ns: None, handlers: [], macros, expanding: [], }
}

///|
/// The next registration id. Ids only have to be unique and to match what the
/// tree carries — `ParseContext::from_ir` recovers the node array from the tree
/// by reading them back — so a counter is the whole of it.
fn ViewBuilder::alloc(self : ViewBuilder) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  id
}

///|
/// Register one element's handlers, answering the `data-eid` it must carry.
///
/// The id IS the position in the table (`@anode.events_of`), so registering and
/// numbering cannot disagree.
fn ViewBuilder::register(
  self : ViewBuilder,
  events : Array[@anode.NodeEvent],
) -> Int {
  self.handlers.push(events)
  self.handlers.length() - 1
}

///|
/// The event table this builder handed out, in registration order.
///
/// A view's handlers are not in its tree — an element points at them through
/// `data-eid` — so anything comparing two trees needs the table to resolve that
/// index against.
pub fn ViewBuilder::events(self : ViewBuilder) -> Array[@anode.NodeEvents] {
  @anode.events_of(self.handlers)
}

///|
/// Every `macro` a view section declares, as trees.
pub fn macros_of(
  decls : Array[@tutufile.Decl],
) -> Map[String, MacroDef] raise ExError {
  let out : Map[String, MacroDef] = Map([])
  for decl in decls {
    guard decl.kind is Macro else { continue }
    let m = @sh.read_member(decl.node)
    let params = []
    for p in m.params {
      params.push(p.name)
    }
    // A parameter's initialiser is its default, written where the parameter is
    // rather than in a table beside it.
    let defaults : Map[String, Ex] = Map([])
    guard decl.node.it is Group(parts) else { continue }
    for t in parts {
      if t.it is Parens(gs) {
        for g in gs {
          for a in @sh.read_args([g]) {
            if a is AKw(name, value) {
              defaults[name] = value
            }
          }
        }
        break
      }
    }
    out[decl.name] = {
      name: decl.name,
      params,
      defaults,
      body: @sh.body_groups(decl),
    }
  }
  out
}

///|
/// One view, as the tree the renderer indexes plus the event table it
/// addresses.
///
/// `@anode.View::from_ir` is the seam the ahead-of-time generator already uses,
/// which is the point: a view read this way and a view generated by `tutuca
/// gen` arrive at the renderer through the same door, so nothing downstream can
/// tell which one it got.
pub fn ViewBuilder::view(
  self : ViewBuilder,
  decl : @tutufile.Decl,
  style? : String = "",
) -> @anode.View raise ExError {
  let childs = []
  let css = StringBuilder()
  for g in @sh.body_groups(decl) {
    // A `@style{…}` written inside a view is the VIEW's style, not a node in
    // it. The section-level reader knows that about a style block at the top of
    // `view:`; one inside a view reaches here as an ordinary group.
    if style_body(g) is Some(text) {
      css.write_string(text)
      continue
    }
    for n in self.content(g, ExCtx::value()) {
      childs.push(n)
    }
  }
  let style = if css.to_string() == "" { style } else { css.to_string() }
  // A view with no content is the comment `ANode::parse` answers one with, so
  // that a view declared empty and a `<template>` left empty are one tree.
  let root = if childs.is_empty() {
    @anode.comment("Empty View in ANode.parse")
  } else if childs.length() == 1 {
    childs[0]
  } else {
    @anode.frag(childs)
  }
  @anode.View::from_ir(view_name(decl.name), root, self.handlers, style~)
}

///|
/// The CSS a `@style{…}` group holds, or `None` when the group is not one.
///
/// The body is one string literal, which is how a style block has to be
/// written: at-notation owns `@`, `{` and `}`, and CSS uses all three.
fn style_body(group : @ast.Node) -> String? {
  guard group.it is Group(parts) && parts.length() >= 1 else { return None }
  guard parts[0].it is Id("style") else { return None }
  let out = StringBuilder()
  for p in parts[1:] {
    guard p.it is Parens(gs) else { continue }
    for g in gs {
      guard g.it is Group(inner) && inner.length() == 1 else { continue }
      match inner[0].it {
        Lit(Str(t)) => out.write_string(t)
        Brackets(items) =>
          for item in items {
            if item.it is Group(one) &&
              one.length() == 1 &&
              one[0].it is Lit(Str(t)) {
              out.write_string(t)
            }
          }
        _ => ()
      }
    }
  }
  Some(out.to_string())
}

///|
/// Adjacent text nodes joined into one.
///
/// A body that contains an at-form escape comes back as SEVERAL content pieces:
/// `@p{a@"@"b}` is the three strings `"a"`, `"@"`, `"b"`, not one `"a@b"`. The
/// DOM has no such distinction — adjacent text is one node — and a tree parsed
/// from HTML has one node there, so a reader that kept the pieces would answer
/// a different tree for the same page.
///
/// The converter avoids the split by writing a text run that holds an owned
/// character WHOLE, as one `@"…"`. This is for the other direction: a file
/// somebody wrote by hand.
fn merge_text(nodes : Array[@anode.ANode]) -> Array[@anode.ANode] {
  let out : Array[@anode.ANode] = []
  for n in nodes {
    if n is Text(d) && out.length() > 0 && out[out.length() - 1] is Text(prev) {
      prev.val = prev.val + d.val
      continue
    }
    out.push(n)
  }
  out
}

///|
/// The VIEW half of a `Comp.view` declaration name.
///
/// A component is one component whatever its views are called, so `Card:`
/// declares Card's `main` view and `Card.edit:` declares its `edit` one. The
/// name is what `data-vid` carries and what a `~as:` selector names, so it is
/// the view's half and never the component's.
fn view_name(declared : String) -> String {
  match declared.rev_find(".") {
    Some(i) => declared[i + 1:].to_owned()
    None => "main"
  }
}

///|
/// One item of an at-notation body: text, a hole, or an element.
///
/// It answers a LIST rather than a node, because a macro call expands to
/// whatever its body holds — which may be several nodes, and wrapping those in
/// a fragment would put an element in the tree the author did not write.
fn ViewBuilder::content(
  self : ViewBuilder,
  group : @ast.Node,
  ctx : ExCtx,
) -> Array[@anode.ANode] raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 else { return [] }
  // A LINE of an at-notation body is one group, and it may hold several items:
  // `@(it.label):@span{n}` is a hole, a piece of text and an element with
  // nothing between them, so nothing separated them into groups. Reading only
  // the first would drop the rest silently.
  let out = []
  let span = @sh.span_of(group)
  let mut i = 0
  while i < parts.length() {
    match parts[i].it {
      // Text, exactly as written. No trim: see this file's header.
      Lit(Str(text)) => {
        out.push(@anode.text(text))
        i = i + 1
      }
      // `@(expr)` — a value with no element around it
      Parens(gs) => {
        guard gs.length() == 1 else { return out }
        let ex = @sh.read_group(gs[0])
        out.push(@anode.dyn_text(@sh.to_expr(ex, ctx, span), id=self.alloc()))
        i = i + 1
      }
      // An element is its name and the parentheses after it, which carry both
      // its options and its body (`split_call` takes them apart).
      Id(word) => {
        // The element's own parentheses, and then anything `split_call`
        // should get the chance to refuse — an option written outside its
        // element is the mistake a first `.tutu` file makes, and its message
        // names the repair.
        let mut take = 1
        if i + take < parts.length() && parts[i + take].it is Parens(_) {
          take = take + 1
        }
        while i + take < parts.length() &&
              parts[i + take].it is (Kw(_) | Block(_)) {
          take = take + 1
        }
        for n in self.element(word, parts[i:i + take].to_owned(), ctx, span) {
          out.push(n)
        }
        i = i + take
      }
      _ =>
        raise ExError(
          message="this is not markup",
          help="a view holds elements, text and `@(…)` holes",
          span~,
        )
    }
  }
  out
}

///|
/// An element, a form, or a macro call — one shape, and the name decides which.
fn ViewBuilder::element(
  self : ViewBuilder,
  word : String,
  parts : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> Array[@anode.ANode] raise ExError {
  if self.macros.get(word) is Some(_) {
    return self.expand_macro(word, parts, ctx, span)
  }
  let (raw, body) = @lower.split_call(parts)
  match word {
    "show" | "hide" => [self.guard_(word, raw, body, ctx, span)]
    "each" => [self.each(raw, body, ctx, span)]
    "render" => [self.render(raw, ctx, span)]
    "slot" => [@anode.slot("", @anode.frag([]))]
    // A comment NODE, which reaches the DOM. `//` is a comment in the FILE.
    "comment" => [@anode.comment(body_text(body))]
    // A style block is not a node. It is the view's style, collected by the
    // caller, and reaching one here means it was written inside an element.
    "style" =>
      raise ExError(
        message="a style block is not part of an element",
        help="write `@style{ … }` at the top of the view, or at the top of `view:` for the whole component",
        span~,
      )
    _ => [self.tag(word, raw, body, ctx, span)]
  }
}

///|
/// The text of a body written as literal pieces, joined.
fn body_text(body : Array[@ast.Node]) -> String {
  let out = StringBuilder()
  for g in body {
    guard g.it is Group(parts) && parts.length() == 1 else { continue }
    if parts[0].it is Lit(Str(t)) {
      out.write_string(t)
    }
  }
  out.to_string()
}

///|
/// A plain element: its attributes, its handlers, and its children.
fn ViewBuilder::tag(
  self : ViewBuilder,
  tag : String,
  raw : Array[@ast.Node],
  body : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.ANode raise ExError {
  let attrs : Array[@anode.AttrItem] = []
  let events : Array[@anode.NodeEvent] = []
  let wrappers : Array[(String, @tutuca.Expr)] = []
  let binds : Array[@tutuca.Expr] = []
  let mut eid_at = 0
  // An event's MODIFIERS are the options written after its handler, which
  // `read_args` flattens into siblings. They belong to the `~on_*` before them.
  let args = @sh.read_args(raw)
  let mut at = 0
  while at < args.length() {
    let a = args[at]
    at = at + 1
    match a {
      AKw(name, value) => {
        let mods = []
        if name.has_prefix("on_") {
          if events.is_empty() {
            eid_at = attrs.length()
          }
          while at < args.length() && is_modifier(args[at]) {
            mods.push(args[at])
            at = at + 1
          }
        }
        self.attribute(
          name, value, mods, ctx, span, attrs, events, wrappers, binds,
        )
      }
      // A bare flag is a valueless attribute, which HTML reads as the boolean
      // it is: `~disabled` and `disabled` are `LBool(true)`, not the empty
      // string an `=""` spelling would give.
      AFlag(name) => attrs.push(@anode.attr_bool(@lower.attr_name(name), true))
      AField(name, _) =>
        raise ExError(
          message="`\{name}:` is not an attribute",
          help="write `~\{name}: <value>` — an attribute is an option of the element",
          span~,
        )
      APos(_) =>
        raise ExError(
          message="an element takes named attributes only",
          help="write `~class: \"x\"` rather than a bare value",
          span~,
        )
    }
  }
  // `~bind:` finishes here, where the element is known: an `input` of type
  // checkbox mirrors `checked` rather than `value`, and a `select` writes back
  // on `change` rather than on `input`. The mirrored property is a real
  // attribute and goes in before `data-eid`, which is where the HTML parser
  // leaves it.
  let mut bind_data : @anode.BindData? = None
  if binds is [target, ..] {
    let low = @lower.tag_name(tag).to_lower()
    let checkbox = low == "input" && static_attr(attrs, "type") == "checkbox"
    let property = if checkbox { "checked" } else { "value" }
    let event_name = if low == "select" { "change" } else { "input" }
    attrs.push(@anode.dyn_attr(property, target))
    if events.is_empty() {
      eid_at = attrs.length()
    }
    let field = target.as_field().unwrap_or("invalidBindTarget")
    let event : @anode.NodeEvent = {
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
    events.push(event)
    bind_data = Some({ target, property, event, })
  }
  // A scope's id is allocated only when there IS one, and before the element is
  // built, because the element carries it: `data-nid` is how a rendered node
  // finds the frame it is in, and the parser stamps it on the wrapped node
  // rather than on the wrapper.
  let mut scope_id = 0
  for w in wrappers {
    if w.0 == "scope" {
      scope_id = self.alloc()
      attrs.push(@anode.attr_num("data-nid", scope_id.to_double()))
    }
  }
  // `@svg{…}` opens the SVG namespace for everything under it, and `@math{…}`
  // MathML. Nothing closes one but the end of the element.
  let outer = self.ns
  self.ns = match tag {
    "svg" => Some(Svg)
    "math" => Some(MathML)
    _ => self.ns
  }
  let childs = []
  for g in body {
    for n in self.content(g, ctx) {
      childs.push(n)
    }
  }
  // `data-eid` goes where the first `~on_*` option was written, which is where
  // the HTML parser puts it — appending it would reorder the element's
  // attributes against a tree parsed from the old notation.
  //
  // And it is registered AFTER the children, because the adapter builds an
  // element once its content is closed: a child's handlers get a lower id than
  // its parent's, and the ids are what `data-eid` carries.
  if !events.is_empty() {
    attrs.insert(eid_at, @anode.eid(self.register(events)))
  }
  let node = @anode.h(
    @lower.tag_name(tag),
    attrs,
    merge_text(childs),
    ns?=self.ns,
    bind?=bind_data,
  )
  self.ns = outer
  // Outermost-first in source order, which is the order `WrapperAttr` records
  // them in — so the last one read is the innermost wrap.
  let mut out = node
  let mut i = wrappers.length() - 1
  while i >= 0 {
    let (kind, val) = wrappers[i]
    out = match kind {
      "show" => @anode.show(val, out)
      "hide" => @anode.hide(val, out)
      "scope" => @anode.scope(scope_id, val, out)
      _ => @anode.push_view(val, out)
    }
    i = i - 1
  }
  out
}

///|
/// One attribute, sorted into the four things an attribute can be: a handler,
/// a wrapper, a markup directive, or a value.
fn ViewBuilder::attribute(
  self : ViewBuilder,
  name : String,
  value : Ex,
  mods : Array[Arg],
  ctx : ExCtx,
  span : @report.Span,
  attrs : Array[@anode.AttrItem],
  events : Array[@anode.NodeEvent],
  wrappers : Array[(String, @tutuca.Expr)],
  binds : Array[@tutuca.Expr],
) -> Unit raise ExError {
  // `~onclick:` is a raw HTML event attribute, which a handler never is: the
  // value would reach the DOM as script text and be stripped two layers later
  // by a sanitizer, with a message about sanitising rather than about spelling.
  if name.has_prefix("on") && !name.has_prefix("on_") {
    raise ExError(
      message="`~\{name}` is not how a view names an event",
      help="write `~on_\{name[2:].to_owned()}:` — a handler is dispatched, and a raw `\{name}` attribute is script text a sanitizer removes",
      span~,
    )
  }
  if name.has_prefix("on_") {
    events.push(self.event(name[3:].to_owned(), value, mods, ctx, span))
    return
  }
  match name {
    // `~bind:` is not an attribute at all: it mirrors a place into a property
    // and registers the event that writes back. `tag` finishes it, because
    // which property and which event depend on the element it is written on.
    "bind" => {
      binds.push(@sh.to_expr(value, ctx, span))
      return
    }
    "push_view" => {
      wrappers.push(("push_view", @sh.to_expr(value, ctx, span)))
      return
    }
    // A loop-less `~enrich_with:` opens a SCOPE frame around the element: the
    // enricher is handed no row and answers the bindings the subtree renders
    // with. On an `@each` the option belongs to the loop and `print_each` has
    // already taken it, so reaching here means there is no loop.
    "enrich_with" => {
      wrappers.push(("scope", @sh.to_expr(value, ctx.as_handler(), span)))
      return
    }
    "inner_html" => {
      attrs.push(@anode.set_inner_html(val=@sh.to_expr(value, ctx, span)))
      return
    }
    // The one construct whose value reaches the DOM unparsed, and the only
    // attribute here whose name says so out loud.
    "dangerously_inner_html" => {
      attrs.push(@anode.raw_html(val=@sh.to_expr(value, ctx, span)))
      return
    }
    "inner_md" => {
      attrs.push(@anode.set_inner_md(val=@sh.to_expr(value, ctx, span)))
      return
    }
    "inner_svg" => {
      attrs.push(@anode.set_inner_svg(val=@sh.to_expr(value, ctx, span)))
      return
    }
    _ => ()
  }
  let attr = @lower.attr_name(name)
  match value {
    // A constant stays a constant, which is what lets a whole element collapse
    // to `ConstAttrs` and never be re-evaluated. A string and a boolean are
    // the two an attribute can be written as in markup — a bare `autofocus` is
    // `LBool(true)` — so both fold, exactly as the parser folds them.
    //
    // A number does not. There is no bare number attribute to write: the
    // parser reads `:rows="6"` as a DYNAMIC attribute holding `LNum(6)`, and a
    // reader that folded it here would change what a view compiles to as a
    // side effect of changing how it is written. Folding it is worth doing on
    // its own, to every backend at once, and not here.
    EStr(s) => attrs.push(@anode.attr(attr, s))
    EBool(b) => attrs.push(@anode.attr_bool(attr, b))
    // A conditional VALUE, which the printer path had to split into three
    // attributes (`@if.x` / `@then.x` / `@else.x`) because HTML has nowhere to
    // put one. Here it is the node it always was.
    EIf(cond, then_, else_) =>
      attrs.push(
        @anode.if_attr(
          attr,
          @sh.to_expr(cond, ctx, span),
          then_val=@sh.to_expr(then_, ctx, span),
          else_val=@sh.to_expr(else_, ctx, span),
        ),
      )
    other => attrs.push(@anode.dyn_attr(attr, @sh.to_expr(other, ctx, span)))
  }
}

///|
/// An event: a handler to dispatch, or a write to one of this component's own
/// properties.
fn ViewBuilder::event(
  self : ViewBuilder,
  spec : String,
  value : Ex,
  mods : Array[Arg],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.NodeEvent raise ExError {
  ignore(self)
  let hctx = ctx.as_handler()
  // `~on_keydown: add ~key: "Enter" ~prevent` — the options after the handler
  // are the modifiers the old notation spelled `@on.keydown.enter+prevent`.
  let modifiers = read_modifiers(mods)
  match value {
    EName(handler) => @anode.on(spec, @tutuca.Expr::name(handler), modifiers~)
    ECall(EName(handler), args) => {
      let out = []
      for a in @sh.positional_args(args) {
        out.push(@sh.to_expr(a, hctx, span))
      }
      @anode.on(spec, @tutuca.Expr::name(handler), args=out, modifiers~)
    }
    // A write to a property. `handler` is null and the ACTION carries it, which
    // is the shape `parse_input_handler` produces for the same source.
    EBin(op, place, v) if op is (":=" | "+=" | "-=") =>
      @anode.on(
        spec,
        @tutuca.Expr::lit(LNull),
        modifiers~,
        action=self.property_write(op, place, v, hctx, span),
      )
    ECall(EMember(recv, op), args) => {
      guard @lower.collection_op(op) is Some(word) else {
        raise ExError(
          message="`\{op}` is not a property action",
          help="the actions are `push`, `insert_at`, `set_at`, `delete_at`, `add`, `remove` and `toggle`",
          span~,
        )
      }
      guard recv is EIt(field) else {
        raise ExError(
          message="a property action writes one of this component's own properties",
          help="write `it.<name>.\{op}(…)`",
          span~,
        )
      }
      let out = []
      for a in @sh.positional_args(args) {
        out.push(@sh.to_expr(a, hctx, span))
      }
      @anode.on(
        spec,
        @tutuca.Expr::lit(LNull),
        modifiers~,
        action=@anode.call_property_action(field, word, out),
      )
    }
    _ =>
      raise ExError(
        message="an event names a handler or writes a property",
        help="write `~on_click: inc`, or `~on_input: it.query := e.value`",
        span~,
      )
  }
}

///|
/// `it.n := v`, `it.n += v`, `it.n -= v` — and `it.n := default`, which is the
/// one write that resets rather than assigns.
fn ViewBuilder::property_write(
  self : ViewBuilder,
  op : String,
  place : Ex,
  v : Ex,
  ctx : ExCtx,
  span : @report.Span,
) -> @tscript.PropertyAction raise ExError {
  ignore(self)
  guard place is EIt(field) else {
    raise ExError(
      message="an event writes one of this component's own properties",
      help="write `it.<name> := <value>`",
      span~,
    )
  }
  if op == ":=" && v is EName("default") {
    return @anode.reset_property_action(field)
  }
  let rhs = @sh.to_expr(v, ctx, span)
  let assigned = match op {
    "+=" => @tutuca.Expr::app("+", [@tutuca.Expr::field(field), rhs])
    "-=" => @tutuca.Expr::app("-", [@tutuca.Expr::field(field), rhs])
    _ => rhs
  }
  @anode.set_property_action(field, assigned)
}

///|
/// Whether an option is one an event takes after its handler.
fn is_modifier(a : Arg) -> Bool {
  match a {
    AFlag(_) => true
    AKw("key", _) => true
    _ => false
  }
}

///|
/// The modifiers an event carries, in the order the old notation spelled them:
/// the key first, then the behaviours.
fn read_modifiers(mods : Array[Arg]) -> Array[String] {
  let out = []
  for m in mods {
    if m is AKw("key", EStr(k)) {
      out.push(k.to_lower())
    }
  }
  for m in mods {
    if m is AFlag(f) {
      out.push(f)
    }
  }
  out
}

///|
/// `@show(c){ … }` / `@hide(c){ … }`.
fn ViewBuilder::guard_(
  self : ViewBuilder,
  word : String,
  raw : Array[@ast.Node],
  body : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.ANode raise ExError {
  let pos = @sh.positional_args(@sh.read_args(raw))
  guard pos.length() == 1 else {
    raise ExError(
      message="`@\{word}` takes one condition",
      help="write `@\{word}(<condition>){ … }`",
      span~,
    )
  }
  let cond = @sh.to_expr(pos[0], ctx, span)
  let inner = self.wrapped_body(word, body, ctx, span)
  if word == "show" {
    @anode.show(cond, inner)
  } else {
    @anode.hide(cond, inner)
  }
}

///|
/// `@each(item, i in xs, ~when: f){ … }`.
fn ViewBuilder::each(
  self : ViewBuilder,
  raw : Array[@ast.Node],
  body : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.ANode raise ExError {
  let (names, seq, after) = @lower.split_binder(raw)
  let args = @sh.read_args(raw[after:].to_owned())
  // The renderer answers a loop with `value` and `key`; the file's own binder
  // names are what this maps onto them.
  let mut inner = ctx
  if names.length() > 0 {
    inner = inner.with_bind(names[0], "value")
  }
  if names.length() > 1 {
    inner = inner.with_bind(names[1], "key")
  }
  let val = @sh.to_expr(seq, ctx, span)
  let trigger = fn(opt : String) -> @tutuca.Expr? raise ExError {
    match @sh.kw_arg(args, opt) {
      Some(EName(f)) => Some(@tutuca.Expr::name(f))
      Some(_) =>
        raise ExError(
          message="`~\{opt}` names a handler",
          help="declare it in the logic section and name it here",
          span~,
        )
      None => None
    }
  }
  // The body registers before the loop does. Registration order is not a
  // contract — `ParseContext::from_ir` recovers the node array from the ids the
  // tree carries — but matching the parser's order keeps an ahead-of-time tree
  // comparable with a parsed one, which is what the equivalence tests read.
  let node = self.wrapped_body("each", body, inner, span)
  // A loop whose whole body is the item itself is what the old notation spelled
  // `<x render-each>`. The marker is for the linter — it says this `Each` has no
  // wrapper-attr record to check instead — and the shape is what decides it,
  // since the new notation has one spelling for both.
  let from_render_each = node is RenderIt(_)
  @anode.each(
    self.alloc(),
    val,
    node,
    from_render_each~,
    when_val?=trigger("when"),
    enrich_with_val?=trigger("enrich_with"),
    loop_with_val?=trigger("loop_with"),
  )
}

///|
/// The one node a wrapping form wraps.
///
/// The old notation put the condition ON an element, so a form had to wrap
/// exactly one. That constraint is gone — the wrapper is a node here, not an
/// attribute looking for a host — but a body with several children still needs
/// something to be the wrapped node, and a fragment is what that is.
fn ViewBuilder::wrapped_body(
  self : ViewBuilder,
  word : String,
  body : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.ANode raise ExError {
  let childs = []
  for g in body {
    for n in self.content(g, ctx) {
      childs.push(n)
    }
  }
  let childs = merge_text(childs)
  guard childs.length() > 0 else {
    raise ExError(
      message="`@\{word}` has nothing to wrap",
      help="give it the content it governs: `@\{word}(…){ … }`",
      span~,
    )
  }
  if childs.length() == 1 {
    childs[0]
  } else {
    @anode.frag(childs)
  }
}

///|
/// `@render(v)` / `@render(v, ~as: "edit")`.
fn ViewBuilder::render(
  self : ViewBuilder,
  raw : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> @anode.ANode raise ExError {
  let args = @sh.read_args(raw)
  let pos = @sh.positional_args(args)
  guard pos.length() == 1 else {
    raise ExError(
      message="`@render` takes one value",
      help="write `@render(it.item)`",
      span~,
    )
  }
  let view = match @sh.kw_arg(args, "as") {
    Some(v) => Some(@sh.to_expr(v, ctx, span))
    None => None
  }
  let val = @sh.to_expr(pos[0], ctx, span)
  // `@render(row)` where `row` is the loop's own binder is RENDER-IT: the node
  // renders the item the loop is on and carries no value of its own. The old
  // notation had two spellings for that — `<x render-it>` and a `<x render>`
  // naming the binding — and the new one has this, so the ARGUMENT decides.
  if is_loop_item(val) {
    return @anode.render_it(self.alloc(), view?)
  }
  @anode.render(self.alloc(), val, view?)
}

///|
/// Whether a value is the loop's own item, which is what `render-it` renders.
fn is_loop_item(val : @tutuca.Expr) -> Bool {
  match val.as_bind() {
    Some(name) => name == "value"
    None => false
  }
}

///|
/// A macro call: the macro's own body, with its parameters substituted.
///
/// This is the whole of what "a macro is a tree" buys. There is no expansion
/// context, no second parse and no `macro_vars` map of source strings — the
/// argument is an `Ex` and it is put where the parameter was.
fn ViewBuilder::expand_macro(
  self : ViewBuilder,
  name : String,
  parts : Array[@ast.Node],
  ctx : ExCtx,
  span : @report.Span,
) -> Array[@anode.ANode] raise ExError {
  guard !self.expanding.contains(name) else {
    raise ExError(
      message="macro `\{name}` reaches itself",
      help="a macro cannot expand into its own body, directly or through another",
      span~,
    )
  }
  guard self.macros.get(name) is Some(def) else { return [] }
  let (raw, _) = @lower.split_call(parts)
  let bound : Map[String, Ex] = Map([])
  for k, v in def.defaults {
    bound[k] = v
  }
  for a in @sh.read_args(raw) {
    match a {
      AKw(arg, value) => bound[arg] = value
      AFlag(arg) => bound[arg] = EBool(true)
      _ => ()
    }
  }
  for p in def.params {
    guard bound.get(p) is Some(_) else {
      raise ExError(
        message="macro `\{name}` was not given `\{p}`",
        help="pass it at the call site — `@\{name}(~\{p}: <value>)` — or give the parameter a default",
        span~,
      )
    }
  }
  let inner = ctx.with_params(bound)
  self.expanding.push(name)
  let out = []
  for g in def.body {
    for n in self.content(g, inner) {
      out.push(n)
    }
  }
  self.expanding.pop() |> ignore
  out
}

///|
/// The constant value an attribute was written with, or `""` when it was not
/// written or is not constant. `~bind:` asks this about `type`, which decides
/// whether a checkbox mirrors `checked` or `value`.
fn static_attr(attrs : Array[@anode.AttrItem], wanted : String) -> String {
  for item in attrs {
    if item is (Plain(name~, val~) | ConstA(name~, val~)) &&
      name == wanted &&
      val.as_lit() is Some(LStr(s)) {
      return s
    }
  }
  ""
}
