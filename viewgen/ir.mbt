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
/// The qualifier the value layer's own constructors carry. A generated module
/// stands in a package with no `moon.pkg` of its own (the playground's View
/// tab), so a name that resolved by expected type here would not resolve
/// there.
let t : String = "@tutuca."

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
  @statedef.double_lit(d)
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
/// The constant builders: a plain `ELit(lit=…, from_macro=false, ..)`, which is
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
/// A place, as the record literal that rebuilds it.
///
/// Spelled out rather than reached through a shape helper because a place is
/// general: the four shapes a slot can write have helpers below, and this is
/// what anything else falls back to.
fn place_expr(p : @tutuca.Place) -> String {
  let root = match p.root {
    PState(n) => "PState(\{quote(n)})"
    PBind(n) => "PBind(\{quote(n)})"
    PParam(n) => "PParam(\{quote(n)})"
    PTarget => "PTarget"
  }
  let steps = p.steps.map(st => {
    match st {
      PField(n) => "PField(\{quote(n)})"
      PIndex(e) => "PIndex(\{val_expr(e)})"
    }
  })
  "{ root: \{root}, steps: [" + steps.join(", ") + "], span: @tutuca.no_span }"
}

///|
/// One template part.
fn tpl_part_expr(part : @tutuca.TplPart) -> String {
  match part {
    TText(text~, from_macro~) =>
      "TText(text=\{quote(text)}, from_macro=\{from_macro})"
    TExpr(e) => "TExpr(\{val_expr(e)})"
  }
}

///|
/// An expression, as the MoonBit that rebuilds it.
///
/// SPAN-FREE, and that is a decision rather than an omission: a generated
/// module is not source anybody points a diagnostic at, so every node it
/// rebuilds carries `no_span`. Which is also why the shape constructors
/// (`Expr::field`, `Expr::bind`, …) are what this emits — they default the
/// span, and they are the same four shapes a slot can write.
fn val_expr(val : @tutuca.Expr) -> String {
  // The four addressable shapes, by their own names. `as_bind_member` before
  // `as_bind` for the reason the parser tries them in that order: `@a.b` is
  // not a whole-binding read.
  if val.as_field() is Some(n) {
    return "\{t}Expr::field(\{quote(n)})"
  }
  if val.as_bind() is Some(n) {
    return "\{t}Expr::bind(\{quote(n)})"
  }
  if val.as_bind_member() is Some((n, prop)) {
    return "\{t}Expr::bind_member(\{quote(n)}, \{quote(prop)})"
  }
  if val.as_seq_access() is Some((seq, key)) {
    return "\{t}Expr::seq_access(\{quote(seq)}, \{quote(key)})"
  }
  match val {
    ELit(lit~, from_macro~, ..) =>
      if from_macro {
        "\{t}Expr::lit(\{lit_expr(lit)}, from_macro=true)"
      } else {
        const_expr(lit)
      }
    ETpl(parts~, ..) =>
      "\{t}Expr::tpl([" + parts.map(tpl_part_expr).join(", ") + "])"
    // The name rides as a string rather than a constructor: the vocabulary is
    // a table, so there is no enum for the generated module to name.
    EApp(name~, args~, ..) =>
      "\{t}Expr::app(\{quote(name)}, [" + args.map(val_expr).join(", ") + "])"
    EEventPath(segments~, ..) =>
      "\{t}Expr::event_path([" +
      segments.map(seg => quote(seg)).join(", ") +
      "])"
    EName(name~, ..) => "\{t}Expr::name(\{quote(name)})"
    ETypeName(name~, ..) => "\{t}Expr::type_name(\{quote(name)})"
    EDyn(name~, ..) => "\{t}Expr::dyn_(\{quote(name)})"
    EMethod(name~, ..) => "\{t}Expr::method_(\{quote(name)})"
    ERead(place~, ..) => "ERead(place=\{place_expr(place)}, span=\{t}no_span)"
    // The forms a slot refuses and a BODY writes. A view file's IR never holds
    // one; they are here because this function is total over the AST and a
    // silent hole in a code generator is the worst kind.
    ERef(place~, ..) => "ERef(place=\{place_expr(place)}, span=\{t}no_span)"
    EMacroVar(name~, ..) => "EMacroVar(name=\{quote(name)}, span=\{t}no_span)"
    EConfigVar(name~, ..) => "EConfigVar(name=\{quote(name)}, span=\{t}no_span)"
    EUnary(op~, operand~, ..) => {
      let word = match op {
        UNot => "UNot"
        UNeg => "UNeg"
      }
      "EUnary(op=\{word}, operand=\{val_expr(operand)}, span=\{t}no_span)"
    }
    EChain(family~, ops~, operands~, ..) => {
      let fam = match family {
        FLogic => "FLogic"
        FCompare => "FCompare"
        FImplies => "FImplies"
        FAdd => "FAdd"
        FMul => "FMul"
      }
      "EChain(family=\{fam}, ops=[" +
      ops.map(quote).join(", ") +
      "], operands=[" +
      operands.map(val_expr).join(", ") +
      "], span=\{t}no_span)"
    }
    EIf(cond~, then_~, else_~, ..) =>
      "EIf(cond=\{val_expr(cond)}, then_=\{val_expr(then_)}, else_=\{val_expr(else_)}, span=\{t}no_span)"
  }
}

