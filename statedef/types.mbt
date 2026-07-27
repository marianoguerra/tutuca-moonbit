// Queries over a StateDef, and the MoonBit source text a type maps to.
//
// Two audiences: viewgen's type environment asks the questions (`elem_of`,
// `field_of`, `is_boolish`), and viewgen's emitter asks for text
// (`moonbit_ty`, `zero_expr`, `field_kind_src`).

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
/// True when this field lives in the state STRUCT.
///
/// A child-component slot does not: the runtime creates it through the
/// registration scope from the `specs~` entry, which is exactly why slots
/// had to be declared out-of-band before the schema. Declaring one here
/// still buys the view check and the generated spec — it just does not
/// become a struct field.
pub fn StateTy::in_struct(self : StateTy) -> Bool {
  !(self is TComp(_))
}

///|
pub fn StateTy::is_boolish(self : StateTy) -> Bool {
  // Everything has a truthiness at runtime; this asks whether writing it in
  // a boolean position looks INTENDED. A list or a record in an `@show` is
  // almost always a forgotten `.length` or field read.
  match self {
    TBool | TAny | TOption(_) | TComp(_) => true
    _ => false
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
/// The `@component.FieldKind` constructor, as source text.
///
/// UNQUALIFIED, and it has to be: the type moved to `@tutuca` and an enum
/// constructor does not resolve through the `pub using` re-export that keeps
/// `@component.FieldKind` spelling correct — nor through the module-root
/// facade the playground compiles examples against, which is a different
/// package again. Bare works in both, because every position the generator
/// writes one into (a `FieldInfo::new` argument, a `<T>Field::kind` return)
/// already knows the type.
pub fn StateTy::field_kind_src(self : StateTy) -> String {
  match self {
    TBool => "FBool"
    TInt(..) => "FInt"
    TFloat => "FFloat"
    TText | TEnum(_) => "FText"
    TList(_) | TTuple(_) => "FList"
    TRecord(_) | TVariant(_) => "FMap"
    TSet | TFlags(_) => "FSet"
    TOMap(_) => "FOMap"
    // FComp carries the component it slots, so it cannot be written bare.
    TComp(Some(c)) => "FComp(comp=\"" + c + "\", args=Map([]))"
    TComp(None) => "FComp(comp=\"\", args=Map([]))"
    TOption(_) | TAny => "FAny"
  }
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
    TEnum(n) =>
      match self.user_ty(n) {
        // The first case is the zero: WIT enums are ordered, and an enum
        // with no cases cannot be declared.
        Some({ name, kind: UEnum(cs), .. }) if !cs.is_empty() =>
          name + "::" + cs[0].1
        _ => "Null"
      }
    TRecord(n) =>
      match self.user_ty(n) {
        Some({ name, kind: URecord(fs), .. }) =>
          name +
          "::{ " +
          fs.map(f => f.binding + ": " + self.zero_expr(f.ty)).join(", ") +
          " }"
        _ => "Null"
      }
    TVariant(n) =>
      match self.user_ty(n) {
        Some({ name, kind: UVariant(cs), .. }) if !cs.is_empty() => {
          let c = cs[0]
          if c.payload.is_empty() {
            name + "::" + c.variant
          } else {
            name +
            "::" +
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
