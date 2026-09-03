// The intent walk.
//
// An intent names a job, not a component, and carries a ROUTE: a list of legs
// to try. `Dyn` walks the dispatch path from the sender's PARENT up to the
// root; `Lex` walks the registration scope chain. One dispatch may therefore
// visit many positions before one of them answers, and this file owns that
// traversal.
//
// Three things end a walk, and the file is organized around them: a handler
// replies or fails (`answer_walk`), a handler stops (`end_walk_unanswered`),
// or the route runs out (`exhaust_walk`). Everything else — every handler that
// merely runs — continues it, which is the one rule.

///|
pub fn Transactor::push_intent(
  self : Transactor,
  path : @tutuca.DispatchPath,
  name : String,
  args : Array[@tutuca.Value],
  opts? : @tutuca.IntentOpts,
  parent? : Transaction,
) -> IntentWalk {
  let opts = match opts {
    Some(o) => o
    None => @tutuca.IntentOpts::new()
  }
  // Track on the sender NOW — during its handler, while its self-unit is still
  // held — so its counter cannot reach zero before the walk registers. The unit
  // is held for the whole WALK rather than for one call, and released exactly
  // once however the walk ends.
  let release = match parent {
    Some(p) => Some(p.completion().track())
    None => None
  }
  let w : IntentWalk = {
    raise_seq: 0,
    id: self.next_walk_id(),
    name,
    route: opts.route,
    leg: 0,
    dyn_at: path,
    args,
    opts,
    sender: path,
    release,
    answered: false,
    stopped: false,
    hops: 0,
  }
  if self.recorder.recording() {
    // Stamped on the walk before anything it causes is pushed, so every hop,
    // offer, answer and reply can point back at it.
    w.raise_seq = self.next_record_seq()
    self.recorder.on_dispatch({
      origin: if parent is None {
        Host
      } else {
        Handler
      },
      bucket: Intent,
      name,
      args,
      at: path.to_transaction_path().pin_keys(self.root),
      walk: w.id,
      parent: match parent {
        Some(p) => p.push_seq
        None => 0
      },
      opts: w.opts,
      turn: self.turn,
      seq: w.raise_seq,
    })
  }
  self.advance_walk(w)
  w
}

///|
/// Move the walk to its next position, or end it.
///
/// A loop rather than a recursion because a leg can contribute nothing — a
/// `dyn` leg from the root has no parent to visit, and a `lex` leg whose scope
/// declares nothing has no handler — and a route of two such legs must reach
/// exhaustion in one call rather than in two nested ones.
fn Transactor::advance_walk(self : Transactor, w : IntentWalk) -> Unit {
  if w.answered || w.stopped {
    return
  }
  while w.leg < w.route.length() {
    match w.route[w.leg] {
      Dyn =>
        // The position to visit is the PARENT of where we are, so the pop
        // comes first. An empty path has no parent, which is what ends the leg.
        if w.dyn_at.can_pop() {
          w.dyn_at = w.dyn_at.pop_step()
          self.queue_hop(w)
          return
        } else {
          w.leg = w.leg + 1
        }
      Lex => {
        // The whole leg, inside the transaction that is already running: the
        // handlers come back as a chain and a `Pass` moves to the next one
        // with a call rather than a queue step.
        let leaf = w.sender.to_transaction_path().lookup(self.root)
        let handlers = match leaf {
          Some(l) => self.intents.intents_for(l, w.name)
          None => []
        }
        w.leg = w.leg + 1
        if handlers.length() > 0 {
          self.try_lex(w, handlers, 0)
          return
        }
      }
    }
  }
  self.exhaust_walk(w)
}

