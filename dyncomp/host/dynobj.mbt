///| DynObj: the uniform &Obj wrapper around one opaque guest instance. The
/// synthesized component (Component::for_type) carries the views; DynObj
/// carries identity + behavior: lazy field reads, forwarded dispatch that
/// swaps in the successor handle (self in, self out — tutuca's COW model),
/// and methods surfaced as self-pre-bound Fns, mirroring Instance.

///|
pub struct DynObj {
  comp_id : Int
  def : DynComponentDef
  guest : &Guest
  handle : Int
  /// What the guest DECLARED about this component (see `register_bundle`).
  /// Carried on the instance because that is where the generic layers ask for
  /// it: `obj_schema` is what gives a guest structural equality, a debug
  /// rendering and a JSON projection without the guest implementing any.
  schema : @tutuca.SchemaInfo
  /// The mutators the schema implies (`setCount`, `pushInItems`, …), built
  /// once per component and shared by every instance of it. They write through
  /// `obj_with_field`, so a guest gets them by declaring its fields.
  mutators : Map[
    String,
    (@component.FieldBox, Array[@tutuca.Value]) -> @tutuca.Value,
  ]
  /// What this instance is CALLED across sessions (`obj_persist_id`), or ""
  /// for one nobody named. Assigned when the instance is created and carried
  /// by every successor, because a successor is the same logical instance one
  /// update later — persisting one under a new key per keystroke would fill a
  /// store with the history of a thing instead of the thing.
  pid : String
  /// The render cache's bucket (see `@tutuca.ObjId`), seeded from the
  /// component's schema fingerprint and the handle this instance started on.
  /// A guest's fields are lazy — reading them means crossing the bridge — so
  /// the handle is the only thing about the instance the host can hash without
  /// paying for a round trip, and it is enough: a bucket only has to spread.
  id : @tutuca.ObjId
  /// The PLACEHOLDERS this instance declared: fields whose type names a
  /// component from another module (`resource universal; body: universal`),
  /// held by the host and never shown to the guest.
  ///
  /// This is how a guest with internal layout offers a hole for a person to
  /// fill. It has to be the host's because the boundary allows nothing else: a
  /// WIT `value` has no case that can carry a host component (`instance(u64)`
  /// is guest-token space, and `to-json` writes instances as null), so an
  /// instance built here cannot be handed over. The guest names the field and
  /// renders it with `<x render=".body">`; everything else is ours.
  ///
  /// The guest is never asked about these names and can never write them,
  /// which is the containment worth having: a placeholder is a hole in the
  /// guest's layout, not a handle it can reach through.
  owned : Map[String, @tutuca.Value]
}

///|
/// The protocol field name DynObj answers with its guest handle, so code
/// holding a `Value::Obj` from a guest (spine rebuilds through nested
/// children, bridges) can recover the handle without downcasting.
pub let handle_field : String = "__dyncomp_handle"

///|
pub fn DynObj::new(
  comp_id : Int,
  def : DynComponentDef,
  guest : &Guest,
  handle : Int,
  schema~ : @tutuca.SchemaInfo,
  pid? : String = "",
  owned? : Map[String, @tutuca.Value] = Map([]),
) -> DynObj {
  {
    comp_id,
    def,
    guest,
    handle,
    schema,
    pid,
    owned,
    mutators: @component.schema_mutators(schema),
    id: @tutuca.ObjId::of(schema.fingerprint, {
      "handle": Num(handle.to_double()),
    }),
  }
}

///|
/// The fields this component declared as holding a component from another
/// module — the placeholders the host fills. `TyComp(None)` (the bare
/// `component` marker) is NOT one of them: it says "some component" and names
/// nothing to build, so the host has nothing to put there and says so by
/// leaving it out.
pub fn placeholder_fields(
  schema : @tutuca.SchemaInfo,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for f in schema.fields {
    if f.ty is TyComp(Some(comp)) {
      out.push((f.name, comp))
    }
  }
  out
}

///|
pub fn DynObj::to_value(self : DynObj) -> @tutuca.Value {
  Obj(self)
}

