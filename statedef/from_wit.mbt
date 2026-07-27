// The WIT subset gate: AST in, StateDef out.
//
// Works on @wit.parse's AST rather than @wit.resolve's flat model, for three
// reasons. Marker names (markers.mbt) and sibling-component names have no
// WIT declaration, so the resolver would reject a block the subset accepts.
// Nothing is prepended to the user's source, so a syntax error's offset still
// indexes what they wrote. And resolving here means the "unknown type" error
// can name the interface, the field and the near misses, where the resolver
// reports a bare message at offset 0.

///|
/// The synthetic package header. WIT requires one; the block does not carry
/// it, because the package identity belongs to the module and repeating it
/// per view file would be a name to keep in sync for no reader's benefit.
const PKG_HEADER = "package tutuca:state;\n"

///|
pub fn parse_state(source : String) -> Array[StateDef] raise DefError {
  // Caught before parsing, because prepending our header to a block that has
  // one of its own yields "expected interface" pointing at THEIR line — a
  // true report of a confusing symptom rather than of the cause.
  if leading_package(source) is Some(p) {
    raise UnexpectedPackage(p)
  }
  // Parsed with the header PREPENDED but offsets reported against the user's
  // text, so the caller can map an offset straight onto their block.
  let file = match @wit.parse(PKG_HEADER + source) {
    Ok(f) => f
    Err(Message(msg, off)) =>
      raise WitSyntax(
        msg~,
        offset=if off > PKG_HEADER.length() {
          off - PKG_HEADER.length()
        } else {
          0
        },
      )
  }
  if !file.worlds.is_empty() {
    let w = file.worlds[0]
    raise UnsupportedItem(
      iface=w.name,
      item="world " + w.name,
      why="a world describes a component's imports and exports, not its state",
    )
  }
  // Pass 1: the component names, so a field may reference a sibling before
  // the interface that declares it appears.
  let comps : Map[String, String] = Map([])
  for iface in file.interfaces {
    let comp = component_of(iface.name)
    if comps.contains(iface.name) {
      raise DuplicateInterface(iface.name)
    }
    comps[iface.name] = comp
  }
  let out : Array[StateDef] = []
  for iface in file.interfaces {
    out.push(one_interface(iface, comps))
  }
  out
}

///|
/// The package name a block declares, if it opens with one. Scans past
/// whitespace and `//` line comments only — a `package` further in is the
/// parser's problem, not ours.
fn leading_package(source : String) -> String? {
  let chars = source.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      i = i + 1
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      while i < chars.length() && chars[i] != '\n' {
        i = i + 1
      }
    } else {
      break
    }
  }
  let rest = String::from_array(chars[i:])
  guard rest.has_prefix("package ") else { return None }
  let name = StringBuilder::new()
  for c in chars[i + 8:] {
    if c == ';' || c == '\n' {
      break
    }
    name.write_char(c)
  }
  Some(name.to_string().trim(chars=" \t").to_owned())
}

///|
/// The type declarations of one interface, keyed by WIT name.
priv struct Decls {
  iface : String
  comp : String
  /// WIT name -> the declaration, for named lookups and the cycle check.
  defs : Map[String, @wit.TypeDef]
  /// Every component in the file, for `own<todo-item>` style slots.
  comps : Map[String, String]
}

