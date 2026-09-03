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
  /// What the guest DECLARED about this component (see `register_module`).
  /// Carried on the instance because that is where the generic layers ask for
  /// it: `schema` is what gives a guest structural equality, a debug
  /// rendering and a JSON projection without the guest implementing any.
  schema : @tutuca.SchemaInfo
  /// The mutators the schema implies (`setCount`, `pushInItems`, …), built
  /// once per component and shared by every instance of it. They write through
  /// `with_member`, so a guest gets them by declaring its fields.
  mutators : Map[
    String,
    (@component.FieldBox, Array[@tutuca.Value]) -> @tutuca.Value,
  ]
  /// What this instance is CALLED across sessions (`persist_id`), or ""
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
  /// The PLACEHOLDERS this instance declared: fields holding a component the
  /// guest cannot — one whose type names a component from another module
  /// (`resource universal; body: universal`), and one declared as a bare
  /// `component` that a caller filled with an instance from outside this
  /// module. Held by the host and never shown to the guest.
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
pub let handle_field : String = "__tgc_handle"

///|
/// A value on its way INTO a guest, with every nested-child instance in it
/// encoded as the `{"$dyn": {"handle": n}}` marker `loader.mjs`'s `jsonToGuest`
/// turns back into an instance token.
///
/// `Value::to_json` cannot do this: an `Obj` has no JSON form, so it projects
/// the object's FIELDS — which for a guest instance is a copy of its state
/// under a name that no longer refers to it. What crosses has to be the handle.
///
/// It recurses, and that is the whole point. A scalar `comp` field (the sample
/// counter's `Pair` holds two that way) is not enough for guests whose children
/// sit in a LIST — where a child that returns a successor is written back as
/// the parent's whole list, one element of which is the new instance.
pub fn child_json(v : @tutuca.Value) -> Json {
  match v {
    Obj(o) =>
      match o.field(handle_field) {
        Some(Num(h)) =>
          Json::object({ "$dyn": Json::object({ "handle": Json::number(h) }) })
        // An object that is not a guest instance — a host component, say.
        // Nothing can be done for it here, so it projects as before.
        _ => v.to_json()
      }
    List(items) => Json::array(items.map(child_json))
    Map(entries) => {
      let obj : Map[String, Json] = Map([])
      for k, item in entries {
        obj[k] = child_json(item)
      }
      Json::object(obj)
    }
    _ => v.to_json()
  }
}

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
/// Who keeps one declared SLOT's value.
///
/// A slot is a field where a child component goes, in any of the spellings
/// that mean it: `ty-comp` with a name, `ty-comp` without one, `ty-comp-
/// protocols`, and a list of any of those. They were three separate questions
/// in three places once, which is how they drifted into four different
/// answers; this is the one question, asked once.
pub(all) enum SlotOwner {
  /// The GUEST's. It can hold this, so it is the source of truth — and that
  /// is the whole reason this case exists rather than the host taking
  /// everything: a guest that dispatches to its own child and keeps the
  /// successor would leave a host-held copy stale.
  Guest
  /// The HOST's, and this is the value. The caller supplied something the
  /// guest cannot hold (see `DynObj.owned`).
  HostHolds(@tutuca.Value)
  /// The HOST's, and nobody supplied one: build the component the slot NAMES.
  /// Only a named slot reaches this — "some component" names nothing to build,
  /// and a LIST of them has no count to build.
  HostBuilds(String)
} derive(Eq, Debug)

