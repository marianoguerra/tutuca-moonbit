// The state language's parser. Implements `parse_state`.
//
// Three declaration forms — `state`, `struct`, `enum` — plus the three message
// buckets, and that is the whole grammar. What it replaced had eight, and the
// five that went were each a form for something the language already had a
// place for:
//
//   interface   a nesting level saying what a `<template id>` already says
//   enum        a payload-free sum, which is a sum
//   flags       an enum plus a container
//   type X = Y  an alias that resolves through and contributes no type
//   resource    an empty declaration to make a name resolvable
//   func        behaviour, in a block whose header says it holds none
//
// Two passes, because a field may name a type declared below it: collect every
// declaration, then resolve every type against the collection. That is the
// same shape the WIT parser had and the reason is unchanged.

///|
/// The parser's cursor.
priv struct P {
  toks : Array[Token]
  mut at : Int
}

///|
fn P::peek(self : P) -> Tok {
  self.toks[self.at].tok
}

///|
fn P::span(self : P) -> Span {
  self.toks[self.at].span
}

///|
fn P::bump(self : P) -> Token {
  let t = self.toks[self.at]
  if self.at + 1 < self.toks.length() {
    self.at = self.at + 1
  }
  t
}

///|
fn[T] P::fail(self : P, want : String) -> T raise DefError {
  raise Syntax(
    msg="expected \{want}, found \{self.peek().describe()}",
    span=self.span(),
  )
}

///|
fn P::expect(self : P, t : Tok, want : String) -> Unit raise DefError {
  if self.peek() == t {
    self.bump() |> ignore
  } else {
    self.fail(want)
  }
}

///|
fn P::ident(self : P, want : String) -> (String, Span) raise DefError {
  match self.peek() {
    TIdent(n) => {
      let t = self.bump()
      (n, t.span)
    }
    _ => self.fail(want)
  }
}

///|
/// A trailing separator is optional everywhere, so a field list reads the same
/// whether an author writes MoonBit's commas or leaves them out.
fn P::skip_comma(self : P) -> Unit {
  if self.peek() is TComma {
    self.bump() |> ignore
  }
}

///|
/// Consecutive `///` lines are one comment.
fn P::docs(self : P) -> String? {
  let lines : Array[String] = []
  while self.peek() is TDoc(text) {
    lines.push(text)
    self.bump() |> ignore
  }
  if lines.is_empty() {
    None
  } else {
    Some(lines.join("\n"))
  }
}

///|
/// `#[a = 1, b = "x", c]`, or nothing.
fn P::attrs(self : P) -> Array[(String, AttrValue)] raise DefError {
  let out : Array[(String, AttrValue)] = []
  while self.peek() is THashBracket {
    self.bump() |> ignore
    if !(self.peek() is TRBracket) {
      for ;; {
        let (key, _) = self.ident("an attribute name")
        let value : AttrValue = if self.peek() is TEquals {
          self.bump() |> ignore
          match self.peek() {
            TNum(v) => {
              self.bump() |> ignore
              ANum(v)
            }
            TStr(v) => {
              self.bump() |> ignore
              AStr(v)
            }
            // A bare identifier reads as its own text: `#[format = email]`
            // and `#[format = "email"]` are the same, which is what an author
            // writes without thinking about it.
            TIdent(v) => {
              self.bump() |> ignore
              AStr(v)
            }
            _ => self.fail("an attribute value")
          }
        } else {
          AFlag
        }
        out.push((key, value))
        if self.peek() is TComma {
          self.bump() |> ignore
          continue
        }
        break
      }
    }
    self.expect(TRBracket, "`]` closing the attribute list")
  }
  out
}

// ---------------------------------------------------------------------------
// Declarations, collected before anything is resolved

///|
priv enum RawKind {
  RState
  RStruct
  REnum
  RBucket(String)
}

///|
priv struct RawDecl {
  kind : RawKind
  /// The component a `state` names, or the type name. "" for a bare `state`
  /// and for a bucket.
  name : String
  name_span : Span
  doc : String?
  /// Fields, for `state` and `struct`.
  fields : Array[RawField]
  /// Cases, for `enum` and the buckets.
  cases : Array[RawCase]
}

///|
priv struct RawField {
  name : String
  span : Span
  doc : String?
  attrs : Array[(String, AttrValue)]
  ty : RawTy
}

///|
priv struct RawCase {
  name : String
  span : Span
  doc : String?
  payload : Array[RawTy]
}

///|
/// A type as written, before any name is resolved.
priv enum RawTy {
  /// `Name`, `Name[A, B]`
  RNamed(name~ : String, args~ : Array[RawTy], span~ : Span)
  /// `T?`
  ROpt(RawTy, Span)
  /// `(A, B)`
  RTuple(Array[RawTy], Span)
}

