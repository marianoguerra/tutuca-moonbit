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
pub fn StateDef::user_ty(self : StateDef, source_name : String) -> UserTy? {
  for t in self.types {
    if t.source_name == source_name {
      return Some(t)
    }
  }
  None
}

///|
/// The types whose spelling takes no arguments and needs no schema.
///
/// Here rather than inline in `named`, because `StateDef::resolve_ty` answers
/// the same question for a `new` in a block and the two must not drift: a
/// second copy of `"Int" => TInt(width=32, signed=true)` is how `new Int16`
/// and `count : Int16` would come to mean different things.
fn scalar_ty(name : String) -> StateTy? {
  match name {
    "Bool" => Some(TBool)
    // Width and signedness survive so decode can range-check, even though
    // every one of them emits a MoonBit `Int`. `Int` is the one an author
    // reaches for; the rest are there when a bound is meant.
    "Int" => Some(TInt(width=32, signed=true))
    "Int8" => Some(TInt(width=8, signed=true))
    "Int16" => Some(TInt(width=16, signed=true))
    "UInt" => Some(TInt(width=32, signed=false))
    "UInt8" => Some(TInt(width=8, signed=false))
    "UInt16" => Some(TInt(width=16, signed=false))
    "Double" => Some(TFloat)
    "String" => Some(TText)
    "Any" => Some(TAny)
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
/// `Component[…]` is deliberately absent: a child instance is MADE through the
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
    ("Array", [e]) => Some(TList(e))
    // `Set[String]` is open membership; `Set[E]` over a declared enum is
    // closed. The container decides the zero, which is empty either way.
    ("Set", [TText]) => Some(TSet)
    ("Set", [TEnum(n)]) => Some(TFlags(n))
    // Ordered, and keyed by String because a JSON object's key is.
    ("Map", [TText, v]) => Some(TOMap(v))
    (_, []) =>
      match self.user_ty(name) {
        Some({ kind: URecord(_), .. }) => Some(TRecord(name))
        Some({ kind: UEnum(_), .. }) => Some(TEnum(name))
        Some({ kind: UVariant(_), .. }) => Some(TVariant(name))
        None => None
      }
    _ => None
  }
}

///|
pub fn StateTy::elem(self : StateTy) -> StateTy? {
  match self {
    TList(e) => Some(e)
    TOMap(v) => Some(v)
    // A set iterates its members, which are text either way: `flags` has
    // closed membership, `text-set` open.
    TSet | TFlags(_) => Some(TText)
    TTuple(_) => Some(TAny)
    // A component instance iterates through its own seq_entries, and a
    // dynamic value may be a list at runtime — neither is knowable here, so
    // both stay permissive rather than becoming a false error.
    TAny | TComp(_) => Some(TAny)
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
    TRecord(n) =>
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
    TOMap(v) => Some(v)
    // Opaque at generation time: a child component's fields belong to its
    // own schema, and a dynamic value has no schema at all.
    TAny | TComp(_) => Some(TAny)
    _ => None
  }
}

///|
/// True when this field lives in the state STRUCT — which is every field.
///
/// A slot is a `@tutuca.Value` field like any other, seeded with `Null` and
/// filled at make time.
pub fn StateTy::in_struct(_self : StateTy) -> Bool {
  true
}

///|
pub fn StateTy::is_boolish(self : StateTy) -> Bool {
  // Everything has a truthiness at runtime; this asks whether writing it in
  // a boolean position can ever decide anything. `Value::is_truthy` answers
  // `true` for List, Map and Obj unconditionally, so a container in an
  // `@show` is a test that cannot fail — almost
  // always a forgotten `.length` or field read.
  //
  // A string, a number and an enum are NOT in that set even though they are
  // not booleans: `@show=".role"` beside `@text=".role"` is the idiomatic way
  // to hide an empty badge, and `@show=".count"` hides a zero. Flagging those
  // would cost more in false failures than the real ones are worth — the rule
  // stated at the head of viewgen/check_state.mbt.
  match self {
    TList(_)
    | TTuple(_)
    | TRecord(_)
    | TVariant(_)
    | TFlags(_)
    | TSet
    | TOMap(_) => false
    _ => true
  }
}

