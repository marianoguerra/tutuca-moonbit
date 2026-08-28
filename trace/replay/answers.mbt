// The host, replaced by what it said last time.
//
// A rerun can recompute everything the tree did and nothing the host did, so
// this is the whole of what a recording has to substitute for. It is the same
// idea as a scene's `intents:` fixture and differs in the one way that matters:
// per-OCCURRENCE rather than per-name. A host that declined the first time and
// answered the second replays as that, rather than as two of whichever came
// first — which is exactly the sequence a bug worth recording tends to be about.

///|
pub fn Answers::of_trace(t : @trace.Trace) -> Answers {
  let by_walk : Map[Int, Array[(String, Int, @tutuca.IntentAnswer)]] = Map([])
  // An answer carries no name — it is a reply, and a reply is about a walk —
  // so the name comes from the intent the walk was.
  let name_of : Map[Int, String] = Map([])
  for e in t.events {
    match e.op {
      Intent(name~, ..) => if e.walk != 0 { name_of[e.walk] = name }
      Offered(name~, ..) =>
        if e.walk != 0 && name_of.get(e.walk) is None {
          name_of[e.walk] = name
        }
      _ => ()
    }
  }
  for e in t.events {
    match e.op {
      Answer(nth~, answer~) =>
        if e.walk != 0 {
          let name = name_of.get(e.walk).unwrap_or("")
          match by_walk.get(e.walk) {
            Some(xs) => xs.push((name, nth, answer))
            None => by_walk[e.walk] = [(name, nth, answer)]
          }
        }
      _ => ()
    }
  }
  { by_walk, next_walk: 0, }
}

///|
/// The answers for the next walk, if it is the walk the recording expected.
///
/// Walk ids are handed out in order, so the *n*th walk of a rerun is the *n*th
/// walk of the recording — while the rerun is faithful. The moment it is not,
/// matching on the id alone would hand a walk somebody else's answer and hide
/// the divergence it should have reported, so the name is checked too and a
/// mismatch answers nothing.
pub fn Answers::take(
  self : Answers,
  name : String,
) -> Array[@tutuca.IntentAnswer] {
  self.next_walk = self.next_walk + 1
  guard self.by_walk.get(self.next_walk) is Some(xs) else { return [] }
  guard xs.iter().all(x => x.0 == "" || x.0 == name) else { return [] }
  xs.map(x => x.2)
}

///|
pub fn RecordedHost::new(
  answers : Answers,
  fallback? : &@transactor.Intents,
) -> RecordedHost {
  { answers, fallback, }
}

///|
/// One handler per recorded answer, in the order the host gave them.
///
/// One per answer and not one that answers repeatedly, because the transactor
/// asks the chain one at a time and a `Pass` moves to the NEXT handler: the
/// shape of the chain is what reproduces the sequence of decisions, and a
/// single handler holding a queue would have to reimplement that.
///
/// A walk the recording says nothing about falls through to whatever the app
/// registered, which is what lets a relocated trace be replayed against a live
/// host for the parts it never captured.
pub impl @transactor.Intents for RecordedHost with fn intents_for(
  self,
  leaf,
  name,
) {
  let recorded = self.answers.take(name)
  if recorded.is_empty() {
    return match self.fallback {
      Some(f) => f.intents_for(leaf, name)
      None => []
    }
  }
  recorded.map(a => @transactor.IntentHandler((_call, answer) => answer(a)))
}
