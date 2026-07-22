// Emitting the compiled tree itself: the @anode.ANode / @anode.NodeEvents
// literals a view parses into, so a program built with them never runs the
// template parser at startup.
//
// Everything reachable here is `pub(all)`, so the tree is expressible as plain
// MoonBit constructor syntax — no serialization format, no decoder to keep in
// sync with the AST. The two things NOT emitted:
//
//   - `ParseContext.nodes`, recovered from the tree by @anode.ParseContext::from_ir
//     (every registered node already carries its node_id).
//   - the data-cid stamp and the constant-subtree optimization, which
//     View::from_ir / View::compile do at load time: cid depends on which
//     component adopts the view, and optimization must follow the stamp.
//
// Macros declared in the view file (`<template id="macro:name">`) ARE
// expanded here, at generation time — that is the point of declaring them in
// the file. What the emitter then sees is a MacroCall wrapping its expansion;
// since MacroData holds a ParseContext (not constructible from outside anode)
// and the renderer only ever renders `d.node`, the call node is replaced by
// its expansion before emitting. The expansion's own registered nodes live in
// the same ParseContext, so node ids stay consistent.

///|
/// True when every view in this set can be emitted as a tree. A single
/// view sends the whole file back to the source path, so a component never
/// mixes the two.
pub fn ir_supported(file : ViewFile) -> Bool {
  let scope = FileMacros::of(file.macros)
  for comp in file.components {
    for view in comp.views {
      try compiled_tree(view, scope) |> ignore catch {
        _ => return false
      }
    }
  }
  true
}

///|
/// Replace every expanded MacroCall with its expansion. Semantically a no-op
/// — render(MacroCall) renders exactly `d.node` — and it leaves a tree with
/// no node type the emitter cannot express.
fn strip_macro_calls(node : @anode.ANode) -> @anode.ANode raise GenError {
  match node {
    MacroCall(d) =>
      match d.node {
        Some(n) => strip_macro_calls(n)
        None =>
          raise ViewParseIssue(view="?", issue="unexpanded macro '\{d.name}'")
      }
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => node
    Dom(d) => {
      strip_childs(d.childs)
      node
    }
    Fragment(d) => {
      strip_childs(d.childs)
      node
    }
    Show(d) | Hide(d) | PushView(d) | Scope(d) => {
      d.node = strip_macro_calls(d.node)
      node
    }
    Slot(d) => {
      d.node = strip_macro_calls(d.node)
      node
    }
    Each(d) => {
      d.node = strip_macro_calls(d.node)
      node
    }
    RenderOnce(d) => {
      // Pre-optimization trees carry none of these; be total anyway.
      let _ = strip_macro_calls(d.node)
      node
    }
  }
}

///|
fn strip_childs(childs : Array[@anode.ANode]) -> Unit raise GenError {
  for i in 0..<childs.length() {
    childs[i] = strip_macro_calls(childs[i])
  }
}

// ---------------------------------------------------------------------------
// Value-layer literals

///|
/// A Double that reads back as the same Double. `Double::to_string` prints
/// whole numbers without a fraction, which MoonBit would then read as an Int.
fn double_lit(d : Double) -> String {
  let s = d.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") || s.contains("N") {
    s
  } else {
    s + ".0"
  }
}

///|
fn lit_expr(lit : @tutuca.Lit) -> String {
  match lit {
    LNull => "LNull"
    LBool(b) => "LBool(\{b})"
    LNum(n) => "LNum(\{double_lit(n)})"
    LStr(s) => "LStr(\{quote(s)})"
  }
}

///|
fn pred_expr(p : @tutuca.Pred) -> String {
  match p {
    IsEmpty => "IsEmpty"
    IsTruthy => "IsTruthy"
    IsFalsy => "IsFalsy"
    IsNull => "IsNull"
    Equals => "Equals"
  }
}

