// TypedInstance: the runtime instance of a typed-state component. The state
// struct S is the source of truth; a parallel encoded fields map (S fields
// plus spec-declared slots such as child components) serves the render/path/
// Value seams. encode/decode are generated field by field, so an `Obj` or an
// `Fn` held by S crosses unchanged — which a Json round trip, the bridge this
// replaced, could not do at all.

///|
/// The S-typed half of a component definition, erased behind Component's
/// make closure. `comp` is wired right after Component construction.
priv struct TypedSpec[S] {
  mut comp : Component?
  init : S
  s_fields : Array[String]
  update : ((S, Dispatch, &@tutuca.Ctx) -> S?)?
  compute : Map[String, (S, Array[@tutuca.Value]) -> @tutuca.Value]
  swap : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?]
  when : Map[String, (S, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool]
  enrich : Map[
    String,
    (S, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit,
  ]
  enrich_scope : Map[String, (S) -> Map[String, @tutuca.Value]]
  loop_with : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith]
  generated : Map[
    String,
    (TypedInstance[S], Array[@tutuca.Value]) -> @tutuca.Value,
  ]
  /// Direct state <-> fields conversion, field by field.
  ///
  /// There used to be a JSON bridge behind these — `S -> Json -> Value` and
  /// back, inside a process-global stash, because `Obj` and `Fn` cannot
  /// survive JSON at all. It was the fallback for a component with no declared
  /// schema to generate a codec from, and measured ~2x slower on encode and
  /// ~5x on decode (benchmarks/codec_bench_test.mbt). Every component declares
  /// one now, so there is nothing left to fall back to and the bridge is gone.
  encode : (S) -> Map[String, @tutuca.Value]
  decode : (Map[String, @tutuca.Value]) -> S?
}

///|
priv struct TypedInstance[S] {
  spec : TypedSpec[S]
  state : S
  fields : Map[String, @tutuca.Value]
  // Memoized `Obj(self)`. The seams downstream of an instance — Path
  // copy-on-write, the transactor's root-swap check — compare Values by
  // IDENTITY, and each `Obj(self)` cast allocates a fresh box. One stable
  // Value per instance is what lets an unchanged instance still look
  // unchanged after a round trip through the value world.
  mut boxed : @tutuca.Value?
}

///|
fn[S] TypedInstance::make(
  spec : TypedSpec[S],
  state : S,
  fields : Map[String, @tutuca.Value],
) -> TypedInstance[S] {
  { spec, state, fields, boxed: None }
}

///|
/// Dispatch/handler args carry no this-slot by the time they reach methods;
/// Fn-convention callers (call_handler) prepend one — drop it.
fn drop_this(args : Array[@tutuca.Value]) -> Array[@tutuca.Value] {
  if args.length() > 0 {
    args[1:].to_owned()
  } else {
    []
  }
}

///|
/// How much comparing an encoded field may cost before `reuse_equal` gives up
/// and keeps the new object. Fuel is spent ONLY where the two sides don't
/// already share structure, so this is not a size limit on state — it is a
/// limit on how deep a scan is worth doing to save an allocation.
const REUSE_FUEL = 64

///|
/// "These two are equal, and finding that out was cheap."
///
/// Keeping the old object is an optimization, so answering `false` is always
/// safe — which is what lets this give up instead of paying for a deep scan.
/// Fuel is spent only where the two sides do NOT already share structure: a
/// list of child components rebuilt by `encode` compares element-wise in O(1)
/// each (the generated codec passes every `Obj` straight through, so the
/// elements ARE the same objects) and costs one unit for the list itself,
/// while a 1000-item list
/// of plain maps would cost a deep map compare per element and bails out
/// after the first handful. Identity is preserved exactly where preserving it
/// is nearly free, which is also where it pays: the subtrees a transaction
/// did not touch.
fn reuse_equal(a : @tutuca.Value, b : @tutuca.Value, fuel : Ref[Int]) -> Bool {
  if physical_equal(a, b) {
    return true
  }
  if fuel.val <= 0 {
    return false
  }
  fuel.val -= 1
  match (a, b) {
    (List(x), List(y)) => {
      if x.length() != y.length() {
        return false
      }
      for i in 0..<x.length() {
        if !reuse_equal(x[i], y[i], fuel) {
          return false
        }
      }
      true
    }
    (Map(x), Map(y)) => {
      if x.length() != y.length() {
        return false
      }
      for k, v in x {
        match y.get(k) {
          Some(v2) => if !reuse_equal(v, v2, fuel) { return false }
          None => return false
        }
      }
      true
    }
    _ => a == b
  }
}

