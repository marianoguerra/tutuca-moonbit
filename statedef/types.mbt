// Queries over a StateDef, and the MoonBit source text a type maps to.
//
// Two audiences: viewgen's type environment asks the questions (`elem_of`,
// `field_of`, `is_boolish`), and viewgen's emitter asks for text
// (`moonbit_ty`, `zero_expr`, `ty_info_src`).

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
pub fn StateDef::user_ty(self : StateDef, wit_name : String) -> UserTy? {
  for t in self.types {
    if t.wit_name == wit_name {
      return Some(t)
    }
  }
  None
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
/// True when this field lives in the state STRUCT — which is now every field.
///
/// A child-component slot used to be excluded: the runtime made it through the
/// registration scope and kept it in a side map, so `update` and `compute` could
/// not see it at all. That is why a component wanting to READ its child wrote
/// the field as `any` instead, giving up the slot's declared component to get a
/// struct field. A slot is a `@tutuca.Value` field like any other now, seeded
/// with `Null` and filled at make time, so the two spellings stop competing.
pub fn StateTy::in_struct(_self : StateTy) -> Bool {
  true
}

///|
pub fn StateTy::is_boolish(self : StateTy) -> Bool {
  // Everything has a truthiness at runtime; this asks whether writing it in
  // a boolean position can ever decide anything. `Value::is_truthy` answers
  // `true` for List, Map and Obj unconditionally (JS objects are always
  // truthy), so a container in an `@show` is a test that cannot fail — almost
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
/// How to write this type in a diagnostic — the WIT spelling, because that
/// is what the author wrote and what they will edit.
pub fn StateTy::show_wit(self : StateTy) -> String {
  match self {
    TBool => "bool"
    TInt(width~, signed~) =>
      (if signed { "s" } else { "u" }) + width.to_string()
    TFloat => "f64"
    TText => "string"
    TList(e) => "list<" + e.show_wit() + ">"
    TTuple(ts) => "tuple<" + ts.map(t => t.show_wit()).join(", ") + ">"
    TOption(e) => "option<" + e.show_wit() + ">"
    TRecord(n) | TEnum(n) | TVariant(n) | TFlags(n) => n
    TSet => "text-set"
    TOMap(v) => "an ordered map of " + v.show_wit()
    TComp(Some(c)) => "the " + c + " component"
    TComp(None) => "component"
    TAny => "any"
  }
}

///|
/// The name in `names` closest to `name`, when one is close enough to be
/// worth suggesting. Levenshtein within a third of the length: near enough
/// to be a typo, far enough that unrelated names stay quiet.
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
fn edit_distance(a : String, b : String) -> Int {
  let (x, y) = (a.to_array(), b.to_array())
  let mut prev = Array::makei(y.length() + 1, i => i)
  for i in 1..<=x.length() {
    let cur = Array::make(y.length() + 1, 0)
    cur[0] = i
    for j in 1..<=y.length() {
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
      cur[j] = m
    }
    prev = cur
  }
  prev[y.length()]
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
        Some({ kind: UFlags(ms), .. }) => ms.map(m => quoted(m.1)).join(", ")
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
/// A MoonBit string literal. Schema identifiers are WIT names, so there is
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
        // The first case is the zero: WIT enums are ordered, and an enum
        // with no cases cannot be declared.
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
/// The identifier a caller should look for in the block to point at this
/// error, or None when the error has no single locus.
///
/// mizchi/wit's AST carries no per-declaration spans and its resolver
/// reports most errors at offset 0, so a semantic failure cannot say where
/// it happened. Naming the identifier lets the caller find it by scanning
/// the block — coarse, but it puts the diagnostic on the right line, which
/// is the whole difference between a usable error and a scavenger hunt.
pub fn DefError::locus(self : DefError) -> String? {
  match self {
    // `where_` is a dotted path (`counter.state.count`); its last segment is
    // the field or case that actually carries the offending type.
    UnsupportedType(where_~, ..) | UnknownTypeRef(where_~, ..) =>
      Some(last_segment(where_))
    UnsupportedItem(item~, ..) => Some(first_word(item))
    NoStateRecord(i) | StateNotRecord(i) | DuplicateInterface(i) => Some(i)
    CyclicType(n) | ReservedName(n) => Some(n)
    Collision(second~, ..) => Some(second)
    BadInterfaceName(_) | UnexpectedPackage(_) | WitSyntax(..) => None
  }
}

///|
fn last_segment(path : String) -> String {
  let parts = path.split(".").map(p => p.to_owned()).collect()
  if parts.is_empty() {
    path
  } else {
    parts[parts.length() - 1]
  }
}

///|
fn first_word(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s.to_array() {
    if c == ' ' || c == ':' || c == '(' {
      break
    }
    sb.write_char(c)
  }
  let w = sb.to_string()
  if w == "" {
    s
  } else {
    w
  }
}

///|
/// The one-line message the CLI reports.
pub fn DefError::message(self : DefError) -> String {
  match self {
    WitSyntax(msg~, offset~) => "state block: \{msg} (at offset \{offset})"
    UnexpectedPackage(p) =>
      "state block declares `package \{p}`; the module supplies the package, so drop the line"
    UnsupportedItem(iface~, item~, why~) =>
      "state block: `\{item}` in interface `\{iface}` is not component state — \{why}"
    NoStateRecord(i) =>
      "state block: interface `\{i}` declares no `record state`; every component's state is one record named `state`"
    StateNotRecord(i) =>
      "state block: `state` in interface `\{i}` is not a record; component state is always a record of fields"
    UnsupportedType(where_~, ty~, why~) =>
      "state block: `\{ty}` at \{where_} is valid WIT but not valid component state — \{why}"
    UnknownTypeRef(where_~, name~) =>
      "state block: unknown type `\{name}` at \{where_}; declare it in this interface, name a component, or use a marker (\{marker_names().join(", ")})"
    CyclicType(n) => "state block: type `\{n}` refers to itself"
    Collision(kind~, ident~, first~, second~) =>
      "state block: \{kind}s `\{first}` and `\{second}` both map to `\{ident}`"
    DuplicateInterface(i) =>
      "state block: two interfaces named `\{i}`; one interface per component"
    BadInterfaceName(i) =>
      "state block: `\{i}` cannot name a component — it must start with a letter"
    ReservedName(n) =>
      "state block: `\{n}` is a reserved marker name and cannot be declared as a type"
  }
}

///|
pub impl Show for DefError with fn output(self, logger) {
  logger.write_string(self.message())
}
