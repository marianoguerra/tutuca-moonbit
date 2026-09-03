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
  update : ((S, Dispatch, &@tutuca.Ctx) -> Update[S])?
  get_property : Map[String, (S) -> @tutuca.Value]
  set_property : Map[String, (S, @tutuca.Value) -> Update[S]]
  compute : Map[
    String,
    (S, Array[@tutuca.Value], &@tutuca.Stack) -> @tutuca.Value,
  ]
  when : Map[
    String,
    (S, @tutuca.Value, @tutuca.Value, @tutuca.Value, &@tutuca.Stack) -> Bool,
  ]
  enrich : Map[
    String,
    (
      S,
      Map[String, @tutuca.Value],
      @tutuca.Value,
      @tutuca.Value,
      @tutuca.Value,
      &@tutuca.Stack,
    ) -> Unit,
  ]
  enrich_scope : Map[String, (S, &@tutuca.Stack) -> Map[String, @tutuca.Value]]
  loop_with : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith]
  generated : Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value]
  /// Direct state <-> fields conversion, field by field.
  encode : (S) -> Map[String, @tutuca.Value]
  decode : (Map[String, @tutuca.Value]) -> S?
}

///|
priv struct TypedInstance[S] {
  spec : TypedSpec[S]
  state : S
  fields : Map[String, @tutuca.Value]
  /// The render cache's bucket for this instance (see `@tutuca.ObjId`):
  /// fingerprinted once at creation, revision bumped by every successor.
  id : @tutuca.ObjId
  // Memoized `Obj(self)`. The seams downstream of an instance — Path
  // copy-on-write, the transactor's root-swap check — compare Values by
  // IDENTITY, and each `Obj(self)` cast allocates a fresh box. One stable
  // Value per instance is what lets an unchanged instance still look
  // unchanged after a round trip through the value world.
  mut boxed : @tutuca.Value?
}

///|
/// The one place an instance comes into being — creation (`make_typed`),
/// an update (`with_state`) and a field write (`set`) all land here.
///
/// `id` is what tells the two apart. Absent, this is a NEW instance and gets a
/// fresh fingerprint over the fields it starts with; present, it is a
/// successor and carries the predecessor's origin with the next revision. The
/// no-op paths never reach this function at all — they return the instance
/// they were given — which is exactly why a revision moving means the
/// instance really did change.
fn[S] TypedInstance::make(
  spec : TypedSpec[S],
  state : S,
  fields : Map[String, @tutuca.Value],
  id? : @tutuca.ObjId,
) -> TypedInstance[S] {
  let id = match id {
    Some(prev) => prev
    None =>
      @tutuca.ObjId::of(
        match spec.comp {
          Some(c) => c.schema.fingerprint
          None => ""
        },
        fields,
      )
  }
  { spec, state, fields, id, boxed: None, }
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
    // Two INSTANCES are the same instance or they are not, and a structural
    // compare cannot tell: an instance's identity is its state under
    // copy-on-write, and `eq` ranges over the DECLARED fields — which is
    // the right answer to "are these two alike" and the wrong one to "may I
    // keep the old one". A guest whose schema does not name everything it
    // holds (a draft, a cursor, a parser's arena) hands back a successor that
    // looks equal on every edit, and keeping the predecessor here threw that
    // edit away — silently, and with the successor's handle already queued
    // for collection.
    //
    // `ObjId` is exactly the question being asked: same origin, same
    // revision. An instance that tracks no identity answers false, which the
    // contract above says is always safe.
    (Obj(x), Obj(y)) =>
      match (x.identity(), y.identity()) {
        (Some(ix), Some(iy)) => ix == iy
        _ => false
      }
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
  TypedInstance::make(self.spec, s, fields, id=self.id.next())
}

///|
fn[S] TypedInstance::get(
  self : TypedInstance[S],
  name : String,
) -> @tutuca.Value {
  self.fields.get(name).unwrap_or(Null)
}

