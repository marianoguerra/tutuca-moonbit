// TypedInstance: the runtime instance of a typed-state component. The state
// struct S is the source of truth; a parallel encoded fields map (S fields
// plus spec-declared slots such as child components) serves the render/path/
// Value seams. encode/decode run inside the core value stash so Obj/Fn
// values held by S survive the Json round-trip losslessly.

///|
/// The S-typed half of a component definition, erased behind Component's
/// make closure. `comp` is wired right after Component construction.
priv struct TypedSpec[S] {
  mut comp : Component?
  init : S
  s_fields : Array[String]
  update : ((S, Dispatch, &@tutuca.Ctx) -> S?)?
  mutate : Map[String, (S, Array[@tutuca.Value]) -> S]
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
}

///|
/// Wrap the renderer's loopCtx Value (a Map of Fn-convention closures) into
/// the typed LoopCtx a @loop-with handler receives.
fn loop_ctx_of(v : @tutuca.Value) -> LoopCtx {
  {
    lookup: name => {
      match v.field("lookup") {
        Fn(f) => f([Null, Str(name)])
        _ => Null
      }
    },
    filter: (k, item, iter) => {
      match v.field("filter") {
        Fn(f) => f([Null, k, item, iter]).is_truthy()
        _ => true
      }
    },
  }
}

///|
/// Encode a LoopWith back into the { iterData?, start?, end?, keys? } Map
/// shape the renderer unpacks.
fn loop_with_value(r : LoopWith) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = Map([])
  match r.iter_data {
    Some(v) => m["iterData"] = v
    None => ()
  }
  match r.start {
    Some(i) => m["start"] = Num(i.to_double())
    None => ()
  }
  match r.end {
    Some(i) => m["end"] = Num(i.to_double())
    None => ()
  }
  match r.keys {
    Some(ks) => m["keys"] = List(ks)
    None => ()
  }
  Map(m)
}