///|
/// `, label=…` for an optional argument that is set, "" for one that is not.
fn val_arg(label : String, val : @tutuca.Expr?) -> String {
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
        ELit(lit~, from_macro=false, ..) => const_attr_expr(name, lit)
        _ => "\{q}attr_val(\{quote(name)}, \{val_expr(val)})"
      }
    Plain(name~, val~) => "\{q}dyn_attr(\{quote(name)}, \{val_expr(val)})"
    RawHtml(val~) =>
      match val {
        Some(v) => "\{q}raw_html(val=\{val_expr(v)})"
        None => "\{q}raw_html()"
      }
    RawMarkdown(val~) =>
      match val {
        Some(v) => "\{q}set_inner_md(val=\{val_expr(v)})"
        None => "\{q}set_inner_md()"
      }
    SafeHtml(val~) =>
      match val {
        Some(v) => "\{q}set_inner_html(val=\{val_expr(v)})"
        None => "\{q}set_inner_html()"
      }
    SafeSvg(val~) =>
      match val {
        Some(v) => "\{q}set_inner_svg(val=\{val_expr(v)})"
        None => "\{q}set_inner_svg()"
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
/// what keeps a `tutuca gen` run readable before `moon fmt`, which owns
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
    // A macro the generator could not expand. Raised rather than emitted:
    // the tree path cannot express it, and `emit_ir_module_opt` turns this
    // into the None that sends the file back to the source path.
    MacroCall(d) =>
      raise ViewParseIssue(
        view="?",
        issue="macro '\{d.name}' cannot be compiled ahead of time",
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
  let binding = match h.binding {
    Some(BindPending) => ", binding=\{q}BindPending"
    Some(BindString) => ", binding=\{q}BindString"
    Some(BindBool) => ", binding=\{q}BindBool"
    Some(BindInt(width~, signed~)) =>
      ", binding=\{q}BindInt(width=\{width}, signed=\{signed})"
    Some(BindDouble) => ", binding=\{q}BindDouble"
    None => ""
  }
  let action = match h.handler.action {
    Some(PropertySet(name~, value~)) =>
      ", action=\{q}set_property_action(\{quote(name)}, \{val_expr(value)})"
    Some(PropertyReset(name)) =>
      ", action=\{q}reset_property_action(\{quote(name)})"
    Some(PropertyCall(name~, operation~, args~)) =>
      ", action=\{q}call_property_action(\{quote(name)}, \{quote(operation)}, [" +
      args.map(val_expr).join(", ") +
      "])"
    None => ""
  }
  "\{q}on(\{quote(h.name)}, \{val_expr(h.handler.handler)}\{args}\{mods}\{binding}\{action})"
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
  file : @viewfile.ViewFile,
) -> String raise GenError {
  emit_ir_module_compiled(name, source_file, file, compile_file(file, name))
}

///|
fn emit_ir_module_compiled(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
  compiled : CompiledFile,
) -> String raise GenError {
  let out = StringBuilder()
  // A schema-only file declares no views, so there is no tree to compile —
  // and no header to write, since the header names the first component.
  guard !file.components.is_empty() else { raise NoViewsToCompile }
  let first = file.components[0].component_name(name)
  emit_ir_header(type_prefix(first), value_prefix(first), source_file, out)
  // Ahead of every component, because every wrapper in the file names it: the
  // block is the FILE's, not one component's.
  let spec_source = emit_spec_source(value_prefix(first), file, out)
  for comp in compiled.components {
    let cname = comp.raw.component_name(name)
    let state = state_for(file, cname, name)
    let surface = with_script(comp.surface, file, cname, state)
    // The script block, compiled — None when the file writes none, and None
    // for a component with no schema, which has no state type to write a
    // transition over.
    let inline = match state {
      Some(def) =>
        inline_emit(
          file,
          cname,
          def,
          surface,
          value_prefix(cname),
          "\{type_prefix(cname)}State",
        )
      None => None
    }
    // A fixture is keyed by the schema's RAW component name, which is "" for
    // a bare `state { … }` — the same key `emit_module` uses.
    let inits = match state {
      Some(def) => file.init.filter(p => p.0 == def.component).map(p => p.1)
      None => []
    }
    emit_ir_component(
      cname, comp, state, surface, inline, inits, spec_source, out,
    )
  }
  out.to_string()
}

///|
/// Emitting a view IS the check: the failure a separate "can this be emitted?"
/// pass would report is the same one caught here, so asking first only bought a
/// second compile of every view.
///
/// Output is all-or-nothing: the builder is discarded with the error, so a file
/// that fails on its last view emits nothing rather than a truncated module.
pub fn emit_ir_module_opt(
  name : String,
  source_file : String,
  file : @viewfile.ViewFile,
) -> String? {
  Some(emit_ir_module(name, source_file, file)) catch {
    _ => None
  }
}

///|
fn emit_ir_header(
  t : String,
  v : String,
  source_file : String,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "// GENERATED by `tutuca gen` from \{source_file} — DO NOT EDIT.\n" +
    "//\n" +
    "// The views of \{t}, already compiled: the @anode.ANode tree each one\n" +
    "// parses into, plus its event table, written with anode's builders.\n" +
    "// Passing \{v}_views() as `views~` means the template parser\n" +
    "// never runs at startup.\n" +
    "//\n" +
    "// A component that also declares a schema gets a `_component` wrapper\n" +
    "// beside its views: component() with the name, the views, the styles,\n" +
    "// the codec and the schema already filled in — pass it the handlers.\n" +
    "//\n" +
    "// The package this file lives in must import:\n" +
    "//   \"marianoguerra/tutuca/anode\", and for the wrapper\n" +
    "//   \"marianoguerra/tutuca/core\" @tutuca, \"marianoguerra/tutuca/component\"\n" +
    "//\n" +
    "// Every builder returns a FRESH tree: View::from_ir stamps and optimizes\n" +
    "// it in place, and each component that adopts a view stamps its own\n" +
    "// data-cid onto it.\n" +
    "\n",
  )
}

