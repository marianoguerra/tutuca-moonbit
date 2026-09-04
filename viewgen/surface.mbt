// Extracting the typed surface from compiled views.
//
// Each view is parsed into a FRESH @anode.ParseContext with a collecting
// handler, the same shadow discipline cli/lint_component.mbt uses. Two passes
// over the result:
//
//   px.events  -> @on handler names, their argument shapes, their call sites
//   the tree   -> $method references, constant ids, root-scope field reads
//
// Handler names come from px.events rather than a tree walk because the
// parser has already resolved them into @core.HandlerParse values (bare name
// -> EHandlerName(ns=Receive, ..), `$name` -> Method), so there is no attribute
// syntax left to re-interpret here.

///|
/// Collects parse issues instead of printing them: a view that would warn at
/// runtime is a generation failure, since the emitted types would describe a
/// view the runtime does not agree with.
priv struct IssueCollector {
  issues : Array[String]
}

///|
impl @anode.ParseHandler for IssueCollector with fn on_parse_issue(
  self,
  issue,
  tag,
) {
  let where_ = match tag {
    Some(t) => " on <\{t}>"
    None => ""
  }
  self.issues.push(issue_message(issue) + where_)
}

///|
/// The macros the view file declares, as the parser's MacroScope. This is
/// what lets `<x:card>` expand at GENERATION time — the whole reason macros
/// are declared in the view file rather than registered from MoonBit.
priv struct FileMacros {
  by_name : Map[String, @anode.Macro]
}

///|
fn FileMacros::of(defs : Array[@viewfile.MacroDef]) -> FileMacros {
  let by_name : Map[String, @anode.Macro] = Map([])
  for d in defs {
    by_name[d.name] = { defaults: d.defaults, raw_view: d.source, }
  }
  { by_name, }
}

///|
impl @anode.MacroScope for FileMacros with fn lookup_macro(self, name) {
  self.by_name.get(name)
}

///|
fn value_issue_message(role : @tscript.IssueRole) -> String {
  match role {
    BadMacroVar => "unknown macro variable"
    // Named as a host-side gap rather than a typo: the view spelled a config
    // variable nothing was bound to, and the fix is in whatever registered it.
    BadConfigVar => "no config variable of that name was bound"
    BadHandlerName => "not a valid handler name"
    BadHandlerArg => "not a valid handler argument"
    UnknownPredicate => "unknown predicate"
    // With an open vocabulary the arity is a fact about the declaration
    // rather than something the reader can look up in an enum, so the
    // message carries it.
    PredicateArity(name~, want~) =>
      "'\{name}' takes \{want} argument" + (if want == 1 { "" } else { "s" })
    BadPredicateArg => "not a valid predicate argument"
    // Answered as a whole sentence by `value_issue_sentence`; this is the
    // phrase form nothing should reach.
    BadExpression(..) => "not a valid expression"
  }
}

///|
/// The roles that answer with a WHOLE SENTENCE rather than a phrase to splice
/// after "bad value 'x' in".
///
/// The splice reads as a place — "in attribute 'class'" — and two of these
/// roles are not places, they are explanations. `bad value 'not' in unknown
/// predicate` was the result, which is not even grammatical, and it named
/// neither the rule nor the way out.
fn value_issue_sentence(role : @tscript.IssueRole, value : String) -> String? {
  match role {
    UnknownPredicate => {
      let tail = "a conditional takes a name applied to values, and the vocabulary is " +
        @tutuca.builtin_names().map(n => "`\{n}`").join(" ") +
        " — name anything else with a `pred` or a `compute` and spell it `$name`"
      Some("`\{value}` is not in the vocabulary: \{tail}")
    }
    BadExpression(why~) => Some("`\{value}` — \{why}")
    _ => None
  }
}

