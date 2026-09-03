// Queries over a StateDef, and the MoonBit source text a type maps to.
//
// Two audiences: viewgen's type environment asks the questions (`elem_of`,
// `field_of`, `is_boolish`), and viewgen's emitter asks for text
// (`moonbit_ty`, `zero_expr`, `ty_info_src`).

///|
/// The component this schema describes: its own name, or the caller's
/// fallback for a file whose single component is unnamed.
///
/// The identical rule `@viewfile.ViewSet::component_name` follows, and
/// deliberately so — a bare `state { … }` and a bare `<template>` are the same
/// claim about the same file, so they resolve the same way.
pub fn StateDef::component_name(self : StateDef, fallback : String) -> String {
  if self.component == "" {
    upper_name(fallback)
  } else {
    self.component
  }
}

///|
pub fn StateDef::field(self : StateDef, name : String) -> FieldDef? {
  for f in self.fields {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
pub fn StateDef::property(self : StateDef, name : String) -> PropertyDef? {
  self.properties.iter().find_first(p => p.name == name)
}

///|
pub fn StateDef::member_ty(self : StateDef, name : String) -> StateTy? {
  match self.property(name) {
    Some(p) => Some(p.ty)
    None => self.field(name).map(f => f.ty)
  }
}

///|
/// The rule of this name, of either kind. `pred` and `invariant` share one
/// namespace, so one name has one answer.
pub fn StateDef::rule(self : StateDef, name : String) -> RuleDecl? {
  for r in self.rules {
    if r.name == name {
      return Some(r)
    }
  }
  None
}

///|
/// The names of the rules this component KEEPS, sorted.
///
/// Sorted because WHICH rule broke is part of the answer, and a report that
/// depended on declaration order would move when an unrelated rule was added
/// above it.
pub fn StateDef::invariants(self : StateDef) -> Array[String] {
  let out : Array[String] = []
  for r in self.rules {
    if r.kind is RInvariant {
      out.push(r.name)
    }
  }
  out.sort_by(str_cmp)
  out
}

///|
pub fn StateDef::user_ty(self : StateDef, source_name : String) -> UserTy? {
  for t in self.types {
    if t.source_name == source_name {
      return Some(t)
    }
  }
  None
}

///|
pub fn StateDef::operation_name(
  self : StateDef,
  source_name : String,
) -> String? {
  let parts : Array[String] = source_name
    .split("::")
    .map(x => x.to_owned())
    .collect()
  if parts.length() == 1 {
    return Some(camel_name(source_name))
  }
  guard parts.length() == 2 else { return None }
  for p in self.protocols {
    if p.local_name == parts[0] {
      return Some(p.id + "::" + camel_name(parts[1]))
    }
  }
  for p in self.protocol_imports {
    if p.local_name == parts[0] {
      return Some(p.id + "::" + camel_name(parts[1]))
    }
  }
  None
}

///|
/// The types whose spelling takes no arguments and needs no schema.
///
/// Here rather than inline in `named`, because `StateDef::resolve_ty` answers
/// the same question for a `new` in a block and the two must not drift: a
/// second copy of `"Int" => TyInt(width=32, signed=true)` is how `new Int16`
/// and `count : Int16` would come to mean different things.
fn scalar_ty(name : String) -> StateTy? {
  match name {
    "Bool" => Some(TyBool)
    // Width and signedness survive so decode can range-check, even though
    // every one of them emits a MoonBit `Int`. `Int` is the one an author
    // reaches for; the rest are there when a bound is meant.
    "Int" => Some(TyInt(width=32, signed=true))
    "Int8" => Some(TyInt(width=8, signed=true))
    "Int16" => Some(TyInt(width=16, signed=true))
    "UInt" => Some(TyInt(width=32, signed=false))
    "UInt8" => Some(TyInt(width=8, signed=false))
    "UInt16" => Some(TyInt(width=16, signed=false))
    "Double" => Some(TyFloat)
    "String" => Some(TyText)
    // Tabular data: typed columns of equal width. The one named shape the
    // schema can describe fully, which is why it is a type here rather than a
    // record nobody can validate.
    "Table" => Some(TyTable)
    "Any" => Some(TyAny)
    _ => None
  }
}

///|
/// Resolve a type written in the state spelling, with its arguments already
/// resolved. None when the name is not a type this schema can name.
///
/// What the block language's `new` goes through. The parse half lives in
/// `tscript`, which sees no schema; this is the half that needs one, and it
/// shares `scalar_ty` with the state block's own resolver so a name cannot
/// mean two things.
///
/// `Instance[…]` is deliberately absent: a child instance is MADE through the
/// registration scope, and a zeroed one would be a `Null` wearing a slot's
/// name.
pub fn StateDef::resolve_ty(
  self : StateDef,
  name : String,
  args : Array[StateTy],
) -> StateTy? {
  if scalar_ty(name) is Some(t) {
    return if args.is_empty() { Some(t) } else { None }
  }
  match (name, args) {
    ("Array", [e]) => Some(TyList(e))
    // `Set[String]` is open membership; `Set[E]` over a declared enum is
    // closed. The container decides the zero, which is empty either way.
    ("Set", [TyText]) => Some(TySet)
    ("Set", [TyEnum(n)]) =>
      match self.user_ty(n) {
        Some({ kind: UEnum(cs), .. }) => Some(TyFlags(n, cs.map(c => c.1)))
        _ => None
      }
    // Ordered, and keyed by String because a JSON object's key is.
    ("Map", [TyText, v]) => Some(TyOMap(v))
    (_, []) =>
      match self.user_ty(name) {
        Some({ kind: URecord(_), .. }) => Some(TyRecord(name))
        Some({ kind: UEnum(_), .. }) => Some(TyEnum(name))
        Some({ kind: UVariant(_), .. }) => Some(TyVariant(name))
        None => None
      }
    _ => None
  }
}

///|
pub fn StateDef::field_of(
  self : StateDef,
  ty : StateTy,
  name : String,
) -> StateTy? {
  match ty {
    TyRecord(n) =>
      match self.user_ty(n) {
        Some({ kind: URecord(fs), .. }) => {
          for f in fs {
            if f.name == name {
              return Some(f.ty)
            }
          }
          None
        }
        _ => None
      }
    TyOMap(v) => Some(v)
    // Opaque at generation time: a child component's fields belong to its
    // own schema, and a dynamic value has no schema at all.
    TyAny | TyComp(_) | TyCompProtocols(_) => Some(TyAny)
    _ => None
  }
}

///|
/// The name in `names` closest to `name`, when one is close enough to be
/// worth suggesting. Distance within a third of the length: near enough
/// to be a typo, far enough that unrelated names stay quiet.
///
/// The TWIN of `lint/closest_name.mbt`, and the two must answer the same way
/// for the same pair — a suggestion that depends on whether the typo reached
/// `gen-views` or the linter is a suggestion nobody can trust. They are two
/// implementations rather than one because `statedef` imports nothing but the
/// stdlib on purpose (see the note on `ty_info_source`), so there is no
/// package both can reach without either inventing a leaf for twenty lines or
/// giving this one a dependency it was built to avoid.
///
/// What legitimately differs is the THRESHOLD, because the domains do: `lint`
/// suggests over command and flag names, a fixed handful where 2 edits is
/// generous; this suggests over field names, which are as long as the author
/// made them.
pub fn nearest(name : String, names : Array[String]) -> String? {
  let limit = 1 + name.length() / 3
  let mut best : String? = None
  let mut best_d = limit + 1
  for n in names {
    let d = edit_distance(name, n)
    if d < best_d {
      best_d = d
      best = Some(n)
    }
  }
  if best_d <= limit {
    best
  } else {
    None
  }
}

///|
/// Damerau-Levenshtein: adjacent transposition counts as ONE edit, matching
/// `lint`'s. Plain Levenshtein scores a swap as two, and a swap is the
/// typo people actually make.
fn edit_distance(a : String, b : String) -> Int {
  let (x, y) = (a.to_array(), b.to_array())
  let n = y.length()
  let mut prev2 = Array::make(n + 1, 0)
  let mut prev = Array::makei(n + 1, i => i)
  for i in 1..<=x.length() {
    let cur = Array::make(n + 1, 0)
    cur[0] = i
    for j in 1..<=n {
      let sub = prev[j - 1] + (if x[i - 1] == y[j - 1] { 0 } else { 1 })
      let del = prev[j] + 1
      let ins = cur[j - 1] + 1
      let mut m = sub
      if del < m {
        m = del
      }
      if ins < m {
        m = ins
      }
      if i > 1 && j > 1 && x[i - 1] == y[j - 2] && x[i - 2] == y[j - 1] {
        let swap = prev2[j - 2] + 1
        if swap < m {
          m = swap
        }
      }
      cur[j] = m
    }
    prev2 = prev
    prev = cur
  }
  prev[n]
}

///|
/// The `where` clauses as the field-domain list a schema carries.
///
/// A rename rather than a projection: a `where` parses straight into
/// `@tutuca.Domain`, so this pairs each clause with its subject and stops.
/// It used to be two functions — one building the value, one writing the
/// source — and they described the same domains in two languages.
pub fn StateDef::field_domains(self : StateDef) -> Array[@tutuca.FieldDomain] {
  self.wheres.map(w => {
    ({ field: w.subject, domain: w.relation, } : @tutuca.FieldDomain)
  })
}

///|
pub fn StateDef::moonbit_ty(self : StateDef, ty : StateTy) -> String {
  match ty {
    TyBool => "Bool"
    // Every width emits Int; the width survives in the decode range check,
    // not in the type.
    TyInt(..) => "Int"
    TyFloat => "Double"
    TyText => "String"
    TyList(e) => "Array[" + self.moonbit_ty(e) + "]"
    TyOption(e) => self.moonbit_ty(e) + "?"
    TyTuple(ts) => "(" + ts.map(t => self.moonbit_ty(t)).join(", ") + ")"
    TyRecord(n) | TyEnum(n) | TyVariant(n) =>
      match self.user_ty(n) {
        Some(t) => t.name
        None => "@tutuca.Value"
      }
    // A set and an ordered map are Map-backed at runtime, and their MoonBit
    // shape follows: the mutators the component generates key by string.
    TyFlags(_, _) | TySet => "Map[String, Bool]"
    TyOMap(v) => "Map[String, " + self.moonbit_ty(v) + "]"
    // A child instance is an Obj behind the Value escape hatch, and a table
    // is a Map with a known shape that no MoonBit type names.
    TyComp(_) | TyCompProtocols(_) | TyTable | TyAny => "@tutuca.Value"
  }
}

///|
pub fn StateDef::zero_expr(self : StateDef, ty : StateTy) -> String {
  match ty {
    TyBool => "false"
    TyInt(..) => "0"
    TyFloat => "0.0"
    TyText => "\"\""
    TyList(_) => "[]"
    TyOption(_) => "None"
    TyTuple(ts) => "(" + ts.map(t => self.zero_expr(t)).join(", ") + ")"
    TyFlags(_, _) | TySet | TyOMap(_) => "Map([])"
    // No columns and therefore no rows. Spelled out rather than left as an
    // empty Map because `{"columns": []}` is a VALID table and `{}` is not.
    TyTable => "Map({ \"columns\": List([]) })"
    // Every zero lands in a position whose type is already known — a field of
    // the generated state struct, or a field of another zero — so none of
    // these names itself. MoonBit resolves a constructor against the expected
    // type, so two enums in one module both declaring `low` stay unambiguous,
    // and naming them anyway is the `unnecessary_annotation` `check` turns on.
    TyEnum(n) =>
      match self.user_ty(n) {
        // The first case is the zero, and an enum with no cases cannot be
        // declared.
        Some({ kind: UEnum(cs), .. }) if !cs.is_empty() => cs[0].1
        _ => "Null"
      }
    TyRecord(n) =>
      match self.user_ty(n) {
        // An empty record declares no MoonBit type (emit_user_types skips it
        // as a transparent alias), so there is nothing to build; a bare `{}`
        // would be an empty Map rather than a struct.
        Some({ name, kind: URecord(fs), .. }) =>
          if fs.is_empty() {
            name + "::{  }"
          } else {
            "{ " +
            fs.map(f => f.binding + ": " + self.zero_expr(f.ty)).join(", ") +
            " }"
          }
        _ => "Null"
      }
    TyVariant(n) =>
      match self.user_ty(n) {
        Some({ kind: UVariant(cs), .. }) if !cs.is_empty() => {
          let c = cs[0]
          if c.payload.is_empty() {
            c.variant
          } else {
            c.variant +
            "(" +
            c.payload.map(p => self.zero_expr(p)).join(", ") +
            ")"
          }
        }
        _ => "Null"
      }
    TyComp(_) | TyCompProtocols(_) | TyAny => "Null"
  }
}

///|
/// Where in the block the failure is.
///
/// Every state-language error carries a span directly.
pub fn DefError::span(self : DefError) -> Span {
  match self {
    Syntax(span~, ..)
    | UnknownDecl(span~, ..)
    | DuplicateComponent(span~, ..)
    | MixedStateNames(span~)
    | NoState(span~)
    | UnsupportedType(span~, ..)
    | UnknownTypeRef(span~, ..)
    | BadTypeArgs(span~, ..)
    | CyclicType(span~, ..)
    | Collision(span~, ..)
    | BadComponentName(span~, ..)
    | ReservedName(span~, ..)
    | UnknownProtocol(span~, ..)
    | ProtocolConflict(span~, ..)
    | DuplicateRule(span~, ..)
    | RuleOutsideState(span~, ..)
    | WhereOutsideState(span~)
    | UnknownWhereSubject(span~, ..)
    | UnknownWhereTarget(span~, ..)
    | WhereTypeMismatch(span~, ..)
    | CyclicWhere(span~, ..) => span
  }
}

///|
/// The one-line message the CLI reports.
///
/// Kept as one readable table rather than an `impl Show`, because the CLI
/// prints these verbatim: they are user-facing text, not debug output.
pub fn DefError::message(self : DefError) -> String {
  match self {
    Syntax(msg~, ..) => "spec block: \{msg}"
    UnknownDecl(got~, ..) =>
      "spec block: `\{got}` is not a declaration — expected state, struct, enum, protocol or import"
    DuplicateComponent(name~, ..) =>
      "spec block: two `state` declarations named `\{name}`; one component declares one state"
    MixedStateNames(..) =>
      "spec block: this file mixes `state { … }` with `state Name { … }` — name every component, or none of them, exactly as its templates do"
    NoState(..) =>
      "spec block: nothing declares `state`; a block of types with no state describes no component"
    UnsupportedType(ty~, why~, ..) =>
      "spec block: `\{ty}` is not something component state can carry — \{why}"
    UnknownTypeRef(name~, ..) =>
      "spec block: unknown type `\{name}`; declare it, name a component in this file, or use a builtin (Bool, Int, Double, String, Array[T], Set[T], Map[String, V], Any, Component)"
    BadTypeArgs(name~, want~, got~, ..) =>
      "spec block: `\{name}` takes \{want} type argument(s), not \{got}"
    CyclicType(name~, ..) =>
      "spec block: `\{name}` contains itself with no `?` or `Array` in between, so it has no size and no zero"
    Collision(kind~, ident~, first~, second~, ..) =>
      "spec block: \{kind}s `\{first}` and `\{second}` both map to `\{ident}`"
    BadComponentName(name~, ..) =>
      "spec block: `\{name}` cannot name a component — it must start with a letter"
    ReservedName(name~, ..) =>
      "spec block: `\{name}` is a builtin type name and cannot be declared as a type"
    UnknownProtocol(local_name~, ..) =>
      "spec block: unknown protocol `\{local_name}` — declare it here or import its canonical string id"
    ProtocolConflict(id~, ..) =>
      "spec block: protocol `\{id}` is declared more than once with different surfaces"
    DuplicateRule(name~, ..) =>
      "spec block: two rules named `\{name}`; a `pred` and an `invariant` share one `$name`, so one name has one answer"
    RuleOutsideState(name~, ..) =>
      "spec block: `\{name}` is a rule, and a rule belongs to the `state` that keeps it — move it inside the `state` body"
    WhereOutsideState(..) =>
      "spec block: a `where` names a field beside it, so it belongs inside the `state` body"
    UnknownWhereSubject(name~, hint~, ..) =>
      "spec block: `where \{name}` — this state declares no field `\{name}`\{hint}"
    UnknownWhereTarget(name~, hint~, ..) =>
      "spec block: `.\{name}` — this state declares no field `\{name}`\{hint}"
    WhereTypeMismatch(subject~, why~, ..) =>
      "spec block: `where \{subject}` cannot say that — \{why}"
    CyclicWhere(names~, ..) =>
      "spec block: the `where` clauses on \{names.map(n => "`" + n + "`").join(", ")} depend on each other in a cycle; a field is drawn after the fields its domain names, and a cycle has no such order"
  }
}

///|
pub impl Show for DefError with fn output(self, logger) {
  logger.write_string(self.message())
}
