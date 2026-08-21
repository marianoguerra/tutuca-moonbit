// A component instance as JSON, and back — the TAGGED projection, beside the
// untagged one in value_json.mbt.
//
// `Value::to_json` answers "what does this instance HOLD"; it walks the
// declared fields and drops everything else, including which component it is.
// That is the right answer for a state dump and the wrong one for a document
// somebody means to read back, because a reader holding `{"count": 3}` has no
// way to know what to build. So this pair adds the one thing that was missing —
// a `$component` key naming the component, resolved through whatever the
// caller uses as a namespace — and walks BY THE DECLARED TYPE rather than by
// what a value happens to be.
//
// Walking by type is the whole difference. A codec that asks "is this field an
// instance?" cannot tell an empty component slot from a null, or an empty list
// of children from a scalar, because at that moment neither holds an instance
// to recognize. `FieldInfo.ty` says so without having to look.
//
// ## The shape
//
//     { "$component": "Tabs", "active": 0,
//       "tabs": [ { "$component": "TabPage", "label": "notes",
//                   "body": { "$component": "Textarea", "text": "hi" } } ] }
//
// Flat: the fields sit at the top level and the identity is a reserved key
// beside them. A declared field can never collide with one — `$` is not an
// identifier start in the state language and not one in WIT — and flatness is
// what makes a document interchangeable with the JSON Schema projection of the
// same component, so a generated form's output is already a constructor
// document.
//
// ## Where a round trip is EXACT
//
// Every declared field whose type this codec can name, at every depth, plus the
// component's identity. In particular an empty slot survives: the encoder
// always writes the key, and a PRESENT null is a different answer from an
// ABSENT one on the way back (see `from_component_json`).
//
// ## Where it is NOT
//
//  1. `Fn` fields — always null, at every depth. JSON has no shape for a
//     function and a structured clone would throw on one too.
//  2. An `Obj` with no schema — an ad-hoc object standing in for a record. With
//     no field list there is nothing to project and no name to rebuild it by.
//     (Not the same as a schema with NO fields, which is complete: it says the
//     name, and the name is the whole instruction.)
//  3. Anything the schema does not name — the `FAny` extras a component keeps
//     beside its declared fields, and whatever a hand-written instance holds
//     privately. `Obj::obj_schema` already says this is the deal.
//  4. A guest's private bytes. The contract says the host does not know their
//     shape; they ride in a side channel its owner threads through `claim~`.
//  5. `TyRecord` / `TyVariant` / `TyEnum` / `TyTable` payloads are DATA. An
//     instance smuggled inside one encodes untagged and returns as a plain Map.
//     Deliberate: the schema knows those types' names and nothing more, so
//     walking into one could only ever hydrate something a hostile document
//     planted.
//  6. Integers are Doubles, because `Value::Num` is and JSON has nothing else.
//     Exact to 2^53.
//  7. A plain Map whose key is literally `$component`, in a position that
//     permits an instance, comes back as an instance. The reserved keys are
//     collision-free against declared FIELD NAMES, not against map CONTENTS.
//  8. Identity. A restored instance is a new instance with a new `ObjId`.

///|
/// The discriminator: the component a tagged object names.
///
/// Collision-free by construction. A declared field name cannot begin with `$`
/// — the state language's identifier start is alpha-or-underscore — and neither
/// can a WIT identifier, so no component can declare a field that shadows this.
pub let component_key : String = "$component"

///|
/// The bundle a tagged object came from, when its writer knew.
///
/// A separate key rather than a `module/Component` join, because a module name
/// may contain a slash — which is exactly why `ComponentRef::to_id` is a label
/// with no way back. Absent means "resolve in whatever namespace you are",
/// which is the only thing a document written without a host can mean.
pub let module_key : String = "$module"

