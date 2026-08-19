// The dispatch workloads do what they say they do.
//
// A benchmark that measures the wrong thing is worse than no benchmark, and
// these are easy to get wrong in a way no timing would reveal: a chain built
// one level short still clicks something, and a `lex` chain whose declining
// handlers are never reached still answers. So the SHAPE is asserted here and
// the timings are read against it.

///|
test "the dyn chain is as deep as it says, and the click reaches the leaf" {
  let h = @benchmarks.mount_tree_chain(8)
  // One `.head` per level, root first.
  inspect(h.find_all(".head").length(), content="8")
  // …and the last one is the leaf the chain was built with.
  inspect(h.text(".head", nth=7), content="leaf")
  h.destroy()
}

///|
test "the dyn walk reaches the root, from every depth" {
  // The root's `Intent` arm is the only thing that writes `log`, so a log entry
  // naming the clicked item is the proof the walk went all the way up. Without
  // it this bench would be timing a click that toggles one item and stops.
  for depth in [1, 4, 16] {
    let h = @benchmarks.mount_tree_chain(depth)
    let _ = @benchmarks.intent_dyn(h, depth)
    inspect(h.find_all("li").length(), content="1")
    inspect(h.text("li"), content="selected: leaf")
    h.destroy()
  }
}

///|
test "the lex chain declines its way to an answer" {
  // With 0 declines and with 64, the card ends in the same place: the answer
  // arrived. What changes is how many `Pass`es the walk went through to get
  // there, which is the only thing the bench varies.
  for n in [0, 4, 48] {
    let h = @benchmarks.mount_lex_chain(n)
    let _ = @benchmarks.intent_lex(h)
    // The fixture answers one row, and `loadDataOk` turns it into one Entry.
    inspect(h.find_all(".card-title").length(), content="1")
    // …and the loading flag is back off, so the round trip completed.
    inspect(h.find_all(".loading").length(), content="0")
    h.destroy()
  }
}

///|
test "a scope that declines all the way answers Unhandled" {
  // The other end of the same chain, and the one v1 could not reach: every
  // handler passes, the route runs out, and the sender hears `loadDataUnhandled`
  // rather than an error somebody invented.
  let h = @harness.mount(
    @examples.request_module(intents=@benchmarks.declining_scope(8)),
    "RequestExample",
  )
  h.send_at_root("init")
  inspect(h.text(".error"), content="nothing in the scope answers `loadData`")
  inspect(h.find_all(".card-title").length(), content="0")
  h.destroy()
}

///|
test "the unanswered dispatch really is unanswered" {
  let h = @benchmarks.mount_counter()
  let before = h.render_count()
  let _ = @benchmarks.dispatch_unanswered(h)
  // Nothing handled it, nothing mutated, so nothing re-rendered. If a future
  // change made an unmatched name fall through to something, this is the test
  // that notices — and the bench beside it would silently start measuring it.
  inspect(h.render_count() == before, content="true")
  let _ = @benchmarks.dispatch_answered(h)
  inspect(h.render_count() > before, content="true")
  h.destroy()
}

///|
test "INTENT_DEPTH bounds the whole route, and it counts hops" {
  // 64, and it is a budget for the WALK rather than for either leg. Worth
  // pinning because the benchmark sizes are chosen around it and because the
  // number a reader is most likely to assume — "64 ancestors, and separately
  // 64 handlers" — is not the one the transactor implements.
  //
  // A `dyn` chain exactly at the bound walks; one past it does not.
  let at_bound = @benchmarks.mount_tree_chain(64)
  let _ = @benchmarks.intent_dyn(at_bound, 64)
  inspect(at_bound.find_all("li").length(), content="1")
  at_bound.destroy()
  let past_bound = @benchmarks.mount_tree_chain(65)
  let _ = @benchmarks.intent_dyn(past_bound, 65)
  inspect(past_bound.find_all("li").length(), content="0")
  past_bound.destroy()
  // And on the `lex` leg the handler that ANSWERS is a hop like any other, so
  // 64 declines before it is one too many.
  let h = @benchmarks.mount_lex_chain(64)
  let _ = @benchmarks.intent_lex(h)
  inspect(h.find_all(".card-title").length(), content="0")
  // What the sender hears is `loadDataUnhandled` — the same message an honest
  // exhaustion sends. Deliberate (`transactor/walk.mbt`: a sender that asked
  // for an answer learns something rather than waiting forever), and the
  // refusal channel is where the two are told apart: this one also raises
  // `RefusalCode::IntentDepth`, and a plain exhaustion does not.
  inspect(h.text(".error"), content="nothing in the scope answers `loadData`")
  h.destroy()
}

///|
test "a walk of any depth settles into ONE render" {
  // The claim under the `dyn` timings, and the one that makes them readable.
  //
  // Every hop is its own queued transaction, so the obvious worry is that a
  // 64-deep walk repaints 64 times. It does not: the transactor drains the
  // cascade and the app reports a single change, exactly as a `send` that fans
  // out does. So what grows with depth in the benchmark is the cost of
  // rendering a DEEPER TREE, not a repaint per hop — which is why the `lex`
  // rows, whose tree is fixed, are the ones to read a per-hop cost off.
  for depth in [1, 4, 16, 64] {
    let h = @benchmarks.mount_tree_chain(depth)
    let before = h.render_count()
    let _ = @benchmarks.intent_dyn(h, depth)
    inspect(h.render_count() - before, content="1")
    h.destroy()
  }
  for n in [0, 4, 16, 48] {
    let h = @benchmarks.mount_lex_chain(n)
    let before = h.render_count()
    let _ = @benchmarks.intent_lex(h)
    inspect(h.render_count() - before, content="1")
    h.destroy()
  }
}
