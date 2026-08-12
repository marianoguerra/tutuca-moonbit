// The MoonBit backend, run against the corpus.
//
// The second of the three adapters the corpus exists for. The interpreter's
// (tscript/interp/conformance_test.mbt) reads the table directly; this one
// cannot, because its answers only exist once `moonc` has compiled them — so
// the corpus is projected into corpus.html by `cmd/dev -- gen-conformance`,
// compiled by `gen-views` like any other view file, and driven here.
//
// Whitebox, because what has to agree with the interpreter is
// `corpus_inline_update` — the package-private function the wrapper composes.
//
// A case the backend REFUSED is not a failure. Roughly a sixth of the corpus
// is reserved for hand-written MoonBit by design, and a typed backend
// legitimately answers some things at build time that the interpreter answers
// at run time. What would be a failure is that set changing silently, so it is
// listed by name and its size is pinned.

///|
/// The dispatch a case sends.
fn dispatch_of(c : @conformance.Case, name : String) -> @component.Dispatch {
  match c.bucket {
    BInput => Input(name, c.args)
    BReceive => Receive(name, c.args)
    BBubble => Bubble(name, c.args)
    BResponse => Response(name, c.args)
  }
}

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
/// The fields the corpus states, as the generated struct.
fn decoded(before : Map[String, @tutuca.Value]) -> CorpusState? {
  @component.Fields::decode(before)
}

///|
test "the MoonBit backend agrees with the corpus" {
  let failures : Array[String] = []
  let refused : Array[String] = []
  let cases = @conformance.cases()
  for i, c in cases {
    guard case_name(i) is Some(name) else {
      failures.push("\{c.name}: the projection left this case out")
      continue
    }
    guard decoded(c.before) is Some(before) else {
      failures.push("\{c.name}: the corpus's `before` does not fit CorpusState")
      continue
    }
    let rec = Recorder::new()
    let got = corpus_inline_update(before, dispatch_of(c, name), rec)
    // `Unhandled` can only come from the catch-all: an emitted arm answers
    // `Next` or `Unchanged`, never `Unhandled`. So it means no arm was
    // emitted, which means the backend refused this declaration.
    if got is Unhandled {
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
    if rec.seen != c.effects {
      failures.push(
        "\{c.name}: expected effects [\{c.effects.join(", ")}], got [\{rec.seen.join(", ")}]",
      )
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
  // Pinned, so the reserved set can shrink but not grow unnoticed. Every entry
  // is one of three things and each is written down in the corpus:
  //
  //   - a read or a write through an INDEX, which needs a bounds check and a
  //     spine rebuild the emitter does not write yet;
  //   - an expression whose type the schema rules out at build time, where the
  //     interpreter only finds out at run time (both answer "no successor",
  //     one of them earlier);
  //   - a parameter with no call site to type it, which a typed backend has
  //     nothing to bind.
  //
  // If this number goes DOWN, lower it. If it goes UP, something regressed.
  @debug.assert_eq(refused.length(), 12, msg=refused.join(", "))
}

///|
test "every projected case names a declaration the file actually holds" {
  // The table and the .html are written by one pass, so they cannot disagree
  // — unless one is regenerated and the other is not, which is exactly what a
  // stale checkout looks like.
  let cases = @conformance.cases()
  for i, _ in cases {
    if case_name(i) is Some(name) {
      assert_true(corpus_declares(name))
    }
  }
}

///|
/// Whether the compiled component answers `name` at all.
///
/// Asked of the INPUT enum rather than of the source: that enum is generated
/// from the views' call sites, which the projection writes one of per case, so
/// a name it does not contain is a case whose call site went missing.
fn corpus_declares(name : String) -> Bool {
  CorpusInput::parse(name) is Some(_) || name == "resetTo"
}
