// Emitting the compiled tree itself: the @anode.ANode / @anode.NodeEvents
// values a view parses into, so a program built with them never runs the
// template parser at startup.
//
// The tree is written with anode's builders (@anode.h / text / attr / on …),
// which are plain constructors over the `pub(all)` AST with the rarely-set
// fields defaulted — no serialization format, no decoder to keep in sync.
// Every call is qualified: the file lands in the user's package, where a
// `using @anode {…}` header would be package-scoped and collide both with the
// user's own names and with the other generated files beside it.
//
// The three things NOT emitted:
//
//   - `ParseContext.nodes`, recovered from the tree by @anode.View::from_ir
//     (every registered node already carries its node_id).
//   - the NodeEvents ids: an id IS the entry's position in the table.
//   - the data-vid stamp, the data-cid stamp and the constant-subtree
//     optimization, which View::from_ir / View::compile do at load time: cid
//     depends on which component adopts the view, and optimization must
//     follow the stamp.
//
// Macros declared in the view file (`<template id="macro:name">`) ARE
// expanded here, at generation time — that is the point of declaring them in
// the file. What the emitter then sees is a MacroCall wrapping its expansion;
// since MacroData holds a ParseContext (not constructible from outside anode)
// and the renderer only ever renders `d.node`, the call node is replaced by
// its expansion before emitting. The expansion's own registered nodes live in
// the same ParseContext, so node ids stay consistent.

///|
/// The qualifier every emitted builder call carries.
let q : String = "@anode."

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