///|
/// New instance from an updated state; slot fields (not part of S) carry over.
///
/// Encoding builds every container fresh — a `list<s32>` field becomes a new
/// `List` on each call, whatever the state did — and identity is exactly what
/// Path copy-on-write reads. So each freshly encoded field is compared with
/// the one it replaces and the OLD object kept when the two are equal; a
/// rebuilt-but-equal field would otherwise propagate a new object all the way
/// to the root. When no encoded field and no slot field changed, the ORIGINAL
/// instance is returned, and the no-op reaches the transactor as "the root is
/// the same object": no re-render is scheduled.
fn[S] TypedInstance::with_state(
  self : TypedInstance[S],
  s : S,
) -> TypedInstance[S] {
  let encoded = (self.spec.encode)(s)
  let fields : Map[String, @tutuca.Value] = Map([])
  let mut changed = false
  for name, v in encoded {
    let fuel = Ref(REUSE_FUEL)
    match self.fields.get(name) {
      Some(old) if reuse_equal(old, v, fuel) => fields[name] = old
      _ => {
        changed = true
        fields[name] = v
      }
    }
  }
  // slot fields (spec-declared, not part of S) are untouched by the state
  for name, v in self.fields {
    if !fields.contains(name) {
      fields[name] = v
    }
  }
  if !changed && fields.length() == self.fields.length() {
    return self
  }
  TypedInstance::make(self.spec, s, fields)
}

///|
fn[S] TypedInstance::get(
  self : TypedInstance[S],
  name : String,
) -> @tutuca.Value {
  self.fields.get(name).unwrap_or(Null)
}

///|
/// Coerced field write; unknown names and undecodable results keep the
/// instance unchanged.
fn[S] TypedInstance::set(
  self : TypedInstance[S],
  name : String,
  v : @tutuca.Value,
) -> TypedInstance[S] {
  guard self.spec.comp is Some(comp) else { return self }
  guard comp.specs.get(name) is Some(fspec) else { return self }
  let coerced = fspec.coerce_or_default(v)
  // Writing a value equal to the one already stored changes nothing, so keep
  // THIS instance — a `$setCompleted value` that re-sends the value the
  // checkbox already holds must not look like a state change. Values are
  // immutable data, so equality is the right test here; keeping the instance
  // is what lets the copy-on-write spine above collapse (see
  // `Value::with_field`), and it is what makes a no-op interaction free.
  if self.fields.get(name) is Some(old) &&
    reuse_equal(old, coerced, Ref(REUSE_FUEL)) {
    return self
  }
  let fields = self.fields.copy()
  fields[name] = coerced
  if self.spec.s_fields.contains(name) {
    match (self.spec.decode)(fields) {
      Some(s) => TypedInstance::make(self.spec, s, fields)
      None => self
    }
  } else {
    TypedInstance::make(self.spec, self.state, fields)
  }
}

