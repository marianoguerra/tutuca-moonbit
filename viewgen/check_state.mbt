// Checking a compiled view against the component's state schema.
//
// A SEPARATE walk from `view_surface`'s. That one extracts names and must go
// on working unchanged for every file with no state block; this one only
// runs when there is a schema to check against, and it carries a type
// environment the extractor has no use for.
//
// The environment is what closes the generator's oldest hole. `view_surface`
// stops collecting field reads under `@each`, `@enrich-with`, a push-view or
// an `<x render>`, because down there `.field` addresses the loop item or
// the child component rather than this component's state — and with no types
// there was nothing to check it against. With the element type in hand the
// body is checkable, so `@value.titel` inside a loop is now caught where
// before it was not even looked at.
//
// The rule everywhere is that unknown is not wrong: a `$method` result, a
// dynamic value, a child component's fields and a bind this file cannot see
// all resolve to "opaque", and an opaque scope silences every check inside
// it. A generator that guessed here would cost more in false failures than
// the real ones are worth.

///|
/// What `.field` resolves against in the current scope.
priv enum SelfTy {
  /// The component's own state record.
  SState
  /// A known type — a loop item, or the target of a push-view.
  STy(@statedef.StateTy)
  /// ANOTHER component's state record, reached by iterating a collection whose
  /// element type names a sibling interface. `.field` and `@value.member` down
  /// there address that component's fields, not this one's — which is what the
  /// single-`StateDef` checker could never say, so it said nothing.
  SComp(@statedef.StateDef)
  /// Not statically known. Every check inside is skipped.
  SOpaque
}

///|
/// The scope a node is checked in.
priv struct Scope {
  self_ty : SelfTy
  /// What `@value` binds to, when this scope is a loop body.
  item : SelfTy
}

///|
priv struct Checker {
  def : @statedef.StateDef
  prog : ProgramIndex
  view : String
  /// Findings that are ADVISORY rather than fatal. A view name resolves at
  /// render time against whatever component the registration scope actually
  /// holds, and a slot declared as the bare `component` marker takes its
  /// component from `component()`'s `slots~` — MoonBit this generator cannot
  /// see. So a missing view is reported, not raised: the alternative is a
  /// build that cannot be fixed without a new opt-out.
  hints : Array[String]
}

///|
/// Check every view of one component against its schema.
fn check_views(
  views : Array[CompiledView],
  def : @statedef.StateDef,
  prog : ProgramIndex,
  hints : Array[String],
) -> Unit raise GenError {
  for view in views {
    let c = Checker::{ def, prog, view: view.raw.name, hints, }
    c.node(view.root, { self_ty: SState, item: SOpaque, })
    for events in view.events {
      for handler in events.handlers {
        c.property_action(handler.handler.action)
      }
    }
  }
}

///|
fn Checker::property_action(
  self : Checker,
  action : @tscript.PropertyAction?,
) -> Unit raise GenError {
  guard action is Some(action) else { return }
  let name = match action {
    PropertySet(name~, ..) | PropertyCall(name~, ..) => name
    PropertyReset(name) => name
  }
  guard self.def.member_ty(name) is Some(_) else {
    raise InvalidPropertyAction(
      view=self.view,
      reason="targets unknown member `.\{name}`",
    )
  }
  if self.def.property(name) is Some(p) && !p.writable {
    raise InvalidPropertyAction(
      view=self.view,
      reason="targets read-only property `.\{name}`",
    )
  }
  guard action is PropertyCall(operation~, ..) else { return }
  if self.def.property(name) is Some(_) {
    raise InvalidPropertyAction(
      view=self.view,
      reason="cannot apply `.\{name}.\{operation}` through an explicit property; assign its complete value",
    )
  }
  guard self.def.field(name) is Some(field) else { return }
  let allowed = match field.ty {
    TList(_) =>
      operation
      is ("push"
      | "insertAt"
      | "setAt"
      | "set"
      | "deleteAt"
      | "removeAt"
      | "delete"
      | "remove"
      | "clear")
    TOMap(_) =>
      operation
      is ("setAt"
      | "set"
      | "deleteAt"
      | "removeAt"
      | "delete"
      | "remove"
      | "clear")
    TSet | TFlags(_) =>
      operation is ("add" | "toggle" | "delete" | "remove" | "clear")
    _ => false
  }
  if !allowed {
    raise InvalidPropertyAction(
      view=self.view,
      reason="`.\{name}.\{operation}` does not apply to \{field.ty.show_source()}",
    )
  }
}

