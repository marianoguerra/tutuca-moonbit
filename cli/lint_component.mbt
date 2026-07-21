// Full component checker: port of tools/core/lint-check.js checkComponent.
//
// Invariant (unchanged from the first port): every view is parsed FRESH into
// a shadow @anode.ParseContext with a @lint.LintCollector handler — the live
// component's compiled views are never touched (see the no-mutate-app lint
// rule in the JS repo).
//
// Rules that do not apply to the MoonBit port (statically impossible, so
// they are cataloged in lint_rules.mbt but never emitted):
// - ASYNC_HANDLER — handlers are plain functions; there is no async color.
// - FIELD_NAME_RESERVED_BY_RECORD — instances are not Immutable Records.
// - COMP_FIELD_BAD_SHAPE — FieldSpec is a typed struct.
// - UNKNOWN_COMPONENT_SPEC_KEY — component() takes labeled arguments.
// - LOOKUP_BAD_SHAPE — LookupSpec is a typed struct; only the source string
//   can be malformed, which is LOOKUP_TARGET_MALFORMED.
// - SUGGEST_BINDING_MEMBER — the JS rule inspects the enrich handler's
//   source text (Function.prototype.toString); MoonBit closures are opaque.

///|
/// One component-lint finding, message pre-rendered (same wording as
/// tools/format/lint.js lintIdToMessage).
pub(all) struct LintFinding {
  code : String
  level : @lint.LintLevel
  where_ : String // "Comp", "Comp/view" or "Comp.provide.name"
  message : String
  suggestion : @lint.Suggestion?
}

///|
pub fn LintFinding::line(self : LintFinding) -> String {
  let level = match self.level {
    Error => ""
    Warn => " (warning)"
    Hint => " (hint)"
  }
  let tail = match suggestion_to_message(self.suggestion) {
    Some(t) => " — " + t
    None => ""
  }
  "\{self.code}\{level} \{self.where_}: \{self.message}\{tail}"
}

///|
fn level_name(level : @lint.LintLevel) -> String {
  match level {
    Error => "error"
    Warn => "warning"
    Hint => "hint"
  }
}

///|
pub fn LintFinding::to_json_value(self : LintFinding) -> Json {
  let obj : Map[String, Json] = {
    "code": self.code.to_json(),
    "level": level_name(self.level).to_json(),
    "where": self.where_.to_json(),
    "message": self.message.to_json(),
  }
  match suggestion_to_message(self.suggestion) {
    Some(t) => obj["suggestion"] = t.to_json()
    None => ()
  }
  Json::object(obj)
}

// ---------------------------------------------------------------------------
// Report context (JS errCtx + the message suffix helpers in format/lint.js)

///|
priv struct ErrCtx {
  tag : String?
  origin_attr : String?
  branch : String?
  handler_name : String?
  event_name : String?
  arg_index : Int?
}

///|
fn err_ctx(
  tag? : String,
  origin_attr? : String,
  branch? : String,
  handler_name? : String,
  event_name? : String,
  arg_index? : Int,
) -> ErrCtx {
  { tag, origin_attr, branch, handler_name, event_name, arg_index }
}

///|
/// " (in @text, handler 'x' arg 0, on <div>)" — format/lint.js fmtOriginSuffix.
fn origin_suffix(ctx : ErrCtx) -> String {
  let parts : Array[String] = []
  match ctx.origin_attr {
    Some(o) => {
      let branch = match ctx.branch {
        Some(b) => "[\{b}]"
        None => ""
      }
      parts.push("in \{o}\{branch}")
    }
    None => ()
  }
  match ctx.handler_name {
    Some(h) => {
      let arg = match ctx.arg_index {
        Some(i) => " arg \{i}"
        None => ""
      }
      parts.push("handler '\{h}'\{arg}")
    }
    None => ()
  }
  match ctx.tag {
    Some(t) => {
      let low = t.to_lower()
      if low != "x" {
        parts.push("on <\{low}>")
      }
    }
    None => ()
  }
  if parts.is_empty() {
    ""
  } else {
    " (" + parts.join(", ") + ")"
  }
}

