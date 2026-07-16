// Dispatch paths (src/path.js compact()/toTransactionPath() over paths that
// carry DynStep markers and per-step component provenance).

///|
pub fn DispatchPath::new(items? : Array[DispatchStep]) -> DispatchPath {
  match items {
    Some(i) => { items: i }
    None => { items: [] }
  }
}

///|
pub fn DispatchPath::of_steps(steps : Array[Step]) -> DispatchPath {
  { items: steps.map(s => DispatchStep::Plain(step=s, origin=None)) }
}

///|
pub fn DispatchPath::concat(
  self : DispatchPath,
  steps : Array[Step],
) -> DispatchPath {
  let items = self.items.copy()
  for s in steps {
    items.push(Plain(step=s, origin=None))
  }
  { items, }
}

///|
pub fn DispatchPath::pop_step(self : DispatchPath) -> DispatchPath {
  let n = self.items.length()
  if n == 0 {
    self
  } else {
    { items: self.items[0:n - 1].to_owned() }
  }
}

///|
pub fn DispatchPath::compact(self : DispatchPath) -> DispatchPath {
  let items : Array[DispatchStep] = []
  for item in self.items {
    match item {
      Plain(step~, origin~) =>
        match step_to_abstract(step) {
          Some(s) => items.push(Plain(step=s, origin~))
          None => () // frame-only: dropped
        }
      _ => items.push(item) // Dyn markers survive: bubbling visits them
    }
  }
  { items, }
}

///|
/// The steps a Dyn marker splices into the transaction path in place of the
/// dropped interior span (JS DynStep/DynEachStep.teleportSteps).
fn teleport_steps(item : DispatchStep) -> Array[Step] {
  match item {
    Plain(..) => []
    Dyn(steps~, ..) => steps
    DynEach(steps~, key~, ..) =>
      match steps {
        [.. init, FieldStep(f)] => {
          let out = init.to_owned()
          out.push(SeqStep(field=f, key~))
          out
        }
        // A seq-access dynamic (`.a[.b]`) cannot address an iterated item; a
        // key-only step does not exist. Splice unchanged rather than build a
        // broken step (JS warns here).
        _ => steps
      }
  }
}

///|
pub fn DispatchPath::to_transaction_path(self : DispatchPath) -> Path {
  let out : Array[(Step, Int?)] = []
  for item in self.items {
    match item {
      Plain(step~, origin~) => out.push((step, origin))
      Dyn(producer~, interior~, ..) | DynEach(producer~, interior~, ..) => {
        // rewind the steps contributed by components interior to the
        // producer..consumer span — the data does not live under them
        while out is [.., (_, Some(cid))] && interior.contains(cid) {
          let _ = out.pop()
        }
        for ts in teleport_steps(item) {
          out.push((ts, Some(producer)))
        }
      }
    }
  }
  { steps: out.map(p => p.0) }
}