///|
fn RawTy::span(self : RawTy) -> Span {
  match self {
    RNamed(span~, ..) => span
    ROpt(_, s) => s
    RTuple(_, s) => s
  }
}

// ---------------------------------------------------------------------------
// Pass 1 — read the declarations

///|
fn parse_decls(p : P) -> Array[RawDecl] raise DefError {
  let out : Array[RawDecl] = []
  for ;; {
    let doc = p.docs()
    if p.peek() is TEof {
      break
    }
    let (word, word_span) = p.ident(
      "a declaration: state, struct, enum, receive, bubble or response",
    )
    let kind : RawKind = match word {
      "state" => RState
      "struct" => RStruct
      "enum" => REnum
      "receive" | "bubble" | "response" => RBucket(word)
      _ => raise UnknownDecl(got=word, span=word_span)
    }
    // A `state` may be bare; everything else is named.
    let (name, name_span) = match kind {
      RState =>
        if p.peek() is TIdent(_) {
          p.ident("the component's name")
        } else {
          ("", word_span)
        }
      // A bucket is named the way a `state` is: bare for the file's single
      // component, named when there are several. Under WIT the `interface`
      // owned it; with that level gone, the bucket has to say whose it is.
      RBucket(_) =>
        if p.peek() is TIdent(_) {
          p.ident("the component whose messages these are")
        } else {
          ("", word_span)
        }
      _ => p.ident("the type's name")
    }
    p.expect(TLBrace, "`{` opening the body")
    let fields : Array[RawField] = []
    let cases : Array[RawCase] = []
    let takes_fields = kind is (RState | RStruct)
    while !(p.peek() is (TRBrace | TEof)) {
      let member_doc = p.docs()
      let attrs = p.attrs()
      let (mname, mspan) = p.ident(
        if takes_fields {
          "a field name"
        } else {
          "a case name"
        },
      )
      if takes_fields {
        p.expect(TColon, "`:` before the field's type")
        fields.push({
          name: mname,
          span: mspan,
          doc: member_doc,
          attrs,
          ty: parse_ty(p),
        })
      } else {
        let payload : Array[RawTy] = []
        if p.peek() is TLParen {
          p.bump() |> ignore
          if !(p.peek() is TRParen) {
            for ;; {
              payload.push(parse_ty(p))
              if p.peek() is TComma {
                p.bump() |> ignore
                continue
              }
              break
            }
          }
          p.expect(TRParen, "`)` closing the payload")
        }
        cases.push({ name: mname, span: mspan, doc: member_doc, payload })
      }
      p.skip_comma()
    }
    p.expect(TRBrace, "`}` closing the body")
    out.push({ kind, name, name_span, doc, fields, cases })
  }
  out
}

///|
fn parse_ty(p : P) -> RawTy raise DefError {
  let from = p.span()
  let base : RawTy = match p.peek() {
    TLParen => {
      p.bump() |> ignore
      let parts : Array[RawTy] = []
      if !(p.peek() is TRParen) {
        for ;; {
          parts.push(parse_ty(p))
          if p.peek() is TComma {
            p.bump() |> ignore
            continue
          }
          break
        }
      }
      p.expect(TRParen, "`)` closing the tuple")
      RTuple(parts, { start: from.start, end_: p.toks[p.at - 1].span.end_ })
    }
    TIdent(_) => {
      let (name, nspan) = p.ident("a type")
      let args : Array[RawTy] = []
      if p.peek() is TLBracket {
        p.bump() |> ignore
        if !(p.peek() is TRBracket) {
          for ;; {
            args.push(parse_ty(p))
            if p.peek() is TComma {
              p.bump() |> ignore
              continue
            }
            break
          }
        }
        p.expect(TRBracket, "`]` closing the type arguments")
      }
      RNamed(name~, args~, span={
        start: nspan.start,
        end_: p.toks[p.at - 1].span.end_,
      })
    }
    // `Component["Legend"]` is the only place a string is a type argument, and
    // it arrives through the branch above.
    _ => p.fail("a type")
  }
  if p.peek() is TQuestion {
    let q = p.bump()
    return ROpt(base, { start: from.start, end_: q.span.end_ })
  }
  base
}

// ---------------------------------------------------------------------------
// Pass 2 — resolve

///|
/// What a name resolves against while types are being built.
priv struct Env {
  /// Type name -> the declaration, for this component.
  decls : Map[String, RawDecl]
  /// Component name -> itself, so a field can name a sibling.
  comps : Map[String, String]
}

