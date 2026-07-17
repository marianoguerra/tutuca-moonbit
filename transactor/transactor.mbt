// The dispatcher (src/transactor.js): queue, the four channels, and the
// leaf-update core (updateRootValue) with completion accounting.

///|
pub fn Transactor::new(
  root : &@tutuca.PathNode,
  requests? : &Requests,
) -> Transactor {
  {
    requests: match requests {
      Some(r) => r
      None => NoRequests::{  }
    },
    root,
    queue: [],
    change_subs: [],
    draining: false,
    observers: [],
    obs_seq: 0,
    drain_subs: [],
  }
}

///|
pub fn Transactor::observe(
  self : Transactor,
  cb : (ObserveRecord) -> Unit,
) -> () -> Unit {
  self.observers.push(cb)
  let done : Ref[Bool] = { val: false }
  () => {
    if !done.val {
      done.val = true
      match self.observers.search_by(o => physical_equal(o, cb)) {
        Some(i) => {
          let _ = self.observers.remove(i)
        }
        None => ()
      }
    }
  }
}

///|
fn Transactor::emit(
  self : Transactor,
  kind : ObserveKind,
  t : Transaction,
  old_root : &@tutuca.PathNode,
  matched : ObserveMatch,
) -> Unit {
  if self.observers.is_empty() {
    return
  }
  // pin field-resolved keys against the root the handler read, so path_keys
  // carries concrete keys (JS _emitTransaction)
  let path = (match t.txn_path {
    Some(p) => p
    None => t.path.to_transaction_path()
  }).pin_keys(old_root)
  self.obs_seq = self.obs_seq + 1
  let record : ObserveRecord = {
    kind,
    name: t.name,
    args: t.args,
    path,
    path_keys: path.to_keys(),
    target_path: t.target_path,
    matched,
    before: t.obs_before,
    after: t.obs_after,
    seq: self.obs_seq,
  }
  for cb in self.observers {
    cb(record)
  }
}

///|
pub fn Transactor::on_drained(self : Transactor, cb : () -> Unit) -> Unit {
  self.drain_subs.push(cb)
}

///|
pub fn Transactor::on_change(
  self : Transactor,
  cb : (&@tutuca.PathNode, &@tutuca.PathNode) -> Unit,
) -> Unit {
  self.change_subs.push(cb)
}

///|
/// Queue `t` and make it a tracked unit of `parent`'s subtree (JS _link):
/// tracking happens while the parent's self-unit is still held, so the
/// parent's counter can't reach zero before the child registers.
fn Transactor::link(
  self : Transactor,
  t : Transaction,
  parent : Transaction?,
) -> Transaction {
  match parent {
    Some(p) => {
      let release = p.completion().track()
      t.completion().on_subtree_settled(release)
    }
    None => ()
  }
  self.queue.push(t)
  t
}

///|
pub fn Transactor::push_send(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
  skip_self? : Bool = false,
  bubbles? : Bool = false,
) -> Transaction {
  self.link(
    {
      transactor: self,
      path,
      bucket: Receive,
      name,
      args,
      target_path: path,
      bubbles,
      skip_self,
      txn_path: None,
      parent,
      cmpl: None,
      obs_matched: None,
      obs_before: None,
      obs_after: None,
    },
    parent,
  )
}

///|
pub fn Transactor::push_input(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
) -> Transaction {
  self.link(
    {
      transactor: self,
      path,
      bucket: Input,
      name,
      args,
      target_path: path,
      bubbles: false,
      skip_self: false,
      txn_path: None,
      parent,
      cmpl: None,
      obs_matched: None,
      obs_before: None,
      obs_after: None,
    },
    parent,
  )
}

///|
/// One bubble hop (JS BubbleEvent): bucket Bubble, keeps bubbling until
/// stop_propagation or the root; target_path stays the fixed origin.
fn Transactor::push_bubble(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent : Transaction?,
  target_path : @tutuca.DispatchPath,
) -> Transaction {
  self.link(
    {
      transactor: self,
      path,
      bucket: Bubble,
      name,
      args,
      target_path,
      bubbles: true,
      skip_self: false,
      txn_path: None,
      parent,
      cmpl: None,
      obs_matched: None,
      obs_before: None,
      obs_after: None,
    },
    parent,
  )
}

