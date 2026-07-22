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
          let v : @tutuca.Value = @json.from_json(jv) catch {
            _ => @tutuca.Value::Null
          }
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
/// New instance from an updated state; slot fields (not part of S) carry over.
fn[S : ToJson] TypedInstance::with_state(
  self : TypedInstance[S],
  s : S,
) -> TypedInstance[S] {
  let fields = encode_state(s)
  for name, v in self.fields {
    if !fields.contains(name) {
      fields[name] = v
    }
  }
  { spec: self.spec, state: s, fields }
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
  let fields = self.fields.copy()
  fields[name] = fspec.coerce_or_default(v)
  if self.spec.s_fields.contains(name) {
    match decode_state(fields, self.spec.s_fields) {
      Some(s) => { spec: self.spec, state: s, fields }
      None => self
    }
  } else {
    { spec: self.spec, state: self.state, fields }
  }
}

///|
fn[S : ToJson + @json.FromJson] TypedInstance::to_value(
  self : TypedInstance[S],
) -> @tutuca.Value {
  Obj(self)
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