///|
priv struct TypedInstance[S] {
  spec : TypedSpec[S]
  state : S
  fields : Map[String, @tutuca.Value]
  // Memoized `Obj(self)`. Every seam downstream of an instance — the render
  // cache, Path copy-on-write, the transactor's root-swap check — compares
  // Values by IDENTITY, and each `Obj(self)` cast allocates a fresh box. One
  // stable Value per instance is what lets an unchanged instance still look
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
/// Encode a state struct to the fields-map representation. Runs in the value
/// stash: Obj/Fn survive identically.
fn[S : ToJson] encode_state(s : S) -> Map[String, @tutuca.Value] {
  @tutuca.with_value_stash(() => {
    match ToJson::to_json(s) {
      Object(m) => {
        let out : Map[String, @tutuca.Value] = Map([])
        for k, jv in m {
          let v : @tutuca.Value = @json.from_json(jv) catch { _ => Null }
          out[k] = v
        }
        out
      }
      _ => Map([])
    }
  })
}

///|
/// Decode the S-subset of a fields map back into the state struct. None on a
/// shape mismatch (callers treat it as a no-op write).
fn[S : @json.FromJson] decode_state(
  fields : Map[String, @tutuca.Value],
  s_fields : Array[String],
) -> S? {
  @tutuca.with_value_stash(() => {
    let obj : Map[String, Json] = Map([])
    for name in s_fields {
      obj[name] = ToJson::to_json(fields.get(name).unwrap_or(Null))
    }
    Some(@json.from_json(Json::object(obj))) catch {
      _ => None
    }
  })
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
/// list of child components rebuilt by the Json round trip compares
/// element-wise in O(1) each (the value stash restores every `Obj` by
/// reference) and costs one unit for the list itself, while a 1000-item list
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
/// Encoding round-trips through Json, which rebuilds every container even
/// when nothing about it changed — and identity is exactly what the render
/// cache and Path copy-on-write read. So each freshly encoded field is
/// compared with the one it replaces and the OLD object kept when the two are
/// equal; a rebuilt-but-equal list would otherwise invalidate a subtree that
/// did not move. When no encoded field and no slot field changed, the
/// ORIGINAL instance is returned, and the no-op reaches the transactor as
/// "the root is the same object": no re-render is scheduled.
fn[S : ToJson] TypedInstance::with_state(
  self : TypedInstance[S],
  s : S,
) -> TypedInstance[S] {
  let encoded = encode_state(s)
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
fn[S : @json.FromJson] TypedInstance::set(
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
    match decode_state(fields, self.spec.s_fields) {
      Some(s) => TypedInstance::make(self.spec, s, fields)
      None => self
    }
  } else {
    TypedInstance::make(self.spec, self.state, fields)
  }
}

///|
/// The instance as a Value — the SAME Value every time (see `boxed`).
fn[S : ToJson + @json.FromJson] TypedInstance::to_value(
  self : TypedInstance[S],
) -> @tutuca.Value {
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
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn component_id(
  self,
) {
  match self.spec.comp {
    Some(c) => Some(c.id)
    None => None
  }
}

///|
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_field(
  self,
  name,
) {
  match self.fields.get(name) {
    Some(v) => Some(v)
    // $-callables surface as self-pre-bound Fns (JS prototype lookup);
    // callers use the Fn convention (element 0 = this), which we drop
    None =>
      match self.spec.compute.get(name) {
        Some(f) => Some(Fn(args => f(self.state, drop_this(args))))
        None =>
          match self.spec.mutate.get(name) {
            Some(f) =>
              Some(
                Fn(args => {
                  self.with_state(f(self.state, drop_this(args))).to_value()
                }),
              )
            None =>
              match self.spec.generated.get(name) {
                Some(g) => Some(Fn(args => g(self, drop_this(args))))
                None => None
              }
          }
      }
  }
}

///|
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_with_field(
  self,
  name,
  v,
) {
  guard self.spec.comp is Some(comp) else { return None }
  if comp.specs.contains(name) {
    Some(self.set(name, v).to_value())
  } else {
    None
  }
}

///|
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_render_handler(
  self,
  name,
  ns,
) {
  // Alter namespace: the four typed render-time buckets first, each adapted
  // to its directive's Fn-convention call shape (element 0 = this).
  if ns is Alter {
    match self.spec.when.get(name) {
      Some(f) =>
        return Fn(args => {
          let a = drop_this(args)
          Bool(
            f(
              self.state,
              a.get(0).unwrap_or(Null),
              a.get(1).unwrap_or(Null),
              a.get(2).unwrap_or(Null),
            ),
          )
        })
      None => ()
    }
    match self.spec.enrich.get(name) {
      Some(f) =>
        return Fn(args => {
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
        })
      None => ()
    }
    match self.spec.enrich_scope.get(name) {
      Some(f) => return Fn(_args => Map(f(self.state)))
      None => ()
    }
    match self.spec.loop_with.get(name) {
      Some(f) =>
        return Fn(args => {
          let a = drop_this(args)
          loop_with_value(
            f(
              self.state,
              a.get(0).unwrap_or(Null),
              loop_ctx_of(a.get(1).unwrap_or(Null)),
            ),
          )
        })
      None => ()
    }
  }
  match self.spec.compute.get(name) {
    Some(f) => Fn(args => f(self.state, drop_this(args)))
    None =>
      match self.spec.mutate.get(name) {
        Some(f) =>
          Fn(args => self.with_state(f(self.state, drop_this(args))).to_value())
        None =>
          match self.spec.generated.get(name) {
            Some(g) => Fn(args => g(self, drop_this(args)))
            None => Null
          }
      }
  }
}

///|
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_handler(
  self,
  bucket,
  name,
) {
  let has_update = self.spec.update is Some(_)
  let input_fallback = bucket is Input &&
    (
      self.spec.swap.contains(name) ||
      self.spec.mutate.contains(name) ||
      self.spec.generated.contains(name)
    )
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
              Some(v) => Some(v as &@tutuca.PathNode)
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
            Some(s2) =>
              return Some(self.with_state(s2).to_value() as &@tutuca.PathNode)
            None => ()
          }
        }
        None => ()
      }
      // Input dispatch falls through to $-mutators so `$setTitle 'x'`-style
      // input works (the JS methods fallback).
      if bucket is Input {
        match self.spec.mutate.get(name) {
          Some(f) =>
            return Some(
              self.with_state(f(self.state, args)).to_value()
              as &@tutuca.PathNode,
            )
          None => ()
        }
        match self.spec.generated.get(name) {
          Some(g) =>
            match g(self, args) {
              Obj(_) as nv => return Some(nv as &@tutuca.PathNode)
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
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_eq(
  self,
  other,
) {
  match self.spec.comp {
    Some(c) => if other.component_id() != Some(c.id) { return false }
    None => return false
  }
  for k, v in self.fields {
    if other.obj_field(k) != Some(v) {
      return false
    }
  }
  true
}

///|
impl[S : ToJson + @json.FromJson] @tutuca.Obj for TypedInstance[S] with fn obj_debug(
  self,
) {
  let cname = match self.spec.comp {
    Some(c) => c.name
    None => "?"
  }
  "\{cname}\{to_repr(self.fields).to_string()}"
}
