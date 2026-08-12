// A card's instance: `@tutuca.Obj` over a plain fields map.
//
// The same shape `dyncomp/host/dynobj.mbt` has, with the guest bridge replaced
// by the interpreter. Reading that file beside this one is the fastest way to
// see what a card IS: everything except `obj_handler` and `obj_field`'s middle
// case is the same answer given for the same reason.

///|
/// What every instance of one card shares. Built once when the card loads, so
/// mounting an instance costs a map copy and nothing else.
///
/// Public for the same reason `CardObj` is, and equally opaque.
pub struct Deck {
  comp_id : Ref[Int]
  schema : @tutuca.SchemaInfo
  /// Handler declarations, by bucket. Four maps rather than one keyed on a
  /// pair, because a lookup happens on every dispatch and the bucket is
  /// already in hand.
  inputs : Map[String, @tscript.Decl]
  receives : Map[String, @tscript.Decl]
  bubbles : Map[String, @tscript.Decl]
  responses : Map[String, @tscript.Decl]
  /// `compute` and `pred`: both answer an application, so both live here.
  callables : Map[String, @tscript.Decl]
  /// `enrich` / `enrichScope`, which the render layer resolves through the
  /// Alter namespace rather than as fields.
  alters : Map[String, @tscript.Decl]
  /// The mutators the schema implies — `setX`, `toggleX`, `pushInX` — from the
  /// same generator a guest's come from. A card gets them for free, which is
  /// why two thirds of the components in the corpus need no handler at all.
  mutators : Map[
    String,
    (@component.FieldBox, Array[@tutuca.Value]) -> @tutuca.Value,
  ]
}

///|
/// One instance: the deck it belongs to, and its fields.
///
/// Public because an `impl` of a public trait cannot be written for a private
/// type, and opaque because nothing outside has any business reaching in — a
/// holder reads it through `@tutuca.Obj` like every other instance in the
/// tree.
pub struct CardObj {
  deck : Deck
  fields : Map[String, @tutuca.Value]
  id : @tutuca.ObjId
}

///|
fn CardObj::new(deck : Deck, fields : Map[String, @tutuca.Value]) -> CardObj {
  { deck, fields, id: @tutuca.ObjId::of(deck.schema.fingerprint, fields) }
}

///|
/// The successor after a write: same origin, next revision, so two generations
/// of one instance do not fight for a render-cache bucket.
fn CardObj::successor(
  self : CardObj,
  fields : Map[String, @tutuca.Value],
) -> CardObj {
  { deck: self.deck, fields, id: self.id.next() }
}

///|
/// The environment a body runs in: this instance's fields, the block's
/// callables, and the schema — which is consulted for exactly one thing, an
/// integer field truncating on the way in.
fn CardObj::env(self : CardObj) -> @interp.Env {
  @interp.Env::of_state(
    self.fields,
    callables=self.deck.callables,
    schema=self.deck.schema,
  )
}

///|
/// Drop the self-prebound `this` a generated mutator's `Fn` receives.
fn drop_this(args : Array[@tutuca.Value]) -> Array[@tutuca.Value] {
  if args.is_empty() {
    args
  } else {
    args[1:].to_owned()
  }
}

///|
/// This instance as the generated mutators see it. Identical to `DynObj`'s,
/// down to the no-op answer being the instance itself — which is what the
/// transactor reads by `physical_equal` as "nothing happened".
fn CardObj::field_box(self : CardObj) -> @component.FieldBox {
  {
    get: name => self.obj_field(name).unwrap_or(Null),
    set: (name, v) => self.obj_with_field(name, v).unwrap_or(Obj(self)),
    value: () => Obj(self),
  }
}

///|
/// A `compute` or a `pred`, as a value a slot can read.
///
/// Self-pre-bound, like every other callable an `Obj` hands out: the closure
/// holds the instance, and argument 0 is the `this` the caller passes and this
/// ignores.
fn CardObj::callable_fn(self : CardObj, d : @tscript.Decl) -> @tutuca.Value {
  Fn(args => {
    let params : Map[String, @tutuca.Value] = Map([])
    let given = drop_this(args)
    for i, p in d.params {
      params[p.name] = given.get(i).unwrap_or(Null)
    }
    match @interp.call(d, { ..self.env(), params, }) {
      Some(v) => v
      // A body that could not finish reads Null, which is what an unanswered
      // name reads as everywhere else in a slot.
      None => Null
    }
  })
}