///|
fn issue_message(issue : @anode.ParseIssue) -> String {
  match issue {
    UnknownDirective(name~, value~) =>
      "unknown directive '@\{name}=\"\{value}\"'"
    UnknownXOp(name~, value~) => "unknown <x> op '\{name}=\"\{value}\"'"
    UnknownXAttr(op~, name~, value~) =>
      "unknown attribute '\{name}=\"\{value}\"' on <x \{op}>"
    LoopDirectiveOnXOp(op~, name~, value~) =>
      "'\{name}=\"\{value}\"' cannot go on <x \{op}>"
    XOpIgnoresChildren(op~) => "<x \{op}> ignores its children"
    BadValue(role~, value~) => {
      if role is ValueIssue(r) && value_issue_sentence(r, value) is Some(said) {
        return said
      }
      let what = match role {
        XOp(op~) => "<x \{op}>"
        Attr(name~) => "attribute '\{name}'"
        Directive(name~) => "directive '\{name}'"
        IfDirective(name~) => "conditional directive '\{name}'"
        ValueIssue(r) => value_issue_message(r)
      }
      "bad value '\{value}' in \{what}"
    }
  }
}

// ---------------------------------------------------------------------------
// Value walking

///|
/// What a tree walk accumulates.
///
/// A struct rather than six positional accumulators: every walker takes all
/// of them anyway.
///
/// The alter names are split by BUCKET, not gathered into one set, because
/// each bucket has its own handler signature — `@when` answers Bool, an
/// in-loop `@enrich-with` mutates the binds map while a loop-less one returns
/// it, and `@loop-with` returns a slice plan. A name is only typeable once you
/// know which of those it is.
priv struct Collect {
  methods : @set.Set[String]
  fields : @set.Set[String]
  ids : @set.Set[String]
  /// Constant `id`s found INSIDE an `@each` body. The loop emits the body
  /// once per item, so any one of these is `document.getElementById` returning
  /// whichever row happens to be first.
  loop_ids : @set.Set[String]
  whens : @set.Set[String]
  enriches : @set.Set[String]
  bind_withs : @set.Set[String]
  loop_withs : @set.Set[String]
  /// What the `value` handler arg decodes to, per event id (`data-eid`), for
  /// the elements where the glue does NOT deliver the input's text: a
  /// checkbox delivers its checked state (Bool), a file input its metadata
  /// Map / Null (Value). Absent = the default `String`. Filled by the tree
  /// walk, read by the events pass; eids restart per view, so walk_view
  /// clears it before each walk.
  value_kinds : Map[Int, ArgType]
  /// Advisory findings the events pass turned up; see `Surface.hints`.
  hints : Array[String]
  /// The view being walked, for a hint raised from inside the value walk —
  /// which is the whole tree below a directive and has no other way to say
  /// where it is.
}

///|
fn Collect::new() -> Collect {
  {
    methods: Set([], capacity=8),
    fields: Set([], capacity=8),
    ids: Set([], capacity=8),
    loop_ids: Set([], capacity=2),
    whens: Set([], capacity=4),
    enriches: Set([], capacity=4),
    bind_withs: Set([], capacity=4),
    loop_withs: Set([], capacity=4),
    value_kinds: Map([]),
    hints: [],
  }
}

///|
/// The handler an alter directive names, into `into`.
///
/// A `$name` there is a method like any other and is already collected by
/// `walk_val`; only the bare `HandlerName` form is a bucket entry.
fn walk_alter(val : @tutuca.Val?, into : @set.Set[String]) -> Unit {
  match val {
    Some(EName(name~, ..)) => into.add(name)
    _ => ()
  }
}

///|
/// Every `$name` a value reaches, and — when `root_scope` — every state field
/// it reads.
fn walk_val(val : @tutuca.Val, c : Collect, root_scope : Bool) -> Unit {
  if val.as_seq_access() is Some((seq, key)) {
    if root_scope {
      c.fields.add(seq)
      c.fields.add(key)
    }
    return
  }
  match val {
    EMethod(name~, ..) => c.methods.add(name)
    ERead(place={ root: PState(name), steps: [], .. }, ..) =>
      if root_scope {
        c.fields.add(name)
      }
    ETpl(parts~, ..) =>
      for p in parts {
        if p is TExpr(v) {
          walk_val(v, c, root_scope)
        }
      }
    EApp(args~, ..) =>
      for a in args {
        walk_val(a, c, root_scope)
      }
    _ => ()
  }
}

///|
fn walk_val_opt(val : @tutuca.Val?, c : Collect, root_scope : Bool) -> Unit {
  match val {
    Some(v) => walk_val(v, c, root_scope)
    None => ()
  }
}

