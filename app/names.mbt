// The name-resolution seam, wired: the two environments a route walks, for the
// questions `Intents` does not answer.
//
// This is the only place that can answer them. The `dyn` leg is the RENDER
// ancestry, which needs the renderer; the `lex` leg is the registration scope,
// which needs the component layer; and `transactor` imports neither. The app
// has both, so the adapter lives here beside `ScopeIntents`.

///|
/// `@transactor.Names` over the component registry and the renderer.
///
/// The memo is the one thing worth explaining. A handler is never handed the
/// stack that evaluated its arguments — that stack is a local in the dispatch
/// pipeline and is gone by the time the body runs, and a `send` or an `intent`
/// transaction never built one at all. So the `dyn` leg REBUILDS it from the
/// two halves the transaction still holds, and a handler that asks twice would
/// otherwise pay for it twice. One slot is enough: the calls that repeat are
/// the ones inside a single handler body, at one root and one position.
pub(all) struct ScopeNames {
  comps : @component.Components
  mut memo_root : @tutuca.Value?
  mut memo_at : @tutuca.DispatchPath?
  mut memo_stack : @render.RenderStack?
}

///|
pub fn ScopeNames::new(comps : @component.Components) -> ScopeNames {
  { comps, memo_root: None, memo_at: None, memo_stack: None, }
}

///|
/// The render stack at `at`, rebuilt from `root`.
///
/// It replays the per-item bindings (`@each`, `@enrich-with`) too, which is
/// new and falls out of the re-cut rather than being added: a binding is a
/// `FrameBind` beside a frame's items now, so COMPACTING a path — which
/// projects each step onto what it addresses — no longer throws the bindings
/// away. The JS original's limit was a consequence of binds pretending to be
/// steps, and it went with them.
fn ScopeNames::stack_at(
  self : ScopeNames,
  root : @tutuca.Value,
  at : @tutuca.DispatchPath,
) -> @render.RenderStack? {
  match (self.memo_root, self.memo_at, self.memo_stack) {
    (Some(r), Some(a), Some(s)) =>
      if physical_equal(r, root) && a == at {
        return Some(s)
      }
    _ => ()
  }
  let base = @render.RenderStack::new(root, comps=self.comps)
  let built = @render.build_dispatch_stack(at, base)
  self.memo_root = Some(root)
  self.memo_at = Some(at)
  self.memo_stack = built
  built
}

///|
/// The component whose handler is running: the innermost component instance on
/// this position's chain.
fn ScopeNames::comp_at(
  self : ScopeNames,
  root : @tutuca.Value,
  at : @tutuca.DispatchPath,
) -> @component.Component? {
  let chain = at.to_transaction_path().resolve_chain(root)
  for i = chain.length() - 1; i >= 0; i = i - 1 {
    match self.comps.get_comp_for(chain[i]) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  None
}

///|
pub impl @transactor.Names for ScopeNames with fn dyn_value(
  self,
  root,
  at,
  name,
) {
  match self.stack_at(root, at) {
    Some(s) =>
      match @tutuca.Stack::lookup_dynamic(s, name) {
        Null => None
        v => Some(v)
      }
    None => None
  }
}

///|
pub impl @transactor.Names for ScopeNames with fn dyn_type(self, root, at, name) {
  match self.stack_at(root, at) {
    Some(s) => s.lookup_dyn_type(name)
    None => None
  }
}

///|
/// Lexical values are registered as absolute paths from the app state root.
pub impl @transactor.Names for ScopeNames with fn lex_value(
  self,
  root,
  at,
  name,
) {
  guard self.comp_at(root, at) is Some(comp) else { return None }
  guard comp.scope is Some(scope) else { return None }
  guard scope.lookup_path(name) is Some(path) else { return None }
  path.lookup(root)
}

///|
/// The `lex` leg needs no stack: it is the registration scope of the component
/// whose handler is running, which the position alone identifies.
pub impl @transactor.Names for ScopeNames with fn lex_type(self, root, at, name) {
  guard self.comp_at(root, at) is Some(comp) else { return None }
  guard comp.scope is Some(scope) else { return None }
  match scope.lookup_component(name) {
    Some(c) => Some(c.id)
    None => None
  }
}

///|
pub impl @transactor.Names for ScopeNames with fn build(self, id, args) {
  match self.comps.get_component_for_id(id) {
    Some(c) => Some(c.make(args))
    None => None
  }
}
