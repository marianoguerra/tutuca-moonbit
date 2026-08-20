// App-layer event wiring: the scope-chain intent registry adapter, event
// modifiers, and the dispatch pipeline —
// reconstruct an event path from a DOM node, evaluate the handler's parsed
// args (DOM InputEvent lookups like `value`/`key`/`isCtrl` via
// render/dom_event) against the rebuilt render stack, and dispatch through
// the transactor. The App struct itself (compile/start/onChange→morph)
// lives in loop.mbt and calls into this file.

///|
/// The lexical LEG of an intent's route, adapted onto the transactor's
/// registry trait.
///
/// It answers with the whole chain rather than with one handler, because a
/// declining handler hands the intent to its parent scope. Resolution goes through the component's REGISTRATION scope
/// rather than its instance — which is where the scope's handlers live,
/// and the one thing about the `lex` leg that did not change.
pub(all) struct ScopeIntents {
  comps : @component.Components
}

///|
pub impl @transactor.Intents for ScopeIntents with fn intents_for(
  self,
  leaf,
  name,
) {
  guard self.comps.get_comp_for(leaf) is Some(comp) else { return [] }
  guard comp.scope is Some(scope) else { return [] }
  scope
  .lookup_intent(name)
  .map(h => {
    let IntentFn(f) = h
    IntentHandler(f)
  })
}

///|
/// Event-modifier gating (JS compileModifiers, anode.js:809): each modifier
/// is a predicate on the event; a failing one makes the handler a no-op.
/// Only keydown and click define modifiers; unknown pairs pass (identity).
fn modifiers_pass(
  event_name : String,
  modifiers : Array[String],
  e : @render.DomEvent,
) -> Bool {
  for m in modifiers {
    let ok = match (event_name, m) {
      ("keydown", "send") => e.key == "Enter"
      ("keydown", "cancel") => e.key == "Escape"
      ("keydown", "ctrl") | ("keydown", "cmd") => e.ctrl_or_cmd
      ("click", "ctrl") | ("click", "cmd") => e.ctrl_or_cmd
      ("keydown", "meta") | ("click", "meta") => e.meta
      ("keydown", "alt") | ("click", "alt") => e.alt
      _ => true
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// Event dispatch (the JS App._dispatchEvent core): reconstruct the path,
/// gate each matched handler on its modifiers, evaluate its parsed args
/// against the rebuilt stack CARRYING the event (so `value`/`key`/`isCtrl`
/// resolve), push through the Input channel, and drain. Returns false when
/// reconstruction found no handler.
fn[N : @vdom.DomWalk] dispatch_event(
  tx : @transactor.Transactor,
  node : N,
  e : @render.DomEvent,
  root_node : N,
  comps : @component.Components,
) -> Bool {
  guard @render.from_node_and_event_name(node, e.name, root_node, comps)
    is Some(ed) else {
    return false
  }
  if ed.handlers.is_empty() {
    return false
  }
  run_handlers(tx, ed, e, comps)
  true
}

///|
/// The handler loop shared by plain and drag dispatch: gate on modifiers,
/// evaluate parsed args against the rebuilt stack CARRYING the event, push
/// through the Input channel, drain.
fn run_handlers(
  tx : @transactor.Transactor,
  ed : @render.EventDispatch,
  e : @render.DomEvent,
  comps : @component.Components,
) -> Unit {
  let root_stack = @render.RenderStack::new(tx.root, comps~, event=e)
  let arg_stack = @render.build_stack(ed.path.to_transaction_path(), root_stack)
  for h in ed.handlers {
    if !modifiers_pass(e.name, h.modifiers, e) {
      continue
    }
    let name = match h.handler.handler {
      HandlerName(name~, ..) => name
      Method(m) => m
      _ => continue
    }
    let args : Array[@tutuca.Value] = []
    match arg_stack {
      Some(st) =>
        for a in h.handler.args {
          args.push(a.eval(st))
        }
      None => ()
    }
    // A view raises a MESSAGE, addressed to the component that owns the view:
    // that is what `send` means, so there is no separate bucket for one. The
    // early exit above — `stop_on_no_event` in
    // `render/from_node_and_event_name` — is untouched, so an unanswered name
    // still costs one lookup.
    let _ = tx.push_send(ed.path, name, args)
  }
  tx.settle() |> ignore
}

///|
/// Name-only sugar over dispatch_event.
pub fn[N : @vdom.DomWalk] dispatch_dom_event(
  tx : @transactor.Transactor,
  node : N,
  event_name : String,
  root_node : N,
  comps : @component.Components,
) -> Bool {
  dispatch_event(
    tx,
    node,
    @render.DomEvent::new(name=event_name),
    root_node,
    comps,
  )
}