///|
/// The instance as a Value — the SAME Value every time (see `boxed`).
fn[S] TypedInstance::to_value(self : TypedInstance[S]) -> @tutuca.Value {
  match self.boxed {
    Some(v) => v
    None => {
      let v : @tutuca.Value = Obj(self)
      self.boxed = Some(v)
      v
    }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn component_id(self) {
  match self.spec.comp {
    Some(c) => Some(c.id)
    None => None
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_field(self, name) {
  match self.fields.get(name) {
    Some(v) => Some(v)
    // $-callables surface as self-pre-bound Fns (JS prototype lookup);
    // callers use the Fn convention (element 0 = this), which we drop
    None =>
      match self.spec.compute.get(name) {
        Some(f) => Some(Fn(args => f(self.state, drop_this(args))))
        None =>
          match self.spec.generated.get(name) {
            Some(g) => Some(Fn(args => g(self, drop_this(args))))
            None => None
          }
      }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_with_field(self, name, v) {
  guard self.spec.comp is Some(comp) else { return None }
  if comp.specs.contains(name) {
    Some(self.set(name, v).to_value())
  } else {
    None
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_callable(self, name, ns) {
  // Alter namespace: the four typed render-time buckets first, each adapted
  // to its directive's Fn-convention call shape (element 0 = this).
  if ns is Alter {
    match self.spec.when.get(name) {
      Some(f) =>
        return Some(
          Fn(args => {
            let a = drop_this(args)
            Bool(
              f(
                self.state,
                a.get(0).unwrap_or(Null),
                a.get(1).unwrap_or(Null),
                a.get(2).unwrap_or(Null),
              ),
            )
          }),
        )
      None => ()
    }
    match self.spec.enrich.get(name) {
      Some(f) =>
        return Some(
          Fn(args => {
            match drop_this(args) {
              [Map(binds), ..] as a => {
                f(
                  self.state,
                  binds,
                  a.get(1).unwrap_or(Null),
                  a.get(2).unwrap_or(Null),
                  a.get(3).unwrap_or(Null),
                )
                Null
              }
              _ => Null
            }
          }),
        )
      None => ()
    }
    match self.spec.enrich_scope.get(name) {
      Some(f) => return Some(Fn(_args => Map(f(self.state))))
      None => ()
    }
    match self.spec.loop_with.get(name) {
      Some(f) =>
        return Some(
          Fn(args => {
            let a = drop_this(args)
            LoopWith::to_value(
              f(
                self.state,
                a.get(0).unwrap_or(Null),
                LoopCtx::of_value(a.get(1).unwrap_or(Null)),
              ),
            )
          }),
        )
      None => ()
    }
  }
  match self.spec.compute.get(name) {
    Some(f) => Some(Fn(args => f(self.state, drop_this(args))))
    None =>
      match self.spec.generated.get(name) {
        Some(g) => Some(Fn(args => g(self, drop_this(args))))
        None => None
      }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_handler(self, bucket, name) {
  let has_update = self.spec.update is Some(_)
  let input_fallback = bucket is Input &&
    (self.spec.swap.contains(name) || self.spec.generated.contains(name))
  if !has_update && !input_fallback {
    return None
  }
  Some(
    Handler((args, ctx) => {
      // swap handlers are name-keyed and may replace this node with an
      // arbitrary Value (another component's instance) — they win over the
      // opaque update match.
      if bucket is Input {
        match self.spec.swap.get(name) {
          Some(f) =>
            return match f(self.state, args, ctx) {
              Some(v) => Some(v)
              None => None
            }
          None => ()
        }
      }
      match self.spec.update {
        Some(u) => {
          let d : Dispatch = match bucket {
            Receive => Receive(name, args)
            Input => Input(name, args)
            Bubble => Bubble(name, args)
            Response => Response(name, args)
          }
          match u(self.state, d, ctx) {
            Some(s2) => return Some(self.with_state(s2).to_value())
            None => ()
          }
        }
        None => ()
      }
      // Input dispatch falls through to the GENERATED mutators, so a view
      // writing `setTitle 'x'` reaches the setter every field gets without
      // the component declaring one.
      if bucket is Input {
        match self.spec.generated.get(name) {
          Some(g) =>
            match g(self, args) {
              Obj(_) as nv => return Some(nv)
              _ => ()
            }
          None => ()
        }
      }
      None
    }),
  )
}

///|
/// The declared description, as the component was built with it — STORED, not
/// rebuilt: `obj_eq`, `obj_debug` and the JSON projection all read it, in
/// loops.
///
/// This one line is what an instance owes the generic-access layer. Everything
/// downstream of it — naming the fields, reading one by kind, structural
/// equality, the debug rendering, the JSON form — is a default in `@tutuca`,
/// which is why `obj_eq` and `obj_debug` are no longer written here.
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_schema(self) {
  match self.spec.comp {
    Some(c) => Some(c.schema)
    None => None
  }
}

///|
/// The single collection field a state stands for, when it has exactly one.
///
/// This is the rule the guest emitter already used, and it is deliberately
/// narrow: the state's ONLY field, and a collection. Iterating an instance
/// means iterating the one sequence it IS, and a state with a second field is
/// not that sequence — it is a record that happens to hold one. Widening this
/// to "the only collection among several fields" makes `{title, items}` iterate
/// as `items` and hide `title`, which is exactly what an inspector opening the
/// instance must not see.
fn[S] TypedInstance::seq_field(self : TypedInstance[S]) -> String? {
  guard self.spec.comp is Some(c) else { return None }
  guard c.schema.fields is [f] else { return None }
  guard f.kind() is (FList | FOMap | FSet | FMap) else { return None }
  Some(f.name)
}

///|
/// Ordered entries, so `@each` can iterate an instance as the sequence it
/// stands for.
///
/// A typed instance used to implement neither this nor `obj_item`, which made
/// it the LEAST capable of the three `Obj` implementations — `DynObj` forwards
/// both to its guest, and the guest emitter derived them from the schema. The
/// host's own instances can be asked the same question off the same schema.
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_seq_entries(self) {
  guard self.seq_field() is Some(name) else { return None }
  Some(self.get(name).entries())
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_item(self, key) {
  guard self.seq_field() is Some(name) else { return None }
  self.get(name).item_opt(key)
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn obj_with_item(self, key, v) {
  guard self.seq_field() is Some(name) else { return None }
  Some(self.set(name, self.get(name).with_item(key, v)).to_value())
}
