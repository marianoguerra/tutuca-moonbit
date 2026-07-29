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
  /// The render cache's bucket (see `@tutuca.ObjId`), seeded from the
  /// component's manifest fingerprint and the handle this instance started on.
  /// A guest's fields are lazy — reading them means crossing the bridge — so
  /// the handle is the only thing about the instance the host can hash without
  /// paying for a round trip, and it is enough: a bucket only has to spread.
  id : @tutuca.ObjId
}

///|
/// The protocol field name DynObj answers with its guest handle, so code
/// holding a `Value::Obj` from a guest (spine rebuilds through nested
/// children, bridges) can recover the handle without downcasting.
pub let handle_field : String = "__dyncomp_handle"

///|
/// Protocol field answering the guest's JSON state projection (Str), used
/// by hot-swap migration (Bundle::migrate_instance) and inspectors.
pub let state_json_field : String = "__dyncomp_state_json"

///|
pub fn DynObj::new(
  comp_id : Int,
  def : DynComponentDef,
  guest : &Guest,
  handle : Int,
  fingerprint~ : String,
) -> DynObj {
  {
    comp_id,
    def,
    guest,
    handle,
    id: @tutuca.ObjId::of(fingerprint, { "handle": Num(handle.to_double()) }),
  }
}

///|
pub fn DynObj::to_value(self : DynObj) -> @tutuca.Value {
  Obj(self)
}

// --- superseded-handle GC ---
// A handler that returns a successor makes the old guest instance garbage
// once its transaction settles. Handles queue here and are dropped at the
// START of the next guest dispatch (by then the previous transaction has
// settled and rendered) — a one-transaction delay instead of lifecycle
// hooks. collect_superseded() drops them eagerly (tests, idle hooks).

///|
let superseded : Array[(&Guest, Int)] = []

///|
pub fn collect_superseded() -> Unit {
  for entry in superseded {
    let (guest, handle) = entry
    guest.drop_instance(handle)
  }
  superseded.clear()
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
  } else if name == state_json_field {
    Some(Str(self.guest.to_json_string(self.handle)))
  } else if self.def.method_names.contains(name) {
    Some(self.method_fn(name))
  } else {
    self.guest.get_field(self.handle, name)
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_with_field(self, name, v) {
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
pub impl @tutuca.Obj for DynObj with fn obj_callable(self, name, _ns) {
  if self.def.method_names.contains(name) {
    Some(self.method_fn(name))
  } else {
    None
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn obj_handler(self, bucket, name) {
  let declared = match bucket {
    Input => self.def.input_handlers.contains(name)
    Receive => self.def.receive_handlers.contains(name)
    Response => self.def.response_handlers.contains(name)
    Bubble => false
  }
  guard declared else { return None }
  Some(
    Handler((args, ctx) => {
      // handles queued by earlier transactions are settled garbage by now
      collect_superseded()
      let result = self.guest.dispatch(self.handle, bucket, name, args)
      for msg in result.msgs {
        match msg {
          Emit(name, args) => ctx.bubble(name, args)
          Send(name, args) => ctx.send(name, args)
          Request(name, args) =>
            ctx.request(name, args, @tutuca.RequestOpts::new(on_res_name=name))
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
pub impl @tutuca.Obj for DynObj with fn obj_debug(self) {
  "\{self.def.name}\{self.guest.to_json_string(self.handle)}"
}