///|
/// One component's builders, its `views()` map, and — when it declares a
/// schema — the `component()` wrapper that defaults to them.
fn emit_ir_component(
  name : String,
  compiled : CompiledComponent,
  state : @statedef.StateDef?,
  surface : Surface,
  inline : @emit_mbt.Emitted?,
  inits : Array[@statedef.InitState],
  /// The file-level spec-source const, named by every wrapper in the file.
  spec_source : String?,
  out : StringBuilder,
) -> Unit raise GenError {
  let t = type_prefix(name)
  let v = value_prefix(name)
  for view in compiled.views {
    let fname = "\{v}_\{value_prefix(view.raw.name)}_view_ir"
    let style = if view.raw.style == "" {
      ""
    } else {
      "    style=\{quote(view.raw.style)},\n"
    }
    out.write_string(
      "///|\n/// The compiled `\{view.raw.name}` view.\nfn \{fname}() -> @anode.View {\n",
    )
    out.write_string(
      "  @anode.View::from_ir(\n" +
      "    \{quote(view.raw.name)},\n" +
      "    " +
      node_expr(view.root, "    ") +
      ",\n" +
      "    " +
      events_expr(view.events, "    ") +
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
  for view in compiled.views {
    out.write_string(
      "    \{quote(view.raw.name)}: \{v}_\{value_prefix(view.raw.name)}_view_ir(),\n",
    )
  }
  out.write_string("  }\n}\n\n")
  // The wrapper defaults `views~` to the map just written, so it belongs
  // with it rather than in the types module: the two arrive and leave
  // together. A component with no schema has no state type to make its
  // parameters out of, and keeps calling `component()` directly.
  // The block's transitions, ahead of the wrapper that composes them.
  let inline_name = match inline {
    Some(e) if e.source != "" => {
      out.write_string(e.source)
      out.write_string("\n")
      // The update function exists only if a TRANSITION compiled; a block of
      // nothing but `compute` bodies emits value functions and no arms.
      if e.answers_input.is_empty() &&
        e.answers_receive.is_empty() &&
        e.answers_intent.is_empty() {
        None
      } else {
        Some(inline_fn_name(v))
      }
    }
    _ => None
  }
  if state is Some(def) {
    emit_wrapper(
      name, t, v, def, surface, inline_name, inline, spec_source, out,
    )
    emit_init_invariants(t, v, def, inits, inline, out)
  }
}

///|
/// `Init => Inv`: every declared initial state keeps every declared invariant,
/// asserted at BUILD time.
///
/// A generated test and not a static evaluation, which is the whole trick. The
/// block interpreter was removed once the two compilers covered what it did,
/// and a constant folder written to decide these here would be a THIRD
/// implementation of the expression semantics — the one place where a rule
/// could quietly mean something different from what it means at runtime. The
/// invariant is already compiled into this module; calling it is exact by
/// construction.
///
/// Only an explicit `Bool(false)` fails, matching the runtime: a rule that
/// cannot be evaluated is unknown, and unknown is not wrong.
///
/// The DECLARED initial states, and not the schema's `zero()`. The zero is what
/// a field falls back to, not a state anybody said the component starts in: a
/// wrapper is normally called with `initial~`, which this cannot see, so a rule
/// that is false of all-zeros and true of every real fixture is a component
/// that works. Asserting over the zero would fail those, which is the shape of
/// a check people turn off.
fn emit_init_invariants(
  t : String,
  v : String,
  def : @statedef.StateDef,
  inits : Array[@statedef.InitState],
  inline : @emit_mbt.Emitted?,
  out : StringBuilder,
) -> Unit {
  let invariants = def.invariants()
  if invariants.is_empty() {
    return
  }
  // Only the ones that actually compiled. A rule the backend refused has no
  // function to call, and a test naming it would not build.
  guard inline is Some(e) else { return }
  let live = invariants.filter(r => e.answers_methods.contains(r))
  if live.is_empty() {
    return
  }
  if inits.is_empty() {
    return
  }
  let seeds : Array[(String, String)] = inits.map(st => {
    (st.name, t + "State::" + st.ident + "()")
  })
  let where_ = if def.source_name == "" { v } else { def.source_name }
  out.write_string(
    "///|\n" +
    "/// Every declared initial state keeps every declared invariant.\n" +
    "///\n" +
    "/// A rule that does not hold in the state a component STARTS in is broken\n" +
    "/// before anything happens, and every transition after it is refused — so\n" +
    "/// this is the one check worth making before the component ever runs.\n" +
    "/// GENERATED — edit the spec block, not this.\n" +
    "test " +
    quote(where_ + ": the declared initial states keep the invariants") +
    " {\n",
  )
  for seed in seeds {
    out.write_string("  let s = " + seed.1 + "\n")
    for rule in live {
      out.write_string(
        "  assert_false(\n" +
        "    " +
        @emit_mbt.value_fn_name(v, RMethod, rule) +
        "(s, [], @tutuca.NullStack::{  }) is Bool(false),\n" +
        "    msg=" +
        quote("the `" + seed.0 + "` initial state breaks `" + rule + "`") +
        ",\n" +
        "  )\n",
      )
    }
  }
  out.write_string("}\n\n")
}

///|
/// Build the views directly, without going through generated source. This is
/// exactly the value `emit_ir_module`'s output reconstructs, which is what the
/// gen tests assert: render through both paths, expect the same DOM. A
/// host that already holds the view text could use it to skip codegen too.
///
/// `state` is the component's schema, and passing it is not optional in the
/// way the default makes it look: `@bind` needs the field's type to pick its
/// coercion, so a view file that uses one and is built WITHOUT its schema is
/// refused. Hardcoding `None` here is what made `gen-css` reject files
/// `gen` accepts. Callers holding a `ViewFile` get it from
/// `ViewFile::state_of`; `None` is right only for a caller that has no schema
/// to give.
pub fn build_views(
  views : @viewfile.ViewSet,
  macros? : Array[@viewfile.MacroDef] = [],
  state? : @statedef.StateDef? = None,
) -> Map[String, @anode.View] raise GenError {
  let scope = FileMacros::of(macros)
  let out : Map[String, @anode.View] = Map([])
  let compiled = compile_views(views.views, scope)
  lower_binds(compiled, state)
  for view in compiled {
    out[view.raw.name] = @anode.View::from_ir(
      view.raw.name,
      view.root,
      view.events.map(ev => ev.handlers),
      style=view.raw.style,
    )
  }
  out
}