///|
pub fn parse_state(
  source : String,
  name? : String = "",
) -> Array[StateDef] raise DefError {
  let p : P = { toks: tokenize(source), at: 0 }
  let raw = parse_decls(p)
  // Which components this file declares, so a field can name a sibling
  // before its `state` appears.
  let comps : Map[String, String] = Map([])
  let mut saw_named = false
  let mut saw_bare = false
  let mut bare_span = no_span
  for d in raw {
    if d.kind is RState {
      if d.name == "" {
        saw_bare = true
        bare_span = d.name_span
      } else {
        saw_named = true
        if comps.contains(d.name) {
          raise DuplicateComponent(name=d.name, span=d.name_span)
        }
        // Validated here rather than at emission: the name heads every
        // generated type, so one that is not an identifier would emit code
        // that does not compile.
        comps[d.name] = component_of(d.name, d.name_span)
      }
    }
  }
  if saw_named && saw_bare {
    raise MixedStateNames(span=bare_span)
  }
  guard saw_named || saw_bare else {
    raise NoState(span=if raw.is_empty() { no_span } else { raw[0].name_span })
  }
  // A bare `state` belongs to the file's single unnamed component, exactly as
  // a bare `<template>` id does — and the caller is who knows what that
  // component is called. It matters beyond a label: the name prefixes every
  // generated type, so a bare state with no fallback would emit `Sample`
  // beside `LoaderBarState`.
  if saw_bare {
    comps[""] = upper_name(name)
  }
  // Everything that is not a `state` belongs to every component in the file.
  // One block, one set of shared types — which is what an author writing two
  // components over one `Label` expects, and what the old per-interface
  // scoping made impossible.
  let decls : Map[String, RawDecl] = Map([])
  for d in raw {
    match d.kind {
      RStruct | REnum => {
        if is_builtin_ty(d.name) {
          raise ReservedName(name=d.name, span=d.name_span)
        }
        decls[d.name] = d
      }
      _ => ()
    }
  }
  let env : Env = { decls, comps }
  let out : Array[StateDef] = []
  for d in raw {
    guard d.kind is RState else { continue }
    out.push(build(d, raw, env, name))
  }
  out
}

///|
/// One component's whole contract.
fn build(
  d : RawDecl,
  raw : Array[RawDecl],
  env : Env,
  fallback : String,
) -> StateDef raise DefError {
  let _ = fallback
  let comp = env.comps.get(d.name).unwrap()
  let fields = fields_of(d.fields, env)
  // The buckets belong to the file, and a file declares one component's
  // messages or none — a second `receive` would be the same bucket twice.
  let bucket = (which : String) => {
    let cases : Array[RawCase] = []
    for r in raw {
      if r.kind is RBucket(w) && w == which && r.name == d.name {
        for c in r.cases {
          cases.push(c)
        }
      }
    }
    msgs_of(cases, env)
  }
  let types : Array[UserTy] = []
  for _name, decl in env.decls {
    types.push(user_ty_of(decl, comp, env))
  }
  types.sort_by((a, b) => str_cmp(a.wit_name, b.wit_name))
  check_acyclic(types, fields, d.name_span)
  {
    wit_name: d.name,
    component: comp,
    fields,
    receive: bucket("receive"),
    bubble: bucket("bubble"),
    response: bucket("response"),
    // `func` is gone: a callable is declared in the script block, where every
    // other callable already lives.
    types,
    doc: d.doc,
  }
}

///|
fn fields_of(
  raw : Array[RawField],
  env : Env,
) -> Array[FieldDef] raise DefError {
  let names = raw.map(f => f.name)
  // The binding is the only mapped spelling left. A field is written the way
  // a view reads it, so `name` and the source spelling are one string — where
  // WIT gave a field three names for one idea.
  let bound = mapped(names, "field", binding_name, span_of(raw))
  let out : Array[FieldDef] = []
  for i, f in raw {
    out.push({
      wit_name: f.name,
      name: f.name,
      binding: bound[i].1,
      ty: resolve(f.ty, env),
      doc: f.doc,
      attrs: f.attrs,
    })
  }
  out
}

///|
fn span_of(raw : Array[RawField]) -> Span {
  match raw.get(0) {
    Some(f) => f.span
    None => no_span
  }
}

