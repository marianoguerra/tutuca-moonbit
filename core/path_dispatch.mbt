// Dispatch paths as a stack of render continuations.

///|
pub fn DispatchPath::new(items? : Array[DispatchStep]) -> DispatchPath {
  { frames: [{ base: Path::new(), items: items.unwrap_or([]), binds: [], }], }
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
pub fn DispatchPath::push_bind(
  self : DispatchPath,
  bind : FrameBind,
) -> DispatchPath {
  guard self.frames is [.. init, last] else {
    return DispatchPath::new().push_bind(bind)
  }
  let binds = last.binds.copy()
  // The index is how many items came BEFORE this bind, which is what lets a
  // rebuild interleave the two without the bind having to be an item.
  binds.push((last.items.length(), bind))
  { frames: [..init, { ..last, binds, }], }
}

///|
pub fn DispatchPath::push_frame(
  self : DispatchPath,
  path : Path,
) -> DispatchPath {
  let frames = self.frames.copy()
  frames.push({ base: path, items: [], binds: [], })
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
/// Drop the binds a popped item carried into scope.
///
/// A bind is placed by how many items preceded it, so the ones that came after
/// the item now gone are exactly those whose index exceeds the shortened list.
fn keep_binds(
  binds : Array[(Int, FrameBind)],
  items_len : Int,
) -> Array[(Int, FrameBind)] {
  binds.filter(b => b.0 <= items_len)
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
    {
      frames: [
        ..init,
        { ..last, items, binds: keep_binds(last.binds, items.length()), },
      ],
    }
  } else if !init.is_empty() {
    { frames: init.to_owned(), }
  } else {
    self
  }
}

///|
/// The addressing projection: every step in its abstract form.
///
/// It no longer DROPS anything — every step addresses something now — so what
/// is left is `EachRenderItStep` abstracting to a plain `SeqStep`.
pub fn DispatchPath::compact(self : DispatchPath) -> DispatchPath {
  let frames : Array[DispatchFrame] = []
  for frame in self.frames {
    let items : Array[DispatchStep] = []
    for item in frame.items {
      match item {
        Plain(step~, origin~) =>
          items.push(Plain(step=step_to_abstract(step), origin~))
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