///|
/// Who keeps this slot, given what the caller supplied.
///
/// `declared_here` says whether a name is one of the guest's own components,
/// which is the line the whole thing turns on: a `ty-comp` field naming a
/// SIBLING is a nested child the guest makes and manages, and a field naming
/// anything else is a hole only the host can fill.
///
/// A non-slot type is `Guest`, which is the right answer twice over: there is
/// no child there, and nothing for the host to keep.
pub fn slot_owner(
  ty : @tutuca.TyInfo,
  given : @tutuca.Value?,
  declared_here~ : (String) -> Bool,
) -> SlotOwner {
  match ty {
    TyComp(Some(name)) =>
      if declared_here(name) {
        Guest
      } else {
        match given {
          Some(v) if v is Obj(_) => HostHolds(v)
          _ => HostBuilds(name)
        }
      }
    // Names nothing, so there is nothing to build — but a caller can still
    // PASS one, and that is what makes a holder a holder.
    TyComp(None) | TyCompProtocols(_) =>
      match given {
        Some(v) if uncrossable(v) => HostHolds(v)
        _ => Guest
      }
    // A list of slots, answered whole: a container whose cells the host
    // supplied is a container the host keeps. One element the guest could
    // never have handed over settles it for the list, because the list is one
    // field and `owned` keeps fields.
    TyList(TyComp(_) | TyCompProtocols(_)) =>
      match given {
        Some(List(items)) if items.iter().any(uncrossable) =>
          HostHolds(given.unwrap())
        _ => Guest
      }
    _ => Guest
  }
}

///|
/// Whether this value is one NO guest could have handed over: an instance with
/// no guest handle on it.
///
/// The test is the VALUE rather than the field, and that is the point. An
/// instance of the guest's own module crosses as a token it holds and reads
/// back through `Module::wrap_instance`; a host component cannot cross at all,
/// because `child_json` has nothing to write for it but its fields — which
/// come back as a Map with the shape of a component and none of its
/// behaviour. So the host keeps what the guest could not have held, and leaves
/// the rest where it is.
fn uncrossable(v : @tutuca.Value) -> Bool {
  v is Obj(o) && o.field(handle_field) is None
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
/// name for the thing than the one the module minted (a slot in a document, a
/// row in a list). Same instance, same guest handle: a name is not state.
pub fn DynObj::with_persist_id(self : DynObj, pid : String) -> DynObj {
  { ..self, pid, }
}

///|
/// The instance that replaces this one: same component, new guest handle, and
/// the same bucket at the next revision — a successor is the same logical
/// instance one update later, which is exactly what the revision means.
fn DynObj::successor(self : DynObj, handle : Int) -> DynObj {
  { ..self, handle, id: self.id.next(), }
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
/// What this component's declared lookups mean AT THIS RENDER POSITION.
///
/// The render-time twin of the map `handler` builds from `ctx.lookup`, and
/// it asks the same question of the other environment: `stack.lookup_dynamic`
/// is what a `*name` in this card's own VIEW reads, so a `*name` in its `pred`
/// reads the same thing. Empty for a component that declares no lookup, which
/// is most of them — and empty when there is no stack to ask, which is the
/// honest answer for a `$compute` read off a bare `Value` outside a render.
fn DynObj::render_bindings(
  self : DynObj,
  stack : &@tutuca.Stack,
) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  for pair in self.def.lookup {
    out[pair.0] = stack.lookup_dynamic(pair.0)
  }
  out
}

///|
fn DynObj::method_fn(
  self : DynObj,
  name : String,
  stack : &@tutuca.Stack,
) -> @tutuca.Value {
  let bindings = self.render_bindings(stack)
  Fn(args => self.guest.compute(self.handle, name, drop_this(args), bindings))
}

///|
/// This instance as the generated mutators see it (see `@component.FieldBox`):
/// a field read is `member`, a field write is `write_field` — the guest's
/// own COW successor, held to the declared domains on the way through — and the
/// no-op answer is the instance itself, which is also what a refused write
/// answers.
fn DynObj::field_box(self : DynObj) -> @component.FieldBox {
  {
    get: name => self.field(name).unwrap_or(Null),
    // The write every generated mutator makes, and where BOTH doors stand for
    // it. Not `with_member`, which is also how the RENDERER rebuilds a
    // spine: refusing there would turn a re-render into a refusal.
    set: (name, v) => self.write_field(name, v),
    value: () => Obj(self),
  }
}

///|
/// A generated mutator's write, held to the component's declared domains.
///
/// Both doors, here rather than one here and one at the dispatch that called
/// it, because of who owns the HANDLE. `with_member` supersedes the handle
/// it wrote from the moment it mints a successor — the old one is unreachable
/// and the sweep drops it — so a check that ran after it and then kept the old
/// instance would be keeping an instance whose handle is queued for collection.
/// Doing the guest write here means the successor exists before anything is
/// superseded, and a refusal drops the SUCCESSOR instead.
fn DynObj::write_field(
  self : DynObj,
  name : String,
  v : @tutuca.Value,
) -> @tutuca.Value {
  // THE FIRST DOOR: only the domains of the field being written, against the
  // fields as they stand — the same division `TypedInstance::set` documents.
  // Asked before the guest is entered, so a refused write mints nothing.
  if self.broken_write(name, v) is Some(_) {
    return Obj(self)
  }
  // A placeholder never reaches the guest and mints no handle, so there is
  // nothing to own and `with_member` is the whole of it.
  if self.owned.contains(name) {
    return @tutuca.Obj::with_field(self, name, v).unwrap_or(Obj(self))
  }
  guard self.guest.with_field(self.handle, name, v) is Some(h) else {
    return Obj(self)
  }
  // THE SECOND DOOR: the whole state. `setItems []` says nothing about
  // `currentIndex` and leaves it stranded, which is precisely what the first
  // door cannot see.
  match self.adopt(@tutuca.mutator_name("set", name), Obj(self.successor(h))) {
    Some(nv) => {
      superseded.push((self.guest, self.handle))
      nv
    }
    // The successor is what nothing holds now, so it is what the sweep takes.
    // The instance that stands is the one this was called on, and its handle
    // was never queued.
    None => {
      superseded.push((self.guest, h))
      Obj(self)
    }
  }
}

///|
/// The domains this component declared, or empty for one that declared none.
///
/// Read off the schema rather than the manifest, because the schema is what
/// every other generic layer reads and a second path to the same list is a
/// second chance for the two to disagree.
fn DynObj::domains(self : DynObj) -> Array[@tutuca.FieldDomain] {
  self.schema.domains
}

///|
/// A guest instance's declared fields, as the map a relation reads.
///
/// A domain is CROSS-FIELD — `currentIndex` is only wrong relative to `items`
/// — so the whole state has to be in hand, and a guest's fields are lazy. That
/// is one bridge crossing per declared field, which is why every caller here
/// asks `domains().is_empty()` first: a component that declared no `where`
/// pays nothing at all.
fn DynObj::fields_of(
  self : DynObj,
  v : @tutuca.Value,
) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  for f in self.schema.fields {
    out[f.name] = v.field(f.name)
  }
  out
}

