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
    name,
    route: opts.route,
    leg: 0,
    dyn_at: path,
    args,
    opts,
    origin: path,
    release,
    answered: false,
    stopped: false,
    hops: 0,
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
        if w.dyn_at.items.length() > 0 {
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
        let leaf = w.origin.to_transaction_path().lookup(self.root)
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
  let t = self.mk_txn(
    w.dyn_at,
    Intent,
    w.name,
    w.args,
    target_path=w.origin,
    walk=w,
  )
  self.queue.push(t)
}

///|
/// Ask the lexical chain, one handler at a time, stopping at the first that
/// does not decline.
///
/// Continuation-passing because an `IntentHandler` is handed a callback and may
/// answer later; the walk does not get to assume it answers before returning. A
/// synchronous `Pass` therefore costs one call and one frame.
fn Transactor::try_lex(
  self : Transactor,
  w : IntentWalk,
  handlers : Array[IntentHandler],
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
        path: w.origin.to_transaction_path(),
      })
    }
    self.exhaust_walk(w)
    return
  }
  let IntentHandler(f) = handlers[i]
  let call : @tutuca.IntentCall = { name: w.name, args: w.args, from: w.origin }
  let done : Ref[Bool] = { val: false }
  f(call, answer => {
    // One answer per handler, whatever the handler does with the callback it
    // was given. The walk's own one-shot is a different guard: that one is per
    // INTENT, and it is what stops a second handler from replying after a
    // first one did.
    if done.val {
      return
    }
    done.val = true
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
    Err(e) => (w.opts.on_error_name.unwrap_or(w.name + "Error"), [e])
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
      match w.opts.on_error_name {
        Some(n) => self.deliver_answer(w, n, [Str("noHandler")])
        None => {
          // A sender that declared `Ok` alone still asked a question, so the
          // missing answer is reported rather than dropped. A sender that
          // declared nothing asked nothing.
          if w.opts.on_ok_name is Some(_) && @tutuca.refusing() {
            @tutuca.refuse({
              code: NoHandler,
              asked: w.name,
              rule: "",
              sentence: "",
              state: self.root,
              path: w.origin.to_transaction_path(),
            })
          }
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
  let txn_path = w.origin.to_transaction_path()
  let res_path = if w.opts.live_path {
    None
  } else {
    Some(txn_path.pin_keys(cur_root))
  }
  let t = self.mk_txn(
    w.origin,
    Receive,
    name,
    args,
    txn_path?=res_path,
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
  self.queue.push(t)
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
