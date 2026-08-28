// The three ways a recording gets shorter, and the small amount of reasoning
// each one needs.
//
// They differ in what they need to know. `prefix` needs nothing — a prefix of a
// recording is a recording, because the state it starts from has not moved.
// `rebase` needs the state the discarded prefix produced, which means running
// the app, which is why the caller brings it. `relocate` needs neither: a
// snapshot's shape is the state's shape, so the subtree is cut out of the JSON.

///|
pub fn Trace::input_count(self : Trace) -> Int {
  self.events.filter(e => e.input).length()
}

///|
pub fn Trace::turns(self : Trace) -> Array[Array[Event]] {
  let out : Array[Array[Event]] = []
  let mut cur = -1
  for e in self.events {
    // Turn 0 is "no turn" — a refusal, an offer, an answer — and those belong
    // with the turn they interrupted rather than in one of their own.
    let t = if e.turn == 0 { cur } else { e.turn }
    if t != cur || out.is_empty() {
      cur = t
      out.push([])
    }
    out[out.length() - 1].push(e)
  }
  out
}

///|
pub fn Trace::places(self : Trace) -> Array[Place] {
  let out : Array[Place] = []
  let seen : Map[String, Bool] = Map([])
  for e in self.events {
    let k = e.at.label()
    if seen.get(k) is None {
      seen[k] = true
      out.push(e.at)
    }
  }
  out
}

// --- prefix -------------------------------------------------------------------

///|
pub fn Trace::prefix(self : Trace, n : Int) -> Trace {
  let n = if n < 0 {
    0
  } else if n > self.events.length() {
    self.events.length()
  } else {
    n
  }
  { ..self, events: self.events[0:n].to_owned(), }
}

// --- rebase -------------------------------------------------------------------

///|
pub fn Trace::rebase(self : Trace, at~ : Int, root~ : Json) -> Trace {
  let at = self.turn_boundary(at)
  let dropped = self.events[0:at].to_owned()
  let tail = self.events[at:].to_owned()
  // A walk whose intent is gone has nothing left to answer, and an answer with
  // no question is an answer a rerun would deliver to a handler that was never
  // waiting. Both go.
  let live_walks : Map[Int, Bool] = Map([])
  for e in tail {
    if e.walk != 0 && e.op is Intent(_) {
      live_walks[e.walk] = true
    }
  }
  let kept : Array[Event] = tail.filter(e => {
    match e.op {
      Answer(_) | Offered(_) => e.walk != 0 && live_walks.get(e.walk) is Some(_)
      _ => true
    }
  })
  // Renumber from 1, and carry `parent` across only where the parent survived:
  // a link to a discarded event is a link a reader would follow into nothing.
  let seq_of : Map[Int, Int] = Map([])
  for i, e in kept {
    seq_of[e.seq] = i + 1
  }
  ignore(dropped)
  let events : Array[Event] = kept.mapi((i, e) => {
    ..e,
    seq: i + 1,
    parent: match seq_of.get(e.parent) {
      Some(p) => p
      None => 0
    },
  })
  { ..self, root, events, }
}

///|
/// The first index at or after `n` that starts a turn.
///
/// A cut lands on a turn boundary or it lands nowhere useful. Half a turn is
/// not a thing that happened: a click whose cascade is cut in the middle leaves
/// the tail beginning with a consequence whose cause is gone, and nothing can
/// produce it again. The same argument `RingRecorder` makes when it drops whole
/// turns.
///
/// Rounding FORWARD, so a caller who asks to keep less keeps less: rounding
/// back would hand them a longer trace than they asked for, which is the
/// opposite of what they were doing.
pub fn Trace::turn_boundary(self : Trace, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n >= self.events.length() {
    return self.events.length()
  }
  // The last turn actually SEEN, not the previous event's. Turn 0 is "no turn
  // of its own" — an offer, an answer, a refusal — and those belong with the
  // turn they interrupted. Comparing against the event before would read the
  // first real turn after one of them as a new turn, and cut a cascade in half
  // at exactly the point the whole rule exists to avoid.
  let mut cur = 0
  for i in 0..<self.events.length() {
    let e = self.events[i]
    if e.turn == 0 {
      continue
    }
    if cur != 0 && e.turn != cur && i >= n {
      return i
    }
    cur = e.turn
  }
  self.events.length()
}

// --- relocate -----------------------------------------------------------------

///|
pub fn cut_root(root : Json, place : Place) -> Json? {
  let mut cur = root
  let Place(keys) = place
  for k in keys {
    guard cur is Object(m) else { return None }
    guard m.get(k.field) is Some(v) else { return None }
    cur = match k.key {
      None => v
      // The tagged encoding writes a list as an array and a keyed map as an
      // object, so an index reads one and a name reads the other. That is not a
      // guess about the state's shape: `to_component_json` decided it, walking
      // the DECLARED type.
      Some(KInt(i)) =>
        match v {
          Array(items) =>
            if i >= 0 && i < items.length() {
              items[i]
            } else {
              return None
            }
          _ => return None
        }
      Some(KStr(s)) =>
        match v {
          Object(mm) =>
            match mm.get(s) {
              Some(x) => x
              None => return None
            }
          _ => return None
        }
    }
  }
  Some(cur)
}

