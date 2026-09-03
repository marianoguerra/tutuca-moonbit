// A parsed schema as runtime description.
//
// Every function here is the VALUE twin of a `statedef` function that returns
// SOURCE. `zero_value` mirrors `StateDef::zero_expr`, and `schema_info`
// mirrors what `viewgen`'s
// `emit_schema` writes out. The twins have to agree, so the suite beside this
// file asserts it the only way that cannot rot: it renders the value back into
// the source spelling and compares that against the emitter's own.
//
// Why twins at all rather than one of them. The generated path has a compiler
// behind it — `viewgen` writes constructor source and `moonc` builds the
// value. A card is mounted in a browser with no generator and no compiler
// anywhere in the payload, so it needs the projection as a function. Neither
// can serve the other's caller.
//
// The TYPE and DOMAIN twins are gone, and that is what one `Ty` and one
// `Domain` bought: each pair described one shape in two languages, and now the
// schema parses into the runtime's own type and `to_mbt_source` prints it.

///|
/// The state a component starts at, as the fields map the render and path
/// layers read.
///
/// Type-directed, exactly as `zero_expr` is, so a card's initial state and a
/// generated `State::zero()` cannot disagree about what "empty" means. The one
/// case a type cannot answer alone is `TyVariant`: its zero is its first case,
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
pub fn zero_of(def : @statedef.StateDef, ty : @tutuca.Ty) -> @tutuca.Value {
  match ty {
    // A record's zero is its fields' zeros, which `TyInfo::zero` cannot build
    // because `TyRecord` keeps only a name — the fields are the instance's to
    // answer. Here the declaration IS in hand, so it answers.
    TyRecord(n) =>
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
    TyTuple(ts) => List(ts.map(t => zero_of(def, t)))
    // An enum's zero is its first case, and an enum with no cases cannot be
    // declared. `TyInfo::zero` answers `Str("")`
    // because it holds only the name.
    TyEnum(n) =>
      match def.user_ty(n) {
        Some({ kind: UEnum(cs), .. }) if !cs.is_empty() => Str(cs[0].1)
        _ => Str("")
      }
    _ => ty.zero()
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
fn resolve_ref(def : @statedef.StateDef, t : @tscript.TyRef) -> @tutuca.Ty? {
  let args : Array[@tutuca.Ty] = []
  for a in t.args {
    guard resolve_ref(def, a) is Some(r) else { return None }
    args.push(r)
  }
  def.resolve_ty(t.name, args)
}

///|
/// What a component's schema declares, as the runtime description an
/// instance answers `schema()` with.
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
  let fields = def.fields.map(f => @tutuca.FieldInfo::new(f.name, f.ty))
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
      ty: x.ty,
      public_: true,
      writable: x.writable,
    }),
    views: p.views,
    provides: p.provides.map(x => (x.name, x.ty)),
    lookups: p.lookups.map(x => (x.name, x.ty)),
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
      ty: p.ty,
      public_: p.public_,
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
/// No longer a projection: a `where` parses straight into `@tutuca.Domain`, so
/// this is the list the declaration already holds, paired with its subject.
/// `domain_of` was the value twin of `domain_src`, and both went the way
/// `ty_info`/`ty_info_src` did — there is one `Domain`, and
/// `Domain::to_mbt_source` prints it.
pub fn domains_of(def : @statedef.StateDef) -> Array[@tutuca.FieldDomain] {
  def.field_domains()
}