///|
/// " in @on.click" — format/lint.js fmtEventSuffix.
fn event_suffix(ctx : ErrCtx) -> String {
  match ctx.origin_attr {
    Some(o) => " in \{o}"
    None =>
      match ctx.event_name {
        Some(e) => " in @on.\{e}"
        None => ""
      }
  }
}

// ---------------------------------------------------------------------------
// Checker state

///|
priv struct LintRun {
  comp : @component.Component
  out : Array[LintFinding]
  referenced_alters : Map[String, Bool]
  referenced_inputs : Map[String, Bool]
  referenced_dynamics : Map[String, Bool]
}

///|
fn LintRun::report(
  self : LintRun,
  code : String,
  level : @lint.LintLevel,
  view : String?,
  message : String,
  suggestion? : @lint.Suggestion,
) -> Unit {
  let where_ = match view {
    Some(v) => "\{self.comp.name}/\{v}"
    None => self.comp.name
  }
  self.out.push({ code, level, where_, message, suggestion })
}

///|
fn replace_name(name : String, candidates : Array[String]) -> @lint.Suggestion? {
  match @lint.closest_name(name, candidates) {
    Some(to) => Some(ReplaceName(from=name, to~))
    None => None
  }
}

///|
fn[V] map_keys(m : Map[String, V]) -> Array[String] {
  let out : Array[String] = []
  for k, _ in m {
    out.push(k)
  }
  out
}

// ---------------------------------------------------------------------------
// Entry point

///|
/// Run every component-model check (JS checkComponent) plus the per-view
/// structural HTML linter and the parse-issue rules. Returns findings in
/// report order; exit-code policy (errors only) is the caller's.
pub fn check_component(comp : @component.Component) -> Array[LintFinding] {
  let run : LintRun = {
    comp,
    out: [],
    referenced_alters: Map([]),
    referenced_inputs: Map([]),
    referenced_dynamics: Map([]),
  }
  check_provides_are_addressable(run)
  check_lookup_targets(run)
  check_scoped_style_top_level(run)
  for vname, view in comp.views {
    check_view(run, vname, view)
  }
  check_unreferenced(run)
  run.out
}

///|
fn check_view(run : LintRun, vname : String, view : @anode.View) -> Unit {
  let comp = run.comp
  // Structural HTML lint on the raw template (JS checkHtmlStructure).
  for f in @lint.lint_html(view.raw_view) {
    run.out.push({
      code: lint_code_name(f.code),
      level: f.level,
      where_: "\{comp.name}/\{vname}",
      message: finding_message(f),
      suggestion: f.suggestion,
    })
  }
  // Fresh shadow parse with a collector handler; compile expands macros so
  // the render-it walk and macro-arg checks see the real tree.
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  let root = @anode.ANode::parse(view.raw_view, px)
  match comp.scope {
    Some(scope) => px.compile(scope) catch { _ => () }
    None => ()
  }
  // Parse-issue rules + host bare directives (JS checkParseIssues).
  for f in @lint.check_collected(collector) {
    run.out.push({
      code: lint_code_name(f.code),
      level: f.level,
      where_: "\{comp.name}/\{vname}",
      message: finding_message(f),
      suggestion: f.suggestion,
    })
  }
  match root {
    Some(node) => check_render_it_in_loop(run, vname, px, node)
    None => ()
  }
  check_event_modifiers(run, vname, px)
  check_event_handlers_have_impls(run, vname, px)
  check_known_handler_names(run, vname, px)
  check_macro_call_args(run, vname, px)
  check_consistent_attrs(run, vname, collector, px)
}

// ---------------------------------------------------------------------------
// <x render-it> outside a loop (JS checkRenderItInLoop / walkForRenderIt)

///|
fn check_render_it_in_loop(
  run : LintRun,
  vname : String,
  px : @anode.ParseContext,
  root : @anode.ANode,
) -> Unit {
  let mut has_render_it = false
  for node in px.nodes {
    if node is RenderIt(_) {
      has_render_it = true
      break
    }
  }
  if !has_render_it {
    return
  }
  walk_for_render_it(run, vname, root, 0)
}