///|
/// The type a value has in this scope, or None when it is not statically
/// known. None means "do not check", never "wrong".
fn Checker::ty_of(
  self : Checker,
  val : @tutuca.Val,
  sc : Scope,
) -> @statedef.StateTy? {
  match val {
    Field(name) =>
      match sc.self_ty {
        SState => self.def.member_ty(name)
        STy(t) => self.def.field_of(t, name)
        SComp(d) => d.member_ty(name)
        SOpaque => None
      }
    // `@value` in a loop body. Other binds belong to @enrich-with, which
    // computes them at runtime, so they stay opaque.
    Bind("value") =>
      match sc.item {
        STy(t) => Some(t)
        _ => None
      }
    Bind("key") => Some(TText)
    Bind("index") => Some(TInt(width=32, signed=true))
    BindMember(name~, prop~) =>
      if name != "value" {
        None
      } else {
        match sc.item {
          STy(t) => self.def.field_of(t, prop)
          SComp(d) => d.field(prop).map(f => f.ty)
          _ => None
        }
      }
    SeqAccess(seq~, ..) =>
      // `.seq[.key]` reads one entry out of the collection.
      match self.ty_of(Field(seq), sc) {
        Some(t) => t.elem()
        None => None
      }
    Const(lit~, ..) =>
      match lit {
        LStr(_) => Some(TText)
        LNum(_) => Some(TFloat)
        LBool(_) => Some(TBool)
        _ => None
      }
    _ => None
  }
}

///|
/// How a value reads in a diagnostic, in the source spelling the author
/// wrote it in.
fn expr_src(val : @tutuca.Val) -> String {
  match val {
    Field(n) => "." + n
    Method(n) => "$" + n
    Bind(n) => "@" + n
    BindMember(name~, prop~) => "@" + name + "." + prop
    Dyn(n) => "*" + n
    SeqAccess(seq~, key~) => ".\{seq}[.\{key}]"
    Name(n) => n
    _ => "the expression"
  }
}

///|
/// Every `.field` and `@value.member` a value reads must exist.
fn Checker::val(
  self : Checker,
  val : @tutuca.Val,
  sc : Scope,
) -> Unit raise GenError {
  match val {
    Field(name) =>
      match sc.self_ty {
        SState =>
          if self.def.member_ty(name) is None {
            let known = self.def.fields.map(f => f.name)
            for p in self.def.properties {
              if !known.contains(p.name) {
                known.push(p.name)
              }
            }
            raise UnknownStateField(
              view=self.view,
              name~,
              scope="the \{self.def.component} state",
              suggestion=@statedef.nearest(name, known),
            )
          }
        STy(t) =>
          if self.def.field_of(t, name) is None {
            raise UnknownStateField(
              view=self.view,
              name~,
              scope=t.show_source(),
              suggestion=self.members_of(t)
                |> fn(ns) { @statedef.nearest(name, ns) },
            )
          }
        SComp(d) =>
          if d.member_ty(name) is None {
            raise UnknownStateField(
              view=self.view,
              name~,
              scope="the \{d.component} state",
              suggestion=@statedef.nearest(name, d.fields.map(f => f.name)),
            )
          }
        SOpaque => ()
      }
    BindMember(name~, prop~) =>
      if name == "value" {
        match sc.item {
          STy(t) =>
            if self.def.field_of(t, prop) is None {
              raise UnknownStateField(
                view=self.view,
                name=prop,
                scope="the loop item (\{t.show_source()})",
                suggestion=self.members_of(t)
                  |> fn(ns) { @statedef.nearest(prop, ns) },
              )
            }
          SComp(d) =>
            if d.field(prop) is None {
              raise UnknownStateField(
                view=self.view,
                name=prop,
                scope="the loop item (the \{d.component} component)",
                suggestion=@statedef.nearest(prop, d.fields.map(f => f.name)),
              )
            }
          _ => ()
        }
      }
    SeqAccess(seq~, ..) => self.val(Field(seq), sc)
    StrTpl(parts) =>
      for p in parts {
        if p is Some(v) {
          self.val(v, sc)
        }
      }
    App(args~, ..) =>
      for a in args {
        self.val(a, sc)
      }
    _ => ()
  }
}

