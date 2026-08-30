// The handler-side `Stack`. One seam — `lookup_dynamic` — with two producers:
// the render chain a view is being built on, and the dispatch route a handler
// is already standing on.

///|
/// A `&Ctx` wearing a `&Stack`'s shape, so a `compute` a TRANSITION calls can
/// be handed an environment without the transition having a render stack.
///
/// A value body takes a `&Stack` because it is normally called BY the render
/// stack. A transition that calls one as a sibling is the other caller, and it
/// holds a `&Ctx` instead — the same two environments, asked from a different
/// position: `Ctx::lookup` walks the dispatch route (`dyn` the render
/// ancestry, `lex` the registration scope) and answers what a `*name` in this
/// component's view would answer.
///
/// Only `lookup_dynamic` is implemented. Every other `Stack` method keeps its
/// `Null` default, and that is a statement rather than an omission: a value
/// body reads its state through `s.field` and its row through its own
/// parameters, so `*name` is the only stack question it emits.
///
/// `pub(all)`, because the code that CONSTRUCTS one is generated into somebody
/// else's package: `gen-views` weaves `@tutuca.CtxStack(ctx)` into a handler
/// arm whose `invariant` calls a `pred`, and a plain `pub struct` is read-only
/// outside the package that declares it — so that arm did not compile, with
/// nothing said at generation time and a `moon check` error afterwards. The
/// wrapped `&Ctx` is the whole representation and there is nothing to hide.
pub(all) struct CtxStack(&Ctx)

///|
pub impl Stack for CtxStack with fn lookup_dynamic(self, name) {
  self.0.lookup(name, LookupOpts::new())
}