///|
fn one_interface(
  iface : @wit.Interface,
  comps : Map[String, String],
) -> StateDef raise DefError {
  let comp = comps.get(iface.name).unwrap()
  let defs : Map[String, @wit.TypeDef] = Map([])
  let funcs : Array[@wit.Function] = []
  for item in iface.items {
    match item {
      TypeDef(td) => {
        if is_reserved(td.name) && td.name != "state" {
          raise ReservedName(td.name)
        }
        defs[td.name] = td
      }
      // A plain `foo: func(...)` DECLARES a `$`-callable. State is still
      // data — this does not put behaviour in the block, it names the method
      // the MoonBit `compute` bucket has to answer, which is the only way a
      // method no view of this component calls can be typed at all.
      Function(f) =>
        if f.kind is Freestanding {
          funcs.push(f)
        } else {
          raise UnsupportedItem(
            iface=iface.name,
            item=f.name + ": func(...)",
            why="a method is declared on the component, not on a resource",
          )
        }
      Use(u) =>
        raise UnsupportedItem(
          iface=iface.name,
          item="use " + u.from.interface,
          why="a state block is self-contained; cross-package types cannot cross the JSON boundary",
        )
    }
  }
  let d = { iface: iface.name, comp, defs, comps }
  guard defs.get("state") is Some(state_td) else {
    raise NoStateRecord(iface.name)
  }
  guard state_td.kind is Record(raw_fields) else {
    raise StateNotRecord(iface.name)
  }
  let fields = record_fields(d, raw_fields, "state")
  // Named types, minus the ones that only exist as buckets.
  let types : Array[UserTy] = []
  for name, td in defs {
    if name == "state" || is_bucket(name) {
      continue
    }
    types.push(user_ty(d, td))
  }
  // Stable order: `defs` is a hash map, and an unstable order would make the
  // generated module churn between runs and break the drift check.
  let sorted = types
  sorted.sort_by((a, b) => str_cmp(a.wit_name, b.wit_name))
  check_acyclic(sorted, fields)
  {
    wit_name: iface.name,
    component: comp,
    fields,
    receive: bucket(d, "receive"),
    bubble: bucket(d, "bubble"),
    response: bucket(d, "response"),
    methods: funcs.map(f => method_def(d, f)),
    types: sorted,
    doc: iface.docs,
  }
}

///|
fn is_bucket(name : String) -> Bool {
  name == "receive" || name == "bubble" || name == "response"
}

///|
/// One message bucket, declared as `variant receive { ... }`. Absent is fine
/// and common — most components raise no messages of their own.
fn bucket(d : Decls, name : String) -> Array[MsgDef] raise DefError {
  guard d.defs.get(name) is Some(td) else { return [] }
  guard td.kind is Variant(cases) else {
    raise UnsupportedType(
      where_="\{d.iface}.\{name}",
      ty=name,
      why="a message bucket must be a `variant`, so each case names one message",
    )
  }
  variant_cases(d, cases, "\{d.iface}.\{name}")
}

///|
fn variant_cases(
  d : Decls,
  cases : Array[@wit.VariantCase],
  where_ : String,
) -> Array[MsgDef] raise DefError {
  let names = cases.map(c => c.name)
  let runtime = mapped(names, "message", camel_name)
  let variants = mapped(names, "message", upper_name)
  let out : Array[MsgDef] = []
  for i, c in cases {
    let payload : Array[StateTy] = match c.ty {
      Some(t) =>
        // `case(tuple<a, b>)` is a two-argument message; anything else is a
        // one-argument message. Dispatch args are a list, so a tuple payload
        // is the natural spelling for arity > 1.
        match t {
          Tuple(ts) => ts.map(x => type_of(d, x, "\{where_}.\{c.name}"))
          _ => [type_of(d, t, "\{where_}.\{c.name}")]
        }
      None => []
    }
    out.push({
      wit_name: c.name,
      name: runtime[i].1,
      variant: variants[i].1,
      payload,
      doc: None,
    })
  }
  out
}

///|
/// One `foo: func(a: string) -> bool` declaration.
///
/// The params and result are resolved through the same type gate as a state
/// field, so a `func` cannot smuggle in a shape the value world has no reading
/// of — and so the inspector can show the signature the author wrote.
fn method_def(d : Decls, f : @wit.Function) -> MethodDef raise DefError {
  let where_ = "\{d.iface}.\{f.name}"
  let params : Array[StateTy] = []
  for p in f.params {
    params.push(type_of(d, p.ty, "\{where_}.\{p.name}"))
  }
  {
    wit_name: f.name,
    name: camel_name(f.name),
    params,
    result: match f.result {
      Some(t) => Some(type_of(d, t, "\{where_}.result"))
      None => None
    },
    doc: f.docs,
  }
}

