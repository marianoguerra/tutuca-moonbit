// The dispatcher: the queue, the two channels — an addressed message and an
// intent's walk — and the leaf-update core with completion accounting.

///|
pub fn Transactor::new(root : @tutuca.Value, intents? : &Intents) -> Transactor {
  {
    intents: match intents {
      Some(i) => i
      None => NoIntents::{  }
    },
    root,
    queue: [],
    queue_head: 0,
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
/// One queued dispatch. The channels differ in a field or three — the bucket,
/// the walk it belongs to, a pre-pinned answer path — and used to say so by
/// writing all fourteen out, once per channel, so a new field meant finding
/// every one of them.
fn Transactor::mk_txn(
  self : Transactor,
  path : @tutuca.DispatchPath,
  bucket : @tutuca.HandlerBucket,
  name : String,
  args : Array[@tutuca.Value],
  target_path? : @tutuca.DispatchPath,
  txn_path? : @tutuca.Path,
  parent? : Transaction,
  walk? : IntentWalk,
  is_answer? : Bool = false,
) -> Transaction {
  {
    transactor: self,
    path,
    bucket,
    name,
    args,
    target_path: target_path.unwrap_or(path),
    txn_path,
    parent,
    walk,
    is_answer,
    cmpl: None,
    self_settled: false,
    finished: false,
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
) -> Transaction {
  self.link(self.mk_txn(path, Receive, name, args, parent?), parent)
}

///|
/// Whether transactions remain queued (JS transactor.hasPendingTransactions).
/// Lets a backend driver time-slice: `settle(max_turns=n)` a bounded batch,
/// yield to the host, and loop while this is true. The pure layer stays
/// clock-free — the actual yield (setTimeout on js) lives in the backend.
pub fn Transactor::has_pending(self : Transactor) -> Bool {
  self.queue_head < self.queue.length()
}

///|
pub fn Transactor::settle(
  self : Transactor,
  max_turns? : Int = 10000,
) -> SettleResult {
  if self.draining || max_turns <= 0 {
    return { processed: 0, pending: self.has_pending() }
  }
  self.draining = true
  let mut processed = 0
  while self.has_pending() && processed < max_turns {
    let t = self.queue[self.queue_head]
    self.queue_head += 1
    self.transact(t)
    processed += 1
  }
  self.draining = false
  if !self.has_pending() {
    self.queue.clear()
    self.queue_head = 0
  } else if self.queue_head >= 1024 &&
    self.queue_head * 2 >= self.queue.length() {
    // Keep front-removal amortized O(1): compact only after a substantial
    // consumed prefix is at least half of the allocation.
    self.queue = self.queue[self.queue_head:].to_owned()
    self.queue_head = 0
  }
  if processed > 0 {
    for cb in self.drain_subs {
      cb()
    }
  }
  { processed, pending: self.has_pending() }
}

///|
fn Transactor::transact(self : Transactor, t : Transaction) -> Unit {
  let cur = self.root
  let next = self.update_root_value(t, cur)
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
      // An answer is an ordinary `Receive` and the handler cannot tell it from
      // one a parent sent — which is the design's claim, so the bucket must
      // not know. An INSPECTOR needs to know, and this is the only place that
      // does.
      self.emit(
        if t.is_answer {
          Answer
        } else {
          ObserveKind::of_bucket(t.bucket)
        },
        t,
        cur,
        matched,
      )
    None => ()
  }
  t.finish()
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
      if self.self_settled {
        c.mark_self_settled()
      }
      if self.finished {
        c.release_self()
      }
      self.cmpl = Some(c)
      c
    }
  }
}

///|
fn Transaction::mark_settled(self : Transaction) -> Unit {
  if self.self_settled {
    return
  }
  self.self_settled = true
  match self.cmpl {
    Some(c) => c.mark_self_settled()
    None => ()
  }
}

///|
fn Transaction::finish(self : Transaction) -> Unit {
  self.mark_settled()
  match self.cmpl {
    Some(c) => c.release_self()
    None => ()
  }
  self.finished = true
}

///|
fn Transaction::after_transaction(self : Transaction) -> Unit {
  // A walk advances on its own. `forward` in an intent body does not push the
  // next hop — it amends the one this is about to push — because the design's
  // rule is that every handler on the route runs and a handler that runs does
  // not consume the intent. A body that says nothing continues the walk, and a
  // body that says `forward .enriched` continues it with different arguments.
  match self.walk {
    Some(w) => {
      self.transactor.advance_walk(w)
      return
    }
    None => ()
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
impl @tutuca.Ctx for EventContext with fn is_answer(self) {
  self.txn.is_answer
}

///|
impl @tutuca.Ctx for EventContext with fn stop_propagation(self) {
  // "served, and no answer" (`totuka-v2.md` section 6). The walk ends and the
  // sender is told nothing, even when it declared an arm — which is exactly
  // what separates `stop` from letting the route run out.
  match self.txn.walk {
    Some(w) => {
      w.stopped = true
      self.txn.transactor.end_walk_unanswered(w)
    }
    None => ()
  }
}

///|
impl @tutuca.Ctx for EventContext with fn intent_at_path(
  self,
  path,
  name,
  args,
  opts,
) {
  let _ = self.txn.transactor.push_intent(
    path,
    name,
    args,
    opts~,
    parent=self.txn,
  )
}

///|
/// `forward` in the two bodies it is legal in, and it is one operation seen
/// from two sides.
///
/// In an INTENT body there is a walk, and forwarding amends the hop the walk
/// is about to make: different arguments, or a narrowed route. The walk would
/// have continued anyway.
///
/// In a RECEIVE body there is no walk, so forwarding STARTS one, from this
/// component's own position — which is where the answer will come back to, and
/// which is the component the user clicked in when the message came from a
/// view. This is the one bridge between the two channels.
impl @tutuca.Ctx for EventContext with fn forward(self, args, opts) {
  match self.txn.walk {
    Some(w) => {
      match args {
        Some(a) => w.args = a
        None => ()
      }
      match opts {
        // Narrowing a route that is already walking. `totuka-v2.md` section 18
        // asks whether this should be allowed at all; until it is answered,
        // the straightforward reading is the one implemented — the rest of the
        // route becomes what the forwarder named.
        Some(o) => {
          w.route = o.route
          w.leg = 0
        }
        None => ()
      }
    }
    None => {
      let _ = self.txn.transactor.push_intent(
        self.txn.path,
        self.txn.name,
        args.unwrap_or(self.txn.args),
        opts?,
        parent=self.txn,
      )
    }
  }
}

///|
impl @tutuca.Ctx for EventContext with fn reply(self, value) {
  match self.txn.walk {
    Some(w) => self.txn.transactor.answer_walk(w, Ok(value))
    // A reply with no walk to answer. `Ctx`'s default is a no-op for the same
    // reason, and this is the running-transaction case of it: a message has no
    // sender to answer, and the checker reports the body that wrote this
    // (`NOT_A_HANDLER`) rather than the runtime failing on it.
    None => ()
  }
}

///|
impl @tutuca.Ctx for EventContext with fn fail(self, error) {
  match self.txn.walk {
    Some(w) => self.txn.transactor.answer_walk(w, Err(error))
    None => ()
  }
}