///|
/// The field names a type offers, for the "did you mean" tail.
fn Checker::members_of(self : Checker, t : @statedef.StateTy) -> Array[String] {
  match t {
    TRecord(n) =>
      match self.def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) => fs.map(f => f.name)
        _ => []
      }
    _ => []
  }
}

///|
/// `as="edit"` on a render site: does the component being rendered have a view
/// by that name?
///
/// The one check that genuinely needs more than one component's schema. When
/// it fails at run time `best_name` falls through to `main` (render/resolve.mbt)
/// and the site renders the DEFAULT view instead of the one asked for — silent,
/// and wrong in a way that looks like it worked.
///
/// Everything about it is conditional on being sure: the view name must be a
/// constant (a `*dyn` or a field read chooses at run time), the target must be
/// a component this job can see, and it must be one that declares templates
/// here. Anything else is unknown, and unknown is not wrong.
fn Checker::child_view(
  self : Checker,
  comp : String?,
  view_val : @tutuca.Val?,
) -> Unit {
  guard comp is Some(c) else { return }
  guard view_val is Some(Const(lit=LStr(want), ..)) else { return }
  guard self.prog.views.get(c) is Some(names) else { return }
  if names.contains(want) {
    return
  }
  let did_you_mean = match @statedef.nearest(want, names) {
    Some(s) => " — did you mean `\{s}`?"
    None => " (it has \{names.join(", ")})"
  }
  self.hints.push(
    "unknown-child-view (hint) \{self.view}: `as=\"\{want}\"` — the \{c} component has no `\{want}` view\{did_you_mean}",
  )
}

///|
/// The component a scope's `self` is, when that is known.
fn self_comp(sc : Scope) -> String? {
  match sc.self_ty {
    SComp(d) => Some(d.component)
    _ => None
  }
}

///|
/// A value in a boolean position: it must exist, and it must be able to
/// decide something. An unknown type checks the reads and stops there.
fn Checker::boolish(
  self : Checker,
  val : @tutuca.Val,
  directive : String,
  sc : Scope,
) -> Unit raise GenError {
  self.val(val, sc)
  if self.ty_of(val, sc) is Some(t) && !t.is_boolish() {
    raise AlwaysTruthy(
      view=self.view,
      directive~,
      expr=expr_src(val),
      ty=t.show_source(),
    )
  }
}

///|
fn Checker::val_opt(
  self : Checker,
  val : @tutuca.Val?,
  sc : Scope,
) -> Unit raise GenError {
  if val is Some(v) {
    self.val(v, sc)
  }
}

///|
fn Checker::attrs(
  self : Checker,
  attrs : @anode.Attrs,
  sc : Scope,
) -> Unit raise GenError {
  match attrs {
    ConstAttrs(_) => ()
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(val~, ..) | ConstA(val~, ..) => self.val(val, sc)
          RawHtml(val~) | RawMarkdown(val~) | SafeHtml(val~) | SafeSvg(val~) =>
            self.val_opt(val, sc)
          If(a) => {
            self.val(a.cond_val, sc)
            self.val_opt(a.then_val, sc)
            self.val_opt(a.else_val, sc)
          }
        }
      }
  }
}

