// Counter-based completion scope (callbacks instead of
// promises).

///|
fn Completion::new() -> Completion {
  {
    pending: 1, // the self-unit, released after handler + after_transaction
    self_settled: false,
    subtree_settled: false,
    self_released: false,
    self_subs: [],
    subtree_subs: [],
  }
}

///|
pub fn Completion::on_settled(self : Completion, cb : () -> Unit) -> Unit {
  if self.self_settled {
    cb()
  } else {
    self.self_subs.push(cb)
  }
}

///|
pub fn Completion::on_subtree_settled(
  self : Completion,
  cb : () -> Unit,
) -> Unit {
  if self.subtree_settled {
    cb()
  } else {
    self.subtree_subs.push(cb)
  }
}

///|
fn Completion::mark_self_settled(self : Completion) -> Unit {
  if self.self_settled {
    return
  }
  self.self_settled = true
  for cb in self.self_subs {
    cb()
  }
  self.self_subs.clear()
}

///|
fn Completion::track(self : Completion) -> () -> Unit {
  self.pending += 1
  let done : Ref[Bool] = { val: false }
  () => {
    if !done.val {
      done.val = true
      self.release_unit()
    }
  }
}

///|
fn Completion::release_self(self : Completion) -> Unit {
  if self.self_released {
    return
  }
  self.self_released = true
  self.release_unit()
}

///|
fn Completion::release_unit(self : Completion) -> Unit {
  self.pending -= 1
  if self.pending == 0 && !self.subtree_settled {
    self.subtree_settled = true
    for cb in self.subtree_subs {
      cb()
    }
    self.subtree_subs.clear()
  }
}