///|
fn record_fields(
  d : Decls,
  raw : Array[@wit.Field],
  where_ : String,
) -> Array[FieldDef] raise DefError {
  let names = raw.map(f => f.name)
  let runtime = mapped(names, "field", camel_name)
  let out : Array[FieldDef] = []
  for i, f in raw {
    let name = runtime[i].1
    out.push({
      wit_name: f.name,
      name,
      binding: binding_name(name),
      ty: type_of(d, f.ty, "\{d.iface}.\{where_}.\{f.name}"),
      // WIT record fields carry no doc comments (@wit.Field has no `docs`
      // field), so a per-field note has to ride on a named type alias.
      doc: None,
    })
  }
  out
}

///|
fn user_ty(d : Decls, td : @wit.TypeDef) -> UserTy raise DefError {
  let kind : UserTyKind = match td.kind {
    Record(fs) => URecord(record_fields(d, fs, td.name))
    Enum(cs) => UEnum(mapped(cs, "enum case", upper_name))
    Flags(fs) => UFlags(mapped(fs, "flag", camel_name))
    Variant(cs) => UVariant(variant_cases(d, cs, "\{d.iface}.\{td.name}"))
    Alias(_) =>
      // An alias is transparent: it exists so a field can carry a marker
      // with a name that explains it. It contributes no MoonBit type.
      return {
        wit_name: td.name,
        name: d.comp + upper_name(td.name),
        kind: URecord([]),
        doc: td.docs,
      }
    Resource(_) =>
      raise UnsupportedType(
        where_="\{d.iface}.\{td.name}",
        ty="resource",
        why="state is plain data; a child component is a field typed by its own interface name",
      )
  }
  { wit_name: td.name, name: d.comp + upper_name(td.name), kind, doc: td.docs }
}

///|
/// The subset gate proper: one WIT type expression -> one StateTy.
fn type_of(
  d : Decls,
  t : @wit.TypeExpr,
  where_ : String,
) -> StateTy raise DefError {
  match t {
    Bool => TBool
    S8 => TInt(width=8, signed=true)
    S16 => TInt(width=16, signed=true)
    S32 => TInt(width=32, signed=true)
    U8 => TInt(width=8, signed=false)
    U16 => TInt(width=16, signed=false)
    U32 => TInt(width=32, signed=false)
    F32 | F64 => TFloat
    String_ | Char => TText
    List(inner) => TList(type_of(d, inner, where_))
    Option(inner) => TOption(type_of(d, inner, where_))
    Tuple(ts) => TTuple(ts.map(x => type_of(d, x, where_)))
    // 64-bit integers do not survive the JSON round trip the whole state
    // travels through: past 2^53 a Double cannot represent them.
    S64 | U64 =>
      raise UnsupportedType(
        where_~,
        ty="s64/u64",
        why="state travels as JSON, where integers past 2^53 lose precision; use s32 or string",
      )
    Result(_, _) =>
      raise UnsupportedType(
        where_~,
        ty="result",
        why="a field is a value, not an outcome; model the error as a field of its own",
      )
    Future(_) =>
      raise UnsupportedType(
        where_~,
        ty="future",
        why="state is synchronous; an in-flight request is a field plus a response handler",
      )
    Stream(_) =>
      raise UnsupportedType(
        where_~,
        ty="stream",
        why="state is synchronous; accumulate into a list field instead",
      )
    // `own<c>` / `borrow<c>` name a child component slot explicitly. The
    // bare `Id` form below reaches the same place, and reads better.
    Own(name) | Borrow(name) => named(d, name, where_)
    Id(name) => named(d, name, where_)
  }
}

