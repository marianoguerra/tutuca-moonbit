// The MoonBit backend, run against the v2 corpus.
//
// The twin of `drive_wbtest.mbt`, over `cases_v2()` and the `CorpusV2`
// component. Whitebox for the same reason: what has to agree with the design
// is `corpus_v2_inline_update`, the package-private function the wrapper
// composes.
//
// The v2 half is a separate file rather than a second loop in the first one
// because the two corpora carry two vocabularies while both exist. Task 25
// deletes the v1 pair and this becomes the only one.

///|
fn v2_dispatch_of(
  c : @conformance.V2Case,
  name : String,
) -> @component.Dispatch {
  match c.bucket {
    VReceive => Receive(name, c.args)
    VIntent => Intent(name, c.args)
  }
}

///|
fn v2_decoded(before : Map[String, @tutuca.Value]) -> CorpusV2State? {
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
  for i, c in @conformance.cases_v2() {
    guard v2_case_name(i) is Some(name) else {
      failures.push("\{c.name}: the projection left this case out")
      continue
    }
    guard v2_decoded(c.before) is Some(before) else {
      failures.push(
        "\{c.name}: the corpus's `before` does not fit CorpusV2State",
      )
      continue
    }
    let rec = Recorder::new()
    let got = corpus_v2_inline_update(before, v2_dispatch_of(c, name), rec)
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
  // Pinned the way the v1 driver's is: the reserved set may shrink, and a
  // growth is a regression. ZERO is the number worth having here — every v2
  // case was written against the design rather than against this backend, so
  // a refusal is the backend failing to express something the design says.
  @debug.assert_eq(refused.length(), 0, msg=refused.join(", "))
}

///|
test "every projected v2 case names a declaration the file actually holds" {
  for i, _ in @conformance.cases_v2() {
    if v2_case_name(i) is Some(name) {
      // Either the component answers it, or the case is about a name nothing
      // answers — which is one of them, deliberately. Asked through
      // `from_dispatch`, which is the router the generator wrote: a name it
      // cannot place is a case whose declaration went missing.
      let placed = CorpusV2Receive::from_dispatch(Receive(name, [])) is Some(_) ||
        CorpusV2Receive::from_dispatch(Intent(name, [])) is Some(_)
      assert_true(placed || name == "nope")
    }
  }
}