///|
fn msgs_of(raw : Array[RawCase], env : Env) -> Array[MsgDef] raise DefError {
  let names = raw.map(c => c.name)
  let first = match raw.get(0) {
    Some(c) => c.span
    None => no_span
  }
  let runtime = mapped(names, "message", camel_name, first)
  let variants = mapped(names, "message", upper_name, first)
  let out : Array[MsgDef] = []
  for i, c in raw {
    let payload : Array[StateTy] = []
    for t in c.payload {
      payload.push(resolve(t, env))
    }
    out.push({
      wit_name: c.name,
      name: runtime[i].1,
      variant: variants[i].1,
      payload,
      doc: c.doc,
    })
  }
  out
}

///|
/// A named type, prefixed with the component so two components' `Label`s do
/// not collide in one generated module.
fn user_ty_of(d : RawDecl, comp : String, env : Env) -> UserTy raise DefError {
  let name = comp + upper_name(d.name)
  let kind : UserTyKind = match d.kind {
    RStruct => URecord(fields_of(d.fields, env))
    _ => {
      // One construct, two encodings. Every case payload-free means the value
      // IS its case name, which is what an enum has always encoded as; one
      // payload anywhere makes it a tagged sum. The author writes `enum`
      // either way, and the split that used to be theirs is the emitter's.
      let mut has_payload = false
      for c in d.cases {
        if !c.payload.is_empty() {
          has_payload = true
        }
      }
      if has_payload {
        UVariant(msgs_of(d.cases, env))
      } else {
        let names = d.cases.map(c => c.name)
        let first = match d.cases.get(0) {
          Some(c) => c.span
          None => no_span
        }
        UEnum(mapped(names, "enum case", upper_name, first))
      }
    }
  }
  { wit_name: d.name, name, kind, doc: d.doc }
}

// ---------------------------------------------------------------------------
// Types

///|
/// The builtin type names, which are reserved.
///
/// Reserved for the reason the markers were: a user type called `Any` would
/// silently change what every `Any` in the file means.
fn is_builtin_ty(name : String) -> Bool {
  name
  is ("Bool"
  | "Int"
  | "Int8"
  | "Int16"
  | "UInt"
  | "UInt8"
  | "UInt16"
  | "Double"
  | "String"
  | "Array"
  | "Set"
  | "Map"
  | "Any"
  | "Component")
}

///|
fn resolve(t : RawTy, env : Env) -> StateTy raise DefError {
  match t {
    ROpt(inner, _) => TOption(resolve(inner, env))
    RTuple(parts, _) => {
      let out : Array[StateTy] = []
      for x in parts {
        out.push(resolve(x, env))
      }
      TTuple(out)
    }
    RNamed(name~, args~, span~) => named(name, args, span, env)
  }
}

///|
fn arity(
  name : String,
  args : Array[RawTy],
  want : Int,
  span : Span,
) -> Unit raise DefError {
  if args.length() != want {
    raise BadTypeArgs(name~, want~, got=args.length(), span~)
  }
}

