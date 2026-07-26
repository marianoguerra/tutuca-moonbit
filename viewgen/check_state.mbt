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
  view : String
}

///|
/// Check every view of one component against its schema.
fn check_views(
  views : Array[RawView],
  macros : Array[MacroDef],
  def : @statedef.StateDef,
) -> Unit raise GenError {
  let scope = FileMacros::of(macros)
  for view in views {
    // Compiled again rather than shared with view_surface: a ParseContext is
    // consumed by compilation, and a second parse of an already-validated
    // view costs far less than threading the first one through two walks
    // with different needs.
    let collector = IssueCollector::{ issues: [] }
    let px = @anode.ParseContext::new(handler=collector)
    let v = @anode.View::new(view.name, raw_view=view.source)
    v.compile(px, scope) catch {
      RecursiveMacro(name) =>
        raise ViewParseIssue(view=view.name, issue="recursive macro '\{name}'")
    }
    guard v.anode is Some(root) else { raise EmptyView(view.name) }
    let c = Checker::{ def, view: view.name }
    c.node(root, { self_ty: SState, item: SOpaque })
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
        SState => self.def.field(name).map(f => f.ty)
        STy(t) => self.def.field_of(t, name)
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
      if name == "value" && sc.item is STy(t) {
        self.def.field_of(t, prop)
      } else {
        None
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
          if self.def.field(name) is None {
            let known = self.def.fields.map(f => f.name)
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
              scope=t.show_wit(),
              suggestion=self.members_of(t)
                |> fn(ns) { @statedef.nearest(name, ns) },
            )
          }
        SOpaque => ()
      }
    BindMember(name~, prop~) =>
      if name == "value" && sc.item is STy(t) {
        if self.def.field_of(t, prop) is None {
          raise UnknownStateField(
            view=self.view,
            name=prop,
            scope="the loop item (\{t.show_wit()})",
            suggestion=self.members_of(t)
              |> fn(ns) { @statedef.nearest(prop, ns) },
          )
        }
      }
    SeqAccess(seq~, ..) => self.val(Field(seq), sc)
    StrTpl(parts) =>
      for p in parts {
        if p is Some(v) {
          self.val(v, sc)
        }
      }
    Predicate(args~, ..) =>
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
          RawHtml(val~) => self.val_opt(val, sc)
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
      if self.ty_of(d.val, sc) is Some(t) && !t.is_renderable() {
        raise NotRenderable(
          view=self.view,
          expr=expr_src(d.val),
          ty=t.show_wit(),
        )
      }
    }
    RenderIt(d) => self.val_opt(d.view_val, sc)
    Show(d) | Hide(d) => {
      self.val(d.val, sc)
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
      let item = match self.ty_of(it.val, sc) {
        Some(t) =>
          match t.elem() {
            Some(TAny) => SOpaque
            Some(e) => STy(e)
            None =>
              raise NotIterable(
                view=self.view,
                expr=expr_src(it.val),
                ty=t.show_wit(),
              )
          }
        None => SOpaque
      }
      // Inside a loop `.field` still addresses the item, and `@value` names
      // it too — the two spellings reach the same place.
      self.node(d.node, { self_ty: item, item })
    }
    MacroCall(d) => if d.node is Some(n) { self.node(n, sc) }
    RenderOnce(d) => self.node(d.node, sc)
  }
}
