// A parsed schema as runtime description.
//
// Every function here is the VALUE twin of a `statedef` function that returns
// SOURCE. `ty_info` mirrors `StateDef::ty_info_src`, `zero_value` mirrors
// `StateDef::zero_expr`, and `schema_info` mirrors what `viewgen`'s
// `emit_schema` writes out. The twins have to agree, so the suite beside this
// file asserts it the only way that cannot rot: it renders the value back into
// the source spelling and compares that against the emitter's own.
//
// Why twins at all rather than one of them. The generated path has a compiler
// behind it — `viewgen` writes `TyInfo` constructor source and `moonc` builds
// the value. A card is mounted in a browser with no generator and no compiler
// anywhere in the payload, so it needs the projection as a function. Neither
// can serve the other's caller.

///|
/// The runtime type a declared type projects to.
///
/// The exact twin of `StateDef::ty_info_src`. A closed set's members are
/// INLINED for the same reason the emitter inlines them: `TyInfo` is read at
/// runtime, where the declaration they would refer to does not exist.
pub fn ty_info(
  def : @statedef.StateDef,
  ty : @statedef.StateTy,
) -> @tutuca.TyInfo {
  match ty {
    TBool => TyBool
    TInt(..) => TyInt
    TFloat => TyFloat
    TText => TyText
    TList(e) => TyList(ty_info(def, e))
    TTuple(ts) => TyTuple(ts.map(t => ty_info(def, t)))
    TOption(e) => TyOption(ty_info(def, e))
    TOMap(v) => TyOMap(ty_info(def, v))
    TRecord(n) => TyRecord(n)
    TEnum(n) => TyEnum(n)
    TVariant(n) => TyVariant(n)
    TFlags(n) => {
      // A closed set names an ENUM now, so its membership is the enum's
      // cases — declared once, where the idea belongs.
      let members : Array[String] = match def.user_ty(n) {
        Some({ kind: UEnum(ms), .. }) => ms.map(m => m.1)
        _ => []
      }
      TyFlags(n, members)
    }
    TSet => TySet
    TComp(c) => TyComp(c)
    TCompProtocols(ids) => TyCompProtocols(ids)
    TAny => TyAny
  }
}

///|
/// The state a component starts at, as the fields map the render and path
/// layers read.
///
/// Type-directed, exactly as `zero_expr` is, so a card's initial state and a
/// generated `State::zero()` cannot disagree about what "empty" means. The one
/// case a type cannot answer alone is `TVariant`: its zero is its first case,
/// and a variant is not a struct, so the honest answer is the same `Null` the
/// generated code falls back to when it cannot name one either.
pub fn zero_value(def : @statedef.StateDef) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  for f in def.fields {
    out[f.name] = zero_of(def, f.ty)
  }
  out
}

///|
/// The zero of one declared type.
pub fn zero_of(
  def : @statedef.StateDef,
  ty : @statedef.StateTy,
) -> @tutuca.Value {
  match ty {
    // A record's zero is its fields' zeros, which `TyInfo::zero` cannot build
    // because `TyRecord` keeps only a name — the fields are the instance's to
    // answer. Here the declaration IS in hand, so it answers.
    TRecord(n) =>
      match def.user_ty(n) {
        Some({ kind: URecord(fs), .. }) => {
          let m : Map[String, @tutuca.Value] = Map([])
          for f in fs {
            m[f.name] = zero_of(def, f.ty)
          }
          Map(m)
        }
        _ => Map(Map([]))
      }
    // A tuple's zero is its elements' zeros, for the same reason.
    TTuple(ts) => List(ts.map(t => zero_of(def, t)))
    // An enum's zero is its first case, and an enum with no cases cannot be
    // declared. `TyInfo::zero` answers `Str("")`
    // because it holds only the name.
    TEnum(n) =>
      match def.user_ty(n) {
        Some({ kind: UEnum(cs), .. }) if !cs.is_empty() => Str(cs[0].1)
        _ => Str("")
      }
    _ => ty_info(def, ty).zero()
  }
}

///|
/// The zero of a type a block's `new` names, or None when this schema declares
/// no such type.
///
/// The two halves of a `new` meeting: `tscript` parses the NAME because it
/// sees no schema, `statedef` resolves it because it is one, and `zero_of`
/// answers what an author gets. The interpreter takes this as a function so it
/// can stay free of both.
pub fn zero_of_ref(
  def : @statedef.StateDef,
  t : @tscript.TyRef,
) -> @tutuca.Value? {
  guard resolve_ref(def, t) is Some(ty) else { return None }
  Some(zero_of(def, ty))
}

///|
/// The type a reference names, or None when it names none.
fn resolve_ref(
  def : @statedef.StateDef,
  t : @tscript.TyRef,
) -> @statedef.StateTy? {
  let args : Array[@statedef.StateTy] = []
  for a in t.args {
    guard resolve_ref(def, a) is Some(r) else { return None }
    args.push(r)
  }
  def.resolve_ty(t.name, args)
}

