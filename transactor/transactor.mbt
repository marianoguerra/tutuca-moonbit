// The dispatcher: the queue, the two channels — an addressed message and an
// intent's walk — and the leaf-update core with completion accounting.

///|
pub fn Transactor::new(
  root : @tutuca.Value,
  intents? : &Intents,
  names? : &Names,
) -> Transactor {
  {
    intents: match intents {
      Some(i) => i
      None => NoIntents::{ }
    },
    names: match names {
      Some(n) => n
      None => NoNames::{ }
    },
    root,
    queue: [],
    queue_head: 0,
    change_subs: [],
    draining: false,
    observers: [],
    obs_seq: 0,
    drain_subs: [],
    recorder: NullRecorder::{ },
    walk_seq: 0,
    turn: 1,
  }
}

///|
pub fn Transactor::set_recorder(self : Transactor, r : &Recorder) -> Unit {
  self.recorder = r
}

///|
pub fn Transactor::recorder(self : Transactor) -> &Recorder {
  self.recorder
}

///|
pub fn Transactor::set_intents(self : Transactor, i : &Intents) -> Unit {
  self.intents = i
}

///|
pub fn Transactor::intents(self : Transactor) -> &Intents {
  self.intents
}

///|
pub fn Transactor::reset_root(self : Transactor, root : @tutuca.Value) -> Unit {
  let cur = self.root
  if physical_equal(root, cur) {
    return
  }
  self.root = root
  for cb in self.change_subs {
    cb(root, cur)
  }
}

///|
pub fn Transactor::set_property(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  value : @tutuca.Value,
) -> @tutuca.PropertyWrite {
  let path = at.to_transaction_path().pin_keys(self.root)
  guard path.lookup(self.root) is Some(leaf) else { return PMissing }
  match leaf.set_property(name, value) {
    PMissing => PMissing
    PUnchanged => PUnchanged
    PRefused => PRefused
    PChanged(next) => {
      let root = path.set_value(self.root, next)
      if physical_equal(root, self.root) {
        PUnchanged
      } else {
        self.reset_root(root)
        // A property call made outside queue draining is its own synchronous
        // transaction. Wake the batched consumers now; inside a handler the
        // surrounding settle owns the one drained notification.
        if !self.draining {
          for cb in self.drain_subs {
            cb()
          }
        }
        PChanged(root)
      }
    }
  }
}

///|
pub fn Transactor::set_member(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  value : @tutuca.Value,
) -> @tutuca.PropertyWrite {
  let path = at.to_transaction_path().pin_keys(self.root)
  guard path.lookup(self.root) is Some(leaf) else { return PMissing }
  match leaf.set_member(name, value) {
    PMissing => PMissing
    PUnchanged => PUnchanged
    PRefused => PRefused
    PChanged(next) => {
      let root = path.set_value(self.root, next)
      if physical_equal(root, self.root) {
        PUnchanged
      } else {
        self.reset_root(root)
        if !self.draining {
          for cb in self.drain_subs {
            cb()
          }
        }
        PChanged(root)
      }
    }
  }
}

///|
pub fn Transactor::mutate_member(
  self : Transactor,
  at : @tutuca.DispatchPath,
  name : String,
  operation : String,
  args : Array[@tutuca.Value],
) -> @tutuca.PropertyWrite {
  let path = at.to_transaction_path().pin_keys(self.root)
  guard path.lookup(self.root) is Some(leaf) else { return PMissing }
  match leaf.mutate_member(name, operation, args) {
    PMissing => PMissing
    PUnchanged => PUnchanged
    PRefused => PRefused
    PChanged(next) => {
      let root = path.set_value(self.root, next)
      if physical_equal(root, self.root) {
        PUnchanged
      } else {
        self.reset_root(root)
        if !self.draining {
          for cb in self.drain_subs {
            cb()
          }
        }
        PChanged(root)
      }
    }
  }
}

///|
/// The next walk id. Never 0: 0 is what a record carries when it belongs to no
/// walk, so a real walk must not be able to collide with it.
fn Transactor::next_walk_id(self : Transactor) -> Int {
  self.walk_seq = self.walk_seq + 1
  self.walk_seq
}

///|
/// Whether anything is watching — an observer, a recorder, or both.
///
/// Asked before a record is BUILT rather than before it is delivered, because
/// building one pins a path and copies an argument list, and a page that
/// installed nothing must not pay for either.
fn Transactor::watched(self : Transactor) -> Bool {
  !self.observers.is_empty() || self.recorder.recording()
}

///|
pub fn Transactor::observe(
  self : Transactor,
  cb : (ObserveRecord) -> Unit,
) -> () -> Unit {
  self.observers.push(cb)
  let done : Ref[Bool] = { val: false, }
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
  walk? : Int = 0,
  parent_seq? : Int = 0,
) -> Int {
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
    walk,
    parent_seq,
  }
  for cb in self.observers {
    cb(record)
  }
  self.recorder.on_observed(record)
  self.obs_seq
}