///|
/// Where instances come from when a document is read back.
///
/// A trait rather than a pair of closures for two reasons. A function TYPE
/// cannot carry labelled parameters, so `build`'s four arguments would be
/// positional and two of them are `String`; and a source that can build a name
/// it cannot describe — a foreign guest — wants to answer only one of the two,
/// which a defaulted method gives it for free.
pub(open) trait ComponentSource {
  /// What the named component DECLARES, so a tagged object's fields decode by
  /// TYPE rather than by guessing at their shape.
  ///
  /// `None` — the default — decodes them structurally instead. That is exactly
  /// right for a document this codec wrote, since the encoder never puts a tag
  /// anywhere the decoder would not look, and it is the honest answer for a
  /// source whose components are opaque to it.
  fn describe(Self, module_ : String?, name : String) -> SchemaInfo? = _
  /// Build it.
  ///
  /// `at` is the RFC 6901 pointer of the object being built, so a caller with a
  /// side table keyed by position — a session's per-instance snapshots — finds
  /// its entry without a second walk over the document.
  ///
  /// `None` means "not here", and the field being filled then falls to its
  /// declared default. Deliberately the same answer a wrong-shaped value gets:
  /// one rule, and no error channel to thread through a page that loads its
  /// bundles by hand.
  fn build(
    Self,
    module_ : String?,
    name : String,
    args : Map[String, Value],
    at~ : String,
  ) -> Value?
}

///|
/// A source that cannot describe what it builds. See `describe`.
impl ComponentSource with fn describe(_self, _module_, _name) {
  None
}

///|
/// A `ComponentSource` out of plain functions, for a caller with no type to
/// hang them on — a test, a one-off, a page that resolves two ways.
pub struct FnSource {
  priv build_ : (String?, String, Map[String, Value], String) -> Value?
  priv describe_ : ((String?, String) -> SchemaInfo?)?
}

///|
pub fn FnSource::new(
  build : (String?, String, Map[String, Value], String) -> Value?,
  describe? : (String?, String) -> SchemaInfo?,
) -> FnSource {
  { build_: build, describe_: describe }
}

///|
pub impl ComponentSource for FnSource with fn describe(self, module_, name) {
  match self.describe_ {
    Some(f) => f(module_, name)
    None => None
  }
}

///|
pub impl ComponentSource for FnSource with fn build(
  self,
  module_,
  name,
  args,
  at~,
) {
  (self.build_)(module_, name, args, at)
}

// --- pointers ---------------------------------------------------------------

///|
/// A child pointer, RFC 6901. Keys holding `~` or `/` are escaped, which
/// matters more than it looks: a component names its own fields, so `a/b` is a
/// name an untrusted manifest can produce.
fn ptr(at : String, key : String) -> String {
  let escaped = key
    .replace_all(old="~", new="~0")
    .replace_all(old="/", new="~1")
  "\{at}/\{escaped}"
}

// --- encode -----------------------------------------------------------------

///|
/// This value as a tagged JSON document, recursively and schema-driven.
///
/// `claim~` sees every instance and its pointer BEFORE any field of it is
/// read; answering `Some(j)` writes `j` in place of the walk. It runs first
/// rather than after because the case it exists for is a component whose state
/// is not the caller's to read, and reading a foreign guest's fields would
/// cross a boundary once per field before the hook could say no.
pub fn Value::to_component_json(
  self : Value,
  claim? : (Value, String) -> Json?,
) -> Json {
  encode_any(self, "", claim)
}

///|
/// One instance. Null for anything that is not a described one — with no field
/// list there is nothing to project and no name to rebuild it by.
fn encode_instance(
  v : Value,
  at : String,
  claim : ((Value, String) -> Json?)?,
) -> Json {
  if claim is Some(f) && f(v, at) is Some(j) {
    return j
  }
  guard v is Obj(o) else { return Json::null() }
  guard o.obj_schema() is Some(sc) else { return Json::null() }
  let out : Map[String, Json] = Map([])
  out[component_key] = Json::string(sc.name)
  for f in sc.fields {
    let fv = o.obj_field(f.name).unwrap_or(Null)
    out[f.name] = encode_field(fv, f.ty, ptr(at, f.name), claim)
  }
  Json::object(out)
}