///|
pub fn Transactor::push_request(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  opts? : @tutuca.RequestOpts,
  parent? : Transaction,
) -> Unit {
  let opts = match opts {
    Some(o) => o
    None => @tutuca.RequestOpts::new()
  }
  // Track on the parent NOW — during the parent's handler, while its
  // self-unit is still held — then transfer the unit onto the response's
  // subtree so the parent stays open until the whole response chain settles.
  let release = match parent {
    Some(p) => Some(p.completion().track())
    None => None
  }
  let cur_root = self.root
  let txn_path = path.to_transaction_path()
  let found = match txn_path.lookup(cur_root) {
    Some(leaf) => self.requests.request_for(leaf, name)
    None => None
  }
  // Pin field-resolved keys to their value NOW, so the response updates the
  // item that issued the request even if the key changes while the request
  // is in flight. live_path opts out and re-evaluates on response.
  let res_path = if opts.live_path {
    None
  } else {
    Some(txn_path.pin_keys(cur_root))
  }
  let base_name = match opts.on_res_name {
    Some(n) => n
    None => name
  }
  // observe the outgoing request (the response side is observed later when
  // its ResponseEvent flows through transact)
  if !self.observers.is_empty() {
    let req_path = txn_path.pin_keys(cur_root)
    self.obs_seq = self.obs_seq + 1
    let record : ObserveRecord = {
      kind: Request,
      name,
      args,
      path: req_path,
      path_keys: req_path.to_keys(),
      target_path: path,
      matched: if found is Some(_) {
        Exact
      } else {
        NoHandler
      },
      before: match txn_path.lookup(cur_root) {
        Some(l) => l.as_value()
        None => None
      },
      after: None,
      seq: self.obs_seq,
    }
    for cb in self.observers {
      cb(record)
    }
  }
  let responded : Ref[Bool] = { val: false }
  let respond = (result : Result[@tutuca.Value, @tutuca.Value]) => {
    if responded.val {
      return
    }
    responded.val = true
    let (specific, res_args) = match result {
      Ok(v) =>
        (
          opts.on_ok_name,
          match opts.on_ok_name {
            Some(_) => [v]
            None => [v, Null]
          },
        )
      Err(e) =>
        (
          opts.on_error_name,
          match opts.on_error_name {
            Some(_) => [e]
            None => [Null, e]
          },
        )
    }
    let t = Transaction::{
      transactor: self,
      path,
      bucket: Response,
      name: match specific {
        Some(n) => n
        None => base_name
      },
      args: res_args,
      target_path: path,
      bubbles: false,
      skip_self: false,
      txn_path: res_path,
      parent,
      cmpl: None,
      obs_matched: None,
      obs_before: None,
      obs_after: None,
    }
    // transfer the parent's request-unit onto the response's subtree; the
    // response is queued directly (not link), so it is not counted twice
    match release {
      Some(r) => t.completion().on_subtree_settled(r)
      None => ()
    }
    self.queue.push(t)
    self.settle()
  }
  match found {
    Some(RequestHandler(f)) => f(args, respond)
    None => respond(Err(Str("Request not found: \{name}")))
  }
}

///|
/// Whether transactions remain queued (JS transactor.hasPendingTransactions).
/// Lets a backend driver time-slice: `settle(max_turns=n)` a bounded batch,
/// yield to the host, and loop while this is true. The pure layer stays
/// clock-free — the actual yield (setTimeout on js) lives in the backend.
pub fn Transactor::has_pending(self : Transactor) -> Bool {
  self.queue.length() > 0
}

///|
pub fn Transactor::settle(self : Transactor, max_turns? : Int = 10000) -> Unit {
  if self.draining {
    return // re-entrant respond mid-drain: the outer loop picks it up
  }
  self.draining = true
  let mut turns = max_turns
  let mut worked = false
  while self.queue.length() > 0 && turns > 0 {
    let t = self.queue.remove(0)
    self.transact(t)
    worked = true
    turns -= 1
  }
  self.draining = false
  if worked {
    for cb in self.drain_subs {
      cb()
    }
  }
}

///|
fn Transactor::transact(self : Transactor, t : Transaction) -> Unit {
  let cur = self.root
  let next = if t.skip_self { cur } else { self.update_root_value(t, cur) }
  if !physical_equal(next, cur) {
    self.root = next
    for cb in self.change_subs {
      cb(next, cur)
    }
  }
  // after_transaction runs before the self-unit release, so a bubble it
  // pushes is counted before the subtree counter can reach zero
  t.after_transaction()
  // a skipSelf send resolves no handler and emits no record (JS
  // _resolvedHandler undefined)
  match t.obs_matched {
    Some(matched) => {
      let kind : ObserveKind = match t.bucket {
        Receive => Receive
        Input => Input
        Bubble => Bubble
        Response => Response
      }
      self.emit(kind, t, cur, matched)
    }
    None => ()
  }
  match t.cmpl {
    Some(c) => {
      c.ensure_self_settled()
      c.release_self()
    }
    None => ()
  }
}