///|
/// Resolve a bare name: a marker, a sibling component, or a type declared in
/// the same interface — in that order, because markers are reserved.
fn named(d : Decls, name : String, where_ : String) -> StateTy raise DefError {
  if marker(name) is Some(ty) {
    return ty
  }
  if d.comps.get(name) is Some(comp) {
    return TComp(Some(comp))
  }
  guard d.defs.get(name) is Some(td) else {
    raise UnknownTypeRef(where_~, name~)
  }
  match td.kind {
    Record(_) => TRecord(name)
    Enum(_) => TEnum(name)
    Variant(_) => TVariant(name)
    Flags(_) => TFlags(name)
    // A transparent alias: resolve THROUGH it, so `type tags = text-set`
    // gives the field the marker's type and not a nominal type of its own.
    Alias(inner) => {
      if inner is Id(next) && next == name {
        raise CyclicType(name)
      }
      type_of(d, inner, where_)
    }
    Resource(_) => TComp(None)
  }
}

///|
/// Refuse a named type that contains ITSELF with no indirection in between.
///
/// `list<node>` and `option<node>` are fine, and this is the point of drawing
/// the line here rather than at "mentions itself": those become an `Array` and
/// an `Option` in MoonBit, so both the struct and the type-directed `zero_expr`
/// terminate, and a tree is a perfectly ordinary thing for a component to hold.
/// `record node { next: node }` is not fine: the struct would have to contain a
/// value of its own size, and the zero would be an infinitely nested literal.
///
/// Only a direct alias (`type a = a`) used to be caught. Everything else ran the
/// emitters off the end of the stack — a segfault with no message, on a schema
/// a person could reasonably write.
fn check_acyclic(
  types : Array[UserTy],
  state_fields : Array[FieldDef],
) -> Unit raise DefError {
  let by_name : Map[String, Array[StateTy]] = Map([])
  for t in types {
    by_name[t.wit_name] = match t.kind {
      URecord(fs) => fs.map(f => f.ty)
      // A variant's zero is its FIRST case, but which case that is depends on
      // declaration order, and a schema whose validity turned on that would be
      // a trap. Every payload counts.
      UVariant(cs) => cs.map(c => c.payload).fold(init=[], (a, b) => a + b)
      UEnum(_) | UFlags(_) => []
    }
  }
  // `state` is not among `types`, but it is a record like any other and a
  // field of it can name one — so it is the root the walk starts from, and it
  // is itself reachable by name.
  by_name["state"] = state_fields.map(f => f.ty)
  let on_path : Map[String, Unit] = Map([])
  for name, _ in by_name {
    walk_named(name, by_name, on_path)
  }
}

///|
/// One step of `check_acyclic`'s depth-first walk. `on_path` holds the names
/// between the root and here: reaching one of them again is the cycle, while
/// reaching a name already finished is just two fields sharing a type.
fn walk_named(
  name : String,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Unit],
) -> Unit raise DefError {
  if on_path.contains(name) {
    raise CyclicType(name)
  }
  guard by_name.get(name) is Some(parts) else { return }
  on_path[name] = ()
  for ty in parts {
    walk_inline(ty, by_name, on_path)
  }
  on_path.remove(name) |> ignore
}

///|
/// Follow only the containment a MoonBit value pays for INLINE. `list`,
/// `option` and the ordered-map marker each put a heap indirection in the way,
/// which is exactly what makes the recursion finite.
fn walk_inline(
  ty : StateTy,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Unit],
) -> Unit raise DefError {
  match ty {
    TList(_) | TOption(_) | TOMap(_) => ()
    TTuple(ts) =>
      for t in ts {
        walk_inline(t, by_name, on_path)
      }
    TRecord(n) | TVariant(n) | TEnum(n) | TFlags(n) =>
      walk_named(n, by_name, on_path)
    TBool | TInt(..) | TFloat | TText | TSet | TComp(_) | TAny => ()
  }
}