///|
fn val_expr(val : @tutuca.Val) -> String {
  match val {
    Const(lit~, from_macro~) =>
      "Const(lit=\{lit_expr(lit)}, from_macro=\{from_macro})"
    StrTpl(parts) => {
      let items = parts.map(p => {
        match p {
          Some(v) => "Some(\{val_expr(v)})"
          None => "None"
        }
      })
      "StrTpl([" + items.join(", ") + "])"
    }
    Predicate(pred~, args~) =>
      "Predicate(pred=\{pred_expr(pred)}, args=[" +
      args.map(val_expr).join(", ") +
      "])"
    Name(n) => "Name(\{quote(n)})"
    HandlerName(name~, ns~) => {
      let ns_name = match ns {
        Input => "Input"
        Alter => "Alter"
      }
      "HandlerName(name=\{quote(name)}, ns=\{ns_name})"
    }
    TypeName(n) => "TypeName(\{quote(n)})"
    Bind(n) => "Bind(\{quote(n)})"
    BindMember(name~, prop~) =>
      "BindMember(name=\{quote(name)}, prop=\{quote(prop)})"
    Dyn(n) => "Dyn(\{quote(n)})"
    Field(n) => "Field(\{quote(n)})"
    Method(n) => "Method(\{quote(n)})"
    SeqAccess(seq~, key~) => "SeqAccess(seq=\{quote(seq)}, key=\{quote(key)})"
  }
}

///|
fn val_opt_expr(val : @tutuca.Val?) -> String {
  match val {
    Some(v) => "Some(\{val_expr(v)})"
    None => "None"
  }
}

// ---------------------------------------------------------------------------
// Attributes

///|
fn attrs_expr(attrs : @anode.Attrs) -> String {
  match attrs {
    ConstAttrs(m) => {
      let entries : Array[String] = []
      for k, lit in m {
        entries.push("\{quote(k)}: \{lit_expr(lit)}")
      }
      if entries.is_empty() {
        "ConstAttrs(Map([]))"
      } else {
        "ConstAttrs({ " + entries.join(", ") + " })"
      }
    }
    DynAttrs(items) =>
      "DynAttrs([" + items.map(attr_item_expr).join(", ") + "])"
  }
}

///|
fn attr_item_expr(item : @anode.AttrItem) -> String {
  match item {
    Plain(name~, val~) => "Plain(name=\{quote(name)}, val=\{val_expr(val)})"
    ConstA(name~, val~) => "ConstA(name=\{quote(name)}, val=\{val_expr(val)})"
    RawHtml(val~) => "RawHtml(val=\{val_opt_expr(val)})"
    If(a) =>
      "If({ name: \{quote(a.name)}, cond_val: \{val_expr(a.cond_val)}, then_val: \{val_opt_expr(a.then_val)}, else_val: \{val_opt_expr(a.else_val)} })"
  }
}

// ---------------------------------------------------------------------------
// The tree

///|
fn int_opt_expr(v : Int?) -> String {
  match v {
    Some(i) => "Some(\{i})"
    None => "None"
  }
}

///|
fn iter_info_expr(info : @anode.IterInfo) -> String {
  "{ val: \{val_expr(info.val)}, when_val: \{val_opt_expr(info.when_val)}, loop_with_val: \{val_opt_expr(info.loop_with_val)}, enrich_with_val: \{val_opt_expr(info.enrich_with_val)} }"
}