///|
/// Attribute values, plus the constant `id` this element declares.
fn walk_attrs(
  attrs : @anode.Attrs,
  c : Collect,
  root_scope : Bool,
  in_loop : Bool,
) -> Unit {
  fn id(v : String) {
    c.ids.add(v)
    if in_loop {
      c.loop_ids.add(v)
    }
  }

  match attrs {
    ConstAttrs(m) =>
      for k, lit in m {
        if k == "id" && lit is LStr(v) {
          id(v)
        }
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => {
            if name == "id" && val is ELit(lit=LStr(v), ..) {
              id(v)
            }
            walk_val(val, c, root_scope)
          }
          RawHtml(val~) | RawMarkdown(val~) | SafeHtml(val~) | SafeSvg(val~) =>
            walk_val_opt(val, c, root_scope)
          If(a) => {
            walk_val(a.cond_val, c, root_scope)
            walk_val_opt(a.then_val, c, root_scope)
            walk_val_opt(a.else_val, c, root_scope)
          }
        }
      }
  }
}

///|
/// Walk the compiled tree. `root_scope` goes false under anything that pushes
/// a new stack frame (@each, @enrich-with, push-view, <x render>): a `.field`
/// down there addresses the item or the child component, not this component's
/// state. `$name` and `id` are collected everywhere.
///
/// `in_loop` goes true under an `@each` body and never back, so a constant
/// `id` down there can be reported: the body is emitted once per item, and an
/// id is supposed to be unique in a document.
fn walk_node(
  node : @anode.ANode,
  c : Collect,
  root_scope : Bool,
  in_loop : Bool,
) -> Unit {
  match node {
    Text(_) | Comment(_) => ()
    Dom(d) => {
      match (eid_of(d.attrs), value_arg_kind(d)) {
        (Some(id), Some(kind)) => c.value_kinds[id] = kind
        _ => ()
      }
      walk_attrs(d.attrs, c, root_scope, in_loop)
      for child in d.childs {
        walk_node(child, c, root_scope, in_loop)
      }
    }
    Fragment(d) =>
      for child in d.childs {
        walk_node(child, c, root_scope, in_loop)
      }
    RenderText(d) => walk_val(d.val, c, root_scope)
    Render(d) => {
      // The value naming the child IS read in this scope; what the child
      // then renders is not.
      walk_val(d.val, c, root_scope)
      walk_val_opt(d.view_val, c, root_scope)
    }
    RenderIt(d) => walk_val_opt(d.view_val, c, root_scope)
    Show(d) | Hide(d) => {
      walk_val(d.val, c, root_scope)
      walk_node(d.node, c, root_scope, in_loop)
    }
    PushView(d) => {
      walk_val(d.val, c, root_scope)
      walk_node(d.node, c, false, in_loop)
    }
    // A Scope node IS an `@enrich-with` with no `@each` around it: its handler
    // returns the binds rather than mutating a map, which is the whole reason
    // `enrich` and `bind_with` are two buckets.
    Scope(d) => {
      walk_alter(Some(d.val), c.bind_withs)
      walk_val(d.val, c, root_scope)
      walk_node(d.node, c, false, in_loop)
    }
    Slot(d) => walk_node(d.node, c, root_scope, in_loop)
    Each(d) => {
      // The iterated value is read here; the body runs per item.
      walk_val(d.iter_info.val, c, root_scope)
      walk_alter(d.iter_info.when_val, c.whens)
      walk_alter(d.iter_info.loop_with_val, c.loop_withs)
      walk_alter(d.iter_info.enrich_with_val, c.enriches)
      walk_val_opt(d.iter_info.when_val, c, root_scope)
      walk_val_opt(d.iter_info.loop_with_val, c, root_scope)
      walk_val_opt(d.iter_info.enrich_with_val, c, root_scope)
      // `<x render-each>` renders each item as a component in its own frame
      // and drops the `<x>` element, so there is no host element to carry an
      // id — only a host-element loop repeats markup written here.
      walk_node(d.node, c, false, in_loop || !d.from_render_each)
    }
    MacroCall(d) =>
      match d.node {
        Some(n) => walk_node(n, c, root_scope, in_loop)
        None => ()
      }
  }
}

// ---------------------------------------------------------------------------
// Argument-shape inference

