// The dispatcher (src/transactor.js): queue, the four channels, and the
// leaf-update core (updateRootValue) with completion accounting.

///|
pub fn Transactor::new(
  root : @tutuca.Value,
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
/// Deliver one record, stamping the sequence number and deriving `path_keys`
/// from the already-pinned path.
///
/// The four places a record is BUILT used to be two, and the second — the
/// outgoing-request record — restated the empty-check, the counter bump and
/// the delivery loop as well as the fields.
fn Transactor::emit_record(
  self : Transactor,
  kind : ObserveKind,
  name : String,
  args : Array[@tutuca.Value],
  path : @tutuca.Path,
  target_path : @tutuca.DispatchPath,
  matched : ObserveMatch,
  before : @tutuca.Value?,
  after : @tutuca.Value?,
) -> Unit {
  self.obs_seq = self.obs_seq + 1
  let record : ObserveRecord = {
    kind,
    name,
    args,
    path,
    path_keys: path.to_keys(),
    target_path,
    matched,
    before,
    after,
    seq: self.obs_seq,
  }
  for cb in self.observers {
    cb(record)
  }
}

///|
fn Transactor::emit(
  self : Transactor,
  kind : ObserveKind,
  t : Transaction,
  old_root : @tutuca.Value,
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
  self.emit_record(
    kind,
    t.name,
    t.args,
    path,
    t.target_path,
    matched,
    t.obs_before,
    t.obs_after,
  )
}

///|
pub fn Transactor::on_drained(self : Transactor, cb : () -> Unit) -> Unit {
  self.drain_subs.push(cb)
}

///|
pub fn Transactor::on_change(
  self : Transactor,
  cb : (@tutuca.Value, @tutuca.Value) -> Unit,
) -> Unit {
  self.change_subs.push(cb)
}

///|
pub fn Transactor::clear_subscriptions(self : Transactor) -> Unit {
  self.change_subs.clear()
  self.drain_subs.clear()
  self.observers.clear()
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
/// One queued dispatch. Every channel differs in a field or three — the
/// bucket, whether it bubbles, a pre-pinned response path — and used to say
/// so by writing all fourteen out, four times over, so a new field meant
/// finding all four.
fn Transactor::mk_txn(
  self : Transactor,
  path : @tutuca.DispatchPath,
  bucket : @tutuca.HandlerBucket,
  name : String,
  args : Array[@tutuca.Value],
  target_path? : @tutuca.DispatchPath,
  bubbles? : Bool = false,
  skip_self? : Bool = false,
  txn_path? : @tutuca.Path,
  parent? : Transaction,
) -> Transaction {
  {
    transactor: self,
    path,
    bucket,
    name,
    args,
    target_path: target_path.unwrap_or(path),
    bubbles,
    skip_self,
    txn_path,
    parent,
    cmpl: None,
    obs_matched: None,
    obs_before: None,
    obs_after: None,
  }
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
    self.mk_txn(path, Receive, name, args, bubbles~, skip_self~, parent?),
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
  self.link(self.mk_txn(path, Input, name, args, parent?), parent)
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
    self.mk_txn(path, Bubble, name, args, target_path~, bubbles=true, parent?),
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
    self.emit_record(
      Request,
      name,
      args,
      txn_path.pin_keys(cur_root),
      path,
      if found is Some(_) {
        Exact
      } else {
        NoHandler
      },
      txn_path.lookup(cur_root),
      None,
    )
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
    let t = self.mk_txn(
      path,
      Response,
      match specific {
        Some(n) => n
        None => base_name
      },
      res_args,
      txn_path?=res_path,
      parent?,
    )
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
  // Physical identity, because that is exactly what the copy-on-write spine
  // preserves: a handler that wrote the value already stored hands back the
  // untouched root, and a root that did not change must not wake the
  // observers — that is what makes a no-op update free.
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
    Some(matched) =>
      self.emit(ObserveKind::of_bucket(t.bucket), t, cur, matched)
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
  cur : @tutuca.Value,
) -> @tutuca.Value {
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
  t.obs_before = Some(leaf)
  // One lookup — see Path::dispatch. The `"$unknown"` sentinel a second one
  // probed for is gone, and with it the `Unknown` observation: a miss is a
  // miss.
  let resolved = match leaf.handler(t.bucket, t.name) {
    Some(h) => {
      t.obs_matched = Some(Exact)
      Some(h)
    }
    None => {
      t.obs_matched = Some(NoHandler)
      None
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
      t.obs_after = Some(new_leaf)
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
// `send` / `bubble` are not implemented: the trait defaults route them to the
// two below at `path()`, which is exactly what they used to spell out again.
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
fn node_component(node : @tutuca.Value) -> (Int, @tutuca.Value)? {
  match node {
    Obj(o) =>
      match o.component_id() {
        Some(id) => Some((id, node))
        None => None
      }
    _ => None
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