// --- superseded-handle GC ---
// A handler that returns a successor makes the old guest instance garbage
// once its transaction settles and the render that reads the successor has
// run. `install_gc` says exactly that: it collects at the end of every
// drained cascade, after the App's own on_drained re-render (subscription
// order — the App subscribes in App::new, a host installs this afterwards).
// collect_superseded() is the same sweep, run by hand.

///|
let superseded : Array[(&Guest, Int)] = []

///|
/// Drop every guest handle a successor replaced. Idempotent, and safe to call
/// at any point where no render is mid-flight.
pub fn collect_superseded() -> Unit {
  for entry in superseded {
    let (guest, handle) = entry
    guest.drop_instance(handle)
  }
  superseded.clear()
}

///|
/// Collect superseded guest handles at the end of every drained cascade.
/// Call once per app, after mounting it — the App subscribes its re-render in
/// `App::new`, and `on_drained` runs subscribers in subscription order, so a
/// later subscription is a post-render hook.
pub fn install_gc(tx : @transactor.Transactor) -> Unit {
  tx.on_drained(collect_superseded)
}

///|
pub fn superseded_count() -> Int {
  superseded.length()
}

///|
pub fn DynObj::handle(self : DynObj) -> Int {
  self.handle
}

///|
/// The component this instance is an instance OF, as the manifest named it.
pub fn DynObj::component_name(self : DynObj) -> String {
  self.def.name
}

///|
/// This instance under a persist id — what a caller uses when it has a better
/// name for the thing than the one the bundle minted (a slot in a document, a
/// row in a list). Same instance, same guest handle: a name is not state.
pub fn DynObj::with_persist_id(self : DynObj, pid : String) -> DynObj {
  { ..self, pid, }
}

///|
/// The instance that replaces this one: same component, new guest handle, and
/// the same bucket at the next revision — a successor is the same logical
/// instance one update later, which is exactly what the revision means.
fn DynObj::successor(self : DynObj, handle : Int) -> DynObj {
  { ..self, handle, id: self.id.next() }
}

///|
/// The Fn convention passes `this` as element 0; guest methods are already
/// pre-bound to the handle, so drop it (mirrors Instance's drop_this).
fn drop_this(args : Array[@tutuca.Value]) -> Array[@tutuca.Value] {
  let out = []
  for i in 1..<args.length() {
    out.push(args[i])
  }
  out
}

///|
fn DynObj::method_fn(self : DynObj, name : String) -> @tutuca.Value {
  Fn(args => self.guest.call_method(self.handle, name, drop_this(args)))
}