///|
/// What `value` decodes to for THIS element, when that differs from the
/// default text read: the glue delivers a checkbox's checked state (Bool)
/// and a file input's metadata Map / Null (Value) — keep in sync with
/// `event_value` in the app glue. Only a STATIC `type` attribute is visible
/// here; a dynamic `:type` keeps the default `String` inference.
fn value_arg_kind(d : @anode.DomData) -> ArgType? {
  guard d.tag == "input" else { return None }
  match static_attr(d.attrs, "type") {
    Some("checkbox") => Some(VBool)
    Some("file") => Some(VValue)
    _ => None
  }
}

///|
/// A constant string attribute's value, whichever attrs representation the
/// element ended up with.
fn static_attr(attrs : @anode.Attrs, name : String) -> String? {
  match attrs {
    ConstAttrs(m) =>
      match m.get(name) {
        Some(LStr(s)) => Some(s)
        _ => None
      }
    DynAttrs(items) => {
      for it in items {
        if it is ConstA(name=n, val=ELit(lit=LStr(s), ..)) && n == name {
          return Some(s)
        }
      }
      None
    }
  }
}

///|
/// The element's `data-eid` stamp — the key into its NodeEvents entry.
fn eid_of(attrs : @anode.Attrs) -> Int? {
  match attrs {
    ConstAttrs(m) =>
      match m.get("data-eid") {
        Some(LNum(n)) => Some(n.to_int())
        _ => None
      }
    DynAttrs(items) => {
      for it in items {
        if it is ConstA(name="data-eid", val=ELit(lit=LNum(n), ..)) {
          return Some(n.to_int())
        }
      }
      None
    }
  }
}

///|
/// The type a handler argument decodes to, from the value written at the call
/// site. A bare name in argument position is a DOM event field (the
/// `known_handler_arg_names` vocabulary the linter checks) — keep this table
/// in sync with `event_field` in render/dom_event.mbt. `@value` and friends
/// are binds, whose contents are not statically known. `value_kind` is what
/// the `value` arg decodes to on the HOST element (String by default; Bool on
/// a checkbox, Value on a file input — see `value_arg_kind`).
fn arg_type_of(val : @tutuca.Val, value_kind : ArgType) -> ArgType {
  match val {
    ELit(lit=LNum(_), ..) => VDouble
    ELit(lit=LStr(_), ..) => VString
    ELit(lit=LBool(_), ..) => VBool
    // A rooted one-segment path decodes through the accessor table, including
    // the `value_kind` the host element's static `type` attribute decided.
    EEventPath(segments=[one], ..) => accessor_type(one, value_kind)
    // A longer path is a layer-2 read, and nothing knows its type: the DOM
    // property table could answer for a rooted one, but not for a path through
    // `detail` or `dataset`, where the shape is the application's. `Value` is
    // the honest answer for all of them.
    EEventPath(segments=_, ..) => VValue
    _ => VValue
  }
}

///|
/// The type one of layer 1's computed accessors decodes to.
fn accessor_type(name : String, value_kind : ArgType) -> ArgType {
  match name {
    "value" => value_kind
    "key" => VString
    "valueAsInt" | "valueAsFloat" | "keyCode" => VDouble
    "isAlt"
    | "isShift"
    | "isCtrl"
    | "isCmd"
    | "isUpKey"
    | "isDownKey"
    | "isSend"
    | "isCancel"
    | "isTabKey" => VBool
    // The drag names answer Null when no drag is in flight, so none of
    // them is the unwrapped type it looks like — `dragKey` is a Value the
    // way `@key` is, and `dragType` is only a String mid-drag.
    "dragInfo" | "dragKey" | "dragValue" | "dragType" => VValue
    _ => VValue
  }
}