///|
/// This instance as the generated mutators see it (see `FieldBox`): read a
/// field, write one and answer with the successor, name the instance itself.
fn[S] TypedInstance::field_box(self : TypedInstance[S]) -> FieldBox {
  {
    get: name => self.get(name),
    set: (name, v) => self.set(name, v).to_value(),
    value: () => self.to_value(),
  }
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
  // THE FIRST DOOR a `where` has: the write itself.
  //
  // Only the domains of the field BEING WRITTEN, and against the fields as
  // they stand — so `setCurrentIndex 99` is turned down here, while shrinking
  // `items` under a `currentIndex` that was fine is not, because that write is
  // about `items` and nothing said anything about its length. The second door
  // (`broken_rule`, after the transition) is what catches the second case, and
  // that division is exactly why there are two.
  //
  // Answering `self` is the refusal: `FieldBox.set` is documented to answer
  // the instance's own value for a write the instance refused, and the
  // transactor reads the unchanged identity as "nothing happened".
  if !comp.schema.domains.is_empty() {
    match
      @tutuca.broken_domain(comp.schema.domains, name, coerced, self.fields) {
      Some(d) => {
        let sentence = @tutuca.domain_sentence(d, name, coerced, self.fields)
        if @tutuca.refusing() {
          @tutuca.refuse({
            code: OutOfRange,
            asked: @tutuca.mutator_name("set", name),
            rule: name,
            sentence,
            state: self.to_value(),
            path: @tutuca.Path::new(),
          })
        } else {
          @tutuca.domain_failed(
            handler=@tutuca.mutator_name("set", name),
            field=name,
            sentence~,
          )
        }
        return self
      }
      None => ()
    }
  }
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
      Some(s) => TypedInstance::make(self.spec, s, fields, id=self.id.next())
      None => self
    }
  } else {
    TypedInstance::make(self.spec, self.state, fields, id=self.id.next())
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
/// A `$`-callable by name: a `compute` first, then a `generated` one.
///
/// Both `member` and `trigger` end in exactly this lookup.
fn[S] TypedInstance::callable_of(
  self : TypedInstance[S],
  name : String,
  stack : &@tutuca.Stack,
) -> @tutuca.Value? {
  match self.spec.compute.get(name) {
    Some(f) => Some(Fn(args => f(self.state, drop_this(args), stack)))
    None =>
      match self.spec.generated.get(name) {
        Some(g) => Some(Fn(args => g(self.field_box(), drop_this(args))))
        None => None
      }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn field(self, name) {
  match self.fields.get(name) {
    Some(v) => Some(v)
    // $-callables surface as self-pre-bound Fns;
    // callers use the Fn convention (element 0 = this), which we drop.
    //
    // `NullStack` because this caller has none: a `$compute` read off a bare
    // `Value` — the JSON projection, a path lookup, the inspector — is not
    // being asked from a render position, so a `*name` inside it has no
    // ancestry to walk and answers Null. `method_at` below is the seam for
    // the caller that DOES have one.
    None => self.callable_of(name, @tutuca.NullStack::{ })
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn with_field(self, name, v) {
  guard self.spec.comp is Some(comp) else { return None }
  if comp.specs.contains(name) {
    Some(self.set(name, v).to_value())
  } else {
    None
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn property(self, name) {
  guard self.spec.comp is Some(comp) else { return None }
  guard comp.schema.properties.iter().any(p => p.name == name && p.public_) else {
    return None
  }
  self.spec.get_property.get(name).map(f => f(self.state))
}

///|
/// The owning view's virtual-member read. Declared getters win; state fields
/// are implicit private properties and therefore form the fallback.
impl[S] @tutuca.Obj for TypedInstance[S] with fn member_at(self, name, _stack) {
  match self.spec.get_property.get(name) {
    Some(f) => Some(f(self.state))
    None => self.fields.get(name)
  }
}

///|
/// Public property writes never enter the message dispatcher. The setter is a
/// typed, synchronous state transition, and the same invariant/domain commit
/// gate used by handlers decides whether its successor may stand.
impl[S] @tutuca.Obj for TypedInstance[S] with fn set_property(self, name, value) {
  guard self.spec.comp is Some(comp) else { return Missing }
  guard comp.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    return Missing
  }
  if !property.public_ {
    return Missing
  }
  self.write_member(name, value, property)
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn set_member(self, name, value) {
  guard self.spec.comp is Some(comp) else { return Missing }
  guard comp.schema.properties.iter().find_first(p => p.name == name)
    is Some(property) else {
    // State fields are implicit private read/write properties. Reuse the
    // generated setter so coercion and schema defaults stay in one place.
    match self.spec.generated.get(@tutuca.mutator_name("set", name)) {
      Some(setter) => {
        let successor = setter(self.field_box(), [value])
        guard successor is Obj(_) else {
          return Refused(
            write_refusal(name, "the setter did not answer an instance", value),
          )
        }
        if physical_equal(successor, self.to_value()) {
          return Unchanged
        }
        return match self.broken_rule(successor) {
          Some(broke) => {
            ignore(self.refuse_broken(broke, name, successor))
            Refused(broke_refusal(broke, name, successor))
          }
          None => Changed(successor)
        }
      }
      None => return Missing
    }
  }
  self.write_member(name, value, property)
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn mutate_member(
  self,
  name,
  operation,
  args,
) {
  guard self.spec.comp is Some(comp) && comp.schema.field(name) is Some(field) else {
    return Missing
  }
  guard member_mutator_name(name, operation, field.kind()) is Some(key) &&
    self.spec.generated.get(key) is Some(mutate) else {
    return Missing
  }
  let successor = mutate(self.field_box(), args)
  guard successor is Obj(_) else {
    return Refused(
      write_refusal(
        name,
        "the operation did not answer an instance",
        self.to_value(),
      ),
    )
  }
  if successor.identity() == self.to_value().identity() {
    return Unchanged
  }
  match self.broken_rule(successor) {
    Some(broke) => {
      ignore(self.refuse_broken(broke, name, successor))
      Refused(broke_refusal(broke, name, successor))
    }
    None => Changed(successor)
  }
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
fn[S] TypedInstance::write_member(
  self : TypedInstance[S],
  name : String,
  value : @tutuca.Value,
  property : @tutuca.PropertyInfo,
) -> @tutuca.Outcome {
  if !property.writable {
    return Refused(
      write_refusal(name, "the property is declared read-only", value),
    )
  }
  guard self.spec.set_property.get(name) is Some(setter) else {
    return Refused(write_refusal(name, "the property has no setter", value))
  }
  match setter(self.state, value) {
    Unhandled => Missing
    Unchanged => Unchanged
    // A setter is one expression over the state; it has no node to supersede
    // and no way to spell a refusal. Both reach here only from a hand-written
    // one, and both are honest as themselves.
    Replace(v) => Changed(v)
    Refused(r) => Refused(r)
    Next(next) => {
      let successor = self.with_state(next).to_value()
      if physical_equal(successor, self.to_value()) {
        return Unchanged
      }
      match self.broken_rule(successor) {
        Some(broke) => {
          ignore(self.refuse_broken(broke, name, successor))
          Refused(broke_refusal(broke, name, successor))
        }
        None => Changed(successor)
      }
    }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn trigger(self, name) {
  @tutuca.Obj::trigger_at(self, name, @tutuca.NullStack::{ })
}

///|
/// The `$compute` half, with the stack the caller is asking from.
impl[S] @tutuca.Obj for TypedInstance[S] with fn method_at(self, name, stack) {
  match self.fields.get(name) {
    Some(v) => Some(v)
    None => self.callable_of(name, stack)
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn trigger_at(self, name, stack) {
  // The four typed render-time buckets first, each adapted to its directive's
  // Fn-convention call shape (element 0 = this).
  //
  // Three of the four take `stack` as their last argument, because a `pred`
  // compiled as a `@when` and the same `pred` compiled as a `$name` are ONE
  // body — so if one of them can read `*name`, both must. `loop_with` does
  // not: no value body compiles into it.
  {
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
                stack,
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
                  stack,
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
      Some(f) => return Some(Fn(_args => Map(f(self.state, stack))))
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
  self.callable_of(name, stack)
}

///|
/// The first `invariant` the successor breaks, or None when it keeps them all.
///
/// The rules are asked THROUGH the successor's own object interface rather than
/// off `self.spec.compute`, so one call site covers both ways a successor is
/// built: an `update` arm's `Next(s2)`, and a generated mutator's brand-new
/// instance value. The second is the case that had no check at all before —
/// nothing wove a rule around `setCount`, because the rules lived in the script
/// block and a generated mutator is not declared there.
///
/// `NullStack` because a dispatch is not a render position: a `*name` inside a
/// rule answers Null here, exactly as it does for a `$compute` read off a bare
/// `Value`. The checker is what stops a rule from depending on one.
///
/// Only an explicit `Bool(false)` counts as broken. A rule that answers `Null`
/// could not be evaluated, and unknown is not wrong — refusing a transition
/// because a rule failed to run would turn a bad rule into a frozen component.
fn[S] TypedInstance::broken_invariant(
  self : TypedInstance[S],
  successor : @tutuca.Value,
) -> String? {
  guard self.spec.comp is Some(comp) else { return None }
  for name in comp.schema.invariants {
    guard successor.method_at(name, @tutuca.NullStack::{ }) is Some(Fn(f)) else {
      continue
    }
    if f([successor]) is Bool(false) {
      return Some(name)
    }
  }
  None
}

///|
/// What the component declared, and the successor did not keep.
///
/// One type over the two, because the two commit points below have to ask one
/// question: "may this successor stand?". A second `if` at each site would be
/// the kind of pair that grows a bug on one side of it a year later.
priv enum Broke {
  /// An `invariant` answered false. Carries the rule's name.
  BInvariant(String)
  /// A field left its declared domain. Carries the field and the sentence the
  /// relation composed — which is why a `where` needs no `format`.
  BDomain(field~ : String, sentence~ : String)
}

///|
/// The first thing the successor breaks, or None.
///
/// Invariants first, deliberately. An `invariant` is a sentence the author
/// wrote about their component; a domain is a relation the schema states. When
/// a transition breaks both, the author's own words are the more useful
/// report, and the domain is usually the mechanism behind them.
fn[S] TypedInstance::broken_rule(
  self : TypedInstance[S],
  successor : @tutuca.Value,
) -> Broke? {
  if self.broken_invariant(successor) is Some(rule) {
    return Some(BInvariant(rule))
  }
  guard self.spec.comp is Some(comp) else { return None }
  guard !comp.schema.domains.is_empty() else { return None }
  // Read off the SUCCESSOR rather than off `self.fields`, because that is the
  // state in question — and a domain is cross-field, so every field has to
  // come from the same one.
  //
  // Field by field through `Obj::member` rather than `Value::map`: an
  // instance is an `Obj` and not a `Map`, so `map()` would answer empty and
  // every relation would silently read `Null`.
  let after : Map[String, @tutuca.Value] = Map([])
  for f in comp.schema.fields {
    after[f.name] = successor.field(f.name)
  }
  // The SAME function the woven guard calls, which is the point of it being a
  // function: a domain this door refuses and the compiled arm admitted would be
  // two readings of one declaration.
  match @tutuca.first_broken_domain(comp.schema.domains, after) {
    Some(d) =>
      Some(
        BDomain(
          field=d.field,
          sentence=@tutuca.broken_domain_sentence(d, after),
        ),
      )
    None => None
  }
}

///|
/// Report a broken invariant and answer the state that stands instead.
///
/// The transition is ABANDONED, which is the answer every other refusal in a
/// body already gives — and the previous state is what stands, so the component
/// is left where it was rather than in the state the rule rejected.
///
/// The `sentence` is empty here and not on the path the generator weaves. A
/// `format` is compiled INTO the arm beside the rule, at the moment it fails,
/// so the values in it are the ones that made it fail; there is no such moment
/// on this path, and inventing one would mean a second evaluation against a
/// state the rule already rejected. The rule's NAME and the rejected STATE are
/// carried, which is what nothing could reach before this existed.
fn[S] TypedInstance::refuse_invariant(
  self : TypedInstance[S],
  rule : String,
  asked : String,
  rejected : @tutuca.Value,
) -> @tutuca.Value {
  if @tutuca.refusing() {
    @tutuca.refuse({
      code: Invariant,
      asked,
      rule,
      sentence: "",
      state: rejected,
      path: @tutuca.Path::new(),
    })
  } else {
    @tutuca.invariant_failed(handler=asked, pred=rule, sentence="")
  }
  self.to_value()
}

///|
/// Report whatever the successor broke, and answer the state that stands.
///
/// Same abandonment either way — the previous state stands, and a generated
/// mutator raises no effects, so nothing half-done is left behind.
///
/// The difference is in what is REPORTED, and it is the difference between the
/// two kinds of declaration. An invariant reports its NAME and no sentence:
/// its `format` is compiled into the arm beside it, at the moment it fails,
/// and there is no such moment here. A domain reports its FIELD and a sentence
/// that always exists, because a relation knows what it wanted and what it
/// got — the whole reason a `where` carries no `format`.
/// The refusal a write answers when the write itself could not be made.
///
/// No rule said no: the setter answered something that is not an instance, or
/// the property is not writable, or nothing implements it. `NoHandler` is the
/// code every other "nothing answered this name" carries.
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
/// The refusal a broken rule or domain produces, as a value.
///
/// Split out of `refuse_broken` because a write now ANSWERS with one:
/// `Outcome::Refused` carries the reason, where `PRefused` carried nothing and
/// a caller had to go and find it in the recorder.
fn broke_refusal(
  broke : Broke,
  asked : String,
  rejected : @tutuca.Value,
) -> @tutuca.Refusal {
  match broke {
    // An invariant reports its NAME and no sentence: its `format` is compiled
    // into the arm beside it, at the moment it fails, and there is no such
    // moment here.
    BInvariant(rule) =>
      {
        code: Invariant,
        asked,
        rule,
        sentence: "",
        state: rejected,
        path: @tutuca.Path::new(),
      }
    BDomain(field~, sentence~) =>
      {
        code: OutOfRange,
        asked,
        // The FIELD goes where a rule's name goes: a `where` has no name, and
        // the field is the thing a reader goes and looks at.
        rule: field,
        sentence,
        state: rejected,
        path: @tutuca.Path::new(),
      }
  }
}

///|
fn[S] TypedInstance::refuse_broken(
  self : TypedInstance[S],
  broke : Broke,
  asked : String,
  rejected : @tutuca.Value,
) -> @tutuca.Value {
  match broke {
    BInvariant(rule) => self.refuse_invariant(rule, asked, rejected)
    BDomain(field~, sentence~) => {
      if @tutuca.refusing() {
        @tutuca.refuse({
          code: OutOfRange,
          asked,
          // The FIELD goes where a rule's name goes: a `where` has no name,
          // and the field is the thing a reader goes and looks at.
          rule: field,
          sentence,
          state: rejected,
          path: @tutuca.Path::new(),
        })
      } else {
        @tutuca.domain_failed(handler=asked, field~, sentence~)
      }
      self.to_value()
    }
  }
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn handler(self, bucket, name) {
  guard self.spec.update is Some(u) else { return None }
  Some(
    Handler((args, ctx) => {
      let d : Dispatch = match bucket {
        Receive => Receive(name, args)
        Intent => Intent(name, args)
      }
      match u(self.state, d, ctx) {
        Next(s2) => {
          let nv = self.with_state(s2).to_value()
          // The rules the component KEEPS, around an arm the generator did
          // not weave them into. A script-declared arm has already been
          // checked inline — and more strictly, before its effect queue
          // flushed — so one that broke a rule answered `Unchanged` and
          // never reached here. What this covers is the hand-written
          // `update~`, whose effects may already have fired: the state is
          // rolled back, the effects are not, and that limit is real.
          match self.broken_rule(nv) {
            Some(broke) => Some(self.refuse_broken(broke, name, nv))
            None => Some(nv)
          }
        }
        // The arm SUPERSEDED the node — an instance of another component,
        // most often. Not checked against this component's rules: what stands
        // here is not this component's state any more.
        Replace(v) => Some(v)
        // Answered, and nothing changed. The instance's own Value, which is
        // memoized — so the transactor's `physical_equal` reads it as
        // "nothing happened".
        Unchanged => Some(self.to_value())
        Refused(r) => {
          if @tutuca.refusing() {
            @tutuca.refuse(r)
          }
          Some(self.to_value())
        }
        // Nothing claimed the name. There is no second answerer: a dispatch a
        // component does not declare is a refusal, and saying so is the
        // difference between a typo in a view and a button that correctly
        // does nothing.
        //
        // There USED to be one — a `Receive` no arm claimed fell through to
        // the generated mutators, so `@on.click="setQuery e.value"` reached a
        // setter the component never declared. That is what `.query = e.value`
        // is for, and it says the same thing where it can be read.
        Unhandled => {
          if @tutuca.refusing() {
            @tutuca.refuse({
              code: NoHandler,
              asked: name,
              rule: "",
              sentence: "",
              state: self.to_value(),
              path: @tutuca.Path::new(),
            })
          }
          None
        }
      }
    }),
  )
}

///|
/// The declared description, as the component was built with it — STORED, not
/// rebuilt: `eq`, `debug` and the JSON projection all read it, in
/// loops.
///
/// This one line is what an instance owes the generic-access layer. Everything
/// downstream of it — naming the fields, reading one by kind, structural
/// equality, the debug rendering, the JSON form — is a default in `@tutuca`.
impl[S] @tutuca.Obj for TypedInstance[S] with fn schema(self) {
  match self.spec.comp {
    Some(c) => Some(c.schema)
    None => None
  }
}

///|
/// The render cache's bucket for this instance — stored, like the schema
/// above, because it is read once per render site per pass.
///
/// It is deliberately absent from `member`, `eq`, `debug` and the
/// JSON projection: a bucket is not state, and an instance that reported one
/// as a field would put a hash into every DOM snapshot and every inspector
/// row.
impl[S] @tutuca.Obj for TypedInstance[S] with fn identity(self) {
  Some(self.id)
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
/// The host's own instances can be asked the same question off the same
/// schema.
impl[S] @tutuca.Obj for TypedInstance[S] with fn seq_entries(self) {
  guard self.seq_field() is Some(name) else { return None }
  Some(self.get(name).entries())
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn item(self, key) {
  guard self.seq_field() is Some(name) else { return None }
  self.get(name).item_opt(key)
}

///|
impl[S] @tutuca.Obj for TypedInstance[S] with fn with_item(self, key, v) {
  guard self.seq_field() is Some(name) else { return None }
  Some(self.set(name, self.get(name).with_item(key, v)).to_value())
}