///|
/// What a component's schema declares, as the runtime description an
/// instance answers `obj_schema()` with.
///
/// The channels come from the declaration; everything else is what the VIEWS
/// contribute, so it arrives from the caller — `view_handlers` are the `@on` names,
/// `methods` the `$name` calls, `ids` the constant element ids. A caller with
/// none of those in hand passes none, which is the honest answer for a schema
/// nobody has views for yet.
pub fn schema_info(
  def : @statedef.StateDef,
  name? : String = "",
  fingerprint? : String,
  view_handlers? : Array[String] = [],
  methods? : Array[String] = [],
  ids? : Array[String] = [],
  view_names? : Array[String] = [],
  init_names? : Array[String] = [],
) -> @tutuca.SchemaInfo {
  let fields = def.fields.map(f => {
    @tutuca.FieldInfo::new(f.name, ty_info(def, f.ty))
  })
  // The same one-element fingerprint the emitter writes, so a card and a
  // generated component of the same schema land in the same render-cache
  // bucket rather than looking like two unrelated shapes.
  let fp = fingerprint.unwrap_or_else(() => @statedef.fingerprint([def]))
  let protocols = def.protocols.map(p => @tutuca.ProtocolInfo::{
    id: p.id,
    handle_messages: p.handle_message.map(m => m.name),
    handle_intents: p.handle_intent.map(m => m.name),
    express_messages: p.express_message.map(m => m.name),
    express_intents: p.express_intent.map(m => m.name),
    properties: p.properties.map(x => @tutuca.PropertyInfo::{
      name: x.name,
      ty: ty_info(def, x.ty),
      writable: x.writable,
    }),
    views: p.views,
    provides: p.provides.map(x => (x.name, ty_info(def, x.ty))),
    lookups: p.lookups.map(x => (x.name, ty_info(def, x.ty))),
  })
  let binding_info = (xs : Array[@statedef.ProtocolBinding]) => {
    xs.map(b => @tutuca.ProtocolBindingInfo::{
      protocol_id: b.protocol_id,
      member_name: b.member_name,
      source: b.source,
    })
  }
  @tutuca.SchemaInfo::new(
    name~,
    fingerprint=fp,
    fields~,
    properties=def.properties.map(p => @tutuca.PropertyInfo::{
      name: p.name,
      ty: ty_info(def, p.ty),
      writable: p.writable,
    }),
    view_handlers~,
    receives=def.receive.map(m => m.name),
    intents=def.intent.map(m => m.name),
    express_messages=def.express_message.map(m => m.name),
    express_intents=def.express_intent.map(m => m.name),
    methods~,
    invariants=def.invariants(),
    domains=domains_of(def),
    ids~,
    view_names~,
    init_names~,
    protocols~,
    implements=def.implements,
    property_bindings=binding_info(def.property_bindings),
    view_bindings=binding_info(def.view_bindings),
    provide_bindings=binding_info(def.provide_bindings),
    lookup_bindings=binding_info(def.lookup_bindings),
  )
}

///|
/// The `where` clauses as runtime domains.
///
/// The value twin of `@statedef.StateDef::domains_src`, and the same
/// relationship every function in this package has with its emitting sibling:
/// a card is compiled in a browser with no MoonBit toolchain, so what the
/// generator writes as source has to be BUILDABLE here as well.
pub fn domains_of(def : @statedef.StateDef) -> Array[@tutuca.FieldDomain] {
  let out : Array[@tutuca.FieldDomain] = []
  for w in def.wheres {
    out.push({ field: w.subject, domain: domain_of(w.relation), })
  }
  out
}

///|
fn domain_of(rel : @statedef.Relation) -> @tutuca.Domain {
  let operand = (o : @statedef.Operand) => {
    match o {
      OLit(n) => (DLit(n) : @tutuca.DomainOperand)
      OField(f) => DField(f)
    }
  }
  match rel {
    RIndexOf(field~, allow_none~) => DIndexOf(field~, allow_none~)
    RKeyOf(field~) => DKeyOf(field~)
    RMemberOf(field~) => DMemberOf(field~)
    RSubsetOf(field~) => DSubsetOf(field~)
    RElementOf(field~) => DElementOf(field~)
    RNonEmpty => DNonEmpty
    RLen(inner) => DLen(domain_of(inner))
    ROneOf(ms) => DOneOf(ms)
    RCompare(op~, rhs~) =>
      DCompare(
        op=match op {
          CGe => DGe
          CGt => DGt
          CLe => DLe
          CLt => DLt
        },
        rhs=operand(rhs),
      )
    RBetween(lo~, hi~) => DBetween(lo=operand(lo), hi=operand(hi))
  }
}