///|
pub impl @tutuca.Obj for CardObj with fn component_id(self) {
  Some(self.deck.comp_id.val)
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_identity(self) {
  Some(self.id)
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_schema(self) {
  Some(self.deck.schema)
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_field(self, name) {
  // A declared field first: state is what a view mostly reads, and a card that
  // let a handler name shadow a field would be a card whose views lie.
  if self.fields.get(name) is Some(v) {
    return Some(v)
  }
  if self.deck.callables.get(name) is Some(d) {
    return Some(self.callable_fn(d))
  }
  match self.deck.mutators.get(name) {
    Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
    None => None
  }
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_with_field(self, name, v) {
  // A field the schema does not declare is not written. The card's fields ARE
  // its schema's fields, and a mutator that grew one would make the descriptor
  // wrong about the instance it describes.
  guard self.fields.contains(name) else { return None }
  let next : Map[String, @tutuca.Value] = Map([])
  for k, old in self.fields {
    next[k] = if k == name { v } else { old }
  }
  Some(Obj(self.successor(next)))
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_callable(self, name, ns) {
  // The render-time namespace: `@when` resolves a predicate here, and
  // `@enrich-with` / `@loop-with` their own declarations.
  if ns is Alter {
    if self.deck.alters.get(name) is Some(d) {
      return Some(self.alter_fn(d))
    }
    if self.deck.callables.get(name) is Some(d) {
      return Some(self.callable_fn(d))
    }
    return None
  }
  if self.deck.callables.get(name) is Some(d) {
    return Some(self.callable_fn(d))
  }
  match self.deck.mutators.get(name) {
    Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
    None => None
  }
}

///|
/// An `enrich` / `enrichScope` declaration, in the shape the renderer calls.
///
/// The renderer passes `(this, binds, key, value, iterData)` for the in-loop
/// form and `(this)` for the scope form, and both come back as the binds map
/// — which is what the scope form returns and what the in-loop form mutates.
/// A card returns a fresh map in both cases and lets the caller merge, since
/// mutating an argument is a MoonBit convenience an interpreter has no need
/// of.
fn CardObj::alter_fn(self : CardObj, d : @tscript.Decl) -> @tutuca.Value {
  Fn(args => {
    let given = drop_this(args)
    let binds : Map[String, @tutuca.Value] = Map([])
    // The in-loop form is handed the binds map it is to extend, then the
    // iteration values. The scope form is handed nothing.
    let rest = match given.get(0) {
      Some(Map(m)) => {
        for k, v in m {
          binds[k] = v
        }
        given[1:].to_owned()
      }
      _ => given
    }
    if rest.get(0) is Some(k) {
      binds["key"] = k
    }
    if rest.get(1) is Some(v) {
      binds["value"] = v
    }
    if rest.get(2) is Some(it) {
      binds["iter"] = it
    }
    let env : @interp.Env = { ..self.env(), binds, }
    match d.body {
      Value(_) =>
        match @interp.call(d, env) {
          Some(v) => v
          None => Null
        }
      Stmts(ss) =>
        match @interp.run(ss, env).state {
          // A statement body over binds writes THEM, not state — the
          // interpreter threads both, and this is the half the renderer wants.
          Some(_) => Map(run_binds(ss, env))
          None => Map(binds)
        }
    }
  })
}

///|
/// The bindings a statement body produced.
fn run_binds(
  ss : Array[@tscript.Stmt],
  env : @interp.Env,
) -> Map[String, @tutuca.Value] {
  let binds : Map[String, @tutuca.Value] = Map([])
  for k, v in env.binds {
    binds[k] = v
  }
  let scoped : @interp.Env = { ..env, binds, }
  @interp.run(ss, scoped) |> ignore
  binds
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_handler(self, bucket, name) {
  let d = match bucket {
    Input => self.deck.inputs.get(name)
    Receive => self.deck.receives.get(name)
    Bubble => self.deck.bubbles.get(name)
    Response => self.deck.responses.get(name)
  }
  // An Input name with no arm here still has to reach the generated mutators:
  // that fallback is the documented dispatch precedence, and it lives INSIDE
  // the handler rather than beside it (`component/instance.mbt` does the same),
  // so declining before building one would take `setLabel` away from every
  // card that did not bother to declare it.
  let mutator = if bucket is Input {
    self.deck.mutators.get(name)
  } else {
    None
  }
  guard d is Some(_) || mutator is Some(_) else { return None }
  Some(
    Handler((args, ctx) => {
      guard d is Some(decl) else {
        // No arm: the mutator answers, and answers with an instance or with
        // nothing at all.
        guard mutator is Some(g) else { return None }
        return match g(self.field_box(), args) {
          Obj(_) as nv => Some(nv)
          _ => None
        }
      }
      let out = @interp.dispatch(decl, args, self.env())
      // Effects go out ONLY when the body finished: `Outcome` drops them with
      // the state, because half a transition — nothing moved but a message
      // went out — is the one outcome nobody can reason about afterwards.
      for e in out.effects {
        match e {
          ESend(name~, args~) => ctx.send(name, args)
          EBubble(name~, args~) => ctx.bubble(name, args)
          ERequest(name~) => ctx.request(name, [], @tutuca.RequestOpts::new())
          // Relative to this component, exactly as the MoonBit idiom is:
          // `ctx.send_at_path(ctx.path().concat([...]), …)`.
          ESendAt(steps~, name~, args~) =>
            ctx.send_at_path(ctx.path().concat(steps), name, args)
          EStop => ctx.stop_propagation()
        }
      }
      match out.state {
        Some(next) => Some(Obj(self.successor(next)))
        // The body declined, or could not finish. Same answer either way, and
        // the same one an `update` arm gives: no successor. It does NOT fall
        // through to a mutator of the same name — a name is answered once, and
        // an arm that returned nothing has answered.
        None => None
      }
    }),
  )
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_item(self, key) {
  match key {
    KStr(k) => self.fields.get(k)
    KInt(_) => None
  }
}

///|
pub impl @tutuca.Obj for CardObj with fn obj_persist_id(_self) {
  None
}