///|
fn Transactor::update_root_value(
  self : Transactor,
  t : Transaction,
  cur : &@tutuca.PathNode,
) -> &@tutuca.PathNode {
  ignore(self)
  let txn_path = match t.txn_path {
    Some(p) => p
    None => t.path.to_transaction_path()
  }
  // a resolved-then-deleted target (pinned response path) is a no-op (still
  // observed with NoHandler, like the JS nullHandler path)
  guard txn_path.lookup(cur) is Some(leaf) else {
    t.obs_matched = Some(NoHandler)
    t.mark_settled()
    return cur
  }
  t.obs_before = leaf.as_value()
  let resolved = match leaf.handler(t.bucket, t.name) {
    Some(h) => {
      t.obs_matched = Some(Exact)
      Some(h)
    }
    None =>
      match leaf.handler(t.bucket, "$unknown") {
        Some(h) => {
          t.obs_matched = Some(Unknown)
          Some(h)
        }
        None => {
          t.obs_matched = Some(NoHandler)
          None
        }
      }
  }
  guard resolved is Some(Handler(f)) else {
    t.mark_settled()
    return cur
  }
  let ctx = EventContext::{ txn: t }
  let result = f(t.args, ctx)
  t.mark_settled()
  match result {
    Some(new_leaf) => {
      t.obs_after = new_leaf.as_value()
      if physical_equal(new_leaf, leaf) {
        cur
      } else {
        txn_path.set_value(cur, new_leaf)
      }
    }
    None => cur
  }
}

///|
pub fn Transaction::completion(self : Transaction) -> Completion {
  match self.cmpl {
    Some(c) => c
    None => {
      let c = Completion::new()
      self.cmpl = Some(c)
      c
    }
  }
}

///|
fn Transaction::mark_settled(self : Transaction) -> Unit {
  match self.cmpl {
    Some(c) => c.mark_self_settled()
    None => ()
  }
}

///|
fn Transaction::after_transaction(self : Transaction) -> Unit {
  if self.bubbles && self.path.items.length() > 0 {
    let _ = self.transactor.push_bubble(
      self.path.pop_step(),
      self.name,
      self.args,
      Some(self),
      self.target_path,
    )
  }
}

///|
/// The ctx handed to a running handler: implements the path package's Ctx
/// seam over this transaction (JS EventContext).
priv struct EventContext {
  txn : Transaction
}

///|
impl @tutuca.Ctx for EventContext with fn path(self) {
  self.txn.path
}

///|
impl @tutuca.Ctx for EventContext with fn target_path(self) {
  self.txn.target_path
}

///|
impl @tutuca.Ctx for EventContext with fn name(self) {
  Some(self.txn.name)
}

///|
impl @tutuca.Ctx for EventContext with fn send(self, name, args) {
  let _ = self.txn.transactor.push_send(
    self.txn.path,
    name,
    args,
    parent=self.txn,
  )
}

///|
impl @tutuca.Ctx for EventContext with fn bubble(self, name, args) {
  let _ = self.txn.transactor.push_send(
    self.txn.path,
    name,
    args,
    parent=self.txn,
    skip_self=true,
    bubbles=true,
  )
}

///|
impl @tutuca.Ctx for EventContext with fn send_at_path(self, path, name, args) {
  let _ = self.txn.transactor.push_send(path, name, args, parent=self.txn)
}

///|
impl @tutuca.Ctx for EventContext with fn bubble_at_path(self, path, name, args) {
  let _ = self.txn.transactor.push_send(
    path,
    name,
    args,
    parent=self.txn,
    skip_self=true,
    bubbles=true,
  )
}

///|
/// The component instance a chain node carries, with its component id — None
/// for non-component nodes (JS Components.getCompFor returning null).
fn node_component(node : &@tutuca.PathNode) -> (Int, @tutuca.Value)? {
  match node.as_value() {
    Some(v) =>
      match v {
        Obj(o) =>
          match o.component_id() {
            Some(id) => Some((id, v))
            None => None
          }
        _ => None
      }
    None => None
  }
}

///|
impl @tutuca.Ctx for EventContext with fn walk_path(self, callback) {
  // The root the handler reads: synchronous dispatch means the transactor's
  // current root IS the one this transaction is being processed against (JS
  // captures transactor.state.val at dispatch for the same reason).
  let root = self.txn.transactor.root
  let chain = self.txn.path.to_transaction_path().resolve_chain(root)
  for i = chain.length() - 1; i >= 0; i = i - 1 {
    match node_component(chain[i]) {
      Some((id, inst)) => if !callback(id, inst) { return }
      None => ()
    }
  }
}

///|
impl @tutuca.Ctx for EventContext with fn request(self, name, args, opts) {
  self.txn.transactor.push_request(
    self.txn.path,
    name,
    args,
    opts~,
    parent=self.txn,
  )
}

///|
impl @tutuca.Ctx for EventContext with fn stop_propagation(self) {
  self.txn.bubbles = false
}