///|
fn walk_for_render_it(
  run : LintRun,
  vname : String,
  node : @anode.ANode,
  loop_depth : Int,
) -> Unit {
  match node {
    RenderIt(_) =>
      if loop_depth == 0 {
        run.report(
          "RENDER_IT_OUTSIDE_OF_LOOP",
          Error,
          Some(vname),
          "<x render-it> used outside of a loop",
          suggestion=Wrap(from="<x render-it>", to="<x render-each>"),
        )
      }
    Each(d) => walk_for_render_it(run, vname, d.node, loop_depth + 1)
    Show(d) | Hide(d) | PushView(d) | Scope(d) =>
      walk_for_render_it(run, vname, d.node, loop_depth)
    Slot(d) => walk_for_render_it(run, vname, d.node, loop_depth)
    RenderOnce(d) => walk_for_render_it(run, vname, d.node, loop_depth)
    MacroCall(d) =>
      match d.node {
        Some(n) => walk_for_render_it(run, vname, n, loop_depth)
        None => ()
      }
    Dom(d) =>
      for child in d.childs {
        walk_for_render_it(run, vname, child, loop_depth)
      }
    Fragment(d) =>
      for child in d.childs {
        walk_for_render_it(run, vname, child, loop_depth)
      }
    Text(_) | Comment(_) | RenderText(_) | Render(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Event modifiers (JS checkEventModifiers, MOD_WRAPPERS_BY_EVENT)

///|
/// Modifiers each event defines (app/app.mbt modifiers_pass — keep in sync).
fn mods_for_event(event_name : String) -> Array[String] {
  match event_name {
    "keydown" => ["send", "cancel", "ctrl", "cmd", "meta", "alt"]
    "click" => ["ctrl", "cmd", "meta", "alt"]
    _ => []
  }
}

///|
fn check_event_modifiers(
  run : LintRun,
  vname : String,
  px : @anode.ParseContext,
) -> Unit {
  for ev in px.events {
    for h in ev.handlers {
      let known = mods_for_event(h.name)
      for m in h.modifiers {
        if !known.contains(m) {
          let written = "@on.\{h.name}+\{h.modifiers.join("+")}"
          let suggestion : @lint.Suggestion? = match
            @lint.closest_name(m, known) {
            Some(close) => Some(ReplaceName(from="+" + m, to="+" + close))
            None => None
          }
          run.report(
            "UNKNOWN_EVENT_MODIFIER",
            Error,
            Some(vname),
            "Unknown modifier '+\{m}' in '\{written}'",
            suggestion?,
          )
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// @on handler implementations (JS checkEventHandlersHaveImpls)

///|
fn check_event_handlers_have_impls(
  run : LintRun,
  vname : String,
  px : @anode.ParseContext,
) -> Unit {
  let comp = run.comp
  for ev in px.events {
    for h in ev.handlers {
      let ctx = err_ctx(event_name=h.name, origin_attr="@on.\{h.name}")
      match h.handler.handler {
        HandlerName(name~, ..) => {
          run.referenced_inputs[name] = true
          if !comp.input.contains(name) {
            if comp.methods.contains(name) {
              // Port divergence from JS: Input dispatch falls back to
              // methods (component/instance.mbt obj_handler), so a bare
              // method name DOES fire — hint at the canonical `$name`
              // spelling instead of erroring on working code.
              run.report(
                "INPUT_HANDLER_METHOD_FOR_INPUT_HANDLER",
                Hint,
                Some(vname),
                "'\{name}' is an input handler reference, but '\{name}' is defined as a method" +
                event_suffix(ctx),
                suggestion=AddPrefix(from=name, to="$" + name),
              )
            } else {
              run.report(
                "INPUT_HANDLER_NOT_IMPLEMENTED",
                Error,
                Some(vname),
                "Input handler '\{name}' is not implemented" + event_suffix(ctx),
                suggestion?=replace_name(name, map_keys(comp.input)),
              )
            }
          }
        }
        Method(name) => {
          run.referenced_inputs[name] = true
          if !comp.methods.contains(name) {
            let is_input_fix = comp.input.contains(name)
            let suggestion : @lint.Suggestion? = if is_input_fix {
              Some(DropPrefix(from="$" + name, to=name))
            } else {
              replace_name(name, map_keys(comp.methods))
            }
            run.report(
              "INPUT_HANDLER_METHOD_NOT_IMPLEMENTED",
              Error,
              Some(vname),
              "Method '$\{name}' is not implemented" + event_suffix(ctx),
              suggestion?,
            )
            if is_input_fix {
              run.report(
                "INPUT_HANDLER_FOR_INPUT_HANDLER_METHOD",
                Hint,
                Some(vname),
                "'$\{name}' is a method reference, but '\{name}' is defined as an input handler" +
                event_suffix(ctx),
                suggestion=DropPrefix(from="$" + name, to=name),
              )
            }
          }
        }
        _ => ()
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Handler argument names (JS checkKnownHandlerNames + KNOWN_HANDLER_NAMES)

///|
/// The closed name→field mapping handler args can use (render/dom_event.mbt
/// event_field — keep in sync). `target`/`event`/`ctx` stay legal template
/// vocabulary for JS-ported views, though the port resolves them to Null
/// (DOM objects are not Values).
let known_handler_arg_names : Array[String] = [
  "value", "valueAsInt", "valueAsFloat", "target", "event", "isAlt", "isShift", "isCtrl",
  "isCmd", "key", "keyCode", "isUpKey", "isDownKey", "isSend", "isCancel", "isTabKey",
  "ctx", "dragInfo",
]

///|
fn check_known_handler_names(
  run : LintRun,
  vname : String,
  px : @anode.ParseContext,
) -> Unit {
  for ev in px.events {
    for h in ev.handlers {
      let handler_name = match h.handler.handler {
        HandlerName(name~, ..) => Some(name)
        Method(name) => Some(name)
        _ => None
      }
      let mut i = 0
      for arg in h.handler.args {
        check_attr_val(
          run,
          vname,
          arg,
          false,
          err_ctx(
            event_name=h.name,
            origin_attr="@on.\{h.name}",
            handler_name?,
            arg_index=i,
          ),
          true,
        )
        i = i + 1
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Macro call arguments (JS checkMacroCallArgs)

///|
fn check_macro_call_args(
  run : LintRun,
  vname : String,
  px : @anode.ParseContext,
) -> Unit {
  guard run.comp.scope is Some(scope) else { return }
  for node in px.macro_nodes {
    guard node is MacroCall(d) else { continue }
    guard scope.lookup_macro(d.name) is Some(m) else { continue }
    for arg_name, _v in d.attrs {
      if !m.defaults.contains(arg_name) {
        run.report(
          "UNKNOWN_MACRO_ARG",
          Error,
          Some(vname),
          "Argument '\{arg_name}' is not declared in macro '\{d.name}'",
          suggestion?=replace_name(arg_name, map_keys(m.defaults)),
        )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Attribute / directive value consistency (JS checkConsistentAttrs)

///|
fn attr_item_name(item : @anode.AttrItem) -> String? {
  match item {
    Plain(name~, ..) | ConstA(name~, ..) => Some(name)
    If(ia) => Some(ia.name)
    RawHtml(_) => Some("dangerouslysetinnerhtml")
  }
}

///|
fn attr_source_label(item : @anode.AttrItem) -> String {
  match item {
    ConstA(_) => "literal"
    If(ia) => "@if.\{ia.name}"
    RawHtml(_) => "@dangerouslysetinnerhtml"
    Plain(name~, ..) => ":\{name}"
  }
}

///|
fn check_consistent_attrs(
  run : LintRun,
  vname : String,
  collector : @lint.LintCollector,
  px : @anode.ParseContext,
) -> Unit {
  for record in collector.attrs {
    let tag = record.tag
    let skip_name_val = record.is_macro_call
    match record.result.attrs {
      DynAttrs(items) => {
        let sources_by_name : Map[String, Array[String]] = Map([])
        for item in items {
          match attr_item_name(item) {
            Some(name) if name != "data-eid" =>
              match sources_by_name.get(name) {
                Some(sources) => sources.push(attr_source_label(item))
                None => sources_by_name[name] = [attr_source_label(item)]
              }
            _ => ()
          }
          match item {
            If(ia) => {
              if ia.then_val is None && ia.else_val is None {
                run.report(
                  "IF_NO_BRANCH_SET",
                  Error,
                  Some(vname),
                  "'@if.\{ia.name}' has no '@then' or '@else' branch — add '@then=\"…\"' or '@else=\"…\"' (or both)" +
                  origin_suffix(err_ctx(tag~)),
                )
              }
              check_attr_val(
                run,
                vname,
                ia.cond_val,
                skip_name_val,
                err_ctx(tag~, origin_attr="@if.\{ia.name}", branch="@if"),
                true,
              )
              match ia.then_val {
                Some(v) =>
                  check_attr_val(
                    run,
                    vname,
                    v,
                    skip_name_val,
                    err_ctx(tag~, origin_attr="@if.\{ia.name}", branch="@then"),
                    true,
                  )
                None => ()
              }
              match ia.else_val {
                Some(v) =>
                  check_attr_val(
                    run,
                    vname,
                    v,
                    skip_name_val,
                    err_ctx(tag~, origin_attr="@if.\{ia.name}", branch="@else"),
                    true,
                  )
                None => ()
              }
            }
            Plain(name~, val~) | ConstA(name~, val~) =>
              check_attr_val(
                run,
                vname,
                val,
                skip_name_val,
                err_ctx(tag~, origin_attr=":\{name}"),
                true,
              )
            RawHtml(val~) =>
              match val {
                Some(v) =>
                  check_attr_val(
                    run,
                    vname,
                    v,
                    skip_name_val,
                    err_ctx(tag~, origin_attr="@dangerouslysetinnerhtml"),
                    true,
                  )
                None => ()
              }
          }
        }
        for name, sources in sources_by_name {
          if sources.length() > 1 {
            // Port divergence from JS: one literal plus one @if.<attr> is a
            // deliberate idiom here — attrs apply in source order and an
            // unset @if branch leaves the literal in place, so the literal
            // is the static fallback (or a class-scanner decoy) and the @if
            // conditionally overrides it. Any other combination is flagged.
            let literal_plus_if = sources.length() == 2 &&
              sources.contains("literal") &&
              sources.contains("@if.\{name}")
            if !literal_plus_if {
              run.report(
                "DUPLICATE_ATTR_DEFINITION",
                Error,
                Some(vname),
                "Attribute '\{name}' is set \{sources.length()} times (\{sources.join(", ")}) on <\{tag.to_lower()}>",
              )
            }
          }
        }
      }
      ConstAttrs(_) => ()
    }
    for w in record.result.wrappers {
      match w.kind {
        Each => {
          match w.when_val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(tag~, origin_attr="@when"),
                true,
              )
            None => ()
          }
          match w.enrich_with_val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(tag~, origin_attr="@enrich-with"),
                true,
              )
            None => ()
          }
          match w.loop_with_val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(tag~, origin_attr="@loop-with"),
                true,
              )
            None => ()
          }
        }
        Scope =>
          match w.val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(tag~, origin_attr="@enrich-with"),
                true,
              )
            None => ()
          }
        Show | Hide | PushView => {
          let origin = match w.kind {
            Show => "@show"
            Hide => "@hide"
            _ => "@push-view"
          }
          match w.val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(tag~, origin_attr=origin),
                true,
              )
            None => ()
          }
        }
      }
    }
    match record.result.text_child {
      Some(v) =>
        check_attr_val(
          run,
          vname,
          v,
          false,
          err_ctx(tag~, origin_attr="@text"),
          true,
        )
      None => ()
    }
  }
  // Registered nodes carrying values with no attrs entry (JS node loop).
  for node in px.nodes {
    match node {
      Scope(_) => () // already checked via the @enrich-with wrapper attr
      RenderText(d) =>
        check_attr_val(
          run,
          vname,
          d.val,
          false,
          err_ctx(origin_attr="<x text>"),
          true,
        )
      Render(d) =>
        check_attr_val(
          run,
          vname,
          d.val,
          false,
          err_ctx(origin_attr="<x render>"),
          true,
        )
      Show(d) =>
        check_attr_val(
          run,
          vname,
          d.val,
          false,
          err_ctx(origin_attr="<x show>"),
          true,
        )
      Hide(d) =>
        check_attr_val(
          run,
          vname,
          d.val,
          false,
          err_ctx(origin_attr="<x hide>"),
          true,
        )
      PushView(d) =>
        check_attr_val(
          run,
          vname,
          d.val,
          false,
          err_ctx(origin_attr="<x push-view>"),
          true,
        )
      Each(d) => {
        check_attr_val(run, vname, d.iter_info.val, false, err_ctx(), true)
        // <x render-each> sugar carries @when/@loop-with on iterInfo with no
        // wrapper-attr entry to check them through (JS fromRenderEach).
        if d.from_render_each {
          match d.iter_info.when_val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(origin_attr="<x render-each @when>"),
                true,
              )
            None => ()
          }
          match d.iter_info.loop_with_val {
            Some(v) =>
              check_attr_val(
                run,
                vname,
                v,
                false,
                err_ctx(origin_attr="<x render-each @loop-with>"),
                true,
              )
            None => ()
          }
        }
      }
      _ => ()
    }
  }
}

// ---------------------------------------------------------------------------
// Per-value-kind consistency checks (JS ATTR_VAL_CHECKERS)

///|
/// Boolean-condition slots: a literal here is a constant condition.
fn is_bool_condition_ctx(ctx : ErrCtx) -> Bool {
  if ctx.branch == Some("@if") {
    return true
  }
  match ctx.origin_attr {
    Some("@show" | "@hide" | "<x show>" | "<x hide>") => true
    _ => false
  }
}

///|
fn is_const_arg(v : @tutuca.Val) -> Bool {
  match v {
    Const(_) => true
    StrTpl(_) => v.is_literal()
    _ => false
  }
}

///|
/// The plain `'…'` source literal of an all-constant string template.
fn strtpl_literal_source(parts : Array[@tutuca.Val?]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('\'')
  for part in parts {
    match part {
      Some(Const(lit=LStr(s), ..)) => buf.write_string(s)
      Some(v) => buf.write_string(v.to_string())
      None => ()
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
fn constant_condition(
  run : LintRun,
  vname : String,
  literal : String,
  ctx : ErrCtx,
) -> Unit {
  run.report(
    "CONSTANT_CONDITION",
    Warn,
    Some(vname),
    "Condition is the constant literal \{literal} — it never changes; reference a field ('.name') or a method ('$name') instead" +
    origin_suffix(ctx),
  )
}

///|
fn check_attr_val(
  run : LintRun,
  vname : String,
  val : @tutuca.Val,
  skip_name_val : Bool,
  ctx : ErrCtx,
  is_root : Bool,
) -> Unit {
  let comp = run.comp
  match val {
    // A non-boolean literal as the whole boolean condition never varies.
    Const(lit~, ..) =>
      if is_root && is_bool_condition_ctx(ctx) && !(lit is LBool(_)) {
        constant_condition(run, vname, val.to_string(), ctx)
      }
    StrTpl(parts) =>
      if val.is_literal() {
        let literal = strtpl_literal_source(parts)
        if is_root && is_bool_condition_ctx(ctx) {
          constant_condition(run, vname, literal, ctx)
        } else {
          run.report(
            "PLACEHOLDERLESS_TEMPLATE_STRING",
            Hint,
            Some(vname),
            "String template has no dynamic parts — use the string literal \{literal} instead" +
            origin_suffix(ctx),
            suggestion=Rewrite(from="$" + literal, to=literal),
          )
        }
      } else {
        // Drop empty constant bookends the way StrTplVal.parse trims them,
        // then a single remaining dynamic part means the template wrapper is
        // redundant: `:class="{.foo}"` should just be `:class=".foo"`.
        let dynamic : Array[@tutuca.Val] = []
        for part in parts {
          match part {
            Some(Const(lit=LStr(""), ..)) | None => ()
            Some(v) => dynamic.push(v)
          }
        }
        if dynamic.length() == 1 && !(dynamic[0] is Const(_)) {
          let simpler = dynamic[0].to_string()
          run.report(
            "REDUNDANT_TEMPLATE_STRING",
            Warn,
            Some(vname),
            "Redundant string template — '{\{simpler}}' should be just '\{simpler}'" +
            origin_suffix(ctx),
            suggestion=Rewrite(from="$'{\{simpler}}'", to=simpler),
          )
        }
        for part in parts {
          match part {
            Some(v) => check_attr_val(run, vname, v, skip_name_val, ctx, false)
            None => ()
          }
        }
      }
    // A predicate whose args are ALL literals never changes either; a
    // literal arg on its own is normal usage (recursed as non-root).
    Predicate(args~, ..) => {
      if is_bool_condition_ctx(ctx) && args.iter().all(is_const_arg) {
        constant_condition(run, vname, val.to_string(), ctx)
      }
      for arg in args {
        check_attr_val(run, vname, arg, skip_name_val, ctx, false)
      }
    }
    // NameVals on a macro call-site attribute are macro-param bindings —
    // their role is validated inside the macro body after ^-substitution.
    Name(name) =>
      if !skip_name_val && !known_handler_arg_names.contains(name) {
        run.report(
          "UNKNOWN_HANDLER_ARG_NAME",
          Error,
          Some(vname),
          "Unknown handler argument '\{name}'" + origin_suffix(ctx),
          suggestion?=replace_name(name, known_handler_arg_names),
        )
      }
    // In value position a handler name resolves in the `alter` namespace.
    HandlerName(name~, ..) => {
      run.referenced_alters[name] = true
      if !comp.alter.contains(name) {
        run.report(
          "ALT_HANDLER_NOT_DEFINED",
          Error,
          Some(vname),
          "Alter handler '\{name}' is not defined" + origin_suffix(ctx),
          suggestion?=replace_name(name, map_keys(comp.alter)),
        )
      }
    }
    TypeName(name) =>
      match comp.scope {
        Some(scope) =>
          if scope.lookup_component(name) is None {
            run.report(
              "UNKNOWN_COMPONENT_NAME",
              Error,
              Some(vname),
              "Unknown component '\{name}'" + origin_suffix(ctx),
              suggestion?=replace_name(name, scope_component_names(scope)),
            )
          }
        None => ()
      }
    Bind(_) | BindMember(_) => ()
    // `*name` resolves either a lookup or the component's own provide.
    Dyn(name) => {
      run.referenced_dynamics[name] = true
      if !comp.provide.contains(name) && !comp.lookup.contains(name) {
        let candidates = map_keys(comp.provide) + map_keys(comp.lookup)
        run.report(
          "DYN_VAL_NOT_DEFINED",
          Error,
          Some(vname),
          "Dynamic binding '*\{name}' is not defined" + origin_suffix(ctx),
          suggestion?=replace_name(name, candidates),
        )
      }
    }
    // `.name` must be a field. If it names a method, the fix is `$name`.
    Field(name) => check_field_ref(run, vname, name, ctx)
    // `$name` must be a method. If it names a field, the fix is `.name`.
    Method(name) =>
      if !comp.methods.contains(name) {
        if comp.fields.contains(name) {
          run.report(
            "METHOD_VAL_IS_FIELD",
            Error,
            Some(vname),
            "'$\{name}' calls a method, but '\{name}' is defined as a field — use '.\{name}'" +
            origin_suffix(ctx),
            suggestion=Rewrite(from="$" + name, to="." + name),
          )
        } else {
          run.report(
            "METHOD_VAL_NOT_DEFINED",
            Error,
            Some(vname),
            "Method '$\{name}' is not defined" + origin_suffix(ctx),
            suggestion?=replace_name(name, map_keys(comp.methods)),
          )
        }
      }
    // `.seq[.key]` reads two fields (JS recurses into the sub-FieldVals).
    SeqAccess(seq~, key~) => {
      check_field_ref(run, vname, seq, ctx)
      check_field_ref(run, vname, key, ctx)
    }
  }
}

///|
fn check_field_ref(
  run : LintRun,
  vname : String,
  name : String,
  ctx : ErrCtx,
) -> Unit {
  let comp = run.comp
  if comp.fields.contains(name) {
    return
  }
  if comp.methods.contains(name) {
    run.report(
      "FIELD_VAL_IS_METHOD",
      Error,
      Some(vname),
      "'.\{name}' reads a field, but '\{name}' is defined as a method — use '$\{name}'" +
      origin_suffix(ctx),
      suggestion=Rewrite(from="." + name, to="$" + name),
    )
  } else {
    run.report(
      "FIELD_VAL_NOT_DEFINED",
      Error,
      Some(vname),
      "Field '.\{name}' is not defined" + origin_suffix(ctx),
      suggestion?=replace_name(name, map_keys(comp.fields)),
    )
  }
}

///|
fn scope_component_names(scope : @component.ComponentStack) -> Array[String] {
  let out : Array[String] = []
  let mut cursor : @component.ComponentStack? = Some(scope)
  while cursor is Some(s) {
    for name, _c in s.by_name {
      out.push(name)
    }
    cursor = s.parent
  }
  out
}

// ---------------------------------------------------------------------------
// provide / lookup shapes (JS checkProvidesAreAddressable, checkLookupShapes)

///|
/// A `provide` value must be addressable: compile() drops any raw provide
/// that fails to parse as a field/seq-access, so a key present in
/// raw_provide but absent from provide is a non-path value.
fn check_provides_are_addressable(run : LintRun) -> Unit {
  let comp = run.comp
  for name, raw in comp.raw_provide {
    if !comp.provide.contains(name) {
      run.out.push({
        code: "PROVIDE_NOT_ADDRESSABLE",
        level: Error,
        where_: "\{comp.name}.provide.\{name}",
        message: "Provide '\{name}' value '\{raw}' must be a field ('.f') or seq-access ('.s[.k]') — a method/constant can't be a render target",
        suggestion: None,
      })
    }
  }
}

///|
/// LookupSpec is a typed struct, so the JS container-shape rule
/// (LOOKUP_BAD_SHAPE) can't fire; only the source string can be malformed.
fn check_lookup_targets(run : LintRun) -> Unit {
  let comp = run.comp
  for name, spec in comp.raw_lookup {
    if !comp.lookup.contains(name) {
      run.out.push({
        code: "LOOKUP_TARGET_MALFORMED",
        level: Error,
        where_: "\{comp.name}.lookup.\{name}",
        message: "Lookup '\{name}' target '\{spec.source}' must be 'Producer.provideName'",
        suggestion: None,
      })
    }
  }
}

// ---------------------------------------------------------------------------
// Unreferenced declarations (JS checkUnreferenced*)

///|
fn check_unreferenced(run : LintRun) -> Unit {
  let comp = run.comp
  for name, _h in comp.alter {
    if !run.referenced_alters.contains(name) {
      run.report(
        "ALT_HANDLER_NOT_REFERENCED",
        Hint,
        None,
        "Alter handler '\{name}' is defined but never used — remove it or reference it from @when, @enrich-with, or @loop-with",
      )
    }
  }
  for name, _h in comp.input {
    if !run.referenced_inputs.contains(name) {
      run.report(
        "INPUT_HANDLER_NOT_REFERENCED",
        Hint,
        None,
        "Input handler '\{name}' is defined but never used — remove it or wire it to an @on.* event",
      )
    }
  }
  // Only lookups: a provide is consumed by CHILD components, so it need not
  // appear in this component's own views.
  for name, _l in comp.lookup {
    if !run.referenced_dynamics.contains(name) {
      run.report(
        "DYN_ALIAS_NOT_REFERENCED",
        Hint,
        None,
        "Lookup '\{name}' is defined but never used — remove it or reference it as '*\{name}' in a view",
      )
    }
  }
}