///|
/// One field, by its DECLARED type. Every declared field is written, including
/// an empty list and an empty slot: a container's constructor fills in what a
/// document leaves out, so an omitted-because-empty field would come back
/// holding something nobody put there.
fn encode_field(
  v : Value,
  ty : TyInfo,
  at : String,
  claim : ((Value, String) -> Json?)?,
) -> Json {
  match (ty, v) {
    // An empty slot is `null`, and the key is still written. That is what makes
    // it distinguishable from a slot the document never mentioned.
    (TyComp(_), Null) => Json::null()
    (TyComp(_), Obj(_)) => encode_instance(v, at, claim)
    // A slot holding something that is not an instance is data nobody declared;
    // let the untagged projection say what it can.
    (TyComp(_), _) => v.to_json()
    (TyAny, _) => encode_any(v, at, claim)
    // An option is its payload or nothing, so it is written as its payload's
    // type would be — which is what keeps a `Set[X]?` spelled the way a `Set[X]`
    // is, rather than as whatever the value happens to look like.
    (TyOption(_), Null) => Json::null()
    (TyOption(inner), _) => encode_field(v, inner, at, claim)
    (TyList(e), List(items)) =>
      Json::array(
        items.mapi((i, it) => encode_field(it, e, ptr(at, i.to_string()), claim)),
      )
    (TyTuple(ts), List(items)) => {
      let out : Array[Json] = []
      for i, it in items {
        out.push(
          if i < ts.length() {
            encode_field(it, ts[i], ptr(at, i.to_string()), claim)
          } else {
            it.to_json()
          },
        )
      }
      Json::array(out)
    }
    (TyOMap(e), Map(m)) => {
      let out : Map[String, Json] = Map([])
      for k, it in m {
        out[k] = encode_field(it, e, ptr(at, k), claim)
      }
      Json::object(out)
    }
    // A set is held as a Map and travels as an ARRAY, which is the spelling the
    // JSON Schema projection describes and the one `coerce_or_default` already
    // reads back (a List at an FSet field coerces into the Map form). Writing
    // the Map would make this codec's document and a generated form's document
    // two different things for one type.
    (TySet, Map(m)) | (TyFlags(_, _), Map(m)) => {
      let out : Array[Json] = []
      for k, _ in m {
        out.push(Json::string(k))
      }
      Json::array(out)
    }
    _ => v.to_json()
  }
}

///|
/// A value whose declared type says nothing about it — `any`, an option's
/// payload, or an element of either. An instance here is still tagged, because
/// this is exactly where a document has to say what it holds.
fn encode_any(
  v : Value,
  at : String,
  claim : ((Value, String) -> Json?)?,
) -> Json {
  match v {
    Obj(o) =>
      if o.obj_schema() is Some(_) {
        encode_instance(v, at, claim)
      } else {
        Json::null()
      }
    List(items) =>
      Json::array(
        items.mapi((i, it) => encode_any(it, ptr(at, i.to_string()), claim)),
      )
    Map(m) => {
      let out : Map[String, Json] = Map([])
      for k, it in m {
        out[k] = encode_any(it, ptr(at, k), claim)
      }
      Json::object(out)
    }
    _ => v.to_json()
  }
}

// --- decode -----------------------------------------------------------------

///|
/// A tagged document back into an instance, through `src`.
///
/// None when the root names nothing `src` can build — a bundle that has not
/// been loaded, a component that was renamed, or a document that is not a
/// tagged object at all.
pub fn Value::from_component_json(j : Json, src : &ComponentSource) -> Value? {
  decode_instance(j, "", src, fallback="")
}

