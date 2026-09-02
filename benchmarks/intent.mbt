// The DISPATCH workload: what a v2 intent's walk costs, and what a name nobody
// answers costs.
//
// render.mbt measures mount, patch.mbt measures the second render. This
// measures the part between them — the routing — because v2's two design
// claims are both about it and neither was measured:
//
//   - a name nothing answers still costs ONE lookup, as v1's did. This is what
//     makes stop-by-default worth having, so it has to be true.
//   - a default-route intent walks every ancestor and then the whole scope
//     chain, ONE QUEUED TRANSACTION PER HOP. Which is a cost per hop, and the
//     ratio between depths is the number to watch rather than any absolute.
//
// Two legs, two workloads, because they are different machinery:
//
//   - `dyn` walks the dispatch path. `intent_dyn(depth)` mounts a chain of
//     TreeItems `depth` deep (`storybook/examples/communication.mbt`) and
//     clicks the deepest one, which raises `intent dyn 'treeItemSelected'`.
//     Every ancestor between it and the root is an OBSERVER — its `Intent` arm
//     runs and does not reply — so the walk goes the whole way and then runs
//     out. The worst case, deliberately: a walk that stops early measures the
//     hop it stopped at rather than the leg.
//   - `lex` walks the registered handlers. `intent_lex(n)` mounts the request
//     example against a scope holding `n` handlers that answer `Pass` followed
//     by one that answers `Ok`, so `n` is the number of DECLINES before an
//     answer. That chain is the shape a `Pass` makes possible and v1 could not
//     express at all.
//
// Both are round trips in the sense patch.mbt means: the app is mounted once,
// outside the timed region, and each iteration dispatches into it. The tree's
// state does change per click (each item toggles its own `isOpen`), which is a
// patch cost riding along with the walk cost — `intent_dyn_noop` is the same
// click on a chain of depth 1, so the per-hop slope is what to read and not the
// intercept.

///|
/// A chain of TreeItems `depth` deep: each holds exactly one child, so the
/// dispatch path from the leaf to the root has `depth` component steps on it.
///
/// One child rather than a fan-out on purpose. The `dyn` leg walks ANCESTORS,
/// so breadth adds render cost and no hops; a chain is the smallest tree that
/// makes depth the only thing changing.
fn tree_chain(depth : Int) -> @tutuca.Value {
  let item = comp_of(tree_module, "TreeItem")
  let make = (label : String, kids : Array[@tutuca.Value]) => {
    item.make({
      "type": Str(if kids.is_empty() { "file" } else { "dir" }),
      "label": Str(label),
      "isOpen": Bool(true),
      "items": List(kids),
    })
  }
  let mut node = make("leaf", [])
  for i in 1..<depth {
    node = make("level \{depth - i}", [node])
  }
  node
}

///|
/// The chains, built once: a `.make` per level is not what this measures.
let tree_chains : Map[Int, @tutuca.Value] = Map([])

///|
/// A TreeRoot holding a chain `depth` deep, mounted.
pub fn mount_tree_chain(depth : Int) -> @harness.MemHarness {
  let root = items_for(tree_chains, depth, () => tree_chain(depth))
  mounted("tree-chain/\{depth}", tree_module, "TreeRoot", { "root": root })
}

///|
/// Click the DEEPEST item and let the walk run out.
///
/// `.head` renders once per item in document order, root first, so `nth` is the
/// index of the level. The selector walk that finds it grows with depth and is
/// the harness's cost rather than the framework's — `find_cost` is the same
/// walk on its own, for subtracting rather than guessing.
pub fn intent_dyn(h : @harness.MemHarness, depth : Int) -> Int {
  h.click(".head", nth=depth - 1) catch {
    e => fail_patch("intent dyn depth \{depth}", e)
  }
  h.render_count()
}

///|
/// The scope for `intent_lex`: `n` handlers that DECLINE, then one that answers.
///
/// A list per name is what the `lex` leg walks, and `Pass` is what makes a list
/// worth having — a handler that must respond has no way to decline, so one with nothing to
/// contribute could only invent an error and there was nothing to walk past.
fn declining_chain(n : Int) -> Map[String, Array[@component.IntentFn]] {
  let fns : Array[@component.IntentFn] = []
  for _ in 0..<n {
    fns.push(@tutuca.IntentFn((_call, answer) => answer(Pass)))
  }
  fns.push(
    @tutuca.IntentFn((_call, answer) => {
      answer(Ok(List([Map({ "title": Str("row"), "description": Str("") })])))
    }),
  )
  { "loadData": fns }
}

///|
/// The request example, against a scope that declines `n` times first.
pub fn mount_lex_chain(n : Int) -> @harness.MemHarness {
  mounted(
    "lex-chain/\{n}",
    @examples.request_module(intents=declining_chain(n)),
    "RequestExample",
    Map([]),
  )
}

///|
/// Raise `intent lex 'loadData'` and settle the answer.
///
/// `receive init` is what raises it, so this is one `send_at_root` and then the
/// whole walk plus the `loadDataOk` that comes back — which is the round trip a
/// caller actually pays for, not the leg on its own.
pub fn intent_lex(h : @harness.MemHarness) -> Int {
  h.send_at_root("init")
  h.render_count()
}

///|
/// One dispatch of a name the component ANSWERS.
///
/// The counter's `inc` is an ordinary handler, so this is lookup + transition +
/// patch: the baseline the next one is read against.
pub fn dispatch_answered(h : @harness.MemHarness) -> Int {
  h.send_at_root("inc")
  h.render_count()
}

///|
/// One dispatch of a name NOTHING answers.
///
/// Not a handler, not a generated mutator, not a field. The claim is that this
/// costs one lookup and stops — the same shape v1 paid, which is what makes
/// stop-by-default worth having rather than a regression dressed as a
/// simplification. Read against `dispatch_answered`: the difference is a
/// transition and a patch this one does not do, so this number being the
/// SMALLER of the two is the claim holding.
pub fn dispatch_unanswered(h : @harness.MemHarness) -> Int {
  h.send_at_root("noSuchNameAtAll")
  h.render_count()
}

///|
let tree_module : @component.ModuleDef = @examples.tree_module()

///|
/// A scope where EVERY handler declines — the chain with no answer at the end.
///
/// Not a bench workload: `intent_test.mbt` uses it to pin the other end of the
/// same walk, where the route runs out and the sender hears `<name>Unhandled`.
pub fn declining_scope(n : Int) -> Map[String, Array[@component.IntentFn]] {
  let fns : Array[@component.IntentFn] = []
  for _ in 0..<n {
    fns.push(@tutuca.IntentFn((_call, answer) => answer(Pass)))
  }
  { "loadData": fns }
}