///|
/// The three things an `@on` argument can be wrong about.
///
/// All three are about the `e.` boundary, which is why they are here rather
/// than in `tscript/check`: that package checks the BLOCK language, and a call
/// site is written in a view.
///
/// One is fatal and two are hints, and the split is the same one `docs/` uses
/// for every diagnostic that touches existing code — a rule whose warned-about
/// code already works cannot break a build on the day it lands.
fn check_event_arg(
  val : @tutuca.Val,
  view_name : String,
  site : String,
  hints : Array[String],
) -> Unit raise GenError {
  match val {
    EEventPath(segments~, ..) => {
      let path = "e." + segments.join(".")
      // OFF-LIST STEP — a HINT, not an error. These views are the author's
      // own code: any path resolves at run time (the OPEN profile), and an
      // author who wanted `e.target.form.action` could have written the same
      // read in JS. What the list still governs is guest-supplied views, and
      // THAT is where the step is refused — a host holds its policy's
      // `event_paths` profile to the allowlist and refuses the bundle at
      // registration, naming this same step. So the generator advises rather
      // than gates: it names the step, the six that survive the safe profile,
      // and who will refuse it.
      //
      // The same finding exists as a lint (`EventPathUnsafeStep`) for callers
      // that report through findings instead of a generation run.
      match @eventpath.EventPathProfile::allows(Safe, segments) {
        BadStep(step~, index~) =>
          hints.push(
            "view \{view_name}: `\{site}=\"… \{path}\"` — `\{step}` (at \{index}) is off the event-path allowlist. It resolves here, but a host compiling guest-supplied views refuses it: every step through a host object must be one of " +
            @eventpath.event_object_steps.join(", "),
          )
        PathOk => ()
      }
      // UNKNOWN_EVENT_PROP — a HINT. `e.target.someVendorThing` may be
      // deliberate, and `e.target.valeu` is a typing mistake; the difference
      // is not one a generator can tell, so it names the closest match and
      // leaves the decision.
      //
      // Asked of the ROOT segment only, and against the union of every
      // interface the table carries rather than against the one this event
      // actually is. Mapping `@on.click` to `MouseEvent` needs a second
      // generated table (webref's `ed/events/`), and the union already catches
      // the case worth catching — a name no event interface anywhere has.
      guard segments.length() == 1 else { return }
      let name = segments[0]
      if is_known_event_root(name) {
        return
      }
      let near = @statedef.nearest(name, event_root_names())
      let did_you_mean = match near {
        Some(alt) => " — did you mean `e." + alt + "`?"
        None => ""
      }
      hints.push(
        "view \{view_name}: `\{site}=\"… \{path}\"` — no event interface has a `\{name}` property\{did_you_mean}",
      )
    }
    // BARE_ARG — an ERROR, and it has to be one.
    //
    // A bare name in an argument slot names nothing: the resolver has no
    // scope to look it up in and answers `Null`, the dispatch lands, and the
    // handler is handed a hole. Nothing reports it at run time, which is
    // exactly the failure a generator is for.
    EName(name~, ..) => raise BareEventArg(view=view_name, name~, site~)
    _ => ()
  }
}

///|
/// Every name a rooted one-segment `e.` path may legitimately carry: the
/// framework's computed accessors, plus every property any event interface in
/// the generated table declares.
///
/// The accessors have to be in it because they are not properties of anything
/// — `e.value` is computed by the glue and a DOM `Event` has no `value` at all
/// — so a check against the specifications alone would warn about the most
/// common read in the language.
fn event_root_names() -> Array[String] {
  let out : Array[String] = @eventpath.event_accessors.copy()
  for row in @eventpath.dom_interfaces {
    // Only the EVENT side of the table: an `Element`'s properties are reachable
    // through `e.target`, not off the root.
    if row.0.has_suffix("Event") {
      for p in @eventpath.dom_props_of(row.0) {
        if !out.contains(p) {
          out.push(p)
        }
      }
    }
  }
  out
}

///|
fn is_known_event_root(name : String) -> Bool {
  event_root_names().contains(name)
}

///|
/// Join two observations of the same argument position: agreement keeps the
/// type, disagreement falls back to the raw Value.
fn join_arg(a : ArgType, b : ArgType) -> ArgType {
  if a == b {
    a
  } else {
    VValue
  }
}

// ---------------------------------------------------------------------------

///|
/// The surface a set of views needs, built straight from their source.
///
/// `state` carries the same weight it does in `build_views`: bind lowering
/// rewrites the handler an `@bind` element raises, so a surface computed
/// without the schema is both refused (when the file uses `@bind`) and wrong
/// (if it were not).
pub fn view_surface(
  views : Array[@viewfile.RawView],
  macros? : Array[@viewfile.MacroDef] = [],
  state? : @statedef.StateDef? = None,
) -> Surface raise GenError {
  let scope = FileMacros::of(macros)
  let compiled = compile_views(views, scope)
  lower_binds(compiled, state)
  surface_of(compiled)
}