///|
/// One ANode as a constructor expression. Emitted at `indent`, breaking a
/// line per child so the generated file stays readable and diffs per node.
fn node_expr(node : @anode.ANode, indent : String) -> String raise GenError {
  let deeper = indent + "  "
  fn childs_expr(childs : Array[@anode.ANode]) -> String raise GenError {
    if childs.is_empty() {
      return "[]"
    }
    let parts : Array[String] = []
    for c in childs {
      parts.push(deeper + "  " + node_expr(c, deeper + "  "))
    }
    "[\n" + parts.join(",\n") + ",\n" + deeper + "]"
  }

  match node {
    Text(d) => "Text({ val: \{quote(d.val)} })"
    Comment(d) => "Comment({ val: \{quote(d.val)} })"
    Dom(d) => {
      let ns = match d.ns {
        Some(Svg) => "Some(Svg)"
        Some(MathML) => "Some(MathML)"
        None => "None"
      }
      "Dom({\n" +
      deeper +
      "tag: \{quote(d.tag)},\n" +
      deeper +
      "attrs: \{attrs_expr(d.attrs)},\n" +
      deeper +
      "childs: \{childs_expr(d.childs)},\n" +
      deeper +
      "ns: \{ns},\n" +
      indent +
      "})"
    }
    Fragment(d) => "Fragment({ childs: \{childs_expr(d.childs)} })"
    RenderText(d) =>
      "RenderText({ node_id: \{int_opt_expr(d.node_id)}, val: \{val_expr(d.val)} })"
    Render(d) =>
      "Render({ node_id: \{d.node_id}, val: \{val_expr(d.val)}, view_val: \{val_opt_expr(d.view_val)} })"
    RenderIt(d) =>
      "RenderIt({ node_id: \{d.node_id}, view_val: \{val_opt_expr(d.view_val)} })"
    Show(d) => wrap_expr("Show", d, indent)
    Hide(d) => wrap_expr("Hide", d, indent)
    PushView(d) => wrap_expr("PushView", d, indent)
    Scope(d) => wrap_expr("Scope", d, indent)
    Slot(d) =>
      "Slot({ name: \{quote(d.name)}, node: \{node_expr(d.node, deeper)} })"
    Each(d) =>
      "Each({\n" +
      deeper +
      "node_id: \{d.node_id},\n" +
      deeper +
      "iter_info: \{iter_info_expr(d.iter_info)},\n" +
      deeper +
      "node: \{node_expr(d.node, deeper)},\n" +
      deeper +
      "from_render_each: \{d.from_render_each},\n" +
      indent +
      "})"
    // Only reachable if the caller skipped ir_supported / emitted after
    // optimization; both are generator bugs rather than user errors.
    MacroCall(d) =>
      raise ViewParseIssue(
        view="?",
        issue="macro '\{d.name}' cannot be compiled ahead of time",
      )
    RenderOnce(_) =>
      raise ViewParseIssue(
        view="?",
        issue="internal: tree was optimized before emission",
      )
  }
}

///|
fn wrap_expr(
  ctor : String,
  d : @anode.WrapData,
  indent : String,
) -> String raise GenError {
  let deeper = indent + "  "
  "\{ctor}({\n" +
  deeper +
  "node_id: \{int_opt_expr(d.node_id)},\n" +
  deeper +
  "val: \{val_expr(d.val)},\n" +
  deeper +
  "node: \{node_expr(d.node, deeper)},\n" +
  indent +
  "})"
}

// ---------------------------------------------------------------------------
// Events

///|
fn handler_expr(h : @anode.NodeEvent) -> String {
  let args = h.handler.args.map(val_expr).join(", ")
  let mods = h.modifiers.map(quote).join(", ")
  "{ name: \{quote(h.name)}, handler: { handler: \{val_expr(h.handler.handler)}, args: [\{args}] }, modifiers: [\{mods}] }"
}

///|
fn events_expr(events : Array[@anode.NodeEvents], indent : String) -> String {
  if events.is_empty() {
    return "[]"
  }
  let parts : Array[String] = []
  for ev in events {
    let hs = ev.handlers.map(handler_expr)
    if hs.is_empty() {
      parts.push("\{indent}  { id: \{ev.id}, handlers: [] }")
    } else {
      parts.push(
        "\{indent}  {\n\{indent}    id: \{ev.id},\n\{indent}    handlers: [\n" +
        hs.map(h => "\{indent}      \{h},").join("\n") +
        "\n\{indent}    ],\n\{indent}  }",
      )
    }
  }
  "[\n" + parts.join(",\n") + ",\n\{indent}]"
}

// ---------------------------------------------------------------------------

///|
/// The companion IR module: one builder per view plus the map to hand
/// `component()` as `views~`.
pub fn emit_ir_module(
  name : String,
  source_file : String,
  file : ViewFile,
) -> String raise GenError {
  let out = StringBuilder::new()
  let first = file.components[0].component_name(name)
  emit_ir_header(type_prefix(first), value_prefix(first), source_file, out)
  let scope = FileMacros::of(file.macros)
  for comp in file.components {
    emit_ir_component(comp.component_name(name), comp, scope, out)
  }
  out.to_string()
}