///|
pub fn Trace::relocate(self : Trace, place : Place) -> (Trace, Array[Gap]) {
  let gaps : Array[Gap] = []
  guard cut_root(self.root, place) is Some(root) else {
    return (
      { ..self, root: Json::null(), events: [], relocated_from: [place], },
      [NoSuchPlace(place=place.label())],
    )
  }
  // A compacted trace has no derived events, so nothing can be promoted and an
  // event that crossed into the subtree is indistinguishable from one that
  // never happened. Read off the flag rather than off the absence of derived
  // events, because a recording where nothing derived ever happened is not
  // missing anything and should not be warned about.
  if self.compacted {
    gaps.push(NoDerivedStream)
  }

  // Which walks are the subtree's own. An intent RAISED inside the cut keeps
  // its offers and its answer even though those are recorded elsewhere: an
  // offer's address is the sender's, and an answer has none at all.
  let own_walks : Map[Int, String] = Map([])
  for e in self.events {
    if e.walk != 0 && e.op is Intent(name~, ..) && e.at.starts_with(place) {
      own_walks[e.walk] = name
    }
  }
  let answered : Map[Int, Bool] = Map([])
  for e in self.events {
    if e.op is Answer(_) && e.walk != 0 {
      answered[e.walk] = true
    }
  }
  // Which events survive the cut, by seq. What makes the promotion below exact:
  // a derived event whose cause is still here was caused from INSIDE, and a
  // rerun of the subtree produces it again.
  let surviving : Map[Int, Bool] = Map([])
  for e in self.events {
    if e.at.starts_with(place) ||
      (e.walk != 0 && own_walks.get(e.walk) is Some(_)) {
      surviving[e.seq] = true
    }
  }
  let events : Array[Event] = []
  for e in self.events {
    let inside = e.at.starts_with(place)
    let ours = e.walk != 0 && own_walks.get(e.walk) is Some(_)
    let keep = match e.op {
      // An offer and an answer belong to their walk, not to a position.
      Offered(_) | Answer(_) => ours
      _ => inside
    }
    if !keep {
      continue
    }
    let at = match e.at.strip_prefix(place) {
      Some(p) => p
      // An offer's address is the SENDER's, which is inside by construction
      // when the walk is ours; anything else that lands here is an answer, and
      // an answer has no address.
      None => Place([])
    }
    // The promotion, and the whole reason the derived stream is recorded.
    //
    // A message a parent sent into the subtree is not the subtree's own doing,
    // and after the cut there is no parent left to send it — so what was a
    // consequence becomes an input. The test is the CAUSAL LINK and not the
    // address: an intent the subtree raised for itself lands inside too, and a
    // rerun raises it again, so promoting that would feed the app something it
    // was about to do anyway. An orphan is an event whose cause did not survive.
    //
    // An offer is never promoted: it is the runtime asking a host, and a rerun
    // asks again. What comes BACK is the input, and it already is one.
    let orphan = !e.input &&
      !(e.op is Offered(_)) &&
      surviving.get(e.parent) is None
    events.push({ ..e, at, input: e.input || orphan, })
  }
  // Renumbered, and the parent links renumbered with them. A link to an event
  // the cut discarded is a link a reader would follow into nothing — and it is
  // the same link `relocate` just used to decide what to promote, so leaving it
  // pointing at the old numbering would be leaving a trap.
  let seq_of : Map[Int, Int] = Map([])
  for i, e in events {
    seq_of[e.seq] = i + 1
  }
  let renumbered : Array[Event] = events.mapi((i, e) => {
    ..e,
    seq: i + 1,
    parent: seq_of.get(e.parent).unwrap_or(0),
  })
  // Scanned AFTER renumbering, so the event a gap names is one the reader can
  // find in the trace they are holding rather than in the one it came from.
  for walk, name in own_walks {
    if answered.get(walk) is None {
      let seq = renumbered
        .iter()
        .filter(e => e.walk == walk)
        .head()
        .map(e => e.seq)
        .unwrap_or(0)
      gaps.push(UnansweredIntent(name~, seq~))
    }
  }
  // A root has to be an instance, and this is the one shape check worth making
  // here: the cut itself is correct, and the trace simply cannot be mounted.
  // Almost always one step too far or one too few — `.rows` for `.rows[0]`.
  if !(root is Object(rm) && rm.get(@tutuca.component_key) is Some(String(_))) {
    gaps.push(NotAComponent(place=place.label()))
  }
  let from = self.relocated_from.copy()
  from.push(place)
  ({ ..self, root, events: renumbered, relocated_from: from, }, gaps)
}

///|
pub fn Trace::compact(self : Trace) -> Trace {
  {
    ..self,
    compacted: true,
    events: self.events
    .filter(e => e.input)
    .mapi((i, e) => {
      ..e,
      seq: i + 1,
      // Every parent link pointed at something; after this most of them point at
      // nothing, and a link into a hole is worse than no link.
      parent: 0,
    }),
  }
}

///|
pub fn Gap::message(self : Gap) -> String {
  match self {
    UnansweredIntent(name~, seq~) =>
      "`\{name}` (event \{seq}) was answered from outside the cut, and no answer was recorded — a rerun will hear `\{name}Unhandled`"
    UnprovidedName(name~) =>
      "`\{name}` is read from an ancestor, and reading is not a dispatch — nothing recorded it and nothing outside the cut is left to answer it"
    NoDerivedStream =>
      "this trace was compacted, so nothing crossing into the subtree could be promoted"
    NoSuchPlace(place~) => "`\{place}` names nothing in the root snapshot"
    NotAComponent(place~) =>
      "`\{place}` is not a component, so the trace it cuts cannot be mounted — did you mean one step deeper, or one fewer?"
  }
}