///|
/// Queue one `dyn` hop, and count it against the depth limit.
fn Transactor::queue_hop(self : Transactor, w : IntentWalk) -> Unit {
  w.hops = w.hops + 1
  if w.hops > INTENT_DEPTH {
    if @tutuca.refusing() {
      @tutuca.refuse({
        code: IntentDepth,
        asked: w.name,
        rule: "",
        sentence: "",
        state: self.root,
        path: w.dyn_at.to_transaction_path(),
      })
    }
    // Ended the way the route ending ends it, so a sender that asked for an
    // answer learns something rather than waiting forever.
    self.exhaust_walk(w)
    return
  }
  // A hop is derived even at the head of the walk: the WALK caused it, and a
  // walk is not a transaction, so there is no parent to say so. What raised
  // the walk itself is recorded once, on the walk.
  let t = self.mk_txn(
    w.dyn_at,
    Intent,
    w.name,
    w.args,
    origin=Handler,
    target_path=w.sender,
    walk=w,
  )
  self.enqueue(t)
}

///|
/// Ask the lexical chain, one handler at a time, stopping at the first that
/// does not decline.
///
/// Continuation-passing because an `IntentFn` is handed a callback and may
/// answer later; the walk does not get to assume it answers before returning. A
/// synchronous `Pass` therefore costs one call and one frame.
fn Transactor::try_lex(
  self : Transactor,
  w : IntentWalk,
  handlers : Array[IntentFn],
  i : Int,
) -> Unit {
  if w.answered || w.stopped {
    return
  }
  if i >= handlers.length() {
    self.advance_walk(w)
    return
  }
  w.hops = w.hops + 1
  if w.hops > INTENT_DEPTH {
    if @tutuca.refusing() {
      @tutuca.refuse({
        code: IntentDepth,
        asked: w.name,
        rule: "",
        sentence: "",
        state: self.root,
        path: w.sender.to_transaction_path(),
      })
    }
    self.exhaust_walk(w)
    return
  }
  let IntentFn(f) = handlers[i]
  let from = w.sender.to_transaction_path().pin_keys(self.root)
  let call : @tutuca.IntentCall = {
    name: w.name,
    args: w.args,
    from: w.sender,
  }
  // The boundary, made visible. A lexical hop is invoked inline rather than
  // queued as a transaction, so nothing here ever reached an observer: a log
  // showed an intent climbing the tree, then stopping, then an answer arriving
  // from nowhere. This hop is the moment the intent LEAVES the tree, and it is
  // the one thing a recording of a host-integrated app cannot do without.
  //
  // `Exact` is the honest answer even though the handler has not run: the
  // chain came back non-empty, so a handler was resolved. Whether it CLAIMS the
  // intent is the answer's business, and a `Pass` is reported by the next hop
  // existing at all.
  if self.watched() {
    self.emit_record(
      Handler,
      Intent,
      false,
      w.name,
      w.args,
      from,
      w.sender,
      Exact,
      None,
      None,
      walk=w.id,
    )
    |> ignore
  }
  if self.recorder.recording() {
    self.recorder.on_offered({
      walk: w.id,
      parent: w.raise_seq,
      name: w.name,
      args: w.args,
      from,
      nth: i,
      seq: self.next_record_seq(),
    })
  }
  let done : Ref[Bool] = { val: false, }
  f(call, answer => {
    // One answer per handler, whatever the handler does with the callback it
    // was given. The walk's own one-shot is a different guard: that one is per
    // INTENT, and it is what stops a second handler from replying after a
    // first one did.
    if done.val {
      return
    }
    done.val = true
    // Recorded BEFORE it is acted on, so a late answer lands in the recording
    // where it actually arrived rather than where the intent was raised. That
    // ordering is the whole reason an asynchronous host can be replayed at all.
    if self.recorder.recording() {
      self.recorder.on_answer({
        walk: w.id,
        parent: w.raise_seq,
        nth: i,
        answer,
        seq: self.next_record_seq(),
      })
    }
    match answer {
      Ok(v) => self.answer_walk(w, Ok(v))
      Failed(e) => self.answer_walk(w, Err(e))
      Pass => self.try_lex(w, handlers, i + 1)
    }
  })
}