///|
fn named(
  name : String,
  args : Array[RawTy],
  span : Span,
  env : Env,
) -> StateTy raise DefError {
  match name {
    "Bool" => {
      arity(name, args, 0, span)
      TBool
    }
    // Width and signedness survive so decode can range-check, even though
    // every one of them emits a MoonBit `Int`. `Int` is the one an author
    // reaches for; the rest are there when a bound is meant.
    "Int" => {
      arity(name, args, 0, span)
      TInt(width=32, signed=true)
    }
    "Int8" => {
      arity(name, args, 0, span)
      TInt(width=8, signed=true)
    }
    "Int16" => {
      arity(name, args, 0, span)
      TInt(width=16, signed=true)
    }
    "UInt" => {
      arity(name, args, 0, span)
      TInt(width=32, signed=false)
    }
    "UInt8" => {
      arity(name, args, 0, span)
      TInt(width=8, signed=false)
    }
    "UInt16" => {
      arity(name, args, 0, span)
      TInt(width=16, signed=false)
    }
    "Double" => {
      arity(name, args, 0, span)
      TFloat
    }
    "String" => {
      arity(name, args, 0, span)
      TText
    }
    "Any" => {
      arity(name, args, 0, span)
      TAny
    }
    "Array" => {
      arity(name, args, 1, span)
      TList(resolve(args[0], env))
    }
    "Set" => {
      arity(name, args, 1, span)
      // `Set[String]` is open membership; `Set[E]` over a declared enum is
      // closed, and the enum is where the membership is written. One spelling,
      // and the container decides the zero — which is empty either way.
      match args[0] {
        RNamed(name=inner, args=[], span=ispan) =>
          if inner == "String" {
            TSet
          } else if env.decls.get(inner) is Some(d) && d.kind is REnum {
            TFlags(inner)
          } else {
            raise UnsupportedType(
              ty="Set[\{inner}]",
              why="a set holds strings or the cases of an enum; `\{inner}` is neither",
              span=ispan,
            )
          }
        other =>
          raise UnsupportedType(
            ty="Set[…]",
            why="a set holds strings or the cases of an enum",
            span=other.span(),
          )
      }
    }
    "Map" => {
      arity(name, args, 2, span)
      // Ordered, which is the refinement the runtime actually keeps. The key
      // is String because a JSON object's key is.
      match args[0] {
        RNamed(name="String", args=[], ..) => TOMap(resolve(args[1], env))
        other =>
          raise UnsupportedType(
            ty="Map[…]",
            why="a map is keyed by String; state travels as JSON, where an object's key is a string",
            span=other.span(),
          )
      }
    }
    "Component" =>
      if args.is_empty() {
        TComp(None)
      } else {
        arity(name, args, 1, span)
        match args[0] {
          // `Component["Legend"]` names a component from another module. A
          // string rather than a bare name because it resolves through the
          // registration scope at make time and this file cannot see it.
          RNamed(name=n, args=[], ..) => TComp(Some(upper_name(n)))
          other =>
            raise UnsupportedType(
              ty="Component[…]",
              why="a component slot names one component",
              span=other.span(),
            )
        }
      }
    // Named rather than silently unknown, because "unknown type `Int64`" would
    // read as a spelling mistake when the answer is that state travels as JSON
    // and a JSON number is a Double.
    "Int64" | "UInt64" =>
      raise UnsupportedType(
        ty=name,
        why="state travels as JSON, where a number is a Double — whole values above 2^53 do not survive the trip; carry it as a String",
        span~,
      )
    _ => {
      arity(name, args, 0, span)
      // A sibling component, then a type this file declares. Siblings first
      // for the same reason builtins are reserved: a slot's type is the more
      // surprising thing to have shadowed.
      if env.comps.get(name) is Some(comp) {
        return TComp(Some(comp))
      }
      guard env.decls.get(name) is Some(d) else {
        raise UnknownTypeRef(name~, span~)
      }
      match d.kind {
        RStruct => TRecord(name)
        _ => {
          let mut has_payload = false
          for c in d.cases {
            if !c.payload.is_empty() {
              has_payload = true
            }
          }
          if has_payload {
            TVariant(name)
          } else {
            TEnum(name)
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Termination

///|
/// Refuse a named type that contains ITSELF with no indirection in between.
///
/// `Array[Node]` and `Node?` are fine, and that is the point of drawing the
/// line here: both become an `Array` and an `Option` in MoonBit, so the struct
/// and the type-directed `zero_expr` both terminate. `struct Node { next : Node }`
/// has no representation and no zero.
fn check_acyclic(
  types : Array[UserTy],
  state_fields : Array[FieldDef],
  span : Span,
) -> Unit raise DefError {
  let by_name : Map[String, Array[StateTy]] = Map([])
  for t in types {
    by_name[t.wit_name] = match t.kind {
      URecord(fs) => fs.map(f => f.ty)
      // Every payload counts, not just the first case: a schema whose validity
      // turned on declaration order would be a trap.
      UVariant(cs) => cs.map(c => c.payload).fold(init=[], (a, b) => a + b)
      UEnum(_) => []
    }
  }
  by_name["state"] = state_fields.map(f => f.ty)
  let on_path : Map[String, Bool] = Map([])
  let done : Map[String, Bool] = Map([])
  walk_named("state", by_name, on_path, done, span)
}

///|
fn walk_named(
  name : String,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Bool],
  done : Map[String, Bool],
  span : Span,
) -> Unit raise DefError {
  if done.contains(name) {
    return
  }
  if on_path.contains(name) {
    raise CyclicType(name~, span~)
  }
  on_path[name] = true
  match by_name.get(name) {
    Some(tys) =>
      for t in tys {
        walk_inline(t, by_name, on_path, done, span)
      }
    None => ()
  }
  on_path.remove(name)
  done[name] = true
}

///|
fn walk_inline(
  ty : StateTy,
  by_name : Map[String, Array[StateTy]],
  on_path : Map[String, Bool],
  done : Map[String, Bool],
  span : Span,
) -> Unit raise DefError {
  match ty {
    // Heap indirection: the recursion is finite and the zero terminates.
    TList(_) | TOption(_) | TOMap(_) => ()
    TTuple(ts) =>
      for t in ts {
        walk_inline(t, by_name, on_path, done, span)
      }
    TRecord(n) | TVariant(n) | TEnum(n) | TFlags(n) =>
      walk_named(n, by_name, on_path, done, span)
    TBool | TInt(..) | TFloat | TText | TSet | TComp(_) | TAny => ()
  }
}