///|
/// The walk half of `view_surface`, over ONE already-compiled view.
///
/// Split out because the IR emitter has the trees already: it compiles every
/// view to emit its builders, and re-parsing them here to answer which buckets
/// the wrapper needs would put the third parse per view back that
/// benchmarks/OPTIMIZATIONS.md #1 took out.
fn walk_view(
  view_name : String,
  root : @anode.ANode,
  events : Array[@anode.NodeEvents],
  c : Collect,
  inputs : Map[String, InputSig],
) -> Unit raise GenError {
  // Eids restart at 0 for every view's ParseContext, so a stale entry from
  // the previous view must not leak into this one's events pass.
  c.value_kinds.clear()
  walk_node(root, c, true, false)
  if c.loop_ids.length() > 0 {
    // Sorted so the message does not depend on set iteration order.
    raise IdInLoop(view=view_name, id=sorted(c.loop_ids)[0])
  }
  for ev in events {
    for h in ev.handlers {
      let site = "@on." + h.name
      match h.handler.action {
        Some(PropertySet(value~, ..)) => {
          walk_val(value, c, false)
          check_event_arg(value, view_name, site, c.hints)
        }
        Some(PropertyCall(args~, ..)) =>
          for arg in args {
            walk_val(arg, c, false)
            check_event_arg(arg, view_name, site, c.hints)
          }
        Some(PropertyReset(_)) | None => ()
      }
      // A `$name` here is REFUSED, and `@anode.NodeEvent::method_in_event` is
      // where the rule lives — the same one `ComponentStack::check_names` runs
      // over a view that arrives at runtime, which this generator never sees.
      if h.method_in_event() is Some(name) {
        raise MethodInEventPosition(view=view_name, name~, site~)
      }
      match h.handler.handler {
        EName(name~, ..) => {
          let value_kind = c.value_kinds.get(ev.id).unwrap_or(VString)
          let shape = h.handler.args.map(a => arg_type_of(a, value_kind))
          for a in h.handler.args {
            walk_val(a, c, false)
            check_event_arg(a, view_name, site, c.hints)
          }
          match inputs.get(name) {
            None => inputs[name] = { name, args: Some(shape), sites: [site], }
            Some(prev) => {
              let args = match prev.args {
                Some(p) if p.length() == shape.length() =>
                  Some(p.mapi((i, t) => join_arg(t, shape[i])))
                // Arity disagrees: the variant carries the raw args.
                _ => None
              }
              if !prev.sites.contains(site) {
                prev.sites.push(site)
              }
              inputs[name] = { ..prev, args, }
            }
          }
        }
        _ => ()
      }
    }
  }
}

///|
/// The collected sets as a `Surface`, sorted.
fn finish_surface(c : Collect, inputs : Map[String, InputSig]) -> Surface {
  {
    inputs: sorted_by_name(inputs),
    methods: sorted(c.methods),
    fields: sorted(c.fields),
    ids: sorted(c.ids),
    whens: sorted(c.whens),
    enriches: sorted(c.enriches),
    bind_withs: sorted(c.bind_withs),
    loop_withs: sorted(c.loop_withs),
    // NOT sorted: a hint reads best in the order the views were walked, which
    // is the order an author reads the file.
    hints: c.hints,
  }
}

///|
/// Sorts through `lexical_compare`: plain `Array[String]::sort()` is a silent
/// no-op here, because that is what String's own `Compare` impl does.
fn sorted(s : @set.Set[String]) -> Array[String] {
  let out = s.to_array()
  out.sort_by((a, b) => a.lexical_compare(b))
  out
}

///|
fn sorted_by_name(m : Map[String, InputSig]) -> Array[InputSig] {
  let names : Array[String] = []
  for k, _ in m {
    names.push(k)
  }
  names.sort_by((a, b) => a.lexical_compare(b))
  names.map(n => m.get(n).unwrap())
}

///|
/// A `<x:name>` with no matching declaration does NOT fail the parse: anode
/// expands it to a `bad macro: name` comment, which would ship a silently
/// broken view. Check the names against what the file declared instead, and
/// turn a miss into a generation error naming the fix.
fn check_macros_resolved(
  vname : String,
  px : @anode.ParseContext,
  scope : FileMacros,
) -> Unit raise GenError {
  for node in px.macro_nodes {
    if node is MacroCall(d) && !scope.by_name.contains(d.name) {
      raise ViewParseIssue(
        view=vname,
        issue="no macro named '\{d.name}' — declare it as <template id=\"macro:\{d.name}\">",
      )
    }
  }
}