///|
fn emit_ir_header(
  t : String,
  v : String,
  source_file : String,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "// GENERATED by `tutuca gen-views` from \{source_file} — DO NOT EDIT.\n" +
    "//\n" +
    "// The views of \{t}, already compiled: the @anode.ANode tree each one\n" +
    "// parses into, plus its event table. Passing \{v}_views() as\n" +
    "// `views~` means the template parser never runs at startup.\n" +
    "//\n" +
    "// Every builder returns a FRESH tree: View::from_ir stamps and optimizes\n" +
    "// it in place, and each component that adopts a view stamps its own\n" +
    "// data-cid onto it.\n" +
    "\n",
  )
}

///|
/// One component's builders plus its `views()` map.
fn emit_ir_component(
  name : String,
  views : ViewSet,
  scope : FileMacros,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(name)
  let v = value_prefix(name)
  let _ = t
  for view in views.views {
    let (root, events) = compiled_tree(view, scope)
    let fname = "\{v}_\{value_prefix(view.name)}_view_ir"
    out.write_string(
      "///|\n/// The compiled `\{view.name}` view.\nfn \{fname}() -> @anode.View {\n",
    )
    out.write_string(
      "  let root : @anode.ANode = " + node_expr(root, "  ") + "\n",
    )
    out.write_string(
      "  let events : Array[@anode.NodeEvents] = " +
      events_expr(events, "  ") +
      "\n",
    )
    out.write_string(
      "  @anode.View::from_ir(\n" +
      "    \{quote(view.name)},\n" +
      "    root,\n" +
      "    @anode.ParseContext::from_ir(root, events),\n" +
      "    style=\{quote(view.style)},\n" +
      "  )\n}\n\n",
    )
  }
  out.write_string(
    "///|\n" +
    "/// The component's views, already compiled — pass as `views~` to\n" +
    "/// @component.component.\n" +
    "pub fn \{v}_views() -> Map[String, @anode.View] {\n  {\n",
  )
  for view in views.views {
    out.write_string(
      "    \{quote(view.name)}: \{v}_\{value_prefix(view.name)}_view_ir(),\n",
    )
  }
  out.write_string("  }\n}\n\n")
}

///|
/// Build the compiled views directly, without going through generated source.
/// This is exactly the value `emit_ir_module`'s output reconstructs, so the
/// two paths can be compared in a test — and a host that already holds the
/// view text (the playground) can skip codegen entirely.
pub fn compiled_views(
  views : ViewSet,
  macros? : Array[MacroDef] = [],
) -> Map[String, @anode.View] raise GenError {
  let scope = FileMacros::of(macros)
  let out : Map[String, @anode.View] = Map([])
  for view in views.views {
    let (root, events) = compiled_tree(view, scope)
    out[view.name] = @anode.View::from_ir(
      view.name,
      root,
      @anode.ParseContext::from_ir(root, events),
      style=view.style,
    )
  }
  out
}

///|
/// Parse one view and hand back the tree plus its event table, exactly as the
/// runtime would have built them — but BEFORE data-cid and optimization,
/// which are load-time concerns.
fn compiled_tree(
  view : RawView,
  scope : FileMacros,
) -> (@anode.ANode, Array[@anode.NodeEvents]) raise GenError {
  let collector = IssueCollector::{ issues: [] }
  // Un-optimized: RenderOnce ids are process-global renderer memo keys, so
  // View::from_ir mints them at load time instead.
  let px = @anode.ParseContext::new(handler=collector, cache_const_nodes=false)
  let v = @anode.View::new(view.name, raw_view=view.source)
  v.compile(px, scope) catch {
    RecursiveMacro(n) =>
      raise ViewParseIssue(view=view.name, issue="recursive macro '\{n}'")
  }
  if collector.issues.length() > 0 {
    raise ViewParseIssue(view=view.name, issue=collector.issues[0])
  }
  check_macros_resolved(view.name, px, scope)
  guard v.anode is Some(root) else { raise EmptyView(view.name) }
  (strip_macro_calls(root), px.events)
}