///|
/// Drop the data-vid `View::compile` stamped while generating: `View::from_ir`
/// stamps it again at load, so emitting it is a second copy that can only
/// drift. Follows set_data_attr's own recursion (Dom carries it, Fragment
/// gives it to every child, a wrapper passes it inward), and leaves it alone
/// unless it is the last attribute — anywhere else it came from the source,
/// where its position is the author's.
fn strip_data_vid(node : @anode.ANode) -> Unit {
  match node {
    Dom(d) =>
      match d.attrs {
        ConstAttrs(m) => {
          let keys = m.keys().collect()
          if keys.last() is Some("data-vid") {
            m.remove("data-vid")
          }
        }
        DynAttrs(items) =>
          if items.last() is Some(ConstA(name="data-vid", ..)) {
            items.remove(items.length() - 1) |> ignore
          }
      }
    Fragment(d) =>
      for c in d.childs {
        strip_data_vid(c)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) => strip_data_vid(d.node)
    Slot(d) => strip_data_vid(d.node)
    Each(d) => strip_data_vid(d.node)
    _ => ()
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
/// Some(i) for a Double that is exactly a small integer, so an id reads as one.
fn whole(d : Double) -> Int? {
  let i = d.to_int()
  if i.to_double() == d {
    Some(i)
  } else {
    None
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
/// The constant builders: a plain `Const(lit=…, from_macro=false)`, which is
/// what every constant a view writes parses to.
fn const_expr(lit : @tutuca.Lit) -> String {
  match lit {
    LNull => "\{q}const_null()"
    LBool(b) => "\{q}const_bool(\{b})"
    LNum(n) => "\{q}const_num(\{double_lit(n)})"
    LStr(s) => "\{q}const_str(\{quote(s)})"
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
      if from_macro {
        "Const(lit=\{lit_expr(lit)}, from_macro=true)"
      } else {
        const_expr(lit)
      }
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
/// `, label=…` for an optional argument that is set, "" for one that is not.
fn val_arg(label : String, val : @tutuca.Val?) -> String {
  match val {
    Some(v) => ", \{label}=\{val_expr(v)}"
    None => ""
  }
}

///|
fn int_arg(label : String, v : Int?) -> String {
  match v {
    Some(i) => ", \{label}=\{i}"
    None => ""
  }
}

// ---------------------------------------------------------------------------
// Attributes
//
// Emitted as the item list `h` takes; it re-derives ConstAttrs vs DynAttrs
// with the very rule the parser applies (@anode.attrs_of_items), so the two
// paths cannot disagree.

///|
fn const_attr_expr(name : String, lit : @tutuca.Lit) -> String {
  match lit {
    LStr(s) => "\{q}attr(\{quote(name)}, \{quote(s)})"
    LNum(n) =>
      match (name, whole(n)) {
        ("data-eid", Some(i)) => "\{q}eid(\{i})"
        _ => "\{q}attr_num(\{quote(name)}, \{double_lit(n)})"
      }
    LBool(b) => "\{q}attr_bool(\{quote(name)}, \{b})"
    LNull => "\{q}attr_val(\{quote(name)}, \{q}const_null())"
  }
}

///|
fn attr_item_expr(item : @anode.AttrItem) -> String {
  match item {
    ConstA(name~, val~) =>
      match val {
        // A macro-var-sourced constant is still a ConstA, but from_macro
        // survives only through the general builder.
        Const(lit~, from_macro=false) => const_attr_expr(name, lit)
        _ => "\{q}attr_val(\{quote(name)}, \{val_expr(val)})"
      }
    Plain(name~, val~) => "\{q}dyn_attr(\{quote(name)}, \{val_expr(val)})"
    RawHtml(val~) =>
      match val {
        Some(v) => "\{q}raw_html(val=\{val_expr(v)})"
        None => "\{q}raw_html()"
      }
    If(a) =>
      "\{q}if_attr(\{quote(a.name)}, \{val_expr(a.cond_val)}" +
      val_arg("then_val", a.then_val) +
      val_arg("else_val", a.else_val) +
      ")"
  }
}

///|
fn attrs_expr(attrs : @anode.Attrs) -> String {
  let entries : Array[String] = []
  match attrs {
    ConstAttrs(m) =>
      for k, lit in m {
        entries.push(const_attr_expr(k, lit))
      }
    DynAttrs(items) =>
      for item in items {
        entries.push(attr_item_expr(item))
      }
  }
  "[" + entries.join(", ") + "]"
}

// ---------------------------------------------------------------------------
// The tree

///|
/// One ANode as a builder call. Only child lists break across lines — that is
/// what keeps a `tutuca gen-views` run readable before `moon fmt`, which owns
/// the final layout, has run.
fn node_expr(node : @anode.ANode, indent : String) -> String raise GenError {
  let deeper = indent + "  "
  fn childs_expr(childs : Array[@anode.ANode]) -> String raise GenError {
    if childs.is_empty() {
      return "[]"
    }
    let parts : Array[String] = []
    for c in childs {
      parts.push(deeper + node_expr(c, deeper))
    }
    "[\n" + parts.join(",\n") + ",\n" + indent + "]"
  }

  match node {
    Text(d) => "\{q}text(\{quote(d.val)})"
    Comment(d) => "\{q}comment(\{quote(d.val)})"
    Dom(d) => {
      let ns = match d.ns {
        Some(Svg) => ", ns=Svg"
        Some(MathML) => ", ns=MathML"
        None => ""
      }
      "\{q}h(\{quote(d.tag)}, \{attrs_expr(d.attrs)}, \{childs_expr(d.childs)}\{ns})"
    }
    Fragment(d) => "\{q}frag(\{childs_expr(d.childs)})"
    RenderText(d) =>
      "\{q}dyn_text(\{val_expr(d.val)}\{int_arg("id", d.node_id)})"
    Render(d) =>
      "\{q}render(\{d.node_id}, \{val_expr(d.val)}\{val_arg("view", d.view_val)})"
    RenderIt(d) => "\{q}render_it(\{d.node_id}\{val_arg("view", d.view_val)})"
    Show(d) => wrap_expr("show", d, indent)
    Hide(d) => wrap_expr("hide", d, indent)
    PushView(d) => wrap_expr("push_view", d, indent)
    // Scope always registers, so the builder takes its id as a plain
    // argument; an unregistered one (which the parser never builds) has to
    // fall back to the raw constructor.
    Scope(d) =>
      match d.node_id {
        Some(id) =>
          "\{q}scope(\{id}, \{val_expr(d.val)}, \{node_expr(d.node, indent)})"
        None =>
          "Scope({ node_id: None, val: \{val_expr(d.val)}, node: \{node_expr(d.node, indent)} })"
      }
    Slot(d) => "\{q}slot(\{quote(d.name)}, \{node_expr(d.node, indent)})"
    Each(d) => {
      let info = d.iter_info
      "\{q}each(\{d.node_id}, \{val_expr(info.val)}, \{node_expr(d.node, indent)}" +
      val_arg("when_val", info.when_val) +
      val_arg("loop_with_val", info.loop_with_val) +
      val_arg("enrich_with_val", info.enrich_with_val) +
      (if d.from_render_each { ", from_render_each=true" } else { "" }) +
      ")"
    }
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
  builder : String,
  d : @anode.WrapData,
  indent : String,
) -> String raise GenError {
  "\{q}\{builder}(\{val_expr(d.val)}, \{node_expr(d.node, indent)}\{int_arg("id", d.node_id)})"
}

// ---------------------------------------------------------------------------
// Events

///|
fn handler_expr(h : @anode.NodeEvent) -> String {
  let args = if h.handler.args.is_empty() {
    ""
  } else {
    ", args=[" + h.handler.args.map(val_expr).join(", ") + "]"
  }
  let mods = if h.modifiers.is_empty() {
    ""
  } else {
    ", modifiers=[" + h.modifiers.map(quote).join(", ") + "]"
  }
  "\{q}on(\{quote(h.name)}, \{val_expr(h.handler.handler)}\{args}\{mods})"
}

///|
/// The handler table: one list per element that registered events, in
/// registration order. The ids are the positions, so they are not written.
fn events_expr(events : Array[@anode.NodeEvents], indent : String) -> String {
  if events.is_empty() {
    return "[]"
  }
  let parts = events.map(ev => {
    "\{indent}  [" + ev.handlers.map(handler_expr).join(", ") + "]"
  })
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
    "// parses into, plus its event table, written with anode's builders.\n" +
    "// Passing \{v}_views() as `views~` means the template parser\n" +
    "// never runs at startup.\n" +
    "//\n" +
    "// The package this file lives in must import:\n" +
    "//   \"marianoguerra/tutuca/anode\"\n" +
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
    let style = if view.style == "" {
      ""
    } else {
      "    style=\{quote(view.style)},\n"
    }
    out.write_string(
      "///|\n/// The compiled `\{view.name}` view.\nfn \{fname}() -> @anode.View {\n",
    )
    out.write_string(
      "  @anode.View::from_ir(\n" +
      "    \{quote(view.name)},\n" +
      "    " +
      node_expr(root, "    ") +
      ",\n" +
      "    " +
      events_expr(events, "    ") +
      ",\n" +
      style +
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
/// Build the views directly, without going through generated source. This is
/// exactly the value `emit_ir_module`'s output reconstructs, which is what the
/// gen-views tests assert: render through both paths, expect the same DOM. A
/// host that already holds the view text could use it to skip codegen too.
pub fn build_views(
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
      events.map(ev => ev.handlers),
      style=view.style,
    )
  }
  out
}

///|
/// Parse one view and hand back the tree plus its event table, exactly as the
/// runtime would have built them — but BEFORE data-cid and optimization,
/// which are load-time concerns, and without the data-vid stamp, which
/// View::from_ir applies again.
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
  let tree = strip_macro_calls(root)
  strip_data_vid(tree)
  (tree, px.events)
}
