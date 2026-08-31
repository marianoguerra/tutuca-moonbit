// Dispatch paths as a stack of render continuations.

///|
pub fn DispatchPath::new(items? : Array[DispatchStep]) -> DispatchPath {
  { frames: [{ base: Path::new(), items: items.unwrap_or([]), }], }
}

///|
pub fn DispatchPath::of_steps(steps : Array[Step]) -> DispatchPath {
  DispatchPath::new(items=steps.map(s => Plain(step=s, origin=None)))
}

///|
pub fn DispatchPath::concat(
  self : DispatchPath,
  steps : Array[Step],
) -> DispatchPath {
  guard self.frames is [.. init, last] else {
    return DispatchPath::of_steps(steps)
  }
  let items = last.items.copy()
  for s in steps {
    items.push(Plain(step=s, origin=None))
  }
  { frames: [..init, { ..last, items, }], }
}

///|
pub fn DispatchPath::push_item(
  self : DispatchPath,
  item : DispatchStep,
) -> DispatchPath {
  guard self.frames is [.. init, last] else {
    return DispatchPath::new(items=[item])
  }
  let items = last.items.copy()
  items.push(item)
  { frames: [..init, { ..last, items, }], }
}

///|
pub fn DispatchPath::push_frame(
  self : DispatchPath,
  path : Path,
) -> DispatchPath {
  let frames = self.frames.copy()
  frames.push({ base: path, items: [], })
  { frames, }
}

///|
pub fn DispatchPath::can_pop(self : DispatchPath) -> Bool {
  match self.frames {
    [.. init, last] => !last.items.is_empty() || !init.is_empty()
    [] => false
  }
}

///|
pub fn DispatchPath::is_root(self : DispatchPath) -> Bool {
  self.to_transaction_path().steps.is_empty()
}

///|
pub fn DispatchPath::pop_step(self : DispatchPath) -> DispatchPath {
  guard self.frames is [.. init, last] else { return self }
  if !last.items.is_empty() {
    let items = last.items[0:last.items.length() - 1].to_owned()
    { frames: [..init, { ..last, items, }], }
  } else if !init.is_empty() {
    { frames: init.to_owned(), }
  } else {
    self
  }
}

///|
pub fn DispatchPath::compact(self : DispatchPath) -> DispatchPath {
  let frames : Array[DispatchFrame] = []
  for frame in self.frames {
    let items : Array[DispatchStep] = []
    for item in frame.items {
      match item {
        Plain(step~, origin~) =>
          match step_to_abstract(step) {
            Some(s) => items.push(Plain(step=s, origin~))
            None => ()
          }
      }
    }
    frames.push({ ..frame, items, })
  }
  { frames, }
}

///|
pub fn DispatchPath::to_transaction_path(self : DispatchPath) -> Path {
  guard self.frames is [.., frame] else { return Path::new() }
  let out = frame.base.steps.copy()
  for item in frame.items {
    match item {
      Plain(step~, ..) => out.push(step)
    }
  }
  { steps: out, }
}