///|
/// Whether writing `v` into `name` would leave that field outside its domain,
/// reporting through the refusal channel when it would.
fn DynObj::broken_write(
  self : DynObj,
  name : String,
  v : @tutuca.Value,
) -> @tutuca.Domain? {
  guard !self.domains().is_empty() else { return None }
  let fields = self.fields_of(Obj(self))
  guard @tutuca.broken_domain(self.domains(), name, v, fields) is Some(d) else {
    return None
  }
  let sentence = @tutuca.domain_sentence(d, name, v, fields)
  if @tutuca.refusing() {
    @tutuca.refuse({
      code: OutOfRange,
      asked: @tutuca.mutator_name("set", name),
      rule: name,
      sentence,
      state: Obj(self),
      path: @tutuca.Path::new(),
    })
  } else {
    @tutuca.domain_failed(
      handler=@tutuca.mutator_name("set", name),
      field=name,
      sentence~,
      state=Map(fields),
    )
  }
  Some(d)
}

///|
/// THE SECOND DOOR: the whole successor, before the host adopts it.
///
/// A guest keeps its own `pred`s and `invariant`s — they are compiled into its
/// module and it declines a transition itself. A DOMAIN is not: it leaves the
/// guest in the manifest and is enforced out here, which is the only place
/// that can, and which is why `core/domain.mbt` was put where a holder of a
/// bare `Value` could reach it.
///
/// Answers the successor when every domain holds, and `None` when one does
/// not — the caller keeps the instance it had, exactly as a typed instance
/// keeps its own on a broken rule.
fn DynObj::adopt(
  self : DynObj,
  asked : String,
  successor : @tutuca.Value,
) -> @tutuca.Value? {
  guard !self.domains().is_empty() else { return Some(successor) }
  let after = self.fields_of(successor)
  guard @tutuca.first_broken_domain(self.domains(), after) is Some(d) else {
    return Some(successor)
  }
  let sentence = @tutuca.broken_domain_sentence(d, after)
  if @tutuca.refusing() {
    @tutuca.refuse({
      code: OutOfRange,
      asked,
      rule: d.field,
      sentence,
      state: Map(after),
      path: @tutuca.Path::new(),
    })
  } else {
    @tutuca.domain_failed(
      handler=asked,
      field=d.field,
      sentence~,
      state=Map(after),
    )
  }
  None
}