///|
fn Transactor::emit(
  self : Transactor,
  kind : ObserveKind,
  t : Transaction,
  old_root : @tutuca.Value,
  matched : ObserveMatch,
) -> Unit {
  if !self.watched() {
    return
  }
  // pin field-resolved keys against the root the handler read, so path_keys
  // carries concrete keys
  let path = (match t.txn_path {
    Some(p) => p
    None => t.path.to_transaction_path()
  }).pin_keys(old_root)
  // The causal link, and why it is read HERE: a parent's record is emitted
  // when the parent's handler finished, which is strictly before it could have
  // pushed this one, so by now `parent.obs_seq` is stamped.
  t.obs_seq = self.emit_record(
    kind,
    t.name,
    t.args,
    path,
    t.target_path,
    matched,
    t.obs_before,
    t.obs_after,
    walk=t.walk_id,
    parent_seq=match t.parent {
      Some(p) => p.obs_seq
      None => 0
    },
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
/// Queue `t` and make it a tracked unit of `parent`'s subtree:
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
  self.enqueue(t, if parent is None { Extern } else { Derived })
  t
}

///|
/// Put a transaction on the queue, telling the recorder it happened.
///
/// The single door, and it has to be single: an answer the runtime writes and
/// one hop of an intent's walk are queued directly rather than through
/// `push_send`, so a hook on the public entry points alone would miss exactly
/// the dispatches that make a walk legible.
///
/// `source` is passed rather than inferred from `parent`, because the two
/// direct pushes have no parent transaction and are nonetheless derived: the
/// walk caused them, and a walk is not a transaction.
fn Transactor::enqueue(
  self : Transactor,
  t : Transaction,
  source : Source,
) -> Unit {
  if self.recorder.recording() {
    t.push_seq = self.next_record_seq()
    self.recorder.on_dispatch({
      source,
      bucket: t.bucket,
      name: t.name,
      args: t.args,
      at: (match t.txn_path {
        Some(p) => p
        None => t.path.to_transaction_path()
      }).pin_keys(self.root),
      walk: t.walk_id,
      // A handler pushed it, or a WALK did — and a walk is not a transaction,
      // so the two cases read from different places and mean the same thing.
      parent: match t.parent {
        Some(p) => p.push_seq
        None => t.walk_parent
      },
      opts: match t.walk {
        Some(w) => w.opts
        None => @tutuca.IntentOpts::new()
      },
      turn: self.turn,
      seq: t.push_seq,
    })
  }
  self.queue.push(t)
}

///|
/// One queued dispatch. The channels differ in a field or three: the bucket,
/// the walk it belongs to, a pre-pinned answer path.
fn Transactor::mk_txn(
  self : Transactor,
  path : @tutuca.DispatchPath,
  bucket : @tutuca.HandlerBucket,
  name : String,
  args : Array[@tutuca.Value],
  provenance? : @tutuca.DispatchProvenance = Host,
  target_path? : @tutuca.DispatchPath,
  txn_path? : @tutuca.Path,
  parent? : Transaction,
  walk? : IntentWalk,
  walk_id? : Int = 0,
  walk_parent? : Int = 0,
  is_answer? : Bool = false,
  origin? : @tutuca.DispatchPath,
  origin_pinned? : @tutuca.Path,
) -> Transaction {
  {
    transactor: self,
    path,
    bucket,
    name,
    args,
    provenance,
    target_path: target_path.unwrap_or(path),
    txn_path,
    parent,
    walk,
    is_answer,
    origin,
    origin_pinned,
    cmpl: None,
    self_settled: false,
    finished: false,
    obs_matched: None,
    obs_before: None,
    obs_after: None,
    obs_seq: 0,
    push_seq: 0,
    walk_parent: match walk {
      Some(w) => w.raise_seq
      None => walk_parent
    },
    walk_id: match walk {
      Some(w) => w.id
      None => walk_id
    },
  }
}

///|
/// `origin` is where the message came FROM, pinned NOW against the current
/// root: a reply must reach the sender that asked even if a key moves while
/// the message is in flight. A send with no origin — the host's
/// `send_at_root`, a view's own `@on.*` — leaves nobody to reply to, which is
/// what `ctx.send_reply` refuses on.
pub fn Transactor::push_send(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  parent? : Transaction,
  origin? : @tutuca.DispatchPath,
  provenance? : @tutuca.DispatchProvenance = Host,
) -> Transaction {
  let origin_pinned : @tutuca.Path? = match origin {
    Some(o) => Some(o.to_transaction_path().pin_keys(self.root))
    None => None
  }
  let t = self.mk_txn(
    path,
    Receive,
    name,
    args,
    provenance~,
    parent?,
    origin?,
    origin_pinned?,
  )
  // `parent` is the whole of the distinction, and `link` is where it is read:
  // a handler pushed this, or something outside the tree did.
  self.link(t, parent)
}

///|
/// A number for a record that is not an `ObserveRecord` — a dispatch entering
/// the queue, an intent offered to a host, an answer coming back.
///
/// The SAME counter the observer records use, deliberately: a recording
/// interleaves both kinds and a reader orders them by this one number. Two
/// counters would mean two orderings and no way to merge them.
fn Transactor::next_record_seq(self : Transactor) -> Int {
  self.obs_seq = self.obs_seq + 1
  self.obs_seq
}

///|
/// Whether transactions remain queued.
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
    return { processed: 0, pending: self.has_pending(), }
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
  // One turn is everything pushed between two drains — one DOM event with two
  // handlers is one turn, not two. Bumped here because `draining` already
  // identifies the outermost pass, so nothing outside has to say where a turn
  // begins.
  self.turn = self.turn + 1
  { processed, pending: self.has_pending(), }
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
      // one a parent sent — that is the claim, so the bucket must not know. An
      // INSPECTOR needs to know, and this is the only place that does.
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
  // observed with NoHandler)
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
  let ctx = EventContext::{ txn: t, }
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
/// seam over this transaction.
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
impl @tutuca.Ctx for EventContext with fn provenance(self) {
  self.txn.provenance
}

///|
// `send` / `bubble` are not implemented: the trait defaults route them to the
// two below at `path()`.
impl @tutuca.Ctx for EventContext with fn send_at_path(self, path, name, args) {
  let _ = self.txn.transactor.push_send(
    path,
    name,
    args,
    parent=self.txn,
    origin=self.txn.path,
    provenance=Component,
  )
}

///|
/// Answer whoever sent the message being handled, under a name this handler
/// picks.
///
/// The reply is an ORDINARY message: it lands in the same `receive` bucket and
/// the sender cannot tell it from any other send. It goes to the sender's
/// position as pinned at the moment they sent — see `Transactor::push_send`.
impl @tutuca.Ctx for EventContext with fn send_reply(self, name, args) {
  let tx = self.txn.transactor
  match (self.txn.origin, self.txn.origin_pinned) {
    (Some(origin), pinned) => {
      let t = tx.mk_txn(
        origin,
        Receive,
        name,
        args,
        txn_path?=pinned,
        parent=self.txn,
        origin=self.txn.path,
        origin_pinned=self.txn.path.to_transaction_path().pin_keys(tx.root),
      )
      let _ = tx.link(t, Some(self.txn))
    }
    // Nobody is waiting. A view's own `@on.*` and the host's `send_at_root`
    // both arrive with no sender, so there is no position to answer at and
    // nothing is dispatched.
    (None, _) =>
      if @tutuca.refusing() {
        @tutuca.refuse({
          code: NoSender,
          asked: name,
          rule: "",
          sentence: "",
          state: tx.root,
          path: self.txn.path.to_transaction_path(),
        })
      }
  }
}

///|
/// Resolve a name along `opts.route` — the handler-side twin of a view's
/// `*name` read.
impl @tutuca.Ctx for EventContext with fn lookup(self, name, opts) {
  let tx = self.txn.transactor
  let root = tx.root
  let at = self.txn.path
  match
    @tutuca.route_lookup(opts.route, () => tx.names.lex_value(root, at, name), () => {
      tx.names.dyn_value(root, at, name)
    }) {
    Some(v) => v
    None => {
      // A qualified lookup is an exercised protocol assumption. Keep the
      // ordinary total lookup behavior, but make the deferred mismatch
      // observable through the same code the static validator uses.
      let parts : Array[String] = name
        .split("::")
        .map(x => x.to_owned())
        .collect()
      if parts.length() == 2 {
        @tutuca.protocol_mismatch({
          code: ProtocolLookupMissing,
          protocol_id: parts[0],
          member_name: parts[1],
          operation: "lookup",
          detail: "no provider answered the qualified protocol lookup",
          component: "",
          path: at.to_transaction_path(),
          state: root,
          resolution: ReturnedNull,
        })
      }
      Null
    }
  }
}

///|
/// Resolve a component type along `opts.route` and build one.
impl @tutuca.Ctx for EventContext with fn make(self, name, args, opts) {
  let tx = self.txn.transactor
  let root = tx.root
  let at = self.txn.path
  match
    @tutuca.route_lookup(opts.route, () => tx.names.lex_type(root, at, name), () => {
      tx.names.dyn_type(root, at, name)
    }) {
    Some(id) => tx.names.build(id, args)
    None => {
      if @tutuca.refusing() {
        @tutuca.refuse({
          code: TypeNotFound,
          asked: name,
          rule: @tutuca.route_label(opts.route),
          sentence: "",
          state: root,
          path: at.to_transaction_path(),
        })
      }
      None
    }
  }
}

///|
/// The component instance a chain node carries, with its component id — None
/// for non-component nodes.
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
impl @tutuca.Ctx for EventContext with fn stop_propagation(self) {
  // "served, and no answer". The walk ends and the
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
        // Narrowing a route that is already walking. the intent walk
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