///|
/// This instance as the generated mutators see it (see `@component.FieldBox`):
/// a field read is `obj_field`, a field write is `obj_with_field` — the guest's
/// own COW successor — and the no-op answer is the instance itself.
fn DynObj::field_box(self : DynObj) -> @component.FieldBox {
  {
    get: name => self.obj_field(name).unwrap_or(Null),
    set: (name, v) => self.obj_with_field(name, v).unwrap_or(Obj(self)),
    value: () => Obj(self),
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn component_id(self) {
  Some(self.comp_id)
}

///|
/// The render cache's bucket — stored, never computed here: it is read once
/// per render site per pass, and every read that crossed the guest bridge
/// would cost more than the cache saves.
pub impl @tutuca.Obj for DynObj with fn obj_identity(self) {
  Some(self.id)
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_field(self, name) {
  if name == handle_field {
    Some(Num(self.handle.to_double()))
  } else if self.owned.get(name) is Some(v) {
    // A placeholder, answered without crossing the bridge — the guest was
    // never given this value and has nothing to say about it.
    Some(v)
  } else if self.def.methods.contains(name) {
    Some(self.method_fn(name))
  } else {
    match self.guest.get_field(self.handle, name) {
      Some(v) => Some(v)
      // A generated mutator surfaces as a self-pre-bound Fn, exactly as it
      // does on a typed instance — `$setCount 5` in a guest view reads the
      // field's setter here and calls it.
      None =>
        match self.mutators.get(name) {
          Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
          None => None
        }
    }
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_with_field(self, name, v) {
  // A write to a placeholder never reaches the guest, so it mints no successor
  // handle and supersedes nothing: the guest's state did not change. The map
  // is rebuilt rather than mutated, because two successors of one instance
  // sharing a map would make a write to either visible in both — which is
  // exactly what COW exists to prevent.
  if self.owned.contains(name) {
    let owned : Map[String, @tutuca.Value] = Map([])
    for k, prev in self.owned {
      owned[k] = prev
    }
    owned[name] = v
    return Some(Obj({ ..self, owned, id: self.id.next() }))
  }
  match self.guest.with_field(self.handle, name, v) {
    Some(h) => {
      superseded.push((self.guest, self.handle))
      Some(Obj(self.successor(h)))
    }
    None => None
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_seq_entries(self) {
  match self.guest.seq_entries(self.handle) {
    Some(entries) => Some(entries.map(e => (KStr(e.0), e.1)))
    None => None
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_callable(self, name, ns) {
  // The render-time (alter) namespace is where a `@when` filter is looked up.
  // It reaches `call-method` like any other declared callable — the guest
  // writes one function and the host reads its answer as a boolean — and this
  // list is what says the name belongs to that namespace.
  if ns is Alter && self.def.whens.contains(name) {
    return Some(self.method_fn(name))
  }
  if self.def.methods.contains(name) {
    Some(self.method_fn(name))
  } else {
    match self.mutators.get(name) {
      Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
      None => None
    }
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_handler(self, bucket, name) {
  // An input name the guest does NOT answer, but the schema generates a
  // mutator for, is handled here: `setCount 5` in a guest view reaches the
  // setter its declared fields imply, through `with-field`, without the guest
  // implementing a handler and without the dispatch crossing the boundary.
  //
  // The guest's own list wins, which is why it is declared rather than
  // inferred: `handle-event` is one opaque entry point that answers to every
  // name, so "is this yours?" cannot be asked without calling it — and calling
  // it would make "unchanged" indistinguishable from "not mine". `resetLeft`
  // is a generated mutator for a `left` field AND a plausible handler name;
  // only the guest can say which it meant.
  if bucket is Input &&
    !self.def.handlers.contains(name) &&
    self.mutators.get(name) is Some(g) {
    return Some(
      Handler((args, _ctx) => {
        match g(self.field_box(), args) {
          Obj(_) as nv => Some(nv)
          _ => None
        }
      }),
    )
  }
  let declared = match bucket {
    Input => self.def.handlers.contains(name)
    Receive => self.def.receives.contains(name)
    Response => self.def.responses.contains(name)
    // A guest child raises these with control.emit; a guest PARENT hears them
    // here, through the same walk the host uses between its own components.
    Bubble => self.def.bubbles.contains(name)
  }
  guard declared else { return None }
  Some(
    Handler((args, ctx) => {
      let result = self.guest.dispatch(self.handle, bucket, name, args)
      for msg in result.msgs {
        match msg {
          Emit(name, args) => ctx.bubble(name, args)
          Send(name, args) => ctx.send(name, args)
          // relative: the guest addresses its own subtree (see ControlMsg)
          SendAt(steps, name, args) =>
            ctx.send_at_path(ctx.path().concat(steps), name, args)
          BubbleAt(steps, name, args) =>
            ctx.bubble_at_path(ctx.path().concat(steps), name, args)
          Request(name, args, opts) => ctx.request(name, args, opts)
          StopPropagation => ctx.stop_propagation()
        }
      }
      match result.next {
        Some(h) => {
          superseded.push((self.guest, self.handle))
          Some((Obj(self.successor(h)) : @tutuca.Value))
        }
        None => None
      }
    }),
  )
}

///|

///|
/// What the guest declared. Everything generic over a schema — structural
/// equality, `obj_debug`, `Value::to_json`, the inspector's form — reads this
/// one method, which is why the contract needs no `eq` and no `to-json`.
pub impl @tutuca.Obj for DynObj with fn obj_schema(self) {
  Some(self.schema)
}

///|
/// What a store keys this instance on. None when nothing named it, which the
/// persistence layer reads as "do not store me" rather than inventing a key
/// that would not be found again.
pub impl @tutuca.Obj for DynObj with fn obj_persist_id(self) {
  if self.pid == "" {
    None
  } else {
    Some(self.pid)
  }
}
