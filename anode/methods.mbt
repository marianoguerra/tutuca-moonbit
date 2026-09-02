// Method-name collection (spec.mbt ANode::collect_method_names /
// View::collect_method_names). The `$name` twin of classes.mbt: where that
// answers "what classes could this template use", this answers "what does this
// template CALL on the thing it renders", which is what a layer holding a list
// of declared names has to compare against.

///|
/// Every `$name` inside one value, including the ones nested in a `$'…'`
/// template's placeholders and in a predicate's arguments — a method reached
/// through either is called exactly as a bare one is.
fn add_val_methods(val : @tutuca.Val, into : Set[String]) -> Unit {
  match val {
    Method(name) => into.add(name)
    StrTpl(parts) =>
      for part in parts {
        if part is Some(v) {
          add_val_methods(v, into)
        }
      }
    App(args~, ..) =>
      for arg in args {
        add_val_methods(arg, into)
      }
    _ => ()
  }
}

///|
fn add_opt_val_methods(val : @tutuca.Val?, into : Set[String]) -> Unit {
  if val is Some(v) {
    add_val_methods(v, into)
  }
}

///|
fn add_attr_methods(attrs : Attrs, into : Set[String]) -> Unit {
  match attrs {
    // A constant attribute map holds literals; `$name` never collapses into one.
    ConstAttrs(_) => ()
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(val~, ..) | ConstA(val~, ..) => add_val_methods(val, into)
          If(ia) => {
            add_val_methods(ia.cond_val, into)
            add_opt_val_methods(ia.then_val, into)
            add_opt_val_methods(ia.else_val, into)
          }
          RawHtml(val~) | RawMarkdown(val~) | SafeHtml(val~) | SafeSvg(val~) =>
            add_opt_val_methods(val, into)
        }
      }
  }
}

///|
pub fn ANode::collect_method_names(self : ANode, into : Set[String]) -> Unit {
  match self {
    Dom(d) => add_attr_methods(d.attrs, into)
    RenderText(d) => add_val_methods(d.val, into)
    Render(d) => {
      add_val_methods(d.val, into)
      add_opt_val_methods(d.view_val, into)
    }
    RenderIt(d) => add_opt_val_methods(d.view_val, into)
    Show(d) | Hide(d) | PushView(d) | Scope(d) => add_val_methods(d.val, into)
    Each(d) => {
      let info = d.iter_info
      add_val_methods(info.val, into)
      add_opt_val_methods(info.when_val, into)
      add_opt_val_methods(info.loop_with_val, into)
      add_opt_val_methods(info.enrich_with_val, into)
    }
    // A MacroCall's own attrs are source strings replayed into the expansion,
    // and the expansion is its child — walking that is what sees them parsed.
    Text(_) | Comment(_) | Fragment(_) | Slot(_) | MacroCall(_) => ()
  }
  self.for_each_child(child => child.collect_method_names(into))
}

///|
pub fn View::collect_method_names(self : View, into : Set[String]) -> Unit {
  if self.anode is Some(node) {
    node.collect_method_names(into)
  }
  // `@on.x="$name arg"` never reaches the tree: attribute parsing registers it
  // on the ParseContext and leaves a data-eid behind, so a tree walk alone
  // would miss every handler-position method.
  if self.ctx is Some(px) {
    for events in px.events {
      for ev in events.handlers {
        add_val_methods(ev.handler.handler, into)
        for arg in ev.handler.args {
          add_val_methods(arg, into)
        }
      }
    }
  }
}

///|
/// The `$name` a handler puts in an `@on` position, when it does.
///
/// A `$name` here is REFUSED, and the rule belongs with the tree rather than
/// with either checker: `app/app.mbt` collapses `HandlerName` and `Method` into
/// one string and pushes both as the same `Receive`, so the two spellings are
/// the same dispatch — including for the generated mutators, which answer to
/// either. The sigil therefore claims a distinction that does not exist, and
/// readers reasonably infer one. `$` keeps its meaning where it has one: a
/// value position, where there is no event and no ctx and an input handler
/// cannot go.
///
/// Two callers, and that is why it is here: the generator refuses it while
/// compiling a view file, and `ComponentStack::check_names` refuses it for a
/// view that arrives at RUNTIME — a runtime macro expansion, or a guest's
/// manifest — which the generator never sees.
pub fn NodeEvent::method_in_event(self : NodeEvent) -> String? {
  match self.handler.handler {
    Method(name) => Some(name)
    _ => None
  }
}

///|
/// Every `$name` in an `@on` position across a compiled view's events, each
/// with the site that carries it (`@on.click`).
///
/// A LIST rather than the first, because the caller that reads it reports
/// rather than raises: a bundle with three of these should say three things.
pub fn methods_in_events(events : Array[NodeEvents]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for ev in events {
    for h in ev.handlers {
      if h.method_in_event() is Some(name) {
        out.push((name, "@on." + h.name))
      }
    }
  }
  out
}
