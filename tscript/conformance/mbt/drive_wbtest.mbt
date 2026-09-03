// The MoonBit backend, run against the corpus.
//
// Over `cases()` and the `Corpus` component. Whitebox because what has to
// agree with the corpus is `corpus_inline_update`, the package-private
// function the wrapper composes, and not the wrapper.

///|
/// A state map in a stable order, for a failure message.
fn show_state(s : Map[String, @tutuca.Value]?) -> String {
  match s {
    None => "(no change)"
    Some(m) => {
      let keys : Array[String] = []
      for k, _ in m {
        keys.push(k)
      }
      keys.sort()
      "{" +
      keys
      .map(k => k + ": " + m.get(k).unwrap().to_repr().to_string())
      .join(", ") +
      "}"
    }
  }
}

///|
fn dispatch_of(c : @conformance.Case, name : String) -> @component.Dispatch {
  match c.bucket {
    BReceive => Receive(name, c.args)
    BIntent => Intent(name, c.args)
  }
}

///|
fn decoded(before : Map[String, @tutuca.Value]) -> CorpusState? {
  @component.Fields::decode(before)
}

///|
test "the MoonBit backend agrees with the v2 corpus" {
  let failures : Array[String] = []
  let refused : Array[String] = []
  // A contract that does not hold reports, which is the feature and is pinned
  // beside each backend. Here it is only noise between the rows.
  let said = @tutuca.warn_hook.val
  @tutuca.warn_hook.val = _ => ()
  defer {
    @tutuca.warn_hook.val = said
  }
  for i, c in @conformance.cases() {
    guard v2_case_name(i) is Some(name) else {
      failures.push("\{c.name}: the projection left this case out")
      continue
    }
    guard decoded(c.before) is Some(before) else {
      failures.push("\{c.name}: the corpus's `before` does not fit CorpusState")
      continue
    }
    let rec = Recorder::new()
    let got = corpus_inline_update(before, dispatch_of(c, name), rec)
    // `Unhandled` from an emitted arm is impossible — an arm answers `Next` or
    // `Unchanged` — so it means the catch-all ran. That is either a refusal or
    // a name this component deliberately does not answer, and the corpus says
    // which: a case whose `after` is None EXPECTS nothing to happen.
    if got is Unhandled {
      if c.after is None && c.effects.is_empty() {
        // The case is about a name no arm answers, and no arm answered it.
        continue
      }
      refused.push(c.name)
      continue
    }
    let after : Map[String, @tutuca.Value]? = match got {
      Next(s2) => Some(@component.Fields::encode(s2))
      _ => None
    }
    if after != c.after {
      failures.push(
        "\{c.name}: expected \{show_state(c.after)}, got \{show_state(after)}",
      )
    }
    let want = c.effects.map(e => e.printed())
    if rec.seen != want {
      failures.push(
        "\{c.name}: expected effects [\{want.join(", ")}], got [\{rec.seen.join(", ")}]",
      )
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
  // Pinned so the reserved set may shrink and a growth is a regression. ZERO
  // is the number worth having: every case is written against the corpus's own
  // vocabulary rather than against this backend, so a refusal means the
  // backend cannot express something the corpus states.
  @debug.assert_eq(refused.length(), 0, msg=refused.join(", "))
}

///|
test "every projected v2 case names a declaration the file actually holds" {
  for i, _ in @conformance.cases() {
    if v2_case_name(i) is Some(name) {
      // Either the component answers it, or the case is about a name nothing
      // answers — which is one of them, deliberately. Asked through
      // `from_dispatch`, which is the router the generator wrote: a name it
      // cannot place is a case whose declaration went missing.
      let placed = CorpusMsg::from_dispatch(Receive(name, [])) is Some(_) ||
        CorpusMsg::from_dispatch(Intent(name, [])) is Some(_)
      assert_true(placed || name == "nope")
    }
  }
}