///|
/// The component this type names, when it names one. `option<greeting>` is a
/// slot like `greeting` is — `is_renderable` already unwraps it, so the
/// question "which component" has to unwrap it the same way or the two
/// disagree about the same field.
pub fn StateTy::component_named(self : StateTy) -> String? {
  match self {
    TComp(c) => c
    TOption(inner) => inner.component_named()
    _ => None
  }
}

///|
pub fn StateTy::is_renderable(self : StateTy) -> Bool {
  match self {
    TComp(_) | TAny => true
    TOption(inner) => inner.is_renderable()
    _ => false
  }
}

///|
/// How to write this type in a diagnostic, using the state-language spelling
/// the author wrote and will edit.
pub fn StateTy::show_source(self : StateTy) -> String {
  match self {
    TBool => "Bool"
    TInt(width~, signed~) =>
      match (width, signed) {
        (32, true) => "Int"
        (8, true) => "Int8"
        (16, true) => "Int16"
        (32, false) => "UInt"
        (8, false) => "UInt8"
        _ => "UInt16"
      }
    TFloat => "Double"
    TText => "String"
    TList(e) => "Array[" + e.show_source() + "]"
    TTuple(ts) => "(" + ts.map(t => t.show_source()).join(", ") + ")"
    TOption(e) => e.show_source() + "?"
    TRecord(n) | TEnum(n) | TVariant(n) => n
    // A closed set names its enum, which is where the membership is written.
    TFlags(n) => "Set[" + n + "]"
    TSet => "Set[String]"
    TOMap(v) => "Map[String, " + v.show_source() + "]"
    TComp(Some(c)) => "Component[" + c + "]"
    TComp(None) => "Component"
    TAny => "Any"
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
/// The MoonBit source of the `@tutuca.TyInfo` expression describing this type.
///
/// Text and not a `TyInfo` value: statedef stays a pure text-in/text-out
/// package, and importing core here would drag `@tutuca.Value` in for the sake
/// of one enum.
///
/// The constructors are written UNQUALIFIED, and have to be: an enum
/// constructor does not resolve through the `pub using` re-export that keeps
/// `@component.TyInfo` spelling correct, nor through the module-root facade
/// the playground compiles examples against. Bare works in both, because the
/// only position the generator writes one into — a `FieldInfo::new` argument —
/// already knows the type.
///
/// A closed set's members are INLINED rather than named: `TyInfo` is read at
/// runtime, where the declaration they would refer to does not exist.
pub fn StateDef::ty_info_src(self : StateDef, ty : StateTy) -> String {
  match ty {
    TBool => "TyBool"
    TInt(..) => "TyInt"
    TFloat => "TyFloat"
    TText => "TyText"
    TList(e) => "TyList(" + self.ty_info_src(e) + ")"
    TTuple(ts) =>
      "TyTuple([" + ts.map(t => self.ty_info_src(t)).join(", ") + "])"
    TOption(e) => "TyOption(" + self.ty_info_src(e) + ")"
    TOMap(v) => "TyOMap(" + self.ty_info_src(v) + ")"
    TRecord(n) => "TyRecord(" + quoted(n) + ")"
    TEnum(n) => "TyEnum(" + quoted(n) + ")"
    TVariant(n) => "TyVariant(" + quoted(n) + ")"
    TFlags(n) => {
      let members = match self.user_ty(n) {
        // A closed set names an ENUM now, so its membership is the enum's
        // cases — declared once, in the place the idea belongs.
        Some({ kind: UEnum(ms), .. }) => ms.map(m => quoted(m.1)).join(", ")
        _ => ""
      }
      "TyFlags(" + quoted(n) + ", [" + members + "])"
    }
    TSet => "TySet"
    TComp(Some(c)) => "TyComp(Some(" + quoted(c) + "))"
    TComp(None) => "TyComp(None)"
    TAny => "TyAny"
  }
}

///|
/// A MoonBit string literal. Schema identifiers contain no quotes, so there is
/// nothing to escape beyond the quotes themselves.
fn quoted(s : String) -> String {
  "\"" + s + "\""
}

///|
pub fn StateDef::moonbit_ty(self : StateDef, ty : StateTy) -> String {
  match ty {
    TBool => "Bool"
    // Every width emits Int; the width survives in the decode range check,
    // not in the type.
    TInt(..) => "Int"
    TFloat => "Double"
    TText => "String"
    TList(e) => "Array[" + self.moonbit_ty(e) + "]"
    TOption(e) => self.moonbit_ty(e) + "?"
    TTuple(ts) => "(" + ts.map(t => self.moonbit_ty(t)).join(", ") + ")"
    TRecord(n) | TEnum(n) | TVariant(n) =>
      match self.user_ty(n) {
        Some(t) => t.name
        None => "@tutuca.Value"
      }
    // A set and an ordered map are Map-backed at runtime, and their MoonBit
    // shape follows: the mutators the component generates key by string.
    TFlags(_) | TSet => "Map[String, Bool]"
    TOMap(v) => "Map[String, " + self.moonbit_ty(v) + "]"
    // A child instance is an Obj behind the Value escape hatch.
    TComp(_) | TAny => "@tutuca.Value"
  }
}

///|
pub fn StateDef::zero_expr(self : StateDef, ty : StateTy) -> String {
  match ty {
    TBool => "false"
    TInt(..) => "0"
    TFloat => "0.0"
    TText => "\"\""
    TList(_) => "[]"
    TOption(_) => "None"
    TTuple(ts) => "(" + ts.map(t => self.zero_expr(t)).join(", ") + ")"
    TFlags(_) | TSet | TOMap(_) => "Map([])"
    // Every zero lands in a position whose type is already known — a field of
    // the generated state struct, or a field of another zero — so none of
    // these names itself. MoonBit resolves a constructor against the expected
    // type, so two enums in one module both declaring `low` stay unambiguous,
    // and naming them anyway is the `unnecessary_annotation` `check` turns on.
    TEnum(n) =>
      match self.user_ty(n) {
        // The first case is the zero, and an enum with no cases cannot be
        // declared.
        Some({ kind: UEnum(cs), .. }) if !cs.is_empty() => cs[0].1
        _ => "Null"
      }
    TRecord(n) =>
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
    TVariant(n) =>
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
    TComp(_) | TAny => "Null"
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
    | ReservedName(span~, ..) => span
  }
}

///|
/// The one-line message the CLI reports.
///
/// Kept as one readable table rather than an `impl Show`, because the CLI
/// prints these verbatim: they are user-facing text, not debug output.
pub fn DefError::message(self : DefError) -> String {
  match self {
    Syntax(msg~, ..) => "state block: \{msg}"
    UnknownDecl(got~, ..) =>
      "state block: `\{got}` is not a declaration — expected state, struct, enum, receive or intent"
    DuplicateComponent(name~, ..) =>
      "state block: two `state` declarations named `\{name}`; one component declares one state"
    MixedStateNames(..) =>
      "state block: this file mixes `state { … }` with `state Name { … }` — name every component, or none of them, exactly as its templates do"
    NoState(..) =>
      "state block: nothing declares `state`; a block of types with no state describes no component"
    UnsupportedType(ty~, why~, ..) =>
      "state block: `\{ty}` is not something component state can carry — \{why}"
    UnknownTypeRef(name~, ..) =>
      "state block: unknown type `\{name}`; declare it, name a component in this file, or use a builtin (Bool, Int, Double, String, Array[T], Set[T], Map[String, V], Any, Component)"
    BadTypeArgs(name~, want~, got~, ..) =>
      "state block: `\{name}` takes \{want} type argument(s), not \{got}"
    CyclicType(name~, ..) =>
      "state block: `\{name}` contains itself with no `?` or `Array` in between, so it has no size and no zero"
    Collision(kind~, ident~, first~, second~, ..) =>
      "state block: \{kind}s `\{first}` and `\{second}` both map to `\{ident}`"
    BadComponentName(name~, ..) =>
      "state block: `\{name}` cannot name a component — it must start with a letter"
    ReservedName(name~, ..) =>
      "state block: `\{name}` is a builtin type name and cannot be declared as a type"
  }
}

///|
pub impl Show for DefError with fn output(self, logger) {
  logger.write_string(self.message())
}