///|
/// One declared field. `None` means OMIT IT, which is the whole mechanism: a
/// field absent from the args map takes the component's own default, and that
/// is what an unresolvable `$component` and a value the type cannot hold both
/// come back as.
///
/// A present `null` is NOT omitted. It decodes to `Null`, which for a slot is
/// how an empty one survives a round trip.
fn decode_field(
  j : Json,
  ty : TyInfo,
  at : String,
  src : &ComponentSource,
) -> Value? {
  match (ty, j) {
    (TyComp(c), Object(_)) =>
      decode_instance(j, at, src, fallback=c.unwrap_or(""))
    (TyComp(_), Null) => Some(Null)
    (TyAny, _) => Some(decode_any(j, at, src))
    (TyOption(_), Null) => Some(Null)
    (TyOption(inner), _) => decode_field(j, inner, at, src)
    (TyList(e), Array(items)) =>
      Some(
        List(
          items.mapi((i, it) => decode_in(it, e, ptr(at, i.to_string()), src)),
        ),
      )
    (TyTuple(ts), Array(items)) => {
      let out : Array[Value] = []
      for i, it in items {
        out.push(
          if i < ts.length() {
            decode_in(it, ts[i], ptr(at, i.to_string()), src)
          } else {
            Value::from_json(it)
          },
        )
      }
      Some(List(out))
    }
    (TyOMap(e), Object(m)) => {
      let out : Map[String, Value] = Map([])
      for k, it in m {
        out[k] = decode_in(it, e, ptr(at, k), src)
      }
      Some(Map(out))
    }
    // Everything else — scalars, sets, and the four named shapes the schema
    // knows only by name — is taken as it stands. `coerce_or_default` is what
    // decides whether it fits, and a set arriving as an array coerces there.
    _ => Some(Value::from_json(j))
  }
}

///|
/// The same, inside a container, where there is no "omit" to answer with.
///
/// An unresolvable instance in a list becomes `Null` rather than disappearing:
/// a grid's cells are row-major, and dropping one would move every cell after
/// it.
fn decode_in(
  j : Json,
  ty : TyInfo,
  at : String,
  src : &ComponentSource,
) -> Value {
  decode_field(j, ty, at, src).unwrap_or(Null)
}

///|
/// A value whose declared type says nothing about it. A tagged object here is
/// an instance; anything else is walked as plain data, so a `$component` deeper
/// inside still resolves.
fn decode_any(j : Json, at : String, src : &ComponentSource) -> Value {
  match j {
    Object(m) =>
      if m.get(component_key) is Some(String(_)) {
        decode_instance(j, at, src, fallback="").unwrap_or(Null)
      } else {
        let out : Map[String, Value] = Map([])
        for k, it in m {
          out[k] = decode_any(it, ptr(at, k), src)
        }
        Map(out)
      }
    Array(items) =>
      List(items.mapi((i, it) => decode_any(it, ptr(at, i.to_string()), src)))
    _ => Value::from_json(j)
  }
}

///|
/// One tagged object. `fallback` is the component to assume when the document
/// does not name one, which is what lets a slot whose TYPE names its component
/// hold an untagged object — the tag is required only where the type cannot
/// say. A tag that disagrees with the fallback wins: the document is the more
/// specific statement, and the constructor re-checks the result anyway.
fn decode_instance(
  j : Json,
  at : String,
  src : &ComponentSource,
  fallback~ : String,
) -> Value? {
  guard j is Object(m) else { return None }
  let name = match m.get(component_key) {
    Some(String(s)) => s
    _ => fallback
  }
  guard name != "" else { return None }
  let module_ = match m.get(module_key) {
    Some(String(s)) => Some(s)
    _ => None
  }
  let args : Map[String, Value] = Map([])
  let schema = src.describe(module_, name)
  for k, v in m {
    if k == component_key || k == module_key {
      continue
    }
    match schema.bind(sc => sc.field(k)) {
      Some(fi) =>
        match decode_field(v, fi.ty, ptr(at, k), src) {
          Some(dv) => args[k] = dv
          // Omitted, so the component's own default applies.
          None => ()
        }
      // A field the schema does not declare, or a source that cannot describe
      // what it builds. Decoded structurally and passed on; a constructor that
      // does not know the name ignores it.
      None => args[k] = decode_any(v, ptr(at, k), src)
    }
  }
  src.build(module_, name, args, at~)
}