///|
/// A handler replied or failed: the walk stops and the answer goes to the
/// sender.
fn Transactor::answer_walk(
  self : Transactor,
  w : IntentWalk,
  result : Result[@tutuca.Value, @tutuca.Value],
) -> Unit {
  if w.answered || w.stopped {
    return
  }
  w.answered = true
  // The names the sender declared, and the derived ones otherwise. Deriving is
  // right here and not in `exhaust_walk`: a reply nobody declared an arm for
  // reaches no arm and produces a `NO_HANDLER` refusal, which is what the
  // design says happens (section 1), while the unhandled outcome's fallback
  // chain is defined in terms of what the sender DECLARED (section 6) and
  // would be unobservable if it derived a name too.
  let (name, args) = match result {
    Ok(v) => (w.opts.on_ok_name.unwrap_or(w.name + "Ok"), [v])
    Err(e) => (w.opts.on_failed_name.unwrap_or(w.name + "Failed"), [e])
  }
  self.deliver_answer(w, name, args)
}

///|
/// The route ended with no reply.
///
/// Three shapes, and which one applies is decided by what the SENDER declared,
/// not by anything a handler did. A sender that declared nothing is sending a
/// notification and hears nothing, which is the common case and has to stay
/// free.
fn Transactor::exhaust_walk(self : Transactor, w : IntentWalk) -> Unit {
  if w.answered || w.stopped {
    return
  }
  w.answered = true
  match w.opts.on_unhandled_name {
    // Carries the intent's OWN arguments, so a sender can degrade or retry
    // without having kept a copy.
    Some(n) => self.deliver_answer(w, n, w.args)
    None =>
      match w.opts.on_failed_name {
        Some(n) => self.deliver_answer(w, n, [Str("noHandler")])
        // A sender that declared `Ok` alone still asked a question, so the
        // missing answer is DELIVERED rather than dropped — under the derived
        // name, the way `Ok` and `Failed` are derived, and carrying the
        // intent's own arguments the way a declared `Unhandled` does. If the
        // sender has no arm for it, that lands as a `NO_HANDLER` refusal
        // naming `<n>Unhandled`, which says more than a refusal naming the
        // intent did. A sender that declared nothing asked nothing.
        None =>
          if w.opts.on_ok_name is Some(_) {
            self.deliver_answer(w, w.name + "Unhandled", w.args)
          } else {
            self.release_walk(w)
          }
      }
  }
}

///|
/// `stop`: the walk ends and the sender is told nothing, even when it declared
/// an arm.
fn Transactor::end_walk_unanswered(self : Transactor, w : IntentWalk) -> Unit {
  ignore(self)
  self.release_walk(w)
}

///|
/// Queue the answer as an ordinary message at the sender's position, and hand
/// the sender's unit to it.
///
/// The sender's path is pinned against the root the walk started from unless
/// `live_path` says otherwise: the answer must reach the item that asked, even
/// if a key changed while the walk ran.
fn Transactor::deliver_answer(
  self : Transactor,
  w : IntentWalk,
  name : String,
  args : Array[@tutuca.Value],
) -> Unit {
  let cur_root = self.root
  let txn_path = w.sender.to_transaction_path()
  let res_path = if w.opts.live_path {
    None
  } else {
    Some(txn_path.pin_keys(cur_root))
  }
  // `walk_id` and not `walk`: the answer BELONGS to the walk, but it must not
  // advance one — the walk is already over, and `after_transaction` advances
  // whatever `walk` names.
  let t = self.mk_txn(
    w.sender,
    Receive,
    name,
    args,
    origin=Handler,
    txn_path?=res_path,
    walk_id=w.id,
    walk_parent=w.raise_seq,
    is_answer=true,
  )
  // Transferred rather than released: the sender stays open until the answer
  // itself and everything it derives have settled. Queued directly rather than
  // linked, so the unit is not counted twice.
  match w.release {
    Some(r) => {
      w.release = None
      t.completion().on_subtree_settled(r)
    }
    None => ()
  }
  self.enqueue(t)
}

///|
/// End the walk with no answer, letting the sender go.
fn Transactor::release_walk(self : Transactor, w : IntentWalk) -> Unit {
  ignore(self)
  match w.release {
    Some(r) => {
      w.release = None
      r()
    }
    None => ()
  }
}