///|
pub impl @tutuca.Obj for DynObj with fn component_id(self) {
  Some(self.comp_id)
}

///|
/// The render cache's bucket — stored, never computed here: it is read once
/// per render site per pass, and every read that crossed the guest bridge
/// would cost more than the cache saves.
pub impl @tutuca.Obj for DynObj with fn identity(self) {
  Some(self.id)
}

///|
pub impl @tutuca.Obj for DynObj with fn field(self, name) {
  // No stack in hand: a `$compute` read off a bare `Value` — the JSON
  // projection, a path lookup, the inspector — is not being asked from a
  // render position, so a `*name` inside it has no ancestry to walk.
  self.field_at(name, @tutuca.NullStack::{ })
}

///|
pub impl @tutuca.Obj for DynObj with fn method_at(self, name, stack) {
  self.field_at(name, stack)
}

///|
fn DynObj::field_at(
  self : DynObj,
  name : String,
  stack : &@tutuca.Stack,
) -> @tutuca.Value? {
  if name == handle_field {
    Some(Num(self.handle.to_double()))
  } else if self.owned.get(name) is Some(v) {
    // A placeholder, answered without crossing the bridge — the guest was
    // never given this value and has nothing to say about it.
    Some(v)
  } else if self.def.methods.contains(name) {
    Some(self.method_fn(name, stack))
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
pub impl @tutuca.Obj for DynObj with fn with_field(self, name, v) {
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
    return Some(Obj({ ..self, owned, id: self.id.next(), }))
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
pub impl @tutuca.Obj for DynObj with fn property(self, name) {
  guard self.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    return None
  }
  if !property.public_ {
    return None
  }
  guard self.guest.get_property(self.handle, name) is Some(value) else {
    return None
  }
  if property.ty.accepts(value) {
    Some(value)
  } else {
    None
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn member_at(self, name, _stack) {
  guard self.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    return self.field_at(name, _stack)
  }
  guard self.guest.get_property(self.handle, name) is Some(value) else {
    return None
  }
  if property.ty.accepts(value) {
    Some(value)
  } else {
    None
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn set_property(self, name, value) {
  guard self.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    return Missing
  }
  if !property.public_ {
    return Missing
  }
  self.write_member(name, value, property)
}

///|
/// The refusal a write to a guest's member answers.
///
/// `Outcome::Refused` carries the reason now, where `PRefused` carried nothing
/// and a caller had to go and look for it in the recorder. A guest's refusal
/// has no rule to name — the guest declined and said nothing about why, which
/// is the contract — so what this carries is the sentence the HOST can say.
fn write_refusal(
  asked : String,
  why : String,
  state : @tutuca.Value,
) -> @tutuca.Refusal {
  {
    code: NoHandler,
    asked,
    rule: "",
    sentence: why,
    state,
    path: @tutuca.Path::new(),
  }
}

///|
fn guest_refusal(name : String) -> @tutuca.Refusal {
  write_refusal(name, "the guest declined the write", Null)
}

///|
pub impl @tutuca.Obj for DynObj with fn set_member(self, name, value) {
  guard self.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    match self.mutators.get(@tutuca.mutator_name("set", name)) {
      Some(setter) => {
        let successor = setter(self.field_box(), [value])
        if successor.identity() == (Obj(self) : @tutuca.Value).identity() {
          Unchanged
        } else if successor is Obj(_) {
          Changed(successor)
        } else {
          Refused(
            write_refusal(name, "the setter did not answer an instance", value),
          )
        }
      }
      None => Missing
    }
  }
  self.write_member(name, value, property)
}

///|
pub impl @tutuca.Obj for DynObj with fn mutate_member(
  self,
  name,
  operation,
  args,
) {
  guard self.schema.field(name) is Some(field) else { return Missing }
  guard member_mutator_name(name, operation, field.kind()) is Some(key) &&
    self.mutators.get(key) is Some(mutate) else {
    return Missing
  }
  let successor = mutate(self.field_box(), args)
  guard successor is Obj(_) else {
    return Refused(
      write_refusal(name, "the operation did not answer an instance", Obj(self)),
    )
  }
  if successor.identity() == (Obj(self) : @tutuca.Value).identity() {
    return Unchanged
  }
  Changed(successor)
}

///|
fn member_mutator_name(
  name : String,
  operation : String,
  kind : @tutuca.FieldKind,
) -> String? {
  match (operation, kind) {
    ("clear", _) => Some(@tutuca.mutator_name("reset", name))
    ("push", _) => Some(@tutuca.mutator_name("pushIn", name))
    ("insertAt", _) => Some(@tutuca.mutator_name("insertIn", name) + "At")
    ("setAt" | "set", _) => Some(@tutuca.mutator_name("setIn", name) + "At")
    ("deleteAt", _) => Some(@tutuca.mutator_name("deleteIn", name) + "At")
    ("removeAt", _) => Some(@tutuca.mutator_name("removeIn", name) + "At")
    ("add", _) => Some(@tutuca.mutator_name("addIn", name))
    ("toggle", _) => Some(@tutuca.mutator_name("toggleIn", name))
    ("delete", FSet) => Some(@tutuca.mutator_name("deleteIn", name))
    ("remove", FSet) => Some(@tutuca.mutator_name("removeIn", name))
    ("delete", _) => Some(@tutuca.mutator_name("deleteIn", name) + "At")
    ("remove", _) => Some(@tutuca.mutator_name("removeIn", name) + "At")
    _ => None
  }
}

///|
fn DynObj::write_member(
  self : DynObj,
  name : String,
  value : @tutuca.Value,
  property : @tutuca.PropertyInfo,
) -> @tutuca.Outcome {
  if !property.writable {
    return Refused(
      write_refusal(name, "the property is declared read-only", value),
    )
  }
  if !property.ty.accepts(value) {
    return Refused(
      write_refusal(
        name,
        "the value is not a \{property.ty.show_source()}",
        value,
      ),
    )
  }
  match self.guest.set_property(self.handle, name, value) {
    GuestPropertyMissing => Missing
    GuestPropertyUnchanged => Unchanged
    GuestPropertyRefused => Refused(guest_refusal(name))
    GuestPropertyChanged(handle) => {
      // A declared getter is part of the same typed contract as its setter.
      // Validate the successor before it enters the host tree; a hand-written
      // guest must not smuggle an ill-typed public result past its manifest.
      guard self.guest.get_property(handle, name) is Some(next_value) &&
        property.ty.accepts(next_value) else {
        self.guest.drop_instance(handle)
        return Refused(
          write_refusal(
            name,
            "the guest answered a value that is not a \{property.ty.show_source()}",
            value,
          ),
        )
      }
      let candidate : @tutuca.Value = Obj(self.successor(handle))
      match self.adopt(name, candidate) {
        None => {
          self.guest.drop_instance(handle)
          Refused(
            write_refusal(name, "the successor could not be adopted", value),
          )
        }
        Some(next) => {
          superseded.push((self.guest, self.handle))
          Changed(next)
        }
      }
    }
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn trigger(self, name) {
  self.callable_at(name, @tutuca.NullStack::{ })
}

///|
pub impl @tutuca.Obj for DynObj with fn trigger_at(self, name, stack) {
  self.callable_at(name, stack)
}

///|
fn DynObj::callable_at(
  self : DynObj,
  name : String,
  stack : &@tutuca.Stack,
) -> @tutuca.Value? {
  // A `@when` filter reaches the fixed `when` operation — the guest writes one
  // function and the host reads its answer as a boolean — and the manifest's
  // `whens` list is what says the name is one.
  if self.def.whens.contains(name) {
    let bindings = self.render_bindings(stack)
    return Some(
      Fn(args => {
        Bool(self.guest.when(self.handle, name, drop_this(args), bindings))
      }),
    )
  }
  // An ENRICHER answers a map of bindings, and the renderer reads the map it
  // PASSED IN rather than what the call returned (`render/render.mbt` discards
  // an enricher's answer, which is why `TypedInstance`'s adapter mutates its
  // argument and returns Null). A guest cannot mutate a host's map, so the
  // guest returns one and this writes it back — the same contract
  // `tutucard/obj.mbt`'s `alter_fn` documents, with the write-back moved to the
  // side of the boundary that can do it.
  if self.def.enriches.contains(name) {
    return Some(
      Fn(args => {
        match drop_this(args) {
          [Map(binds), ..] as a => {
            // The row's bindings go DOWN so the body can read one it did not
            // write, then `key` / `value` / `iter`, which is the shape
            // `component/instance.mbt` uses and the offsets the generated
            // guest reads them at.
            let out = self.guest.enrich(
              self.handle,
              name,
              [
                Map(binds),
                a.get(1).unwrap_or(Null),
                a.get(2).unwrap_or(Null),
                a.get(3).unwrap_or(Null),
              ],
              self.render_bindings(stack),
            )
            match out {
              Map(bound) =>
                for k, v in bound {
                  // `key`, `value` and `iter` belong to the LOOP: the renderer
                  // restores the first two right after this call and never puts
                  // the third in the map. Writing them back would be a guest
                  // binding a name a host component does not.
                  if k != "key" && k != "value" && k != "iter" {
                    binds[k] = v
                  }
                }
              // A body that could not finish binds nothing, and the row keeps
              // what it arrived with.
              _ => ()
            }
            Null
          }
          _ => Null
        }
      }),
    )
  }
  // The scope form is handed no row and its answer IS the map, so there is
  // nothing to write back.
  if self.def.bind_withs.contains(name) {
    return Some(
      Fn(_args => {
        match
          self.guest.bind_with(self.handle, name, self.render_bindings(stack)) {
          Map(_) as m => m
          _ => Map(Map([]))
        }
      }),
    )
  }
  if self.def.methods.contains(name) {
    Some(self.method_fn(name, stack))
  } else {
    match self.mutators.get(name) {
      Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
      None => None
    }
  }
}

///|
pub impl @tutuca.Obj for DynObj with fn handler(self, bucket, name) {
  // `Receive` is not gated on the manifest: a message's name is discovered
  // dynamically and the guest answers `unhandled` for one it does not know.
  // `def.receives` therefore documents rather than gates.
  //
  // `Intent` is gated, because a walk offers the intent to every hop and a
  // guest that declares none should not be entered at all.
  let declared = match bucket {
    Receive => true
    Intent => self.def.intents.contains(name)
  }
  guard declared else { return None }
  Some(
    Handler((args, ctx) => {
      // The host's buckets and the wire's are the SAME two, so there is
      // nothing to translate: the bucket goes out as it came in, and the
      // guest's buffered control calls come back as the host's own.
      // What this component's declared lookups mean HERE, resolved before the
      // guest is entered. `ctx.lookup` walks the default route, so a card's
      // `*theme` in a handler reads exactly what a `*theme` in its view would
      // — the same question, answered at the same position.
      let bindings : Map[String, @tutuca.Value] = Map([])
      for pair in self.def.lookup {
        bindings[pair.0] = ctx.lookup(pair.0, @tutuca.LookupOpts::new())
      }
      let result = match bucket {
        Receive => self.guest.handle_message(self.handle, name, args, bindings)
        Intent => self.guest.handle_intent(self.handle, name, args, bindings)
      }
      // THE DOMAINS, BEFORE the guest's buffered control calls go out.
      //
      // A guest buffers its effects for exactly this reason — the interpreter
      // drops the effects of a transition it abandons, and the host cannot
      // un-hear a `send`. The guest already applies that to its OWN rules; a
      // domain is the host's to keep, so the host has to apply it at the same
      // moment. Checking after this loop would have been a transition that
      // did not happen and messages that did.
      let adopted : @tutuca.Value? = match result.next {
        Some(h) => self.adopt(name, Obj(self.successor(h)))
        None => None
      }
      if result.next is Some(h) && adopted is None {
        // The successor is what nothing holds, so it is what the sweep takes.
        // The instance that stands is the one this handler was called on, and
        // its handle was never queued — which is the whole reason the check
        // sits here rather than after the successor has been adopted.
        superseded.push((self.guest, h))
        return Some((Obj(self) : @tutuca.Value))
      }
      for msg in result.msgs {
        match msg {
          Send(name, args) => ctx.send(name, args)
          // The host applies these exactly as it applies a host component's —
          // a guest is not a special case, which is the whole point of the
          // calls being buffered rather than acting.
          Intent(name, args, opts) => ctx.intent(name, args, opts)
          IntentAt(steps, name, args, opts) =>
            ctx.intent_at_path(ctx.path().concat(steps), name, args, opts)
          Forward(args, opts) =>
            ctx.forward(
              if args.is_empty() {
                None
              } else {
                Some(args)
              },
              if opts.route.is_empty() {
                None
              } else {
                Some(opts)
              },
            )
          Reply(v) => ctx.reply(v)
          Fail(e) => ctx.fail(e)
          SendReply(name, args) => ctx.send_reply(name, args)
          // relative: the guest addresses its own subtree (see ControlMsg)
          SendAt(steps, name, args) =>
            ctx.send_at_path(ctx.path().concat(steps), name, args)
          SetAt(steps, name, v) =>
            ctx.set_property_at_path(ctx.path().concat(steps), name, v)
          StopPropagation => ctx.stop_propagation()
        }
      }
      // A guest that answered `unhandled` has answered: nothing claimed the
      // name. There is no fallback to a mutator the field implies — that is
      // what a view's `.field = v` is for, and it reaches `set_member` rather
      // than the dispatch path. `self.mutators` stays, because a WRITE goes
      // through it.
      if !result.handled {
        return None
      }
      match adopted {
        Some(_) as nv => {
          superseded.push((self.guest, self.handle))
          nv
        }
        None => None
      }
    }),
  )
}

///|

///|
/// What the guest declared. Everything generic over a schema — structural
/// equality, `debug`, `Value::to_json`, the inspector's form — reads this
/// one method, which is why the contract needs no `eq` and no `to-json`.
pub impl @tutuca.Obj for DynObj with fn schema(self) {
  Some(self.schema)
}

///|
/// What a store keys this instance on. None when nothing named it, which the
/// persistence layer reads as "do not store me" rather than inventing a key
/// that would not be found again.
pub impl @tutuca.Obj for DynObj with fn persist_id(self) {
  if self.pid == "" {
    None
  } else {
    Some(self.pid)
  }
}
