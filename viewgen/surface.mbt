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
// -> HandlerName(ns=Input), `$name` -> Method), so there is no attribute
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
priv struct NoMacros {}

///|
impl @anode.MacroScope for NoMacros with fn lookup_macro(_self, _name) {
  None
}

///|
fn value_issue_message(role : @tutuca.IssueRole) -> String {
  match role {
    BadMacroVar => "unknown macro variable"
    BadHandlerName => "not a valid handler name"
    BadHandlerArg => "not a valid handler argument"
    UnknownPredicate => "unknown predicate"
    PredicateArity(p) => "wrong number of arguments for '\{p.name()}'"
    BadPredicateArg => "not a valid predicate argument"
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
    XOpIgnoresChildren(op~) => "<x \{op}> ignores its children"
    BadValue(role~, value~) => {
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
/// Every `$name` a value reaches, and — when `root_scope` — every state field
/// it reads.
fn walk_val(
  val : @tutuca.Val,
  methods : @set.Set[String],
  fields : @set.Set[String],
  root_scope : Bool,
) -> Unit {
  match val {
    Method(name) => methods.add(name)
    Field(name) => if root_scope { fields.add(name) }
    SeqAccess(seq~, key~) =>
      if root_scope {
        fields.add(seq)
        fields.add(key)
      }
    StrTpl(parts) =>
      for p in parts {
        match p {
          Some(v) => walk_val(v, methods, fields, root_scope)
          None => ()
        }
      }
    Predicate(args~, ..) =>
      for a in args {
        walk_val(a, methods, fields, root_scope)
      }
    _ => ()
  }
}

///|
fn walk_val_opt(
  val : @tutuca.Val?,
  methods : @set.Set[String],
  fields : @set.Set[String],
  root_scope : Bool,
) -> Unit {
  match val {
    Some(v) => walk_val(v, methods, fields, root_scope)
    None => ()
  }
}

///|
/// Attribute values, plus the constant `id` this element declares.
fn walk_attrs(
  attrs : @anode.Attrs,
  methods : @set.Set[String],
  fields : @set.Set[String],
  ids : @set.Set[String],
  root_scope : Bool,
) -> Unit {
  match attrs {
    ConstAttrs(m) =>
      for k, lit in m {
        if k == "id" && lit is LStr(v) {
          ids.add(v)
        }
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => {
            if name == "id" && val is Const(lit=LStr(v), ..) {
              ids.add(v)
            }
            walk_val(val, methods, fields, root_scope)
          }
          RawHtml(val~) => walk_val_opt(val, methods, fields, root_scope)
          If(a) => {
            walk_val(a.cond_val, methods, fields, root_scope)
            walk_val_opt(a.then_val, methods, fields, root_scope)
            walk_val_opt(a.else_val, methods, fields, root_scope)
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
fn walk_node(
  node : @anode.ANode,
  methods : @set.Set[String],
  fields : @set.Set[String],
  ids : @set.Set[String],
  root_scope : Bool,
) -> Unit {
  match node {
    Text(_) | Comment(_) => ()
    Dom(d) => {
      walk_attrs(d.attrs, methods, fields, ids, root_scope)
      for c in d.childs {
        walk_node(c, methods, fields, ids, root_scope)
      }
    }
    Fragment(d) =>
      for c in d.childs {
        walk_node(c, methods, fields, ids, root_scope)
      }
    RenderText(d) => walk_val(d.val, methods, fields, root_scope)
    Render(d) => {
      // The value naming the child IS read in this scope; what the child
      // then renders is not.
      walk_val(d.val, methods, fields, root_scope)
      walk_val_opt(d.view_val, methods, fields, root_scope)
    }
    RenderIt(d) => walk_val_opt(d.view_val, methods, fields, root_scope)
    Show(d) | Hide(d) => {
      walk_val(d.val, methods, fields, root_scope)
      walk_node(d.node, methods, fields, ids, root_scope)
    }
    PushView(d) | Scope(d) => {
      walk_val(d.val, methods, fields, root_scope)
      walk_node(d.node, methods, fields, ids, false)
    }
    Slot(d) => walk_node(d.node, methods, fields, ids, root_scope)
    Each(d) => {
      // The iterated value is read here; the body runs per item.
      walk_val(d.iter_info.val, methods, fields, root_scope)
      walk_val_opt(d.iter_info.when_val, methods, fields, root_scope)
      walk_val_opt(d.iter_info.loop_with_val, methods, fields, root_scope)
      walk_val_opt(d.iter_info.enrich_with_val, methods, fields, root_scope)
      walk_node(d.node, methods, fields, ids, false)
    }
    MacroCall(d) =>
      match d.node {
        Some(n) => walk_node(n, methods, fields, ids, root_scope)
        None => ()
      }
    RenderOnce(d) => walk_node(d.node, methods, fields, ids, root_scope)
  }
}

// ---------------------------------------------------------------------------
// Argument-shape inference

///|
/// The type a handler argument decodes to, from the value written at the call
/// site. A bare name in argument position is a DOM event field (the
/// `known_handler_arg_names` vocabulary the linter checks) — keep this table
/// in sync with `event_field` in render/dom_event.mbt. `@value` and friends
/// are binds, whose contents are not statically known.
fn arg_type_of(val : @tutuca.Val) -> ArgType {
  match val {
    Const(lit=LNum(_), ..) => VDouble
    Const(lit=LStr(_), ..) => VString
    Const(lit=LBool(_), ..) => VBool
    Name(name) =>
      match name {
        "value" | "key" => VString
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
        _ => VValue
      }
    _ => VValue
  }
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
pub fn view_surface(views : Array[RawView]) -> Surface raise GenError {
  let methods = @set.Set::Set([], capacity=8)
  let fields = @set.Set::Set([], capacity=8)
  let ids = @set.Set::Set([], capacity=8)
  // Insertion-ordered so the emitted variants follow first use, and the
  // signature of a name seen in two views is the join of both.
  let inputs : Map[String, InputSig] = Map([])
  for view in views {
    let collector = IssueCollector::{ issues: [] }
    let px = @anode.ParseContext::new(handler=collector)
    let v = @anode.View::new(view.name, raw_view=view.source)
    v.compile(px, NoMacros::{  }) catch {
      RecursiveMacro(name) =>
        raise ViewParseIssue(view=view.name, issue="recursive macro '\{name}'")
    }
    if collector.issues.length() > 0 {
      raise ViewParseIssue(view=view.name, issue=collector.issues[0])
    }
    guard v.anode is Some(root) else { raise EmptyView(view.name) }
    walk_node(root, methods, fields, ids, true)
    for ev in px.events {
      for h in ev.handlers {
        let site = "@on." + h.name
        match h.handler.handler {
          // A `$name` in event position dispatches through the same bucket
          // as a mutate/compute/swap call (component/instance.mbt), so it is
          // a method reference, not an input.
          Method(name) => methods.add(name)
          HandlerName(name~, ..) => {
            let shape = h.handler.args.map(arg_type_of)
            for a in h.handler.args {
              walk_val(a, methods, fields, false)
            }
            match inputs.get(name) {
              None => inputs[name] = { name, args: Some(shape), sites: [site] }
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
  {
    inputs: sorted_by_name(inputs),
    methods: sorted(methods),
    fields: sorted(fields),
    ids: sorted(ids),
  }
}

///|
/// NOTE: plain `Array[String]::sort()` is a silent no-op here — String's
/// `Compare` impl is deprecated in favour of `lexical_compare`.
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