///|
fn Checker::node(
  self : Checker,
  node : @anode.ANode,
  sc : Scope,
) -> Unit raise GenError {
  match node {
    Text(_) | Comment(_) => ()
    Dom(d) => {
      self.attrs(d.attrs, sc)
      for c in d.childs {
        self.node(c, sc)
      }
    }
    Fragment(d) =>
      for c in d.childs {
        self.node(c, sc)
      }
    RenderText(d) => self.val(d.val, sc)
    Render(d) => {
      self.val(d.val, sc)
      self.val_opt(d.view_val, sc)
      // `<x render>` needs a component instance. A string or a number there
      // renders nothing at all, silently.
      match self.ty_of(d.val, sc) {
        Some(t) => {
          if !t.is_renderable() {
            raise NotRenderable(
              view=self.view,
              expr=expr_src(d.val),
              ty=t.show_source(),
            )
          }
          // `option<comp>` is renderable through its inner type, so ask the
          // type which component it names rather than matching TComp here.
          self.child_view(t.component_named(), d.view_val)
        }
        None => ()
      }
    }
    // `<x render-it>` renders the CURRENT item, so the scope already says
    // which component that is — which is how a `render-each ... as="edit"`
    // gets checked: the loop resolved the element type first.
    RenderIt(d) => {
      self.val_opt(d.view_val, sc)
      self.child_view(self_comp(sc), d.view_val)
    }
    // A predicate (`empty? .alts`) answers a Bool, so `ty_of` returns None for
    // it and the container check below never sees it — which is the point:
    // wrapping the container in a predicate is exactly the fix being asked
    // for.
    Show(d) => {
      self.boolish(d.val, "@show", sc)
      self.node(d.node, sc)
    }
    Hide(d) => {
      self.boolish(d.val, "@hide", sc)
      self.node(d.node, sc)
    }
    // Neither changes what `.field` addresses. `@push-view` pushes a VIEW
    // NAME onto the render stack (render/render.mbt:63 push_view_name) and
    // `@enrich-with` pushes BINDS — the state under both is still this
    // component's, so its fields stay checkable rather than going opaque.
    PushView(d) | Scope(d) => {
      self.val(d.val, sc)
      self.node(d.node, sc)
    }
    Slot(d) => self.node(d.node, sc)
    Each(d) => {
      let it = d.iter_info
      self.val(it.val, sc)
      self.val_opt(it.when_val, sc)
      self.val_opt(it.loop_with_val, sc)
      self.val_opt(it.enrich_with_val, sc)
      // The body's scope is the ELEMENT type — the thing view_surface could
      // never look at.
      //
      // `elem()` answers TAny for a collection of child components, because a
      // StateTy cannot spell "that component's state record". The name is in
      // the type though (`TComp(Some("Todo"))`), so ask the program for the
      // sibling's schema and check the body against it. Absent from the
      // table — an untyped `component` slot, a component this job cannot see —
      // and it stays opaque.
      let item = match self.ty_of(it.val, sc) {
        Some(t) =>
          match t.elem() {
            Some(TComp(Some(c))) =>
              match self.prog.defs.get(c) {
                Some(d) => SComp(d)
                None => SOpaque
              }
            Some(TAny) | Some(TComp(None)) => SOpaque
            Some(e) => STy(e)
            None =>
              raise NotIterable(
                view=self.view,
                expr=expr_src(it.val),
                ty=t.show_source(),
              )
          }
        None => SOpaque
      }
      // Inside a loop `.field` still addresses the item, and `@value` names
      // it too — the two spellings reach the same place.
      self.node(d.node, { self_ty: item, item, })
    }
    MacroCall(d) => if d.node is Some(n) { self.node(n, sc) }
  }
}

///|
/// Check ONE component's views against its schema, and answer the surface its
/// BLOCK should be checked against — from one compile of the templates.
///
/// The two things a caller that holds views and a block both needs.
/// `gen-views` gets them as a side effect of emitting, because
/// `emit_component` compiles every view anyway. A CARD compiles none: its
/// block was checked against a surface that says "I have no views"
/// (`knows_views: false`), which is the honest answer for a caller holding a
/// block alone and a false one for a caller holding the same FILE the views
/// are in. What that cost is three rules that never fired for a card —
/// `NO_VIEW_HANDLER`, the arity cross-check, and the call-site parameter
/// types — plus the view checks in this file, which nothing ran at all.
///
/// The fatal findings RAISE, in the checker's own words; `hints` collects the
/// advisory ones. A caller that reports rather than builds (a live editor) can
/// catch the first and list both.
///
/// `open_senders` is the caller saying whether the views are the only place a
/// message can come from — false for a file the generator owns end to end,
/// true for a card, which a host dispatches into. See
/// `@check.Surface::open_senders`.
pub fn check_component_views(
  views : Array[@viewfile.RawView],
  def : @statedef.StateDef,
  prog : ProgramIndex,
  macros? : Array[@viewfile.MacroDef] = [],
  comps? : Array[String] = [],
  open_senders? : Bool = false,
  hints? : Array[String] = [],
) -> @check.Surface raise GenError {
  let compiled = compile_views(views, FileMacros::of(macros))
  lower_binds(compiled, Some(def))
  check_views(compiled, def, prog, hints)
  { ..inline_surface(surface_of(compiled)), comps, open_senders, }
}
